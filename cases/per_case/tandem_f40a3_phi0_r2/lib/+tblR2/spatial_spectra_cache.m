function result = spatial_spectra_cache(cache_file, cfg, stats, phase_stats, mean_bl, branch)
%SPATIAL_SPECTRA_CACHE Direct spatial FFT of u(x) for each snapshot and y.
% =========================================================================
% 【Section 6 空间谱合同】
%   - 每个流向窗口内，对每帧 u(x) 逐法向行直接 FFT（先 fillmissing
%     linear + EndValues nearest 修复、必要时插值到均匀 x 网格、
%     detrend('linear')、hann 窗），再对快照谱取平均；不使用 Taylor 假设，
%     不引入时间频率换算（definition 明确标记 'no Taylor hypothesis'）。
%   - 单边谱约定 spectrum_convention 标记 'One-sided'：正频箱加倍，
%     偶数长度窗口的 Nyquist 箱不加倍；PSD 按 dx/sum(w^2) 归一。
%   - PSD 的自变量首先定义为 spatial_frequency_cycles_per_m。输出同时提供
%     f_x*Phi_f 和等价的 k_x*Phi_k（k_x=2*pi*f_x），避免 cycles/m 与 rad/m
%     的符号混用；所选 y+ 曲线采用前者。
%   - cfg.spatial.skip_nearwall_rows 从数组 idx=1（最靠壁）开始排除指定
%     行数；这些行不读取、不做 FFT，也不参与 selected_y_plus 最近行选择。
%     cfg.spatial.skip_fov_top_rows 同理从数组末端（FOV最高处）排除。
%     输出保留 used_rows、两端 excluded_*_rows 和零 snapshot_count 供审计。
% =========================================================================

if ~ismember(branch, {'total', 'random'})
    error('tblR2:spatial_spectra_cache:InvalidBranch', ...
        'branch 必须是 total 或 random。');
end
if strcmp(branch, 'random') && isempty(phase_stats)
    error('tblR2:spatial_spectra_cache:MissingPhaseStatistics', ...
        'controlled random 分支需要 phase 统计。');
end

windows = cfg.spatial.windows_mm;
skip_nearwall_rows = 0;
if isfield(cfg.spatial, 'skip_nearwall_rows') && ...
        ~isempty(cfg.spatial.skip_nearwall_rows)
    skip_nearwall_rows = double(cfg.spatial.skip_nearwall_rows);
end
if ~(isscalar(skip_nearwall_rows) && isfinite(skip_nearwall_rows) && ...
        skip_nearwall_rows >= 0 && ...
        skip_nearwall_rows == floor(skip_nearwall_rows))
    error('tblR2:spatial_spectra_cache:InvalidNearwallRowSkip', ...
        'cfg.spatial.skip_nearwall_rows 必须是非负整数。');
end
skip_fov_top_rows = 0;
if isfield(cfg.spatial, 'skip_fov_top_rows') && ...
        ~isempty(cfg.spatial.skip_fov_top_rows)
    skip_fov_top_rows = double(cfg.spatial.skip_fov_top_rows);
end
if ~(isscalar(skip_fov_top_rows) && isfinite(skip_fov_top_rows) && ...
        skip_fov_top_rows >= 0 && ...
        skip_fov_top_rows == floor(skip_fov_top_rows))
    error('tblR2:spatial_spectra_cache:InvalidFovTopRowSkip', ...
        'cfg.spatial.skip_fov_top_rows 必须是非负整数。');
end
window_cells = cell(size(windows, 1), 1);
for iw = 1:size(windows, 1)
    window_cells{iw} = one_window(windows(iw, :));
end
window_results = vertcat(window_cells{:});
result = struct('branch', branch, 'windows', window_results, ...
    'definition', ['Direct FFT of u(x) on each snapshot and wall-normal row. ' ...
    'Snapshot spectra are averaged only after FFT; no Taylor hypothesis or ' ...
    'temporal frequency conversion enters this product.']);

    function out = one_window(bounds)
        x_original = stats.X(1, :);
        cols = find(x_original >= bounds(1) & x_original <= bounds(2));
        if numel(cols) < 8
            error('tblR2:spatial_spectra_cache:TooFewColumns', ...
                '空间窗口 [%.3g %.3g] mm 包含的流向列少于 8 列。', ...
                bounds(1), bounds(2));
        end
        x_m = x_original(cols) .* 1e-3;
        dx = median(diff(x_m));
        uniform_error = max(abs(diff(x_m) - dx));
        interpolate_uniform = uniform_error > max(1e-12, 1e-6 * abs(dx));
        if interpolate_uniform
            x_uniform = linspace(x_m(1), x_m(end), numel(x_m));
            dx = x_uniform(2) - x_uniform(1);
        else
            x_uniform = x_m;
        end

        n_x = numel(cols);
        n_positive = floor(n_x / 2);
        frequency_x = (1:n_positive) ./ (n_x * dx);
        lambda_x_m = 1 ./ frequency_x;
        one_sided_factor = 2 .* ones(1, n_positive);
        if mod(n_x, 2) == 0
            one_sided_factor(end) = 1; % Nyquist bin has no negative pair.
        end
        J = size(stats.X, 1);
        if skip_nearwall_rows + skip_fov_top_rows >= J
            error('tblR2:spatial_spectra_cache:TooManyRowsSkipped', ...
                ['请求排除的近壁/视场顶部行数（%d + %d）使 J=%d 的网格没有剩余法向行。'], ...
                skip_nearwall_rows, skip_fov_top_rows, J);
        end
        used_rows = (skip_nearwall_rows + 1):(J - skip_fov_top_rows);
        excluded_nearwall_rows = 1:skip_nearwall_rows;
        excluded_fov_top_rows = (J - skip_fov_top_rows + 1):J;
        spectrum_sum = zeros(J, n_positive);
        spectrum_count = zeros(J, n_positive);
        window_x = hann(n_x, 'periodic')';
        window_energy = sum(window_x .^ 2);

        for first = 1:cfg.chunk_frames:stats.n_frames
            last = min(stats.n_frames, first + cfg.chunk_frames - 1);
            chunk = tblR2.read_cache_chunk(cache_file, first:last, ...
                used_rows, cols, branch, stats, phase_stats);
            for local_row = 1:numel(used_rows)
                iy = used_rows(local_row);
                signals = squeeze(chunk.U(:, local_row, :));
                if isvector(signals)
                    signals = reshape(signals, 1, []);
                end
                finite = isfinite(signals);
                included = sum(finite, 2) ./ n_x >= ...
                    cfg.spatial.min_valid_fraction & sum(finite, 2) >= 8;
                if ~any(included)
                    continue;
                end
                signals = signals(included, :);
                if any(~isfinite(signals), 'all')
                    signals = fillmissing(signals, 'linear', 2, ...
                        'EndValues', 'nearest');
                end
                if interpolate_uniform
                    signals = interp1(x_m, signals', x_uniform, ...
                        'linear', 'extrap')';
                end
                signals = detrend(signals', 'linear')';
                transform = fft(signals .* window_x, [], 2);
                phi = (abs(transform(:, 2:n_positive + 1)) .^ 2) .* ...
                    dx ./ window_energy .* one_sided_factor;
                finite_phi = isfinite(phi);
                phi(~finite_phi) = 0;
                spectrum_sum(iy, :) = spectrum_sum(iy, :) + sum(phi, 1);
                spectrum_count(iy, :) = spectrum_count(iy, :) + ...
                    sum(finite_phi, 1);
            end
        end

        phi_mean = spectrum_sum ./ max(spectrum_count, 1);
        phi_mean(spectrum_count == 0) = NaN;
        % phi_mean is a PSD with respect to f_x in cycles/m.  The
        % corresponding angular-wavenumber PSD is Phi_k=Phi_f/(2*pi), so
        % f_x*Phi_f and k_x*Phi_k are numerically identical.
        wavenumber_rad_per_m = 2 * pi .* frequency_x;
        phi_uu_per_rad_per_m = phi_mean ./ (2 * pi);
        premultiplied_frequency_phi = phi_mean .* frequency_x;
        premultiplied_k_phi = phi_uu_per_rad_per_m .* wavenumber_rad_per_m;
        center_x = mean(bounds);
        delta_ref = interp1(mean_bl.boundary_layer.x, ...
            mean_bl.boundary_layer.delta99, center_x, 'linear', NaN);
        if ~isfinite(delta_ref) || delta_ref <= 0
            delta_ref = mean_bl.delta99_reference_mm;
        end
        lambda_over_delta = (lambda_x_m .* 1e3) ./ delta_ref;
        y_plus = mean(mean_bl.y_plus(:, cols), 2, 'omitnan');
        candidate_rows = used_rows(isfinite(y_plus(used_rows)));
        finite_y_plus = y_plus(candidate_rows);
        if isempty(finite_y_plus)
            error('tblR2:spatial_spectra_cache:MissingYPlus', ...
                '空间窗口 [%.3g %.3g] mm 内没有可用的有限 y+ 坐标。', ...
                bounds(1), bounds(2));
        end
        available_y_plus_range = [min(finite_y_plus), max(finite_y_plus)];
        selected_rows = zeros(numel(cfg.spatial.selected_y_plus), 1);
        selected_in_range = false(numel(selected_rows), 1);
        for iy = 1:numel(selected_rows)
            [~, candidate_index] = min( ...
                abs(finite_y_plus - cfg.spatial.selected_y_plus(iy)));
            selected_rows(iy) = candidate_rows(candidate_index);
            selected_in_range(iy) = ...
                cfg.spatial.selected_y_plus(iy) >= available_y_plus_range(1) && ...
                cfg.spatial.selected_y_plus(iy) <= available_y_plus_range(2);
        end

        out = struct();
        out.requested_window_mm = bounds;
        out.actual_window_mm = [x_original(cols(1)) x_original(cols(end))];
        out.columns = cols;
        out.x_uniform_m = x_uniform;
        out.interpolated_to_uniform_grid = interpolate_uniform;
        out.uniform_grid_max_spacing_error_m = uniform_error;
        out.spatial_frequency_resolution_cycles_per_m = 1 / (n_x * dx);
        out.longest_resolvable_wavelength_mm = n_x * dx * 1e3;
        out.spatial_frequency_cycles_per_m = frequency_x;
        out.wavenumber_rad_per_m = wavenumber_rad_per_m;
        out.one_sided_factor = one_sided_factor;
        out.spectrum_convention = ['One-sided spatial PSD; positive-frequency ' ...
            'bins are doubled except the even-length Nyquist bin.'];
        out.lambda_x_over_delta99_ref = lambda_over_delta;
        out.delta99_ref_mm = delta_ref;
        out.y_plus = y_plus;
        out.skip_nearwall_rows = skip_nearwall_rows;
        out.skip_fov_top_rows = skip_fov_top_rows;
        out.used_rows = used_rows;
        out.excluded_nearwall_rows = excluded_nearwall_rows;
        out.excluded_fov_top_rows = excluded_fov_top_rows;
        out.phi_uu = phi_mean;
        out.phi_uu_per_rad_per_m = phi_uu_per_rad_per_m;
        out.premultiplied_frequency_phi = premultiplied_frequency_phi;
        % Compatibility alias: this has the same numerical value as
        % k_x*Phi_k after the explicit cycles/m-to-rad/m conversion above.
        out.premultiplied_k_phi = premultiplied_k_phi;
        out.snapshot_count = spectrum_count;
        out.selected_y_plus_requested = cfg.spatial.selected_y_plus(:);
        out.selected_rows = selected_rows;
        out.selected_y_plus_actual = y_plus(selected_rows);
        out.selected_y_plus_in_range = selected_in_range;
        out.available_y_plus_range = available_y_plus_range;
        out.selection_policy = ['Nearest measured row is retained and explicitly ' ...
            'flagged; no wall-normal extrapolation is performed.'];
        out.selected_curves = premultiplied_frequency_phi(selected_rows, :);
    end
end
