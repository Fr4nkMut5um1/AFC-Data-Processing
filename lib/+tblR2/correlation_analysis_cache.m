function result = correlation_analysis_cache(cache_file, cfg, stats, phase_stats, mean_bl, branch)
%CORRELATION_ANALYSIS_CACHE Temporal, spatial, two-point, and space-time correlations.

if ~ismember(branch, {'total', 'random'})
    error('tblR2:correlation_analysis_cache:InvalidBranch', ...
        'branch 必须是 total 或 random。');
end
if strcmp(branch, 'random') && isempty(phase_stats)
    error('tblR2:correlation_analysis_cache:MissingPhaseStatistics', ...
        'random 相关性需要 phase 统计。');
end

points = cfg.correlations.reference_points_mm;
n_ref = size(points, 1);
J = size(stats.X, 1);
I = size(stats.X, 2);
Y_wall_mm = mean_bl.wall_distance_mm;
if ~isequal(size(Y_wall_mm), size(stats.Y))
    error('tblR2:correlation_analysis_cache:WallGridSizeMismatch', ...
        'mean_bl.wall_distance_mm 必须与统计网格尺寸一致。');
end
n_frames = stats.n_frames;
max_lag = min(n_frames - 1, round(cfg.correlations.max_time_lag_s * cfg.fs));
do_two_point = option_enabled(cfg.correlations, 'two_point', true);
do_space_time = option_enabled(cfg.correlations, 'space_time', true);
do_streamwise = option_enabled(cfg.correlations, 'streamwise', true);
reference_rows = zeros(n_ref, 1);
reference_cols = zeros(n_ref, 1);
probe_u = nan(n_frames, n_ref);
probe_v = nan(n_frames, n_ref);
for ir = 1:n_ref
    distance = hypot(stats.X - points(ir, 1), Y_wall_mm - points(ir, 2));
    [~, linear] = min(distance(:));
    [reference_rows(ir), reference_cols(ir)] = ind2sub([J I], linear);
    probe = tblR2.read_cache_chunk(cache_file, 1:n_frames, ...
        reference_rows(ir), reference_cols(ir), branch, stats, phase_stats);
    probe_u(:, ir) = squeeze(probe.U);
    probe_v(:, ir) = squeeze(probe.V);
end

lag_samples = (0:max_lag)';
lag_seconds = lag_samples ./ cfg.fs;
temporal_cells = cell(n_ref, 1);
two_point_cells = cell(n_ref, 1);
space_time_cells = cell(n_ref, 1);
for ir = 1:n_ref
    u = repair_series(probe_u(:, ir));
    v = repair_series(probe_v(:, ir));
    [ruu_all, lags] = xcorr(u, max_lag, 'coeff');
    [rvv_all, ~] = xcorr(v, max_lag, 'coeff');
    [ruv_all, ~] = xcorr(u, v, max_lag, 'coeff');
    positive = lags >= 0;
    ruu = ruu_all(positive);
    rvv = rvv_all(positive);
    ruv = ruv_all(positive);
    first_zero = find(ruu <= 0, 1);
    if isempty(first_zero)
        first_zero = numel(ruu);
    end
    integral_time = trapz(lag_seconds(1:first_zero), ruu(1:first_zero));
    nfft = min(cfg.temporal.nfft, n_frames);
    window = hann(nfft, 'periodic');
    overlap = floor(cfg.temporal.overlap_fraction * nfft);
    [cross_spectrum, f] = cpsd(u, v, window, overlap, nfft, cfg.fs);
    coherence = mscohere(u, v, window, overlap, nfft, cfg.fs);
    temporal_cells{ir} = struct('requested_point_mm', points(ir, :), ...
        'actual_point_mm', [stats.X(reference_rows(ir), reference_cols(ir)), ...
        Y_wall_mm(reference_rows(ir), reference_cols(ir))], ...
        'lag_samples', lag_samples, 'lag_seconds', lag_seconds, ...
        'Ruu', ruu, 'Rvv', rvv, 'Ruv', ruv, ...
        'integral_time_scale_s', integral_time, ...
        'frequency_hz', f, 'uv_cross_spectrum', cross_spectrum, ...
        'uv_magnitude_squared_coherence', coherence);
    if do_two_point
        two_point_cells{ir} = two_point_map(ir);
    else
        two_point_cells{ir} = struct('enabled', false, ...
            'reason', 'two-point maps disabled in compact r2 configuration');
    end
    if do_space_time
        space_time_cells{ir} = spacetime_map(ir);
    else
        space_time_cells{ir} = struct('enabled', false, ...
            'reason', 'space-time maps disabled in compact r2 configuration');
    end
end
temporal = vertcat(temporal_cells{:});
two_point = vertcat(two_point_cells{:});
space_time = vertcat(space_time_cells{:});

y_plus_profile = mean(mean_bl.y_plus, 2, 'omitnan');
finite_y_plus = y_plus_profile(isfinite(y_plus_profile));
if isempty(finite_y_plus)
    error('tblR2:correlation_analysis_cache:MissingYPlus', ...
        '选定的流向相关性位置没有可用的有限 y+ 坐标。');
end
available_y_plus_range = [min(finite_y_plus), max(finite_y_plus)];
selected_rows = zeros(numel(cfg.correlations.selected_y_plus), 1);
selected_in_range = false(numel(selected_rows), 1);
for i = 1:numel(selected_rows)
    [~, selected_rows(i)] = min(abs( ...
        y_plus_profile - cfg.correlations.selected_y_plus(i)));
    selected_in_range(i) = ...
        cfg.correlations.selected_y_plus(i) >= available_y_plus_range(1) && ...
        cfg.correlations.selected_y_plus(i) <= available_y_plus_range(2);
end
streamwise_cells = cell(numel(selected_rows), 1);
for i = 1:numel(selected_rows)
    if do_streamwise
        row = selected_rows(i);
        reference_col = reference_cols(1);
        streamwise_cells{i} = same_height_streamwise(row, reference_col);
    else
        streamwise_cells{i} = struct('enabled', false, ...
            'reason', 'same-height streamwise maps disabled in compact r2 configuration');
    end
end
streamwise = vertcat(streamwise_cells{:});

external = external_signal_result();
result = struct();
result.branch = branch;
result.reference_rows = reference_rows;
result.reference_cols = reference_cols;
result.temporal = temporal;
result.two_point = two_point;
result.space_time = space_time;
result.streamwise_spatial = streamwise;
result.selected_y_plus_requested = cfg.correlations.selected_y_plus(:);
result.selected_y_plus_actual = y_plus_profile(selected_rows);
result.selected_y_plus_in_range = selected_in_range;
result.available_y_plus_range = available_y_plus_range;
result.selection_policy = ['Nearest measured row is retained and explicitly ' ...
    'flagged; no wall-normal extrapolation is performed.'];
result.external_surface_coherence = external;
result.definition = ['Core output is temporal auto/cross-correlation and internal ' ...
    'u-v cross-spectrum/coherence at declared probes. Two-point, same-height ' ...
    'streamwise, and space-time maps are explicit opt-in products. When enabled, ' ...
    'two-point and space-time coefficients use ' ...
    'pairwise-centred normalization on identical joint-valid samples, which ' ...
    'guarantees a bounded Pearson coefficient when variance is nonzero. ' ...
    'all pairwise statistics use jointly valid samples and no invalid field sample ' ...
    'contributes to a mean.'];
result.enabled_products = struct('temporal', true, 'two_point', do_two_point, ...
    'space_time', do_space_time, 'streamwise', do_streamwise, ...
    'external_signal', ~isempty(strtrim(char(cfg.correlations.external_signal_file))));

    function mapped = same_height_streamwise(row, reference_col)
        line_chunk = tblR2.read_cache_chunk(cache_file, 1:n_frames, ...
            row, 1:I, branch, stats, phase_stats);
        line_u = double(squeeze(line_chunk.U));
        reference = line_u(:, reference_col);
        [Ruu, valid_pair_count] = ...
            pairwise_correlation_columns(reference, line_u);
        delta_x = stats.X(row, :) - stats.X(row, reference_col);
        Ruu(abs(delta_x) > cfg.correlations.max_streamwise_lag_mm) = NaN;
        mapped = struct('row', row, ...
            'y_plus_actual', y_plus_profile(row), ...
            'reference_column', reference_col, ...
            'reference_point_mm', ...
            [stats.X(row, reference_col), Y_wall_mm(row, reference_col)], ...
            'delta_x_mm', delta_x, 'Ruu', Ruu, ...
            'valid_pair_count', valid_pair_count, ...
            'definition', ['Same-height pairwise-centred Pearson correlation: ' ...
            'both signals use this selected row and identical joint-valid samples.']);
    end

    function mapped = two_point_map(reference_index)
        row = reference_rows(reference_index);
        col = reference_cols(reference_index);
        sum_uu = zeros(J, I); sum_u = zeros(J, I);
        sum_uref_uu = zeros(J, I); sum_u2 = zeros(J, I);
        sum_uref2_uu = zeros(J, I); count_uu = zeros(J, I);
        sum_vv = zeros(J, I); sum_v = zeros(J, I);
        sum_vref_vv = zeros(J, I); sum_v2 = zeros(J, I);
        sum_vref2_vv = zeros(J, I); count_vv = zeros(J, I);
        sum_uv = zeros(J, I); sum_v_uv = zeros(J, I);
        sum_uref_uv = zeros(J, I); sum_v2_uv = zeros(J, I);
        sum_uref2_uv = zeros(J, I); count_uv = zeros(J, I);
        q2_sum_u = zeros(J, I);
        q2_sum_v = zeros(J, I);
        q4_sum_u = zeros(J, I);
        q4_sum_v = zeros(J, I);
        q2_count = zeros(J, I);
        q4_count = zeros(J, I);
        for first = 1:cfg.chunk_frames:n_frames
            last = min(n_frames, first + cfg.chunk_frames - 1);
            ids = first:last;
            chunk = tblR2.read_cache_chunk(cache_file, ids, 1:J, 1:I, ...
                branch, stats, phase_stats);
            U = chunk.U;
            V = chunk.V;
            u_ref = U(:, row, col);
            v_ref = V(:, row, col);
            valid_uu = chunk.sampleValid & isfinite(U) & isfinite(u_ref);
            valid_vv = chunk.sampleValid & isfinite(V) & isfinite(v_ref);
            valid_uv = chunk.sampleValid & isfinite(V) & isfinite(u_ref);
            U_uu = double(U); U_uu(~valid_uu) = 0;
            V_vv = double(V); V_vv(~valid_vv) = 0;
            V_uv = double(V); V_uv(~valid_uv) = 0;
            uref_uu = double(u_ref) + zeros(size(valid_uu));
            vref_vv = double(v_ref) + zeros(size(valid_vv));
            uref_uv = double(u_ref) + zeros(size(valid_uv));
            % NaN .* false remains NaN in MATLAB.  Explicit assignment is
            % therefore required so one invalid reference sample cannot
            % contaminate every spatial accumulator.
            uref_uu(~valid_uu) = 0;
            vref_vv(~valid_vv) = 0;
            uref_uv(~valid_uv) = 0;
            count_uu = count_uu + squeeze(sum(valid_uu, 1));
            count_vv = count_vv + squeeze(sum(valid_vv, 1));
            count_uv = count_uv + squeeze(sum(valid_uv, 1));
            sum_u = sum_u + squeeze(sum(U_uu, 1));
            sum_uref_uu = sum_uref_uu + squeeze(sum(uref_uu, 1));
            sum_u2 = sum_u2 + squeeze(sum(U_uu .^ 2, 1));
            sum_uref2_uu = sum_uref2_uu + squeeze(sum(uref_uu .^ 2, 1));
            sum_uu = sum_uu + squeeze(sum(U_uu .* uref_uu, 1));
            sum_v = sum_v + squeeze(sum(V_vv, 1));
            sum_vref_vv = sum_vref_vv + squeeze(sum(vref_vv, 1));
            sum_v2 = sum_v2 + squeeze(sum(V_vv .^ 2, 1));
            sum_vref2_vv = sum_vref2_vv + squeeze(sum(vref_vv .^ 2, 1));
            sum_vv = sum_vv + squeeze(sum(V_vv .* vref_vv, 1));
            sum_v_uv = sum_v_uv + squeeze(sum(V_uv, 1));
            sum_uref_uv = sum_uref_uv + squeeze(sum(uref_uv, 1));
            sum_v2_uv = sum_v2_uv + squeeze(sum(V_uv .^ 2, 1));
            sum_uref2_uv = sum_uref2_uv + squeeze(sum(uref_uv .^ 2, 1));
            sum_uv = sum_uv + squeeze(sum(V_uv .* uref_uv, 1));
            valid = chunk.sampleValid & isfinite(U) & isfinite(V) & ...
                isfinite(u_ref) & isfinite(v_ref);
            q2_event = valid & (u_ref < 0) & (v_ref > 0);
            q4_event = valid & (u_ref > 0) & (v_ref < 0);
            q2_sum_u = q2_sum_u + squeeze(sum(U .* q2_event, 1, 'omitnan'));
            q2_sum_v = q2_sum_v + squeeze(sum(V .* q2_event, 1, 'omitnan'));
            q2_count = q2_count + squeeze(sum(q2_event, 1));
            q4_sum_u = q4_sum_u + squeeze(sum(U .* q4_event, 1, 'omitnan'));
            q4_sum_v = q4_sum_v + squeeze(sum(V .* q4_event, 1, 'omitnan'));
            q4_count = q4_count + squeeze(sum(q4_event, 1));
        end
        Ruu_map = correlation_from_sums(sum_uu, sum_u, sum_uref_uu, ...
            sum_u2, sum_uref2_uu, count_uu);
        Rvv_map = correlation_from_sums(sum_vv, sum_v, sum_vref_vv, ...
            sum_v2, sum_vref2_vv, count_vv);
        Ruv_map = correlation_from_sums(sum_uv, sum_v_uv, sum_uref_uv, ...
            sum_v2_uv, sum_uref2_uv, count_uv);
        mapped = struct('Ruu', Ruu_map, ...
            'Rvv', Rvv_map, ...
            'Ruv', Ruv_map, ...
            'valid_count', count_uu, ...
            'valid_count_uu', count_uu, ...
            'valid_count_vv', count_vv, ...
            'valid_count_uv', count_uv, ...
            'Q2_conditional_U', q2_sum_u ./ max(q2_count, 1), ...
            'Q2_conditional_V', q2_sum_v ./ max(q2_count, 1), ...
            'Q2_event_count', q2_count, ...
            'Q4_conditional_U', q4_sum_u ./ max(q4_count, 1), ...
            'Q4_conditional_V', q4_sum_v ./ max(q4_count, 1), ...
            'Q4_event_count', q4_count, ...
            'normalization', ['pairwise-centred Pearson coefficient: ' ...
            'cross moment and both variances use the identical joint-valid samples']);
    end

    function mapped = spacetime_map(reference_index)
        row = reference_rows(reference_index);
        col = reference_cols(reference_index);
        line_chunk = tblR2.read_cache_chunk(cache_file, 1:n_frames, ...
            row, 1:I, branch, stats, phase_stats);
        line_u = squeeze(line_chunk.U);
        reference = line_u(:, col);
        R = nan(max_lag + 1, I);
        pair_count = zeros(max_lag + 1, I);
        for lag = 0:max_lag
            a = reference(1:n_frames - lag);
            b = line_u(1 + lag:n_frames, :);
            [R(lag + 1, :), pair_count(lag + 1, :)] = ...
                pairwise_correlation_columns(a, b);
        end
        x_line = stats.X(row, :);
        outside_requested_lag = abs(x_line - x_line(col)) > ...
            cfg.correlations.max_streamwise_lag_mm;
        R(:, outside_requested_lag) = NaN;
        ridge_x = nan(max_lag + 1, 1);
        ridge_value = nan(max_lag + 1, 1);
        for lag = 1:max_lag
            downstream = x_line > x_line(col);
            values = R(lag + 1, :);
            values(~downstream) = -Inf;
            [ridge_value(lag + 1), index] = max(values, [], 'omitnan');
            if isfinite(ridge_value(lag + 1))
                ridge_x(lag + 1) = x_line(index) - x_line(col);
            end
        end
        fit_mask = lag_seconds > 0 & isfinite(ridge_x) & ...
            ridge_value >= cfg.correlations.ridge_min_correlation;
        if nnz(fit_mask) >= 2
            coefficient = polyfit(lag_seconds(fit_mask), ...
                ridge_x(fit_mask) .* 1e-3, 1);
            Uc_ridge = coefficient(1);
            if ~(isfinite(Uc_ridge) && Uc_ridge > 0)
                Uc_ridge = NaN;
                ridge_status = 'rejected_nonpositive_fitted_velocity';
            else
                ridge_status = 'accepted';
            end
        else
            Uc_ridge = NaN;
            ridge_status = 'insufficient_points_above_correlation_threshold';
        end
        mapped = struct('lag_seconds', lag_seconds, ...
            'delta_x_mm', x_line - x_line(col), 'Ruu', R, ...
            'valid_pair_count', pair_count, ...
            'ridge_delta_x_mm', ridge_x, ...
            'ridge_correlation', ridge_value, ...
            'ridge_fit_mask', fit_mask, ...
            'ridge_fit_point_count', nnz(fit_mask), ...
            'ridge_min_correlation', cfg.correlations.ridge_min_correlation, ...
            'ridge_status', ridge_status, ...
            'convection_velocity_ridge_mps', Uc_ridge, ...
            'normalization', ['pairwise-centred Pearson coefficient at each ' ...
            'lag and streamwise column using identical joint-valid samples']);
    end

    function external = external_signal_result()
        filename = char(cfg.correlations.external_signal_file);
        if isempty(strtrim(filename))
            external = struct('status', 'not_available', ...
                'reason', ['No synchronized external surface signal was declared; ' ...
                'external coherence is not fabricated.']);
            return;
        end
        if ~isfile(filename)
            error('tblR2:correlation_analysis_cache:MissingExternalSignal', ...
                '声明的外部信号文件不存在：%s', filename);
        end
        loaded = load(filename);
        if ~isfield(loaded, 'signal') || ~isfield(loaded, 'fs')
            error('tblR2:correlation_analysis_cache:InvalidExternalSignal', ...
                '外部 MAT 文件必须包含 signal 和 fs 变量。');
        end
        if loaded.fs ~= cfg.fs || numel(loaded.signal) < n_frames
            error('tblR2:correlation_analysis_cache:UnsynchronizedExternalSignal', ...
                ['外部信号必须已经按 cfg.fs 完成同步，且至少包含 cfg.n_frames 个样本。']);
        end
        u = repair_series(probe_u(:, 1));
        signal = double(loaded.signal(1:n_frames));
        nfft = min(cfg.temporal.nfft, n_frames);
        if ~any(isfinite(signal))
            error('tblR2:correlation_analysis_cache:EmptyExternalSignal', ...
                '声明的外部信号不包含任何有限样本，无法计算相干性。');
        end
        if nnz(isfinite(signal)) < min(nfft, n_frames)
            error('tblR2:correlation_analysis_cache:TooFewExternalSamples', ...
                ['声明的外部信号有限样本数（%d）少于 Welch 分块所需数量（%d），' ...
                 '不会伪造相干性结果。'], ...
                nnz(isfinite(signal)), min(nfft, n_frames));
        end
        window = hann(nfft, 'periodic');
        overlap = floor(cfg.temporal.overlap_fraction * nfft);
        [coherence, f] = mscohere(u, signal, window, overlap, nfft, cfg.fs);
        external = struct('status', 'computed', 'source_file', filename, ...
            'frequency_hz', f, 'coherence', coherence);
    end
end


function correlation = correlation_from_sums( ...
        sum_xy, sum_x, sum_y, sum_x2, sum_y2, count)
safe_count = max(count, 1);
cross = sum_xy - sum_x .* sum_y ./ safe_count;
energy_x = sum_x2 - sum_x .^ 2 ./ safe_count;
energy_y = sum_y2 - sum_y .^ 2 ./ safe_count;
energy_x = max(energy_x, 0);
energy_y = max(energy_y, 0);
denominator = sqrt(energy_x .* energy_y);
valid = count >= 2 & isfinite(cross) & isfinite(denominator) & ...
    denominator > eps(max(energy_x, energy_y));
correlation = nan(size(sum_xy));
correlation(valid) = cross(valid) ./ denominator(valid);
correlation(valid) = max(-1, min(1, correlation(valid)));
end


function [correlation, count] = pairwise_correlation_columns(reference, field)
reference = double(reference(:));
field = double(field);
valid = isfinite(field) & isfinite(reference);
x = field;
x(~valid) = 0;
y = reference + zeros(size(valid));
y(~valid) = 0;
count = sum(valid, 1);
sum_x = sum(x, 1);
sum_y = sum(y, 1);
sum_x2 = sum(x .^ 2, 1);
sum_y2 = sum(y .^ 2, 1);
sum_xy = sum(x .* y, 1);
correlation = correlation_from_sums( ...
    sum_xy, sum_x, sum_y, sum_x2, sum_y2, count);
end

function signal = repair_series(signal)
finite = isfinite(signal);
if nnz(finite) < 3
    error('tblR2:correlation_analysis_cache:InvalidProbe', ...
        '参考探针的有限样本少于三个。');
end
if any(~finite)
    signal = fillmissing(signal, 'linear', 'EndValues', 'nearest');
end
signal = detrend(signal, 'constant');
end

function value = option_enabled(settings, name, default_value)
value = default_value;
if isstruct(settings) && isfield(settings, name) && ~isempty(settings.(name))
    value = logical(settings.(name));
end
end
