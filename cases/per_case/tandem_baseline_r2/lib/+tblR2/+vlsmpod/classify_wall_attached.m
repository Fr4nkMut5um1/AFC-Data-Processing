function T = classify_wall_attached(T, ctx, options)
%CLASSIFY_WALL_ATTACHED 追加 wall-attached 分类列（Hwang & Sung 2018, JFM 思路）。
%
% 判据用外尺度，不是原论文的内尺度 y_min+≈0
% ----------------------------------------------
% 本数据的第一行有效行在 y+ = 33.7（dy=0.515mm, u_tau=0.9675 m/s, nu=1.48e-5），
% 缓冲层（y+<30）整个落在测量域之外，内尺度判据 y_min+≈0 恒为空集，无法使用。
%
% 改用外尺度：YMin_over_delta = YMin_mm / Delta99Ref_mm。物理含义是「结构根部
% 处于对数区下缘」，不依赖 u_tau 标定精度，阈值可事后重设而不必重跑识别（连续列
% YMin_plus / YMin_over_delta 都保留，IsWallAttached 只是对其中一列的二值化）。
%
% **这不是 Hwang & Sung 的内尺度 attached 分类，两者不可直接对标。**
%
% 输入
%   T       : identify_structures/identify_frame 输出的 structures 表
%   ctx     : tblR2.vlsmpod.prepare_context 的输出（用 u_tau/nu 算 YMin_plus）
%   options : 结构体，.attached_delta_threshold 默认 0.05
%
% 输出：T 追加 4 列 YMin_plus / YMin_over_delta / IsWallAttached /
%       AttachedDeltaThreshold

if nargin < 3 || isempty(options); options = struct(); end
threshold = 0.05;
if isfield(options, 'attached_delta_threshold') && ...
        ~isempty(options.attached_delta_threshold)
    threshold = options.attached_delta_threshold;
end

nrows = height(T);
if nrows == 0
    T = add_empty_columns(T, threshold);
    return;
end

y_min_over_delta = T.YMin_mm ./ T.Delta99Ref_mm;

y_min_plus = nan(nrows, 1);
if isfinite(ctx.u_tau) && isfinite(ctx.nu) && ctx.nu > 0
    y_min_plus = (T.YMin_mm * 1e-3) * ctx.u_tau / ctx.nu;
end

is_attached = y_min_over_delta < threshold;

T = addvars(T, y_min_plus, y_min_over_delta, is_attached, ...
    repmat(threshold, nrows, 1), 'NewVariableNames', ...
    {'YMin_plus', 'YMin_over_delta', 'IsWallAttached', 'AttachedDeltaThreshold'});
end

% =========================================================================
function T = add_empty_columns(T, threshold)
T.YMin_plus = zeros(0, 1);
T.YMin_over_delta = zeros(0, 1);
T.IsWallAttached = false(0, 1);
T.AttachedDeltaThreshold = zeros(0, 1); %#ok<NASGU>
T.AttachedDeltaThreshold = repmat(threshold, 0, 1);
end
