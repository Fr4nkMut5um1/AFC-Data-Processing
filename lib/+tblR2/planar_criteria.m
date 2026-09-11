function result = planar_criteria(U, V, X_mm, Y_mm, valid_mask)
%PLANAR_CRITERIA Compute explicitly planar 2D-2C gradient diagnostics.

if ~isequal(size(U), size(V), size(X_mm), size(Y_mm)) || ~ismatrix(U)
    error('tblR2:planar_criteria:SizeMismatch', ...
        'U、V、X_mm 和 Y_mm 必须是尺寸相同的二维数组。');
end
if nargin < 5 || isempty(valid_mask)
    valid_mask = isfinite(U) & isfinite(V);
    require_complete_stencil = false;
elseif ~isequal(size(valid_mask), size(U)) || ~islogical(valid_mask)
    error('tblR2:planar_criteria:InvalidMask', ...
        '可选 valid_mask 必须是同尺寸二维逻辑数组。');
else
    require_complete_stencil = true;
end
input_valid_original = valid_mask & isfinite(U) & isfinite(V);
x_m = double(X_mm(1, :)) * 1e-3;
y_m = double(Y_mm(:, 1)) * 1e-3;
x_increasing = all(diff(x_m) > 0);
x_decreasing = all(diff(x_m) < 0);
y_increasing = all(diff(y_m) > 0);
y_decreasing = all(diff(y_m) < 0);
if ~(x_increasing || x_decreasing) || ~(y_increasing || y_decreasing)
    error('tblR2:planar_criteria:NonMonotonicGrid', ...
        '处理壁面行后，X 和 Y 坐标必须严格单调。');
end

U_work = double(U);
V_work = double(V);
if x_decreasing
    x_work = fliplr(x_m);
    U_work = fliplr(U_work);
    V_work = fliplr(V_work);
else
    x_work = x_m;
end
if y_decreasing
    y_work = flipud(y_m);
    U_work = flipud(U_work);
    V_work = flipud(V_work);
else
    y_work = y_m;
end

[dUdx, dUdy] = gradient(U_work, x_work, y_work);
[dVdx, dVdy] = gradient(V_work, x_work, y_work);
if y_decreasing
    dUdx = flipud(dUdx);
    dUdy = flipud(dUdy);
    dVdx = flipud(dVdx);
    dVdy = flipud(dVdy);
end
if x_decreasing
    dUdx = fliplr(dUdx);
    dUdy = fliplr(dUdy);
    dVdx = fliplr(dVdx);
    dVdy = fliplr(dVdy);
end

omega_z = dVdx - dUdy;
q_planar = -0.5 .* (dUdx .^ 2 + dVdy .^ 2 + 2 .* dUdy .* dVdx);

s12 = 0.5 .* (dUdy + dVdx);
o12 = 0.5 .* (dUdy - dVdx);
m11 = dUdx .^ 2 + s12 .^ 2 - o12 .^ 2;
m22 = dVdy .^ 2 + s12 .^ 2 - o12 .^ 2;
m12 = s12 .* (dUdx + dVdy);
lambda2_planar = 0.5 .* (m11 + m22) - ...
    sqrt(max(0, (0.5 .* (m11 - m22)) .^ 2 + m12 .^ 2));

trace_a = dUdx + dVdy;
det_a = dUdx .* dVdy - dUdy .* dVdx;
lambda_ci = sqrt(max(0, det_a - 0.25 .* trace_a .^ 2));

% When the caller supplies a trust mask, derivatives are retained only where
% the complete 3x3 stencil is trusted. This removes MATLAB gradient's
% one-sided outer-edge values and prevents NaN/mask boundaries from producing
% apparently finite vortex criteria. The legacy four-argument call keeps its
% former finite-input behaviour for analytic/tests that intentionally use
% boundary derivatives.
if require_complete_stencil
    derivative_valid = tblR2.buffer_valid_mask( ...
        input_valid_original, [1 1]);
else
    derivative_valid = input_valid_original;
end
invalid_input = ~derivative_valid;
output_fields = {'dUdx', 'dUdy', 'dVdx', 'dVdy', 'omega_z', ...
    'Q_planar', 'lambda2_planar', 'lambda_ci'};

result = struct();
result.dUdx = dUdx;
result.dUdy = dUdy;
result.dVdx = dVdx;
result.dVdy = dVdy;
result.omega_z = omega_z;
result.Q_planar = q_planar;
result.lambda2_planar = lambda2_planar;
result.lambda_ci = lambda_ci;
% 把输入无效点位置的输出字段统一置 NaN（在 result 构造后应用）。
for fi = 1:numel(output_fields)
    result.(output_fields{fi})(invalid_input) = NaN;
end
result.input_valid_mask = input_valid_original;
result.derivative_valid_mask = derivative_valid;
result.complete_stencil_required = require_complete_stencil;
result.units = struct('gradients', '1/s', 'omega_z', '1/s', ...
    'Q_planar', '1/s^2', 'lambda2_planar', '1/s^2', ...
    'lambda_ci', '1/s');
result.scope = ['Planar 2D-2C surrogates in the measured XOY plane only; ' ...
    'these fields are not full three-dimensional vortex criteria.'];
end
