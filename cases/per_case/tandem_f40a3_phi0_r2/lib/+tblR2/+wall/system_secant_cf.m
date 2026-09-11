function [Cf_system_secant, diag] = system_secant_cf(theta, x, x_end, opts)
%SYSTEM_SECANT_CF 计算面向用户报告的全系统区间割线Cf。
% =========================================================================
% 【零压梯度口径】
%   Cf_system = 2*(theta_e-theta_s)/(x_e-x_s)
%
% 【考虑沿程压力梯度的端点状态口径】
% 局部动量积分方程为
%   Cf/2 = dtheta/dx + ((2*theta+delta_star)/Ue)*dUe/dx。
% 两边乘以Ue^2后，利用乘积求导可写成
%   (Cf/2)*Ue^2 = d(Ue^2*theta)/dx + (delta_star/2)*d(Ue^2)/dx。
% 对起点s到终点e积分，并以端点平均量构造system secant：
%
%   Cf_system = 2/(x_e-x_s) * [
%       (Ue_e^2*theta_e-Ue_s^2*theta_s)/Ue2_bar
%       + delta_star_bar*(Ue_e^2-Ue_s^2)/(2*Ue2_bar) ]
%
%   Ue2_bar        = (Ue_s^2+Ue_e^2)/2；它是“速度平方的平均”，不是
%                    “平均速度的平方”。
%   第一项          = Delta(Ue^2*theta)/Ue2_bar，表示动量亏损通量的端点变化。
%                    展开d(Ue^2*theta)/dx后，其中已经包含压力项的2*theta部分，
%                    因而绝不能在第二项中再次加入2*theta，否则会重复计算。
%   第二项          = delta_star_bar*Delta(Ue^2)/(2*Ue2_bar)，只补上位移厚度
%                    delta_star对应的剩余压力贡献。逆压梯度Ue_e<Ue_s时该项为负，
%                    顺压梯度时为正，Ue恒定时为零。
%   2/(x_e-x_s)    = 把括号内具有长度量纲的状态变化转换为无量纲平均Cf。
%
% full模式只使用opts中显式传入的同一条p平滑Ue，不会自行平滑，也不会在输入
% 缚失时退回ZPG。range_mean/range_median/multi_mean模式下，theta、Ue和delta_star
% 的起点状态始终使用完全相同的一组源索引，避免不同变量取自不同站位。
% =========================================================================

if nargin < 4 || ~isstruct(opts) || ~isscalar(opts)
    error('tblR2:wall:system_secant_cf:InvalidOptions', ...
        'opts 必须是包含 contamination_x 的标量结构体。');
end
validate_vector_pair(theta, x);
if ~isnumeric(x_end) || ~isreal(x_end) || isempty(x_end) || ...
        any(~isfinite(x_end(:)))
    error('tblR2:wall:system_secant_cf:InvalidEndpoint', ...
        'x_end 必须包含有限实数形式的目标终点。');
end
if ~isfield(opts, 'contamination_x') || isempty(opts.contamination_x)
    contamination_x = [];
else
    contamination_x = validate_range(opts.contamination_x, ...
        'tblR2:wall:system_secant_cf:InvalidContaminationRange');
end

equation = option_text(opts, 'equation', 'zpg');
if ~ismember(equation, {'zpg', 'full'})
    error('tblR2:wall:system_secant_cf:InvalidEquation', ...
        'opts.equation 必须是 ''zpg'' 或 ''full''。');
end

x_row = x(:).';
theta_row = theta(:).';
input_size = size(x);
Ue_row = [];
delta_row = [];
if strcmp(equation, 'full')
    if ~isfield(opts, 'Ue') || ~isfield(opts, 'delta_star')
        error('tblR2:wall:system_secant_cf:MissingFullInput', ...
            ['full 方程的割线求解需要 opts.Ue 和 opts.delta_star；' ...
             '函数不会退回 ZPG。']);
    end
    Ue_row = matching_vector(opts.Ue, input_size, 'Ue');
    delta_row = matching_vector(opts.delta_star, input_size, 'delta_star');
end

if ~isfield(opts, 'upstream_mode') || isempty(opts.upstream_mode)
    mode = 'range_mean';
else
    mode = lower(char(opts.upstream_mode));
end
if ~isfield(opts, 'upstream_range') || isempty(opts.upstream_range)
    upstream_range = [0, 10];
else
    upstream_range = validate_range(opts.upstream_range, ...
        'tblR2:wall:system_secant_cf:InvalidUpstreamRange');
end

finite_state = isfinite(theta_row);
if strcmp(equation, 'full')
    finite_state = finite_state & isfinite(Ue_row) & Ue_row > 0 & ...
        isfinite(delta_row);
end
% 起点除了x位置以外，还要同步得到theta、Ue和delta_star三个状态量。
switch mode
    case {'range_mean', 'range_median'}
        start_requested_contaminated = ranges_overlap_half_open( ...
            upstream_range, contamination_x);
        mask = finite_state & x_row >= upstream_range(1) & ...
            x_row < upstream_range(2);
        if ~any(mask)
            if ~start_requested_contaminated
                error('tblR2:wall:system_secant_cf:NoUpstreamData', ...
                    '[%.6g, %.6g) 内不存在有限的上游状态。', ...
                    upstream_range(1), upstream_range(2));
            end
            x_start_actual = NaN;
            theta_start = NaN;
            Ue_start = NaN;
            delta_start = NaN;
            start_indices = [];
        else
            start_indices = find(mask);
            if strcmp(mode, 'range_mean')
                reducer = @mean;
            else
                reducer = @median;
            end
            x_start_actual = reducer(x_row(start_indices));
            theta_start = reducer(theta_row(start_indices));
            [Ue_start, delta_start] = reduce_full_state( ...
                equation, reducer, Ue_row, delta_row, start_indices);
        end

    case 'fixed'
        if ~isfield(opts, 'x_start') || ~isscalar(opts.x_start) || ...
                ~isfinite(opts.x_start) || ~isreal(opts.x_start)
            error('tblR2:wall:system_secant_cf:MissingFixedStart', ...
                'fixed 模式需要有限标量 opts.x_start。');
        end
        start_requested_contaminated = in_half_open(opts.x_start, contamination_x);
        idx = nearest_index(x_row, finite_state, opts.x_start);
        start_indices = idx;
        x_start_actual = x_row(idx);
        theta_start = theta_row(idx);
        [Ue_start, delta_start] = direct_full_state( ...
            equation, Ue_row, delta_row, idx);

    case 'multi_mean'
        if ~isfield(opts, 'x_start_values') || ...
                ~isnumeric(opts.x_start_values) || ...
                isempty(opts.x_start_values) || ...
                any(~isfinite(opts.x_start_values(:)))
            error('tblR2:wall:system_secant_cf:MissingMultipleStarts', ...
                'multi_mean 模式需要有限的 opts.x_start_values。');
        end
        requested = opts.x_start_values(:).';
        start_requested_contaminated = any(in_half_open(requested, contamination_x));
        start_indices = zeros(size(requested));
        for k = 1:numel(requested)
            start_indices(k) = nearest_index(x_row, finite_state, requested(k));
        end
        start_indices = unique(start_indices, 'stable');
        x_start_actual = mean(x_row(start_indices));
        theta_start = mean(theta_row(start_indices));
        [Ue_start, delta_start] = reduce_full_state( ...
            equation, @mean, Ue_row, delta_row, start_indices);

    otherwise
        error('tblR2:wall:system_secant_cf:InvalidUpstreamMode', ...
            'upstream_mode 必须是 range_mean、range_median、fixed 或 multi_mean。');
end

out_size = size(x_end);
Cf_system_secant = NaN(out_size);
x_end_actual = NaN(out_size);
theta_end = NaN(out_size);
Ue_end = NaN(out_size);
delta_end = NaN(out_size);
Ue2_bar = NaN(out_size);
delta_bar = NaN(out_size);
momentum_flux_state_term = NaN(out_size);
displacement_pressure_term = NaN(out_size);
half_cf_length_sum = NaN(out_size);
valid = false(out_size);
status = repmat({'unprocessed'}, out_size);

start_contaminated = start_requested_contaminated || ...
    any(in_half_open(x_row(start_indices), contamination_x)) || ...
    in_half_open(x_start_actual, contamination_x);
endpoint_requested_contaminated = in_half_open(x_end, contamination_x);
for k = 1:numel(x_end)
    idx = nearest_index(x_row, finite_state, x_end(k));
    x_end_actual(k) = x_row(idx);
    theta_end(k) = theta_row(idx);
    if strcmp(equation, 'full')
        Ue_end(k) = Ue_row(idx);
        delta_end(k) = delta_row(idx);
    end

    if start_contaminated
        status{k} = 'contaminated_start';
    elseif endpoint_requested_contaminated(k) || ...
            in_half_open(x_end_actual(k), contamination_x)
        status{k} = 'contaminated_endpoint';
    elseif x_end_actual(k) <= x_start_actual
        status{k} = 'invalid_interval';
    elseif strcmp(equation, 'zpg')
        Cf_system_secant(k) = tblR2.wall.secant_cf( ...
            theta_start, theta_end(k), x_start_actual, x_end_actual(k));
        momentum_flux_state_term(k) = theta_end(k)-theta_start;
        displacement_pressure_term(k) = 0;
        half_cf_length_sum(k) = momentum_flux_state_term(k);
        valid(k) = true;
        status{k} = 'ok';
    else
        [Cf_system_secant(k), terms] = full_endpoint_secant( ...
            theta_start, theta_end(k), Ue_start, Ue_end(k), ...
            delta_start, delta_end(k), x_start_actual, x_end_actual(k));
        Ue2_bar(k) = terms.Ue2_bar;
        delta_bar(k) = terms.delta_star_bar;
        momentum_flux_state_term(k) = terms.momentum_flux_state_term;
        displacement_pressure_term(k) = terms.displacement_pressure_term;
        half_cf_length_sum(k) = terms.half_cf_length_sum;
        valid(k) = true;
        status{k} = 'ok';
    end
end

diag = struct();
diag.quantity_name = 'system_secant_cf';
diag.Cf_system_secant = Cf_system_secant;
diag.equation = equation;
diag.pressure_gradient_enabled = strcmp(equation, 'full');
diag.upstream_mode = mode;
diag.upstream_range = upstream_range;
diag.start_indices = start_indices;
diag.x_start_actual = x_start_actual;
diag.theta_start = theta_start;
diag.Ue_start = Ue_start;
diag.delta_star_start = delta_start;
diag.x_end_requested = x_end;
diag.x_end_actual = x_end_actual;
diag.theta_end = theta_end;
diag.Ue_end = Ue_end;
diag.delta_star_end = delta_end;
diag.Ue2_bar = Ue2_bar;
diag.delta_star_bar = delta_bar;
diag.momentum_flux_state_term = momentum_flux_state_term;
diag.displacement_pressure_term = displacement_pressure_term;
diag.half_cf_length_sum = half_cf_length_sum;
diag.contamination_x = contamination_x;
diag.valid = valid;
diag.status = status;
if strcmp(equation, 'zpg')
    diag.equation_description = ...
        'ZPG: Cf_system=2*(theta_e-theta_s)/(x_e-x_s).';
else
    diag.equation_description = [ ...
        'full endpoint-state secant: Delta(Ue^2*theta)/Ue2_bar plus ' ...
        'delta_star_bar*Delta(Ue^2)/(2*Ue2_bar); the 2*theta pressure ' ...
        'contribution is already inside Delta(Ue^2*theta).'];
end
end


function [Cf, terms] = full_endpoint_secant( ...
        theta_s, theta_e, Ue_s, Ue_e, delta_s, delta_e, x_s, x_e)
%FULL_ENDPOINT_SECANT 按起终点两状态计算压力修正system secant。
Ue2_bar = 0.5 .* (Ue_s.^2 + Ue_e.^2);
delta_star_bar = 0.5 .* (delta_s + delta_e);
if any(~isfinite(Ue2_bar(:))) || any(Ue2_bar(:) <= 0)
    error('tblR2:wall:system_secant_cf:InvalidFullState', ...
        '终点 Ue^2 平均值必须是有限正数。');
end
momentum_flux_state_term = ...
    (Ue_e.^2 .* theta_e - Ue_s.^2 .* theta_s) ./ Ue2_bar;
displacement_pressure_term = delta_star_bar .* ...
    (Ue_e.^2-Ue_s.^2) ./ (2 .* Ue2_bar);
half_cf_length_sum = momentum_flux_state_term + displacement_pressure_term;
Cf = 2 .* half_cf_length_sum ./ (x_e-x_s);
terms = struct('Ue2_bar', Ue2_bar, ...
    'delta_star_bar', delta_star_bar, ...
    'momentum_flux_state_term', momentum_flux_state_term, ...
    'displacement_pressure_term', displacement_pressure_term, ...
    'half_cf_length_sum', half_cf_length_sum);
end


function [Ue_value, delta_value] = reduce_full_state( ...
        equation, reducer, Ue, delta_star, indices)
if strcmp(equation, 'full')
    Ue_value = reducer(Ue(indices));
    delta_value = reducer(delta_star(indices));
else
    Ue_value = NaN;
    delta_value = NaN;
end
end


function [Ue_value, delta_value] = direct_full_state( ...
        equation, Ue, delta_star, index)
if strcmp(equation, 'full')
    Ue_value = Ue(index);
    delta_value = delta_star(index);
else
    Ue_value = NaN;
    delta_value = NaN;
end
end


function validate_vector_pair(theta, x)
if ~isnumeric(theta) || ~isreal(theta) || ~isvector(theta) || ...
        ~isnumeric(x) || ~isreal(x) || ~isvector(x) || numel(theta) ~= numel(x)
    error('tblR2:wall:system_secant_cf:SizeMismatch', ...
        'theta 和 x 必须是长度相同的实数数值向量。');
end
if numel(x) < 2 || any(~isfinite(x(:))) || any(diff(x(:)) <= 0)
    error('tblR2:wall:system_secant_cf:InvalidX', ...
        'x 必须是有限且严格递增、至少包含两个点的向量。');
end
end


function value = matching_vector(value, target_size, name)
if ~isnumeric(value) || ~isreal(value) || ~isvector(value) || ...
        ~isequal(size(value), target_size)
    error('tblR2:wall:system_secant_cf:SizeMismatch', ...
        'opts.%s 必须与 x 完全同尺寸。', name);
end
value = value(:).';
end


function range = validate_range(value, error_id)
if ~isnumeric(value) || ~isreal(value) || numel(value) ~= 2 || ...
        any(~isfinite(value(:))) || value(2) <= value(1)
    error(error_id, ...
        '区间值必须是有限的 [最小值，最大值]，且最大值大于最小值。');
end
range = reshape(value, 1, 2);
end


function idx = nearest_index(x, allowed, requested)
candidates = find(allowed);
if isempty(candidates)
    error('tblR2:wall:system_secant_cf:NoFiniteData', ...
        '没有可用的有限完整状态列。');
end
[~, local_idx] = min(abs(x(candidates)-requested));
idx = candidates(local_idx);
end


function value = option_text(opts, name, default_value)
if isfield(opts, name) && ~isempty(opts.(name))
    if ~(ischar(opts.(name)) || ...
            (isstring(opts.(name)) && isscalar(opts.(name))))
        error('tblR2:wall:system_secant_cf:InvalidOption', ...
            'opts.%s 必须是文本标量。', name);
    end
    value = lower(char(opts.(name)));
else
    value = default_value;
end
end


function tf = in_half_open(value, range)
if isempty(range)
    tf = false(size(value));
else
    tf = value >= range(1) & value < range(2);
end
end


function tf = ranges_overlap_half_open(left, right)
tf = ~isempty(right) && left(1) < right(2) && right(1) < left(2);
end
