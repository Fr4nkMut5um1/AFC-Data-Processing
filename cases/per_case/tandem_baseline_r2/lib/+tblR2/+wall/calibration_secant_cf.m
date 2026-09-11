function [Cf_calibration_secant, diag] = calibration_secant_cf( ...
        theta, Ue, delta_star, x, x_end, opts)
%CALIBRATION_SECANT_CF 计算用于核对局部Cf积分一致性的下游校准割线。
% 起点固定为80 mm处或其后的第一个实测列。zpg使用theta两点割线；full使用
% 完整动量方程的逐小区间守恒和。调用方必须传入与局部Cf相同的平滑Ue，函数
% 不自行平滑Ue，也不会在Ue/delta_star缺失时静默退回zpg。

if nargin < 6 || isempty(opts)
    opts = struct();
end
if ~isstruct(opts) || ~isscalar(opts)
    error('tblR2:wall:calibration_secant_cf:InvalidOptions', ...
        'opts 必须是标量结构体。');
end
if isfield(opts, 'x_start')
    error('tblR2:wall:calibration_secant_cf:UnsupportedOption', ...
        '不支持 opts.x_start；校准起点固定为 80 mm。');
end
[theta_row, x_row, original_size] = validate_core(theta, x);
if ~isnumeric(x_end) || ~isreal(x_end) || isempty(x_end) || any(~isfinite(x_end(:)))
    error('tblR2:wall:calibration_secant_cf:InvalidEndpoint', ...
        'x_end 必须包含有限实数形式的目标终点。');
end

equation = option_text(opts, 'equation', 'zpg');
if ~ismember(equation, {'zpg', 'full'})
    error('tblR2:wall:calibration_secant_cf:InvalidEquation', ...
        'equation 必须是 ''zpg'' 或 ''full''。');
end
x_start_target = 80;
x_min = option_scalar(opts, 'x_min', 80);
x_max = option_scalar(opts, 'x_max', 328);
if x_min ~= x_start_target || x_max > 328 || x_start_target >= x_max
    error('tblR2:wall:calibration_secant_cf:InvalidDomain', ...
        '要求 x_min = 80 < x_max <= 328 mm。');
end

U_row = optional_matching_vector(Ue, original_size, 'Ue');
delta_row = optional_matching_vector(delta_star, original_size, 'delta_star');
if strcmp(equation, 'full') && (isempty(U_row) || isempty(delta_row))
    error('tblR2:wall:calibration_secant_cf:MissingFullInput', ...
        'full 校准需要同时提供 Ue 和 delta_star。');
end

start_index = find(x_row >= x_start_target & x_row <= x_max, 1, 'first');
if isempty(start_index)
    error('tblR2:wall:calibration_secant_cf:NoStartColumn', ...
        '下游域内不存在位于 80 mm 及其下游的实测列。');
end
if ~isfinite(theta_row(start_index))
    error('tblR2:wall:calibration_secant_cf:InvalidStartData', ...
        '固定的下游起始列包含非有限 theta。');
end

domain_indices = find(x_row >= x_row(start_index) & x_row <= x_max);
required_finite = isfinite(theta_row(domain_indices));
truncated_at_gap = false;
if strcmp(equation, 'full')
    required_finite = required_finite & isfinite(U_row(domain_indices)) & ...
        U_row(domain_indices) > 0 & isfinite(delta_row(domain_indices));
end
% 无论zpg或full，都只允许从80 mm开始的第一段连续有效数据。当前数据最后一个
% 流向站位被明确列为失真点，因此应在该点前正常终止，而不是让整个full计算报错。
first_gap = find(~required_finite, 1, 'first');
if ~isempty(first_gap)
    domain_indices = domain_indices(1:first_gap-1);
    truncated_at_gap = true;
end
if isempty(domain_indices) || domain_indices(1) ~= start_index
    error('tblR2:wall:calibration_secant_cf:NoContinuousDomain', ...
        '从校准起点开始没有连续的下游有效数据段。');
end

out_size = size(x_end);
Cf_calibration_secant = NaN(out_size);
x_end_actual = NaN(out_size);
theta_end = NaN(out_size);
valid = false(out_size);
status = repmat({'unprocessed'}, out_size);
end_index = NaN(out_size);

for k = 1:numel(x_end)
    if x_end(k) < x_row(start_index) || x_end(k) > x_max
        status{k} = 'outside_downstream_domain';
        continue;
    end
    if truncated_at_gap && x_end(k) > x_row(domain_indices(end))
        status{k} = 'outside_continuous_domain';
        continue;
    end
    [~, local_idx] = min(abs(x_row(domain_indices) - x_end(k)));
    idx = domain_indices(local_idx);
    end_index(k) = idx;
    x_end_actual(k) = x_row(idx);
    theta_end(k) = theta_row(idx);
    if idx <= start_index
        status{k} = 'invalid_interval';
        continue;
    end
    if strcmp(equation, 'zpg')
        Cf_calibration_secant(k) = tblR2.wall.secant_cf( ...
            theta_row(start_index), theta_row(idx), x_row(start_index), x_row(idx));
    else
        Cf_calibration_secant(k) = full_conservation_secant( ...
            theta_row, U_row, delta_row, x_row, start_index, idx);
    end
    valid(k) = true;
    status{k} = 'ok';
end

diag = struct();
diag.quantity_name = 'calibration_secant_cf';
diag.Cf_calibration_secant = Cf_calibration_secant;
diag.equation = equation;
if strcmp(equation, 'zpg')
    diag.equation_description = 'ZPG: Cf = 2*dtheta/dx (two-point secant).';
else
    diag.equation_description = [ ...
        'full calibration: interval conservation sum of d(Ue^2*theta) ' ...
        'plus (delta_star/2)*d(Ue^2), using the shared smooth Ue.'];
end
diag.domain = [x_min, x_max];
diag.x_start_target = x_start_target;
diag.start_index = start_index;
diag.x_start_actual = x_row(start_index);
diag.theta_start = theta_row(start_index);
if strcmp(equation, 'full')
    diag.Ue_start = U_row(start_index);
    diag.delta_star_start = delta_row(start_index);
else
    diag.Ue_start = NaN;
    diag.delta_star_start = NaN;
end
diag.x_end_requested = x_end;
diag.end_index = end_index;
diag.x_end_actual = x_end_actual;
diag.theta_end = theta_end;
diag.Ue_end = NaN(out_size);
diag.delta_star_end = NaN(out_size);
full_end = isfinite(end_index) & strcmp(equation, 'full');
for k = find(full_end)
    diag.Ue_end(k) = U_row(end_index(k));
    diag.delta_star_end(k) = delta_row(end_index(k));
end
diag.valid = valid;
diag.status = status;
end

function Cf = full_conservation_secant(theta, Ue, delta_star, x, i0, i1)
%FULL_CONSERVATION_SECANT 对局部完整方程逐网格积分，供quality核对使用。
% 与reader-facing system secant的“仅起终点代表状态”不同，本函数需要比较
% trapz(Cf_local)与完整方程在同一区间的离散积分，因此每个小区间都用Ue^2中值
% 归一化。传入的Ue必须已经是Section 4那一条统一的p平滑外缘速度曲线。
idx = i0:i1;
u2 = Ue(idx).^2;
u2_mid = 0.5 .* (u2(1:end-1) + u2(2:end));
d_u2_theta = diff(u2 .* theta(idx));
d_half_u2 = 0.5 .* diff(u2);
delta_mid = 0.5 .* (delta_star(idx(1:end-1)) + delta_star(idx(2:end)));
half_cf_integral = sum(d_u2_theta ./ u2_mid + delta_mid .* d_half_u2 ./ u2_mid);
Cf = 2 .* half_cf_integral ./ (x(i1) - x(i0));
end

function [theta_row, x_row, original_size] = validate_core(theta, x)
if ~isnumeric(theta) || ~isreal(theta) || ~isvector(theta) || ...
        ~isnumeric(x) || ~isreal(x) || ~isvector(x) || numel(theta) ~= numel(x)
    error('tblR2:wall:calibration_secant_cf:SizeMismatch', ...
        'theta 和 x 必须是长度相同的实数数值向量。');
end
if numel(x) < 2 || any(~isfinite(x(:))) || any(diff(x(:)) <= 0)
    error('tblR2:wall:calibration_secant_cf:InvalidX', ...
        'x 必须是有限且严格递增的向量。');
end
original_size = size(x);
theta_row = theta(:).';
x_row = x(:).';
end

function value = optional_matching_vector(value, target_size, name)
if isempty(value)
    value = [];
    return;
end
if ~isnumeric(value) || ~isreal(value) || ~isvector(value) || ~isequal(size(value), target_size)
    error('tblR2:wall:calibration_secant_cf:SizeMismatch', ...
        '%s 必须为空，或与 x 完全同尺寸。', name);
end
value = value(:).';
end

function value = option_scalar(opts, name, default_value)
if isfield(opts, name)
    value = opts.(name);
else
    value = default_value;
end
if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ~isfinite(value)
    error('tblR2:wall:calibration_secant_cf:InvalidOption', ...
        'opts.%s 必须是有限实数标量。', name);
end
end

function value = option_text(opts, name, default_value)
if isfield(opts, name) && ~isempty(opts.(name))
    value = lower(char(opts.(name)));
else
    value = default_value;
end
end
