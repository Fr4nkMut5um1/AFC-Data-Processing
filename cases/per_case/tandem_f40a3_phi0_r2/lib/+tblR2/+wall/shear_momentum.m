function [tau_w, diag] = shear_momentum(theta, Uinf_local, x, rho, nu, delta_star, opts)
%SHEAR_MOMENTUM 用动量积分方程计算沿程局部Cf和壁面剪切应力。
%   零压梯度（equation='zpg'）：
%       Cf = 2*dtheta/dx
%       tau_w = rho*Ue^2*dtheta/dx
%
%   考虑沿程压力梯度（equation='full'）：
%       Cf/2 = dtheta/dx + ((2*theta+delta_star)/Ue)*dUe/dx
%       tau_w = rho*[Ue^2*dtheta/dx +
%                    Ue*dUe/dx*(2*theta+delta_star)]
%
%   full模式下，Uinf_local参数必须已经是Section 4独立得到的p平滑Ue，且
%   opts.Ue_derivative必须是同一条csaps样条的精确导数。函数不会在内部再次
%   平滑Ue，也不会在缺少导数时静默退回零压梯度公式。
%
%   Inputs theta, delta_star, and x use mm. Derivative unit conversions
%   cancel. The formal local curve exists only in 80 <= x <= 328 mm (or a
%   caller-selected subdomain). The first invalid point terminates the only
%   admissible contiguous downstream run.
%
%   opts.theta_source controls where the theta curve comes from:
%   shared_thickness_p_smooth      - reuse the same p/gap smoothing contract
%                                    as Figure 5(c), including its exact
%                                    csaps derivative;
%   independent_downstream_p_smooth - legacy behavior: independently fit
%                                    theta only inside the local-Cf domain.

if nargin < 7 || ~isstruct(opts) || ~isscalar(opts)
    error('tblR2:wall:shear_momentum:MissingPreSmoothP', ...
        '必须显式提供 opts.pre_smooth_p；传入 [] 才表示显式关闭平滑。');
end
if ~isfield(opts, 'pre_smooth_p')
    error('tblR2:wall:shear_momentum:MissingPreSmoothP', ...
        '必须显式提供 opts.pre_smooth_p；传入 [] 才表示显式关闭平滑。');
end

[theta_row, U_row, x_row, input_size] = validate_inputs(theta, Uinf_local, x, rho, nu);

if ~isfield(opts, 'equation') || isempty(opts.equation)
    equation = 'zpg';
else
    equation = lower(char(opts.equation));
end
if ~ismember(equation, {'zpg', 'full'})
    error('tblR2:wall:shear_momentum:InvalidEquation', ...
        'opts.equation 必须是 ''zpg'' 或 ''full''。');
end

p = opts.pre_smooth_p;
if ~(isempty(p) || (isnumeric(p) && isreal(p) && isscalar(p) && ...
        isfinite(p) && p >= 0 && p <= 1))
    error('tblR2:wall:shear_momentum:InvalidPreSmoothP', ...
        'opts.pre_smooth_p 必须为 [] 或 [0,1] 内的有限标量。');
end

theta_source = parse_theta_source(opts);
shared_theta_diag = struct();
shared_theta_row = NaN(size(theta_row));
shared_dtheta_dx = NaN(size(theta_row));
if strcmp(theta_source, 'shared_thickness_p_smooth')
    if isempty(p)
        error('tblR2:wall:shear_momentum:SharedThetaRequiresP', ...
            ['shared_thickness_p_smooth 需要有限的 pre_smooth_p；' ...
             '不能与 pre_smooth_p=[] 同时使用。']);
    end
    if ~all(isfield(opts, {'gap_mode', 'contamination_x'}))
        error('tblR2:wall:shear_momentum:MissingSharedThetaOptions', ...
            ['shared_thickness_p_smooth 需要 opts.gap_mode 和 ' ...
             'opts.contamination_x。']);
    end
    shared_opts = struct('gap_mode', opts.gap_mode, ...
        'contamination_x', opts.contamination_x);
    [shared_theta, shared_theta_diag] = ...
        tblR2.wall.smooth_streamwise_series(theta, x, p, shared_opts);
    shared_theta_row = shared_theta(:).';
    shared_dtheta_dx = shared_theta_diag.derivative(:).';
end

[x_min, x_max] = parse_domain(opts);

if strcmp(equation, 'full')
    if nargin < 6 || isempty(delta_star)
        error('tblR2:wall:shear_momentum:MissingDeltaStar', ...
            'full 方程需要 delta_star，且不会退回 ZPG。');
    end
    if ~isnumeric(delta_star) || ~isreal(delta_star) || ~isvector(delta_star) || ...
            ~isequal(size(delta_star), input_size)
        error('tblR2:wall:shear_momentum:SizeMismatch', ...
            '对于 full 方程，delta_star 必须与 x 完全同尺寸。');
    end
    delta_row = delta_star(:).';
    if ~isfield(opts, 'Ue_derivative') || ...
            ~isnumeric(opts.Ue_derivative) || ~isreal(opts.Ue_derivative) || ...
            ~isvector(opts.Ue_derivative) || ...
            ~isequal(size(opts.Ue_derivative), input_size)
        error('tblR2:wall:shear_momentum:MissingEdgeVelocityDerivative', ...
            ['full 方程需要与 x 完全同尺寸的 opts.Ue_derivative；' ...
             '函数内部不会再次平滑 Ue。']);
    end
    Ue_derivative_row = opts.Ue_derivative(:).';
    if ~isfield(opts, 'Ue_pre_smooth_p') || ...
            ~isnumeric(opts.Ue_pre_smooth_p) || ...
            ~isreal(opts.Ue_pre_smooth_p) || ...
            ~isscalar(opts.Ue_pre_smooth_p) || ...
            ~isfinite(opts.Ue_pre_smooth_p) || ...
            opts.Ue_pre_smooth_p < 0 || opts.Ue_pre_smooth_p > 1
        error('tblR2:wall:shear_momentum:MissingEdgeVelocityP', ...
            'full 方程需要 [0,1] 内的有限 opts.Ue_pre_smooth_p。');
    end
else
    if nargin >= 6 && ~isempty(delta_star)
        if ~isnumeric(delta_star) || ~isreal(delta_star) || ~isvector(delta_star) || ...
                ~isequal(size(delta_star), input_size)
            error('tblR2:wall:shear_momentum:SizeMismatch', ...
                'delta_star 必须为空，或与 x 完全同尺寸。');
        end
        delta_row = delta_star(:).';
    else
        delta_row = [];
    end
    Ue_derivative_row = [];
end

n = numel(x_row);
in_domain = x_row >= x_min & x_row <= x_max;
theta_valid_source = theta_row;
if strcmp(theta_source, 'shared_thickness_p_smooth')
    theta_valid_source = shared_theta_row;
end
valid = in_domain & isfinite(theta_valid_source) & ...
    isfinite(U_row) & U_row > 0;
if strcmp(equation, 'full')
    valid = valid & isfinite(delta_row) & isfinite(Ue_derivative_row);
end

[segment_start, segment_end] = contiguous_runs(valid);
long_enough = segment_end - segment_start + 1 >= 2;
segment_start = segment_start(long_enough);
segment_end = segment_end(long_enough);
domain_start = find(in_domain, 1, 'first');
first_run = find(segment_start == domain_start, 1, 'first');
if isempty(first_run)
    error('tblR2:wall:shear_momentum:InsufficientDomainData', ...
        '给定域内的第一列必须在 [%.6g, %.6g] mm 内开启至少包含两个点的有效连续段。', ...
        x_min, x_max);
end
segment_start = segment_start(first_run);
segment_end = segment_end(first_run);

theta_smooth = NaN(1, n);
U_smooth = NaN(1, n);
dtheta_dx = NaN(1, n);
dU_dx = NaN(1, n);
fit_segments = NaN(numel(segment_start), 2);

for s = 1:numel(segment_start)
    idx = segment_start(s):segment_end(s);
    fit_segments(s, :) = [x_row(idx(1)), x_row(idx(end))];
    if strcmp(theta_source, 'shared_thickness_p_smooth')
        % theta值和导数直接来自Figure 5(c)同口径的csaps，不进行二次平滑。
        theta_smooth(idx) = shared_theta_row(idx);
        dtheta_dx(idx) = shared_dtheta_dx(idx);
    elseif isempty(p)
        theta_smooth(idx) = theta_row(idx);
        dtheta_dx(idx) = local_gradient(theta_row(idx), x_row(idx));
    else
        [theta_smooth(idx), dtheta_dx(idx)] = strict_spline_derivative( ...
            theta_row(idx), x_row(idx), p, 'theta', s);
    end

    if strcmp(equation, 'full')
        % Ue及其导数来自Section 4预先构造的同一条全流向样条；这里不二次平滑。
        U_smooth(idx) = U_row(idx);
        dU_dx(idx) = Ue_derivative_row(idx);
    elseif isempty(p)
        U_smooth(idx) = U_row(idx);
        dU_dx(idx) = local_gradient(U_row(idx), x_row(idx));
    else
        [U_smooth(idx), dU_dx(idx)] = strict_spline_derivative( ...
            U_row(idx), x_row(idx), p, 'Uinf_local', s);
    end
end

growth_term = rho .* U_smooth.^2 .* dtheta_dx;
tau_zpg = growth_term;
pressure_term = NaN(1, n);
Cf_local = NaN(1, n);

if strcmp(equation, 'zpg')
    tau_row = tau_zpg;
    Cf_local(valid) = 2 .* dtheta_dx(valid);
    equation_description = 'ZPG: Cf = 2*dtheta/dx; tau = rho*Ue^2*dtheta/dx.';
else
    pressure_term = rho .* U_smooth .* dU_dx .* (2 .* theta_smooth + delta_row);
    tau_row = growth_term + pressure_term;
    Cf_local(valid) = 2 .* (dtheta_dx(valid) + ...
        ((2 .* theta_smooth(valid) + delta_row(valid)) ./ U_smooth(valid)) .* dU_dx(valid));
    equation_description = ['full: Cf/2 = dtheta/dx + ' ...
        '((2*theta+delta_star)/Ue)*dUe/dx; Ue and dUe/dx share one external spline.'];
end

% Singleton valid points do not belong to a fitted run and stay NaN.
computed = isfinite(dtheta_dx) & isfinite(U_smooth);
if strcmp(equation, 'full')
    computed = computed & isfinite(dU_dx) & isfinite(delta_row);
end
tau_row(~computed) = NaN;
Cf_local(~computed) = NaN;

tau_w = reshape(tau_row, input_size);
diag = struct();
diag.equation = equation;
diag.equation_description = equation_description;
diag.domain = [x_min, x_max];
diag.x_min = x_min;
diag.x_max = x_max;
diag.pre_smooth_p = p;
diag.p = p;
diag.theta_source = theta_source;
if strcmp(theta_source, 'shared_thickness_p_smooth')
    diag.theta_source_description = ...
        'theta and dtheta/dx reuse the shared thickness p-smoothing curve.';
    diag.theta_source_smoothing = shared_theta_diag;
else
    diag.theta_source_description = ...
        'theta is independently p-smoothed inside the local-Cf domain.';
    diag.theta_source_smoothing = struct( ...
        'gap_mode', 'local_domain_only', ...
        'fit_segments_x', fit_segments, ...
        'method', 'independent downstream csaps/fnder');
end
diag.Cf_local = reshape(Cf_local, input_size);
diag.tau_w_raw = tau_w;
diag.tau_w_zpg_raw = reshape(tau_zpg, input_size);
diag.dtheta_dx = reshape(dtheta_dx, input_size);
diag.dU_dx = reshape(dU_dx, input_size);
diag.growth_term = reshape(growth_term, input_size);
diag.pressure_term = reshape(pressure_term, input_size);
diag.theta_smooth = reshape(theta_smooth, input_size);
diag.Uinf_local_smooth = reshape(U_smooth, input_size);
if strcmp(equation, 'full')
    diag.Ue_pre_smooth_p = opts.Ue_pre_smooth_p;
    diag.Ue_derivative_is_external = true;
    if isfield(opts, 'Ue_source_description')
        diag.Ue_source_description = opts.Ue_source_description;
    else
        diag.Ue_source_description = ...
            'Externally prepared smooth Ue and derivative from one csaps spline.';
    end
else
    diag.Ue_pre_smooth_p = p;
    diag.Ue_derivative_is_external = false;
    diag.Ue_source_description = ...
        'Legacy ZPG path: Uinf_local is smoothed inside the local-Cf domain.';
end
diag.x = x;
diag.theta = theta;
diag.Uinf_local = Uinf_local;
diag.delta_star = delta_star;
diag.valid_mask = reshape(computed, input_size);
diag.fit_segments = fit_segments;
diag.pre_smoothing_applied = ~isempty(p);
if isempty(p)
    diag.pre_smoothing_message = 'Explicitly disabled by pre_smooth_p=[].';
else
    diag.pre_smoothing_message = '';
end
% Retained compatibility diagnostics: no post-fit smoothing or edge trim.
diag.edge_trim_n = 0;
diag.smoothing_applied = false;
diag.smoothing_message = 'Post-fit smoothing is not applied.';
end

function source = parse_theta_source(opts)
if ~isfield(opts, 'theta_source') || isempty(opts.theta_source)
    % 保留旧调用者的历史行为；正式单case脚本会始终显式传入该选项。
    source = 'independent_downstream_p_smooth';
elseif ischar(opts.theta_source) || ...
        (isstring(opts.theta_source) && isscalar(opts.theta_source))
    source = lower(char(opts.theta_source));
else
    error('tblR2:wall:shear_momentum:InvalidThetaSource', ...
        'opts.theta_source 必须是文本标量。');
end
if ~ismember(source, {'shared_thickness_p_smooth', ...
        'independent_downstream_p_smooth'})
    error('tblR2:wall:shear_momentum:InvalidThetaSource', ...
        ['opts.theta_source 必须是 ''shared_thickness_p_smooth'' 或 ' ...
         '''independent_downstream_p_smooth''。']);
end
end

function [theta_row, U_row, x_row, input_size] = validate_inputs(theta, Ue, x, rho, nu)
if ~isnumeric(theta) || ~isreal(theta) || ~isvector(theta) || ...
        ~isnumeric(Ue) || ~isreal(Ue) || ~isvector(Ue) || ...
        ~isnumeric(x) || ~isreal(x) || ~isvector(x) || ...
        ~isequal(size(theta), size(Ue), size(x))
    error('tblR2:wall:shear_momentum:SizeMismatch', ...
        'theta、Uinf_local 和 x 必须是尺寸相同的实数数值向量。');
end
if numel(x) < 2 || any(~isfinite(x(:))) || any(diff(x(:)) <= 0)
    error('tblR2:wall:shear_momentum:InvalidX', ...
        'x 必须是有限且严格递增的向量。');
end
if ~isnumeric(rho) || ~isreal(rho) || ~isscalar(rho) || ~isfinite(rho) || rho <= 0
    error('tblR2:wall:shear_momentum:InvalidRho', 'rho 必须是有限正数标量。');
end
if ~isnumeric(nu) || ~isreal(nu) || ~isscalar(nu) || ~isfinite(nu) || nu <= 0
    error('tblR2:wall:shear_momentum:InvalidNu', 'nu 必须是有限正数标量。');
end
input_size = size(x);
theta_row = theta(:).';
U_row = Ue(:).';
x_row = x(:).';
end

function [x_min, x_max] = parse_domain(opts)
if isfield(opts, 'domain') && ~isempty(opts.domain)
    if ~isnumeric(opts.domain) || ~isreal(opts.domain) || numel(opts.domain) ~= 2
        error('tblR2:wall:shear_momentum:InvalidDomain', ...
            'opts.domain 必须是 [x_min, x_max]。');
    end
    domain = reshape(opts.domain, 1, 2);
    x_min = domain(1);
    x_max = domain(2);
else
    if isfield(opts, 'x_min'), x_min = opts.x_min; else, x_min = 80; end
    if isfield(opts, 'x_max'), x_max = opts.x_max; else, x_max = 328; end
end
if ~isnumeric(x_min) || ~isnumeric(x_max) || ~isreal(x_min) || ~isreal(x_max) || ...
        ~isscalar(x_min) || ~isscalar(x_max) || ~isfinite(x_min) || ~isfinite(x_max) || ...
        x_min < 80 || x_max > 328 || x_max <= x_min
    error('tblR2:wall:shear_momentum:InvalidDomain', ...
        'local-Cf 计算域必须满足 80 <= x_min < x_max <= 328 mm。');
end
end

function [starts, ends] = contiguous_runs(mask)
edges = diff([false, mask, false]);
starts = find(edges == 1);
ends = find(edges == -1) - 1;
end

function df = local_gradient(f, x)
n = numel(f);
df = NaN(size(f));
if n == 2
    slope = (f(2) - f(1)) ./ (x(2) - x(1));
    df(:) = slope;
    return;
end
df(1) = (f(2) - f(1)) ./ (x(2) - x(1));
df(end) = (f(end) - f(end-1)) ./ (x(end) - x(end-1));
df(2:end-1) = (f(3:end) - f(1:end-2)) ./ (x(3:end) - x(1:end-2));
end

function [y_smooth, dy_dx] = strict_spline_derivative(y, x, p, field_name, segment_number)
try
    pp = csaps(x, y, p);
    dpp = fnder(pp, 1);
    y_smooth = reshape(fnval(pp, x), 1, []);
    dy_dx = reshape(fnval(dpp, x), 1, []);
catch ME
    error('tblR2:wall:shear_momentum:SplineFailure', ...
        '在连续段 %d 中对 %s 执行 csaps/fnder 失败（p=%.17g）：%s', ...
        segment_number, field_name, p, ME.message);
end
if any(~isfinite(y_smooth)) || any(~isfinite(dy_dx))
    error('tblR2:wall:shear_momentum:SplineFailure', ...
        'csaps/fnder 在连续段 %d 中返回了非有限的 %s 值（p=%.17g）。', ...
        segment_number, field_name, p);
end
end
