function result = gradient_y_sensitivity(field, X_mm, Y_mm, rbf_epsilon_scale)
%GRADIENT_Y_SENSITIVITY Compare finite-difference and local RBF-FD d()/dy.

if nargin < 4 || isempty(rbf_epsilon_scale)
    rbf_epsilon_scale = 1.2;
end
if ~isequal(size(field), size(X_mm), size(Y_mm)) || ~ismatrix(field)
    error('tblR2:gradient_y_sensitivity:SizeMismatch', ...
        'field、X_mm 和 Y_mm 必须是尺寸相同的二维数组。');
end
if ~(isscalar(rbf_epsilon_scale) && isfinite(rbf_epsilon_scale) && ...
        rbf_epsilon_scale > 0)
    error('tblR2:gradient_y_sensitivity:InvalidEpsilon', ...
        'rbf_epsilon_scale 必须为正数。');
end

x_mm = double(X_mm(1, :));
y_mm = double(Y_mm(:, 1));
x_increasing = all(diff(x_mm) > 0);
x_decreasing = numel(x_mm) > 1 && all(diff(x_mm) < 0);
y_increasing = all(diff(y_mm) > 0);
y_decreasing = all(diff(y_mm) < 0);
if numel(y_mm) < 3 || any(~isfinite(x_mm)) || any(~isfinite(y_mm)) || ...
        ~(x_increasing || x_decreasing) || ~(y_increasing || y_decreasing)
    error('tblR2:gradient_y_sensitivity:InvalidGrid', ...
        ['坐标网格至少应包含三行法向网格点，且 x/y 坐标必须有限、严格单调并可分离。']);
end

if x_decreasing
    x_mm = fliplr(x_mm);
end
if y_decreasing
    y_mm = flipud(y_mm);
end
dx_mm = median(diff(x_mm), 'omitnan');
if numel(x_mm) == 1; dx_mm = 0; end
dy_mm = median(diff(y_mm), 'omitnan');
X_check = double(X_mm);
Y_check = double(Y_mm);
if x_decreasing
    X_check = fliplr(X_check);
end
if y_decreasing
    Y_check = flipud(Y_check);
end
x_separability_error_mm = max(abs(X_check - x_mm), [], 'all');
y_separability_error_mm = max(abs(Y_check - y_mm), [], 'all');
separability_tolerance_mm = max(1e-9, ...
    1e-6 * max(abs([dx_mm, dy_mm])));
if x_separability_error_mm > separability_tolerance_mm || ...
        y_separability_error_mm > separability_tolerance_mm
    error('tblR2:gradient_y_sensitivity:NonseparableGrid', ...
        ['局部法向 RBF-FD 敏感性分析要求使用可分离网格。' ...
         '请先将曲线网格插值到声明的 x/y 坐标。']);
end

y_m = y_mm * 1e-3;
field_work = double(field);
if x_decreasing
    field_work = fliplr(field_work);
end
if y_decreasing
    field_work = flipud(field_work);
end
% Only the y derivative is needed; keep a single-column profile valid too.
fd = nan(size(field_work));
fd(2:end-1, :) = (field_work(3:end, :) - field_work(1:end-2, :)) ./ ...
    (y_m(3:end) - y_m(1:end-2));
fd(1, :) = (field_work(2, :) - field_work(1, :)) / (y_m(2) - y_m(1));
fd(end, :) = (field_work(end, :) - field_work(end-1, :)) / (y_m(end) - y_m(end-1));

% Use the actual local wall-normal coordinates rather than forcing rounded
% DAT coordinates onto an exactly uniform grid. The three-node Gaussian
% RBF-FD stencil is polynomially augmented so constants and linear y are
% differentiated exactly. It is applied to every x column simultaneously.
rbf = nan(size(field));
field_double = field_work;
for row = 2:numel(y_m) - 1
    nodes = y_m(row - 1:row + 1) - y_m(row);
    radius = max(abs(nodes));
    epsilon = rbf_epsilon_scale / radius;
    distance = nodes - nodes';
    Phi = exp(-(epsilon .* distance) .^ 2);
    P = [ones(3, 1), nodes];
    system_matrix = [Phi, P; P', zeros(2)];
    phi0 = exp(-(epsilon .* nodes) .^ 2);
    rhs = [2 .* epsilon .^ 2 .* nodes .* phi0; 0; 1];
    weights = system_matrix \ rhs;
    rbf(row, :) = weights(1:3)' * field_double(row - 1:row + 1, :);
end
rbf([1 end], :) = fd([1 end], :);
if y_decreasing
    fd = flipud(fd);
    rbf = flipud(rbf);
end
if x_decreasing
    fd = fliplr(fd);
    rbf = fliplr(rbf);
end

finite_pair = isfinite(fd) & isfinite(rbf);
difference = rbf - fd;
scale = sqrt(mean(fd(finite_pair) .^ 2, 'omitnan'));
if isempty(scale) || ~isfinite(scale) || scale <= eps
    relative_rms = NaN;
else
    relative_rms = sqrt(mean(difference(finite_pair) .^ 2, 'omitnan')) / scale;
end

result = struct('finite_difference', fd, 'rbf_fd', rbf, ...
    'difference', difference, 'relative_rms_difference', relative_rms, ...
    'rbf_epsilon_scale', rbf_epsilon_scale, ...
    'grid_treatment', 'actual_separable_nonuniform_y_coordinates', ...
    'x_separability_error_mm', x_separability_error_mm, ...
    'y_separability_error_mm', y_separability_error_mm, ...
    'scope', ['Local Gaussian RBF-FD on the actual separable wall-normal ' ...
              'coordinates is a sensitivity branch; finite difference remains ' ...
              'the primary reported gradient.']);
end
