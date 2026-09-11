function fit = composite_profile_fit_rodriguez_lopez( ...
        u_profile, y_reference_mm, nu, Uinf_arg, h_mm, options, option_a)
%COMPOSITE_PROFILE_FIT_RODRIGUEZ_LOPEZ Constrained modern Clauser fit.
% Option B follows the composite-profile framework of Rodriguez-Lopez,
% Bruce and Buxton (2015, Exp. Fluids 56:68, doi:10.1007/s00348-015-1935-5):
% Musker's inner law, the Monkewitz bump, and the Coles--Chauhan wake are
% fitted to the complete measured mean profile.  This implementation keeps
% the wall location and ZPG kappa--B pair fixed because the present PIV
% profiles need not include a y+ < 10 point; it therefore estimates only
% [u_tau, Pi, delta].  It must not be described as the paper's free
% five-parameter wall-location fit.

if nargin < 7 || isempty(option_a)
    option_a = struct();
end
options = resolve_options(options, h_mm);
positive_input_scalar(nu, 'nu');
positive_input_scalar(Uinf_arg, 'Uinf_arg');
positive_input_scalar(h_mm, 'h_mm');

u_profile = double(u_profile(:));
y_reference_mm = double(y_reference_mm(:));
if numel(u_profile) ~= numel(y_reference_mm)
    error('tblR2:bl:composite_profile_fit_rodriguez_lopez:ProfileSizeMismatch', ...
        'u_profile 和 y_reference_mm 必须包含相同数量的点。');
end
valid = isfinite(u_profile) & isfinite(y_reference_mm) & ...
    u_profile > 0 & y_reference_mm > 0;
u_mps = u_profile(valid);
y_reference_mm = y_reference_mm(valid);
valid_point_count = numel(u_mps);
if valid_point_count - options.skip_nearwall < options.minimum_points
    error('tblR2:bl:composite_profile_fit_rodriguez_lopez:InsufficientProfilePoints', ...
        ['B 方案有 %d 个有限正剖面点，但跳过 %d 个近壁点后将少于所需的 %d 个点。'], ...
        valid_point_count, options.skip_nearwall, options.minimum_points);
end
excluded_u_mps = u_mps(1:options.skip_nearwall);
excluded_y_reference_mm = y_reference_mm(1:options.skip_nearwall);
u_mps = u_mps(options.skip_nearwall + 1:end);
y_reference_mm = y_reference_mm(options.skip_nearwall + 1:end);
if numel(u_mps) < options.minimum_points
    error('tblR2:bl:composite_profile_fit_rodriguez_lopez:InsufficientProfilePoints', ...
        'B 方案至少需要 %d 个有限正剖面点。', ...
        options.minimum_points);
end

% The global wall grid uses option A's reference offset.  Option B carries
% its own fixed offset, so a B-only sensitivity change cannot alter option A.
reference_dy_h = field_or(option_a, 'dy_h_opt', options.dy_h);
y_mm = y_reference_mm + (options.dy_h - reference_dy_h) .* h_mm;
excluded_y_mm = excluded_y_reference_mm + ...
    (options.dy_h - reference_dy_h) .* h_mm;
if any(y_mm <= 0)
    error('tblR2:bl:composite_profile_fit_rodriguez_lopez:InvalidWallOffset', ...
        'B 方案的 dy_h 使一个或多个保留点落在壁面上或壁面以下。');
end

Uinf_used = tblR2.bl.local_uinf(u_mps, options.U_inf_n_top);
if abs(Uinf_used - Uinf_arg) / max(abs(Uinf_arg), eps) > 0.05
    fprintf(['    modern Clauser: profile-top Uinf=%.4f differs from input ' ...
             'Uinf=%.4f by more than 5%%.\n'], Uinf_used, Uinf_arg);
end

[u_tau_initial, delta_initial_mm] = initial_scales( ...
    u_mps, y_mm, nu, Uinf_used, option_a);
u_tau_bounds = options.u_tau_scale_bounds .* u_tau_initial;
delta_bounds_mm = options.delta_scale_bounds .* delta_initial_mm;
pi_bounds = options.pi_bounds;
if u_tau_bounds(1) <= 0 || delta_bounds_mm(1) <= 0
    error('tblR2:bl:composite_profile_fit_rodriguez_lopez:InvalidBounds', ...
        'B 方案的尺度下界必须严格为正。');
end

% Build the Musker inner-law lookup once.  In the published method it is
% obtained by Euler marching; the configurable step controls only numerical
% quadrature precision, not the physical model.
max_yplus = max([y_mm; delta_bounds_mm(2)]) .* 1e-3 .* ...
    u_tau_bounds(2) ./ nu .* 1.05;
lookup_point_count = floor(max_yplus ./ options.inner_step_yplus) + 1;
if lookup_point_count > 5e6
    error('tblR2:bl:composite_profile_fit_rodriguez_lopez:InnerLookupTooLarge', ...
        ['请求的 Musker 查找表将包含 %.0f 个点。请增大 inner_step_yplus，' ...
         '或收紧尺度边界。'], lookup_point_count);
end
inner = build_inner_lookup(max_yplus, options.kappa, options.B, ...
    options.inner_step_yplus);

theta0 = encode_parameters(u_tau_initial, options.pi_initial, ...
    delta_initial_mm, u_tau_bounds, pi_bounds, delta_bounds_mm);
objective = @(theta) composite_objective(theta, u_mps, y_mm, nu, ...
    options, inner, u_tau_bounds, pi_bounds, delta_bounds_mm);
optim_options = optimset('Display', 'off', ...
    'MaxIter', options.max_iterations, ...
    'MaxFunEvals', options.max_function_evaluations, ...
    'TolX', options.tolerance, 'TolFun', options.tolerance);
[theta_opt, ~, exitflag, optimizer_output] = ...
    fminsearch(objective, theta0, optim_options);
[u_tau, Pi, delta_mm] = decode_parameters(theta_opt, u_tau_bounds, ...
    pi_bounds, delta_bounds_mm);
[objective_value, model] = composite_objective(theta_opt, u_mps, y_mm, nu, ...
    options, inner, u_tau_bounds, pi_bounds, delta_bounds_mm);

fit = struct();
fit.option = 'B';
fit.method = 'Rodriguez-Lopez_Bruce_Buxton_2015_constrained_bump1';
fit.reference = struct( ...
    'authors', 'Rodriguez-Lopez, Bruce and Buxton', ...
    'year', 2015, ...
    'journal', 'Experiments in Fluids', ...
    'doi', '10.1007/s00348-015-1935-5', ...
    'model', 'Musker inner law + Monkewitz bump + Coles-Chauhan wake');
fit.identifiability = struct( ...
    'fitted_parameters', {{'u_tau', 'Pi', 'delta'}}, ...
    'fixed_parameters', {{'dy_h', 'kappa', 'B'}}, ...
    'reason', ['The five-parameter method requires at least one y+ < 10 ' ...
               'point to robustly identify the wall location; the current ' ...
               'Section 2 configuration therefore fixes dy_h.']);
fit.enabled = true;
fit.data_selection = struct( ...
    'rule', 'finite positive points followed by configured near-wall exclusion', ...
    'input_point_count', numel(u_profile), ...
    'valid_point_count_before_skip', valid_point_count, ...
    'skip_nearwall', options.skip_nearwall, ...
    'fitted_point_count', numel(u_mps), ...
    'reason', ['The configured first retained point(s) are excluded from the ' ...
               'fit because wall reflections make their measured velocity unreliable.']);
fit.n_skip = options.skip_nearwall;
fit.n_points = numel(u_mps);
fit.converged = exitflag > 0 && isfinite(objective_value);
fit.exitflag = exitflag;
fit.optimizer = struct('algorithm', 'fminsearch_bounded_transform', ...
    'iterations', optimizer_output.iterations, ...
    'function_count', optimizer_output.funcCount, ...
    'message', optimizer_output.message, 'theta', theta_opt);
fit.objective = struct('name', 'Rodriguez-Lopez_E1_mean_relative_error', ...
    'value', objective_value, 'relative_rmse', ...
    sqrt(mean(model.relative_residual .^ 2)), ...
    'velocity_rmse_mps', sqrt(mean((model.u_model_mps - u_mps) .^ 2)));
fit.u_tau = u_tau;
fit.Cf = 2 .* (u_tau ./ Uinf_used) .^ 2;
fit.Re_tau = delta_mm .* 1e-3 .* u_tau ./ nu;
fit.Pi = Pi;
fit.delta_mm = delta_mm;
fit.kappa = options.kappa;
fit.B = options.B;
fit.dy_h = options.dy_h;
fit.dy_mm = options.dy_h .* h_mm;
fit.reference_dy_h = reference_dy_h;
fit.Uinf_used = Uinf_used;
fit.Uinf_input = Uinf_arg;
fit.Uinf_relative_difference = abs(Uinf_used - Uinf_arg) ./ abs(Uinf_arg);
fit.nu = nu;
fit.y_mm = y_mm;
fit.u_mps = u_mps;
fit.y_plus = model.y_plus;
fit.u_plus_exp = u_mps ./ u_tau;
fit.u_plus_model = model.u_plus;
fit.u_model_mps = model.u_model_mps;
fit.relative_residual = model.relative_residual;
fit.excluded_nearwall = struct( ...
    'u_mps', excluded_u_mps, ...
    'y_reference_mm', excluded_y_reference_mm, ...
    'y_mm', excluded_y_mm, ...
    'y_plus', excluded_y_mm .* 1e-3 .* u_tau ./ nu, ...
    'u_plus_exp', excluded_u_mps ./ u_tau, ...
    'reason', 'wall-reflection-contaminated; displayed for audit only');
fit.bounds = struct('u_tau_mps', u_tau_bounds, 'Pi', pi_bounds, ...
    'delta_mm', delta_bounds_mm);
fit.at_bounds = struct( ...
    'u_tau', is_near_bound(u_tau, u_tau_bounds), ...
    'Pi', is_near_bound(Pi, pi_bounds), ...
    'delta', is_near_bound(delta_mm, delta_bounds_mm));
fit.initial = struct('u_tau_mps', u_tau_initial, ...
    'Pi', options.pi_initial, 'delta_mm', delta_initial_mm);
fit.options = options;
warnings = {};
if ~fit.converged
    warnings{end + 1} = ['Option B optimisation did not report convergence; ' ...
        'inspect the objective, bounds, and composite-profile figure before use.'];
end
bound_names = fieldnames(fit.at_bounds);
active_bounds = bound_names(structfun(@(value) value, fit.at_bounds));
if ~isempty(active_bounds)
    warnings{end + 1} = sprintf( ...
        ['Option B parameter(s) near a configured bound: %s. Treat the fit ' ...
         'as bound-sensitive and inspect the composite-profile figure.'], ...
        strjoin(active_bounds, ', '));
end
if fit.Uinf_relative_difference > 0.05
    warnings{end + 1} = sprintf( ...
        'Profile-top Uinf differs from input Uinf by %.1f%%.', ...
        100 .* fit.Uinf_relative_difference);
end
fit.warning = strjoin(warnings, ' ');
if ~isempty(fit.warning)
    fprintf('    modern Clauser warning: %s\n', fit.warning);
end

fprintf(['modern Clauser Option B [Rodriguez-Lopez 2015]: u_tau=%.4f m/s, ' ...
    'Cf=%.5f, Pi=%.3f, delta=%.2f mm, E1=%.4g\n'], ...
    fit.u_tau, fit.Cf, fit.Pi, fit.delta_mm, fit.objective.value);
end


function [value, model] = composite_objective(theta, u_mps, y_mm, nu, ...
        options, inner, u_tau_bounds, pi_bounds, delta_bounds_mm)
[u_tau, Pi, delta_mm] = decode_parameters(theta, u_tau_bounds, pi_bounds, ...
    delta_bounds_mm);
model = evaluate_composite(y_mm, u_tau, Pi, delta_mm, nu, options, inner);
relative_residual = (model.u_model_mps - u_mps) ./ ...
    max(abs(model.u_model_mps), 1e-9);
relative_residual(~isfinite(relative_residual)) = 1e6;
model.relative_residual = relative_residual;
value = mean(abs(relative_residual));
if ~isfinite(value)
    value = 1e6;
end
end


function model = evaluate_composite(y_mm, u_tau, Pi, delta_mm, nu, options, inner)
y_plus = y_mm .* 1e-3 .* u_tau ./ nu;
eta = y_mm ./ delta_mm;
u_inner = interp1(inner.y_plus, inner.u_plus, y_plus, 'pchip', 'extrap');
u_bump = bump_profile(y_plus, options.enable_bump);
eta_inner = min(max(eta, 0), 1);
wake = chauhan_wake_term(eta_inner, Pi, options.kappa);
u_plus = u_inner + u_bump + wake;

% Beyond delta the Coles composite profile uses the edge velocity reached
% at eta=1, rather than extending the wake formula beyond its definition.
y_plus_delta = delta_mm .* 1e-3 .* u_tau ./ nu;
u_edge = interp1(inner.y_plus, inner.u_plus, y_plus_delta, 'pchip', 'extrap') + ...
    bump_profile(y_plus_delta, options.enable_bump) + 2 .* Pi ./ options.kappa;
u_plus(eta > 1) = u_edge;
model = struct('y_plus', y_plus, 'u_plus', u_plus, ...
    'u_model_mps', u_tau .* u_plus);
end


function inner = build_inner_lookup(max_yplus, kappa, B, step)
% Musker (1979) equation as reproduced by Rodriguez-Lopez et al. (2015):
% dU+/dy+ = (y+^2/kappa + 1/s)/(y+^3 + y+^2/kappa + 1/s).
s = solve_musker_s(kappa, B);
y_plus = (0:step:max_yplus)';
derivative = ((y_plus .^ 2) ./ kappa + 1 ./ s) ./ ...
    (y_plus .^ 3 + (y_plus .^ 2) ./ kappa + 1 ./ s);
u_plus = cumtrapz(y_plus, derivative);
inner = struct('y_plus', y_plus, 'u_plus', u_plus, 's', s);
end


function s = solve_musker_s(kappa, B_target)
% The integration constant s is chosen so the Musker profile has the
% configured asymptotic intercept B.  This keeps kappa and B as the
% documented ZPG pair rather than fitting a correlated pair to this profile.
target = B_target;
residual = @(log_s) musker_intercept(exp(log_s), kappa) - target;
grid = linspace(log(1e-6), log(1e6), 81);
values = arrayfun(residual, grid);
crossing = find(values(1:end-1) .* values(2:end) <= 0, 1, 'first');
if isempty(crossing)
    [~, index] = min(abs(values));
    s = exp(grid(index));
else
    s = exp(fzero(residual, [grid(crossing), grid(crossing + 1)]));
end
end


function value = musker_intercept(s, kappa)
y_max = 2e4;
derivative = @(y_plus) ((y_plus .^ 2) ./ kappa + 1 ./ s) ./ ...
    (y_plus .^ 3 + (y_plus .^ 2) ./ kappa + 1 ./ s);
u_plus = integral(derivative, 0, y_max, ...
    'AbsTol', 1e-9, 'RelTol', 1e-8, 'ArrayValued', true);
value = u_plus - log(y_max) ./ kappa;
end


function value = bump_profile(y_plus, enabled)
if ~enabled
    value = zeros(size(y_plus));
    return;
end
M1 = 30;
M2 = 2.85;
safe_y_plus = max(y_plus, realmin('double'));
% Rodriguez-Lopez et al. (2015), Eq. (2): the entire exponential is
% divided by M2.  M2 is the inverse peak amplitude, not a Gaussian-width
% multiplier.
value = exp(-(log(safe_y_plus ./ M1) .^ 2)) ./ M2;
value(y_plus <= 0) = 0;
end


function value = chauhan_wake_term(eta, Pi, kappa)
% Chauhan, Monkewitz and Nagib (2009) exponential wake used by the
% Rodriguez-Lopez composite profile.  Algebraically combining 2*Pi/kappa
% with W(eta) avoids a singular expression when Pi is close to zero.
a2 = 132.8410;
a3 = -166.2041;
a4 = 71.9114;
q = 0.25 .* (5 .* a2 + 6 .* a3 + 7 .* a4) .* eta .^ 4 - ...
    a2 .* eta .^ 5 - a3 .* eta .^ 6 - a4 .* eta .^ 7;
q1 = 0.25 .* (a2 + 2 .* a3 + 3 .* a4);
base = (1 - exp(-q)) ./ (1 - exp(-q1));
safe_eta = max(eta, realmin('double'));
value = base .* (2 .* Pi - log(safe_eta)) ./ kappa;
value(eta <= 0) = 0;
end


function [u_tau_initial, delta_initial_mm] = initial_scales( ...
        u_mps, y_mm, nu, Uinf, option_a)
u_tau_initial = field_or(option_a, 'u_tau', NaN);
if ~(isfinite(u_tau_initial) && u_tau_initial > 0)
    u_tau_initial = max(0.02 .* Uinf, sqrt(nu .* Uinf ./ max(y_mm .* 1e-3)));
end
delta_initial_mm = field_or(option_a, 'delta99', NaN);
if ~(isfinite(delta_initial_mm) && delta_initial_mm > 0)
    first = find(u_mps >= 0.99 .* Uinf, 1, 'first');
    if isempty(first)
        delta_initial_mm = max(y_mm);
    else
        delta_initial_mm = y_mm(first);
    end
end
end


function theta = encode_parameters(u_tau, Pi, delta_mm, u_bounds, pi_bounds, delta_bounds)
theta = [logit_to_real(u_tau, u_bounds); ...
    logit_to_real(Pi, pi_bounds); ...
    logit_to_real(delta_mm, delta_bounds)];
end


function [u_tau, Pi, delta_mm] = decode_parameters(theta, u_bounds, pi_bounds, delta_bounds)
u_tau = logistic_to_real(theta(1), u_bounds);
Pi = logistic_to_real(theta(2), pi_bounds);
delta_mm = logistic_to_real(theta(3), delta_bounds);
end


function value = logit_to_real(x, bounds)
fraction = (x - bounds(1)) ./ (bounds(2) - bounds(1));
fraction = min(max(fraction, 1e-8), 1 - 1e-8);
value = log(fraction ./ (1 - fraction));
end


function value = logistic_to_real(x, bounds)
if x >= 0
    fraction = 1 ./ (1 + exp(-x));
else
    exponential = exp(x);
    fraction = exponential ./ (1 + exponential);
end
value = bounds(1) + (bounds(2) - bounds(1)) .* fraction;
end


function options = resolve_options(options, h_mm)
defaults = struct( ...
    'enabled', true, ...
    'method', 'rodriguez_lopez_2015_constrained_bump1', ...
    'kappa', 0.384, ...
    'B', 4.17, ...
    'dy_h', 2.0, ...
    'skip_nearwall', 0, ...
    'U_inf_n_top', 5, ...
    'enable_bump', true, ...
    'inner_step_yplus', 0.01, ...
    'pi_initial', 0.20, ...
    'pi_bounds', [0 2], ...
    'u_tau_scale_bounds', [0.5 1.8], ...
    'delta_scale_bounds', [0.5 2.0], ...
    'minimum_points', 10, ...
    'max_iterations', 400, ...
    'max_function_evaluations', 1600, ...
    'tolerance', 1e-7);
if nargin < 1 || isempty(options)
    options = struct();
end
if ~isstruct(options) || ~isscalar(options)
    error('tblR2:bl:composite_profile_fit_rodriguez_lopez:InvalidOptions', ...
        'options 必须是标量结构体。');
end
names = fieldnames(defaults);
for i = 1:numel(names)
    name = names{i};
    if ~isfield(options, name) || isempty(options.(name))
        options.(name) = defaults.(name);
    end
end
logical_scalar(options.enabled, 'enabled');
if ~logical(options.enabled)
    error('tblR2:bl:composite_profile_fit_rodriguez_lopez:Disabled', ...
        '当 enabled=false 时，必须由第 2 节的调用方处理。');
end
if ~strcmp(char(options.method), defaults.method)
    error('tblR2:bl:composite_profile_fit_rodriguez_lopez:UnsupportedMethod', ...
        '当前仅实现 %s 方法。', defaults.method);
end
positive_scalar(options.kappa, 'kappa');
finite_scalar(options.B, 'B');
nonnegative_scalar(options.dy_h, 'dy_h');
nonnegative_integer(options.skip_nearwall, 'skip_nearwall');
positive_integer(options.U_inf_n_top, 'U_inf_n_top');
positive_scalar(options.inner_step_yplus, 'inner_step_yplus');
positive_integer(options.minimum_points, 'minimum_points');
positive_integer(options.max_iterations, 'max_iterations');
positive_integer(options.max_function_evaluations, 'max_function_evaluations');
positive_scalar(options.tolerance, 'tolerance');
range_pair(options.pi_bounds, 'pi_bounds', true);
range_pair(options.u_tau_scale_bounds, 'u_tau_scale_bounds', true);
range_pair(options.delta_scale_bounds, 'delta_scale_bounds', true);
if options.pi_initial < options.pi_bounds(1) || options.pi_initial > options.pi_bounds(2)
    error('tblR2:bl:composite_profile_fit_rodriguez_lopez:InvalidPiInitial', ...
        'pi_initial 必须位于 pi_bounds 范围内。');
end
logical_scalar(options.enable_bump, 'enable_bump');
options.enabled = logical(options.enabled);
options.enable_bump = logical(options.enable_bump);
options.h_mm = h_mm;
end


function value = field_or(source, name, fallback)
if isstruct(source) && isfield(source, name) && ...
        isscalar(source.(name)) && isfinite(source.(name))
    value = double(source.(name));
else
    value = fallback;
end
end


function positive_scalar(value, name)
if ~(isnumeric(value) && isreal(value) && isscalar(value) && ...
        isfinite(value) && value > 0)
    error('tblR2:bl:composite_profile_fit_rodriguez_lopez:InvalidOption', ...
        '%s 必须是有限正数标量。', name);
end
end


function nonnegative_scalar(value, name)
if ~(isnumeric(value) && isreal(value) && isscalar(value) && ...
        isfinite(value) && value >= 0)
    error('tblR2:bl:composite_profile_fit_rodriguez_lopez:InvalidOption', ...
        '%s 必须是有限非负标量。', name);
end
end


function finite_scalar(value, name)
if ~(isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value))
    error('tblR2:bl:composite_profile_fit_rodriguez_lopez:InvalidOption', ...
        '%s 必须是有限标量。', name);
end
end


function positive_integer(value, name)
positive_scalar(value, name);
if value ~= round(value)
    error('tblR2:bl:composite_profile_fit_rodriguez_lopez:InvalidOption', ...
        '%s 必须是整数。', name);
end
end


function nonnegative_integer(value, name)
nonnegative_scalar(value, name);
if value ~= round(value)
    error('tblR2:bl:composite_profile_fit_rodriguez_lopez:InvalidOption', ...
        '%s 必须是整数。', name);
end
end


function range_pair(value, name, allow_zero_lower)
if ~(isnumeric(value) && isreal(value) && numel(value) == 2 && ...
        all(isfinite(value(:))) && value(2) > value(1) && ...
        (value(1) > 0 || (allow_zero_lower && value(1) >= 0)))
    error('tblR2:bl:composite_profile_fit_rodriguez_lopez:InvalidOption', ...
        '%s 必须是有序的有限双元素区间。', name);
end
end


function logical_scalar(value, name)
valid_logical = islogical(value) && isscalar(value);
valid_numeric = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && ismember(value, [0 1]);
if ~(valid_logical || valid_numeric)
    error('tblR2:bl:composite_profile_fit_rodriguez_lopez:InvalidOption', ...
        '%s 必须是逻辑标量或 0/1 数值。', name);
end
end


function positive_input_scalar(value, name)
if ~(isnumeric(value) && isreal(value) && isscalar(value) && ...
        isfinite(value) && value > 0)
    error('tblR2:bl:composite_profile_fit_rodriguez_lopez:InvalidInput', ...
        '%s 必须是有限正数标量。', name);
end
end


function tf = is_near_bound(value, bounds)
fraction = (value - bounds(1)) ./ (bounds(2) - bounds(1));
tf = fraction <= 0.01 | fraction >= 0.99;
end
