function result = temporal_spectra_cache(cache_file, cfg, stats, phase_stats, mean_bl, branch)
%TEMPORAL_SPECTRA_CACHE Welch PSD at each x, then average PSD across x.
% =========================================================================
% 【Section 6 时域谱合同】
%   - 严格"各 x 先 PSD、再平均 PSD"：每条 u'(t) 经共享
%     tblR2.spectra.welch_series 修复（fillmissing linear + EndValues
%     nearest，低有效率整条排除）+ detrend + pwelch 得到单点 PSD，
%     再在 cfg.temporal.x_interval_mm 内对 PSD 取平均。绝无先平均信号。
%   - 频带 cfg.temporal.frequency_band_hz 只对 Welch 频率箱做切片选择，
%     不调用时域 bandpass，保留箱内 PSD 数值不变。
%   - Taylor 换算只用于 lambda_x_plus：Uc 是 cfg.temporal.Uc 的显式
%     profile_fraction 设置（含近壁 Uc+ 覆盖），不静默替换成 Ue；
%     f*Phi_f/u_tau^2 = lambda*Phi_lambda/u_tau^2 由换元公式保证。
% =========================================================================

if ~ismember(branch, {'total', 'random'})
    error('tblR2:temporal_spectra_cache:InvalidBranch', ...
        'branch 必须是 total 或 random。');
end
if strcmp(branch, 'random') && isempty(phase_stats)
    error('tblR2:temporal_spectra_cache:MissingPhaseStatistics', ...
        'controlled random 分支需要 phase 统计。');
end
if exist('pwelch', 'file') ~= 2
    error('tblR2:temporal_spectra_cache:MissingToolbox', ...
        '时频分析需要信号处理工具箱中的 pwelch 函数。');
end

x = stats.X(1, :);
Y_wall_mm = mean_bl.wall_distance_mm;
if ~isequal(size(Y_wall_mm), size(stats.Y))
    error('tblR2:temporal_spectra_cache:WallGridSizeMismatch', ...
        'mean_bl.wall_distance_mm 必须与统计网格尺寸一致。');
end
cols = find(x >= cfg.temporal.x_interval_mm(1) & ...
    x <= cfg.temporal.x_interval_mm(2));
if isempty(cols)
    error('tblR2:temporal_spectra_cache:EmptyInterval', ...
        'cfg.temporal.x_interval_mm 内没有可用的流向网格列。');
end
J = size(stats.X, 1);
n_frames = stats.n_frames;
nfft = cfg.temporal.nfft;
window = hann(nfft, 'periodic');
noverlap = floor(cfg.temporal.overlap_fraction * nfft);
[~, frequency_full] = pwelch(zeros(n_frames, 1), window, noverlap, nfft, cfg.fs);
frequency_mask = frequency_full > 0 & ...
    frequency_full >= cfg.temporal.frequency_band_hz(1) & ...
    frequency_full <= cfg.temporal.frequency_band_hz(2);
frequency = frequency_full(frequency_mask);
if isempty(frequency)
    error('tblR2:temporal_spectra_cache:EmptyFrequencyBand', ...
        '声明的时域频带内没有 Welch 频率箱。');
end

phi_by_x = nan(J, numel(frequency), numel(cols), 'single');
valid_fraction_by_x = nan(J, numel(cols));
repaired_sample_count = zeros(J, numel(cols));
column_batch = max(1, min(8, numel(cols)));
for first_col = 1:column_batch:numel(cols)
    local = first_col:min(numel(cols), first_col + column_batch - 1);
    col_ids = cols(local);
    chunk = tblR2.read_cache_chunk(cache_file, 1:n_frames, ...
        1:J, col_ids, branch, stats, phase_stats);
    series = reshape(chunk.U, n_frames, []);
    finite = isfinite(series);
    valid_fraction = sum(finite, 1) ./ n_frames;
    valid_fraction_by_x(:, local) = reshape( ...
        valid_fraction, J, numel(col_ids));
    repaired_sample_count(:, local) = reshape( ...
        sum(~finite, 1), J, numel(col_ids));
    [phi_full, f_checked] = tblR2.spectra.welch_series( ...
        series, window, noverlap, nfft, cfg.fs, cfg.temporal.min_valid_fraction);
    if numel(f_checked) ~= numel(frequency_full) || ...
            max(abs(f_checked - frequency_full)) > 100 * eps(cfg.fs)
        error('tblR2:temporal_spectra_cache:WelchGridMismatch', ...
            'pwelch 返回的频率网格与预期不一致。');
    end
    phi_grid = phi_full(frequency_mask, :);
    phi_by_x(:, :, local) = single(permute( ...
        reshape(phi_grid, numel(frequency), J, numel(col_ids)), [2 1 3]));
end

phi_mean = mean(double(phi_by_x), 3, 'omitnan');
u_tau = mean_bl.normalization.u_tau;
inner_length_m = cfg.nu / u_tau;
U_profile = mean(stats.Uavex(:, cols), 2, 'omitnan');
Uc = cfg.temporal.Uc.fraction .* U_profile;
n_nearwall = min(J, cfg.temporal.Uc.nearwall_n);
if n_nearwall > 0
    Uc(1:n_nearwall) = cfg.temporal.Uc.nearwall_plus .* u_tau;
end
valid_uc = isfinite(Uc) & Uc > 0;
lambda_m = nan(J, numel(frequency));
lambda_m(valid_uc, :) = Uc(valid_uc) ./ frequency';
lambda_plus = lambda_m ./ inner_length_m;
premultiplied_f = phi_mean .* frequency' ./ (u_tau ^ 2);
% Preserve energy under the frequency-to-wavelength change of variables:
% f*Phi_f/u_tau^2 = lambda*Phi_lambda/u_tau^2, with
% Phi_lambda = Phi_f*|df/dlambda| = Phi_f*Uc/lambda^2.
phi_lambda = phi_mean .* Uc ./ (lambda_m .^ 2);
premultiplied_lambda = phi_lambda .* lambda_m ./ (u_tau ^ 2);

result = struct();
result.branch = branch;
result.frequency_hz = frequency;
result.phi_uu_mean_across_x = phi_mean;
result.phi_uu_by_x = phi_by_x;
result.premultiplied_f_phi_over_utau2 = premultiplied_f;
result.phi_uu_per_wavelength_m = phi_lambda;
result.premultiplied_lambda_phi_over_utau2 = premultiplied_lambda;
% Compatibility alias retained for early plot consumers. Its value now
% follows the correct logarithmic-band invariant above.
result.premultiplied_phi_over_lambda = premultiplied_lambda;
result.lambda_x_plus = lambda_plus;
result.y_plus = mean(mean_bl.y_plus(:, cols), 2, 'omitnan');
result.wall_distance_mm = mean(Y_wall_mm(:, cols), 2, 'omitnan');
result.Uc_mps = Uc;
result.uc_method = cfg.temporal.Uc.method;
result.min_valid_fraction = cfg.temporal.min_valid_fraction;
result.x_columns = cols;
result.x_mm = x(cols);
result.valid_fraction_by_x = valid_fraction_by_x;
result.repaired_sample_count = repaired_sample_count;
result.nfft = nfft;
result.df_hz = cfg.fs / nfft;
result.order_of_operations = ['Welch PSD is computed independently for every ' ...
    'valid u(t) at each x and y; PSDs are then averaged across the declared ' ...
    'x interval. Signals are never averaged before PSD.'];
result.taylor_scope = ['Taylor conversion is used only for lambda_x_plus in ' ...
    'this temporal product. Uc is the explicit profile_fraction setting; ' ...
    'Ue is not substituted silently.'];
result.change_of_variables = ['Frequency and wavelength pre-multiplied levels ' ...
    'satisfy f*Phi_f/u_tau^2 = lambda*Phi_lambda/u_tau^2.'];
end
