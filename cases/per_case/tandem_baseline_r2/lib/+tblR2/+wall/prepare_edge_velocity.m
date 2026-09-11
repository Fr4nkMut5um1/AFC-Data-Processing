function edge = prepare_edge_velocity(Uavex, X, n_top, p)
%PREPARE_EDGE_VELOCITY 从原始平均速度场独立提取并平滑沿程外缘速度Ue。
% =========================================================================
% 【为什么需要独立计算Ue】
% 边界层厚度BL来自用于阻力积分的S_drag；该统计场会把10--80 mm污染区整列
% 屏蔽，因此BL.Uinf_local在污染区内没有数值。沿程压力梯度却必须使用完整流向
% 范围的外缘速度，所以本函数必须直接读取仅屏蔽污染矩形的S.Uavex，不能从
% S_drag或BL.Uinf_local回填。
%
% 【计算口径】
% 1. 每个流向列先剔除0和NaN，再调用tblR2.bl.local_uinf，以与Section 2/3相同的
%    “最高n_top个有效速度的均值”定义原始Ue；
% 2. 数组开头的无效段、开头第一个有限站位、末尾最后一个有限站位以及其后的
%    尾段全部列入edge_exclusion_mask。列本身不删除，x坐标也不移动；
% 3. 使用其余全部有限Ue一次性拟合csaps。10--80 mm的外缘速度本身有效，必须
%    作为拟合样本参与，不能套用厚度曲线的污染区排除规则；
% 4. Ue_smooth和dUe_dx由同一个样条pp及其一阶导数fnder(pp,1)得到，避免先后
%    两次拟合造成数值口径不一致；
% 5. 首尾被排除位置在raw/smooth/derivative中都保留原索引并写为NaN。
%
% 【输入】
% Uavex : J×I时间平均流向速度场，单位m/s，来自S.Uavex；
% X      : 与Uavex同尺寸的流向坐标，单位mm；
% n_top  : 每列估计Ue时使用的有效高速点数；
% p      : Ue专用csaps平滑参数，范围[0,1]。
%
% 【输出edge的主要字段】
% raw             : 原始Ue，首尾排除位置为NaN；
% smooth          : p平滑后的Ue，首尾排除位置为NaN；
% derivative      : 同一条样条的dUe/dx，单位(m/s)/mm；
% fit_mask        : 实际参与样条拟合的原始Ue位置；
% interpolated_mask: 原始Ue无效但由样条在内部补值的位置；
% edge_exclusion_mask: 首尾失真位置；所有数组均保持I列。
% =========================================================================

if ~isnumeric(Uavex) || ~isreal(Uavex) || ~ismatrix(Uavex) || ...
        ~isnumeric(X) || ~isreal(X) || ~isequal(size(Uavex), size(X)) || ...
        size(Uavex, 2) < 4
    error('tblR2:wall:prepare_edge_velocity:InvalidField', ...
        'Uavex 和 X 必须是尺寸相同的实数矩阵，且至少包含四列。');
end
if ~isnumeric(n_top) || ~isreal(n_top) || ~isscalar(n_top) || ...
        ~isfinite(n_top) || n_top < 1 || n_top ~= fix(n_top)
    error('tblR2:wall:prepare_edge_velocity:InvalidNTop', ...
        'n_top 必须是有限正整数。');
end
if ~isnumeric(p) || ~isreal(p) || ~isscalar(p) || ...
        ~isfinite(p) || p < 0 || p > 1
    error('tblR2:wall:prepare_edge_velocity:InvalidP', ...
        'p 必须是 [0,1] 内的有限标量。');
end

x = reshape(X(1, :), 1, []);
if any(~isfinite(x)) || any(diff(x) <= 0)
    error('tblR2:wall:prepare_edge_velocity:InvalidX', ...
        'X(1,:) 必须是有限且严格递增的坐标。');
end

% 逐列提取原始Ue。这里故意不使用S_drag，确保10--80 mm的有效外缘速度保留。
n_x = numel(x);
raw_unmasked = NaN(1, n_x);
for col = 1:n_x
    u_column = Uavex(:, col);
    u_valid = u_column(isfinite(u_column) & u_column ~= 0);
    raw_unmasked(col) = tblR2.bl.local_uinf(u_valid, n_top);
end
raw_unmasked(~isfinite(raw_unmasked) | raw_unmasked <= 0) = NaN;

finite_raw = isfinite(raw_unmasked);
first_finite = find(finite_raw, 1, 'first');
last_finite = find(finite_raw, 1, 'last');
if isempty(first_finite) || isempty(last_finite) || last_finite-first_finite < 2
    error('tblR2:wall:prepare_edge_velocity:InsufficientData', ...
        '执行边缘排除前至少需要三个有序且有限的 Ue 站位。');
end

% 保留全部列，但把开头无效段+首个有限站位、末个有限站位+尾段统一置NaN。
% 对当前636列真实数据，这一规则对应源索引1--3和636。
edge_exclusion_mask = false(1, n_x);
edge_exclusion_mask(1:first_finite) = true;
edge_exclusion_mask(last_finite:end) = true;
fit_mask = finite_raw & ~edge_exclusion_mask;
if nnz(fit_mask) < 2
    error('tblR2:wall:prepare_edge_velocity:InsufficientFitData', ...
        '排除边缘站位后剩余的有限 Ue 站位少于两个。');
end

fit_indices = find(fit_mask);
evaluation_mask = ~edge_exclusion_mask & ...
    x >= x(fit_indices(1)) & x <= x(fit_indices(end));
evaluation_indices = find(evaluation_mask);
try
    pp = csaps(x(fit_mask), raw_unmasked(fit_mask), p);
    dpp = fnder(pp, 1);
    smooth = NaN(1, n_x);
    derivative = NaN(1, n_x);
    smooth(evaluation_indices) = reshape( ...
        fnval(pp, x(evaluation_indices)), 1, []);
    derivative(evaluation_indices) = reshape( ...
        fnval(dpp, x(evaluation_indices)), 1, []);
catch ME
    error('tblR2:wall:prepare_edge_velocity:SplineFailure', ...
        '对 Ue 执行 csaps/fnder 失败（p=%.17g）：%s', p, ME.message);
end
if any(~isfinite(smooth(evaluation_indices))) || ...
        any(~isfinite(derivative(evaluation_indices))) || ...
        any(smooth(evaluation_indices) <= 0)
    error('tblR2:wall:prepare_edge_velocity:SplineFailure', ...
        'Ue 样条在评估范围内返回了非有限或非正值。');
end

raw = raw_unmasked;
raw(edge_exclusion_mask) = NaN;
interpolated_mask = evaluation_mask & ~finite_raw;

edge = struct();
edge.schema_version = 1;
edge.quantity_name = 'streamwise_edge_velocity';
edge.x = x;
edge.raw = raw;
edge.raw_before_edge_exclusion = raw_unmasked;
edge.smooth = smooth;
edge.derivative = derivative;
edge.p = p;
edge.n_top = n_top;
edge.fit_mask = fit_mask;
edge.evaluation_mask = evaluation_mask;
edge.interpolated_mask = interpolated_mask;
edge.edge_exclusion_mask = edge_exclusion_mask;
edge.first_finite_source_index = first_finite;
edge.last_finite_source_index = last_finite;
edge.excluded_source_indices = find(edge_exclusion_mask);
edge.excluded_x_mm = x(edge_exclusion_mask);
edge.source_description = [ ...
    'S.Uavex columnwise tblR2.bl.local_uinf; all valid x including 10--80 mm; ' ...
    'one global csaps/fnder fit; edge columns retained as NaN.'];
edge.derivative_units = '(m/s)/mm';
end
