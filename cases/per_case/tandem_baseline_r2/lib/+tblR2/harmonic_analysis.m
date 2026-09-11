function result = harmonic_analysis(phase_stats, cfg, stats, mean_bl)
%HARMONIC_ANALYSIS First three harmonics of phase-coherent velocity fields.
% =========================================================================
% 【合同（Section 8 harmonics 的受控分支）】
%   - 输入：Section 3 的 phase_stats（u_coherent/v_coherent 为 n_bins×J×I）、
%     cfg.phase（f0_hz、phi0_user_deg）、stats.X、mean_bl 的 y_plus 与
%     wall_distance_mm。
%   - 对每个相位箱沿箱序号做 DFT：U_fft=fft(u_coherent,[],1)/n_bins；
%     第 ih 次谐波幅值 A=2*|C(ih+1)|，相对相位为 C(ih+1) 的辐角（deg），
%     即 cos 约定下的相位滞后：u~A*cos(ih*phi - phase_deg*pi/180)。
%   - phi0_user_deg 为空：机械相位保持 NaN；非空时机械相位 =
%     wrap180(相对相位 - ih*phi0)（与 bin 中心机械相位定义一致）。
%   - selected_y_plus 行选择：取最接近的实测行并显式标记是否在可用范围内，
%     不做法向插值。
% =========================================================================

if isempty(phase_stats) || ~isfield(phase_stats, 'u_coherent')
    error('tblR2:harmonic_analysis:MissingPhaseStatistics', ...
        '谐波图需要 controlled 工况的相位统计结果。');
end
n_bins = size(phase_stats.u_coherent, 1);
n_harmonics = min(3, floor((n_bins - 1) / 2));
U_fft = fft(phase_stats.u_coherent, [], 1) ./ n_bins;
V_fft = fft(phase_stats.v_coherent, [], 1) ./ n_bins;
J = size(stats.X, 1);
I = size(stats.X, 2);
u_amplitude = nan(n_harmonics, J, I);
v_amplitude = nan(n_harmonics, J, I);
u_phase_relative_deg = nan(n_harmonics, J, I);
v_phase_relative_deg = nan(n_harmonics, J, I);
u_phase_mechanical_deg = nan(n_harmonics, J, I);
v_phase_mechanical_deg = nan(n_harmonics, J, I);

for ih = 1:n_harmonics
    coefficient_u = U_fft(ih + 1, :, :);
    coefficient_v = V_fft(ih + 1, :, :);
    u_amplitude(ih, :, :) = 2 .* abs(coefficient_u);
    v_amplitude(ih, :, :) = 2 .* abs(coefficient_v);
    u_phase_relative_deg(ih, :, :) = rad2deg(angle(coefficient_u));
    v_phase_relative_deg(ih, :, :) = rad2deg(angle(coefficient_v));
    if ~isempty(cfg.phase.phi0_user_deg)
        u_phase_mechanical_deg(ih, :, :) = ...
            wrap180(reshape(u_phase_relative_deg(ih, :, :), 1, J, I) - ...
            ih .* cfg.phase.phi0_user_deg);
        v_phase_mechanical_deg(ih, :, :) = ...
            wrap180(reshape(v_phase_relative_deg(ih, :, :), 1, J, I) - ...
            ih .* cfg.phase.phi0_user_deg);
    end
end

y_plus_profile = mean(mean_bl.y_plus, 2, 'omitnan');
finite_y_plus = y_plus_profile(isfinite(y_plus_profile));
if isempty(finite_y_plus)
    error('tblR2:harmonic_analysis:MissingYPlus', ...
        '谐波流向曲线没有可用的有限 y+ 坐标。');
end
available_y_plus_range = [min(finite_y_plus), max(finite_y_plus)];
requested = cfg.correlations.selected_y_plus(:);
selected_rows = zeros(numel(requested), 1);
selected_in_range = false(numel(requested), 1);
for i = 1:numel(requested)
    [~, selected_rows(i)] = min(abs(y_plus_profile - requested(i)));
    selected_in_range(i) = requested(i) >= available_y_plus_range(1) && ...
        requested(i) <= available_y_plus_range(2);
end

result = struct();
result.harmonic_number = (1:n_harmonics)';
result.frequency_hz = (1:n_harmonics)' .* cfg.phase.f0_hz;
result.u_amplitude_mps = u_amplitude;
result.v_amplitude_mps = v_amplitude;
result.u_phase_relative_deg = u_phase_relative_deg;
result.v_phase_relative_deg = v_phase_relative_deg;
result.u_phase_mechanical_deg = u_phase_mechanical_deg;
result.v_phase_mechanical_deg = v_phase_mechanical_deg;
result.selected_y_plus_requested = requested;
result.selected_rows = selected_rows;
result.selected_y_plus_actual = y_plus_profile(selected_rows);
result.selected_y_plus_in_range = selected_in_range;
result.available_y_plus_range = available_y_plus_range;
result.selection_policy = ['Nearest measured row is retained and explicitly ' ...
    'flagged; no wall-normal extrapolation is performed.'];
result.streamwise_u_amplitude = u_amplitude(:, selected_rows, :);
result.streamwise_v_amplitude = v_amplitude(:, selected_rows, :);
result.X_mm = stats.X;
result.Y_mm = mean_bl.wall_distance_mm;
result.Y_source_mm = stats.Y;
result.definition = ['Discrete Fourier coefficients of the native relative-phase ' ...
    'means. Reported relative phase is the DFT coefficient angle in degrees ' ...
    '(cos convention, u~A*cos(ih*phi - phase_deg)). Mechanical-phase angles are ' ...
    'populated only when phi0_user_deg is provided; no data-driven phase ' ...
    'recovery is performed.'] ;
end

function value = wrap180(value)
value = mod(value + 180, 360) - 180;
end
