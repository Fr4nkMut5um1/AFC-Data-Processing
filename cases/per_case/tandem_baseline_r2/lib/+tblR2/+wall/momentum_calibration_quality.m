function quality = momentum_calibration_quality( ...
        theta, Ue, delta_star, x, Cf_local, pre_smooth_p, opts)
%MOMENTUM_CALIBRATION_QUALITY Evaluate one configured local-Cf curve.
%   This does not search p. It reports the residual of the formal configured
%   curve against the matching raw calibration secants, plus convergence and
%   p-grid boundary status.

if nargin < 7 || ~isstruct(opts) || ~isscalar(opts)
    error('tblR2:wall:momentum_calibration_quality:InvalidOptions', ...
        'opts 必须是标量结构体。');
end
if ~isnumeric(pre_smooth_p) || ~isreal(pre_smooth_p) || ...
        ~isscalar(pre_smooth_p) || ~isfinite(pre_smooth_p) || ...
        pre_smooth_p < 0 || pre_smooth_p > 1
    error('tblR2:wall:momentum_calibration_quality:InvalidPreSmoothP', ...
        'pre_smooth_p 必须是 [0,1] 内的有限标量。');
end
if ~isnumeric(x) || ~isreal(x) || ~isvector(x) || ...
        ~isnumeric(Cf_local) || ~isreal(Cf_local) || ...
        ~isvector(Cf_local) || ~isequal(size(x), size(Cf_local)) || ...
        any(~isfinite(x(:))) || any(diff(x(:)) <= 0)
    error('tblR2:wall:momentum_calibration_quality:InvalidInput', ...
        'x 和 Cf_local 必须是尺寸相同的向量，且 x 必须有限并严格递增。');
end

equation = option_text(opts, 'equation', 'zpg');
if ~ismember(equation, {'zpg', 'full'})
    error('tblR2:wall:momentum_calibration_quality:InvalidEquation', ...
        'opts.equation 必须是 ''zpg'' 或 ''full''。');
end
x_min = option_scalar(opts, 'x_min', 80);
x_max = option_scalar(opts, 'x_max', 328);
if x_min ~= 80 || x_max > 328 || x_max <= x_min
    error('tblR2:wall:momentum_calibration_quality:InvalidDomain', ...
        '要求 x_min = 80 < x_max <= 328 mm。');
end
tolerance_pct = option_scalar(opts, 'tolerance_pct', 10);
if tolerance_pct < 0
    error('tblR2:wall:momentum_calibration_quality:InvalidTolerance', ...
        'opts.tolerance_pct 必须是非负数。');
end
if isfield(opts, 'p_grid')
    p_grid = opts.p_grid;
else
    p_grid = 1 - 10.^(0:-0.5:-5);
end
if ~isnumeric(p_grid) || ~isreal(p_grid) || ~isvector(p_grid) || ...
        isempty(p_grid) || any(~isfinite(p_grid(:))) || ...
        any(p_grid(:) < 0) || any(p_grid(:) > 1) || ...
        any(diff(p_grid(:)) <= 0)
    error('tblR2:wall:momentum_calibration_quality:InvalidPGrid', ...
        'opts.p_grid 必须是 [0,1] 内有限且严格递增的向量。');
end
p_grid = p_grid(:).';

x_row = x(:).';
cf_row = Cf_local(:).';
endpoint_requested = x_row(x_row >= x_min & x_row <= x_max);
cal_opts = struct('equation', equation, 'x_min', x_min, 'x_max', x_max);
[Cf_secant, secant_diag] = tblR2.wall.calibration_secant_cf( ...
    theta, Ue, delta_star, x, endpoint_requested, cal_opts);

point_count = secant_diag.end_index - secant_diag.start_index + 1;
candidate = secant_diag.valid & point_count >= 5 & ...
    isfinite(Cf_secant) & abs(Cf_secant) > eps;
residual_by_endpoint = NaN(size(endpoint_requested));
local_average_cf = NaN(size(endpoint_requested));
for k = find(candidate)
    idx = secant_diag.start_index:secant_diag.end_index(k);
    if numel(idx) < 5 || any(~isfinite(cf_row(idx)))
        continue;
    end
    dx = x_row(idx(end)) - x_row(idx(1));
    local_average_cf(k) = trapz(x_row(idx), cf_row(idx)) ./ dx;
    residual_by_endpoint(k) = 100 .* ...
        (local_average_cf(k) - Cf_secant(k)) ./ abs(Cf_secant(k));
end
finite_residual = isfinite(residual_by_endpoint);
if ~any(finite_residual)
    error('tblR2:wall:momentum_calibration_quality:NoValidResidual', ...
        '没有可用的有限五点校准残差。');
end
residual_pct = sqrt(mean(residual_by_endpoint(finite_residual).^2));

scale = max(1, max(abs([pre_smooth_p, p_grid])));
p_tol = 16 .* eps(scale);
boundary_hit = any(abs(pre_smooth_p-p_grid([1 end])) <= p_tol);

quality = struct();
quality.schema_version = 1;
quality.quantity_name = 'local_cf_calibration_quality';
quality.equation = equation;
quality.domain = [x_min, x_max];
quality.pre_smooth_p = pre_smooth_p;
quality.p_grid = p_grid;
quality.tolerance_pct = tolerance_pct;
quality.residual_pct = residual_pct;
quality.converged = logical(residual_pct <= tolerance_pct);
quality.boundary_hit = logical(boundary_hit);
quality.endpoint_requested = endpoint_requested;
quality.endpoint_actual = secant_diag.x_end_actual;
quality.valid_endpoint_mask = finite_residual;
quality.residual_pct_by_endpoint = residual_by_endpoint;
quality.local_average_cf = local_average_cf;
quality.Cf_calibration_secant = Cf_secant;
quality.calibration_secant_diag = secant_diag;
end


function value = option_scalar(opts, name, default_value)
if isfield(opts, name)
    value = opts.(name);
else
    value = default_value;
end
if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
        ~isfinite(value)
    error('tblR2:wall:momentum_calibration_quality:InvalidOption', ...
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
