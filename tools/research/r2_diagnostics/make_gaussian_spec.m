function spec = make_gaussian_spec(base_spec, sigma_cells, radius_cells)
%MAKE_GAUSSIAN_SPEC Build a preprocessing spec whose sigma actually applies.
%
%   simple_gaussian_filter2 constructs its kernel from the DIRECTIONAL fields
%   (sigma_x_cells, sigma_y_cells, radius_x_cells, radius_y_cells) only.  Its
%   normalize_options backfills those from the scalar sigma_cells/radius_cells
%   aliases ONLY when they are absent or empty.  The spec that
%   structure_analysis_cache/structure_preprocessing produces pre-populates
%   them with non-empty defaults (sigma 0.8, radius 1), so setting the scalar
%   alias alone has NO effect on the kernel.
%
%   Any diagnostic that sweeps sigma must therefore set all four fields.  This
%   helper does that, so callers cannot silently sweep a parameter that is
%   being ignored.
%
%   sigma_cells / radius_cells each accept either
%     - a scalar          -> isotropic kernel (legacy behaviour, name unchanged)
%     - [x_value y_value] -> directional kernel, x = streamwise (columns),
%                            y = wall-normal (rows)
%
%   The kernel that simple_gaussian_filter2 builds is (2*ry+1) rows by
%   (2*rx+1) columns, and the field is [J x I] = [wall-normal x streamwise].
%   So a streamwise-only blur of 11 streamwise cells by 3 wall-normal cells is
%   radius_cells = [5 1], i.e. an 11-column by 3-row kernel.
%
%   radius_cells is optional; it defaults to ceil(3*sigma) per direction, which
%   captures ~99.7% of the Gaussian mass.

if nargin < 3 || isempty(radius_cells)
    radius_cells = max(1, ceil(3 * sigma_cells));
end
sigma_xy = expand_pair(sigma_cells, 'sigma_cells');
radius_xy = expand_pair(radius_cells, 'radius_cells');
for k = 1:2
    if ~(isfinite(sigma_xy(k)) && sigma_xy(k) > 0)
        error('tblR2:make_gaussian_spec:InvalidSigma', ...
            'sigma_cells 的每个分量都必须是有限正数。');
    end
    if ~(isfinite(radius_xy(k)) && radius_xy(k) >= 1 && ...
            radius_xy(k) == fix(radius_xy(k)))
        error('tblR2:make_gaussian_spec:InvalidRadius', ...
            'radius_cells 的每个分量都必须是 >= 1 的整数。');
    end
end

spec = base_spec;
spec.enabled = true;
spec.gaussian.enabled         = true;
% 标量别名保留：simple_gaussian_filter2 的位置参数要用，且 preprocess_structure_velocity
% 是按 options.gaussian.sigma_cells / radius_cells 取位置参数传进去的。方向性字段
% 已经填满，所以这两个别名只作记录，不参与建核。
spec.gaussian.sigma_cells     = sigma_xy(1);
spec.gaussian.radius_cells    = radius_xy(1);
spec.gaussian.sigma_x_cells   = sigma_xy(1);
spec.gaussian.sigma_y_cells   = sigma_xy(2);
spec.gaussian.radius_x_cells  = radius_xy(1);
spec.gaussian.radius_y_cells  = radius_xy(2);

nx = 2 * radius_xy(1) + 1;
ny = 2 * radius_xy(2) + 1;
if isotropic(sigma_xy) && isotropic(radius_xy)
    % 各向同性分支的命名保持逐字不变：既有诊断产物的 provenance 字符串依赖它。
    spec.name = sprintf('Gaussian_sigma%s_%dx%d', num_tag(sigma_xy(1)), nx, ny);
else
    spec.name = sprintf('Gaussian_sigmax%s_sigmay%s_%dx%d', ...
        num_tag(sigma_xy(1)), num_tag(sigma_xy(2)), nx, ny);
end
end

% =========================================================================
function pair = expand_pair(value, name)
%EXPAND_PAIR 标量 -> [v v]；两元素向量原样返回 [x y]。
if ~isnumeric(value) || ~isreal(value)
    error('tblR2:make_gaussian_spec:InvalidParameter', ...
        '%s 必须是实数标量或两元素向量。', name);
end
value = double(value(:).');
switch numel(value)
    case 1
        pair = [value value];
    case 2
        pair = value;
    otherwise
        error('tblR2:make_gaussian_spec:InvalidParameter', ...
            '%s 必须是标量或 [流向 法向] 两元素向量，当前有 %d 个元素。', ...
            name, numel(value));
end
end

% =========================================================================
function tf = isotropic(pair)
tf = pair(1) == pair(2);
end

% =========================================================================
function tag = num_tag(value)
tag = strrep(sprintf('%.4g', value), '.', 'p');
end
