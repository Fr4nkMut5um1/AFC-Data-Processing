function [filtered, output_mask, meta] = simple_gaussian_filter2( ...
        field, valid_mask, sigma_cells, radius_cells, options)
%SIMPLE_GAUSSIAN_FILTER2 Configurable ordinary 2-D Gaussian blur.
% The four-argument calling form is retained for backwards compatibility.
% Invalid samples are zero-filled for the legacy ordinary convolution and
% restored as NaN afterwards.  Optional mask-aware normalization and boundary
% modes are explicit so that they are part of the cache provenance.

if nargin < 5 || isempty(options)
    options = struct();
end
options = normalize_options(options, sigma_cells, radius_cells);

if ~isequal(size(field), size(valid_mask)) || ~islogical(valid_mask)
    error('tblR2:simple_gaussian_filter2:SizeMismatch', ...
        'field 和 valid_mask 必须是同尺寸数组，且 valid_mask 必须为逻辑数组。');
end
source_mask = valid_mask & isfinite(field);
work = double(field);
work(~source_mask) = 0;
kernel = gaussian_kernel(options);
filtered = convolve_with_boundary(work, kernel, options.boundary_mode);
output_mask = source_mask;

if options.mask_aware
    support = convolve_with_boundary(double(source_mask), kernel, ...
        options.boundary_mode);
    normalized = filtered;
    good = support >= options.min_support_fraction & support > 0;
    normalized(good) = filtered(good) ./ support(good);
    normalized(~good) = NaN;
    filtered = normalized;
    output_mask = source_mask & good;
end

filtered(~output_mask) = NaN;
meta = struct();
meta.sigma_x_cells = options.sigma_x_cells;
meta.sigma_y_cells = options.sigma_y_cells;
meta.radius_x_cells = options.radius_x_cells;
meta.radius_y_cells = options.radius_y_cells;
meta.kernel_type = options.kernel_type;
meta.kernel_normalization = options.kernel_normalization;
meta.boundary_mode = options.boundary_mode;
meta.mask_aware = options.mask_aware;
meta.min_support_fraction = options.min_support_fraction;
meta.source_valid_count = nnz(source_mask);
meta.output_valid_count = nnz(output_mask);
meta.method = 'configurable ordinary 2-D Gaussian convolution';
end

function options = normalize_options(options, sigma_cells, radius_cells)
defaults = struct( ...
    'sigma_x_cells', sigma_cells, ...
    'sigma_y_cells', sigma_cells, ...
    'radius_x_cells', radius_cells, ...
    'radius_y_cells', radius_cells, ...
    'kernel_type', 'gaussian', ...
    'kernel_normalization', 'sum1', ...
    'boundary_mode', 'legacy_zero', ...
    'mask_aware', false, ...
    'min_support_fraction', 0.50);
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(options, names{i}) || isempty(options.(names{i}))
        options.(names{i}) = defaults.(names{i});
    end
end
positive_scalar(options.sigma_x_cells, 'sigma_x_cells');
positive_scalar(options.sigma_y_cells, 'sigma_y_cells');
positive_integer(options.radius_x_cells, 'radius_x_cells');
positive_integer(options.radius_y_cells, 'radius_y_cells');
if ~(ischar(options.kernel_type) || (isstring(options.kernel_type) && isscalar(options.kernel_type)))
    error('tblR2:simple_gaussian_filter2:InvalidKernelType', ...
        'kernel_type 必须是文本。');
end
if ~strcmpi(char(options.kernel_type), 'gaussian')
    error('tblR2:simple_gaussian_filter2:UnsupportedKernelType', ...
        '当前仅支持 kernel_type="gaussian"。');
end
if ~(ischar(options.kernel_normalization) || ...
        (isstring(options.kernel_normalization) && isscalar(options.kernel_normalization)))
    error('tblR2:simple_gaussian_filter2:InvalidKernelNormalization', ...
        'kernel_normalization 必须是文本。');
end
if ~strcmpi(char(options.kernel_normalization), 'sum1')
    error('tblR2:simple_gaussian_filter2:UnsupportedKernelNormalization', ...
        '当前仅支持 kernel_normalization="sum1"。');
end
valid_boundary = {'legacy_zero', 'symmetric', 'replicate'};
if ~any(strcmpi(char(options.boundary_mode), valid_boundary))
    error('tblR2:simple_gaussian_filter2:InvalidBoundaryMode', ...
        'boundary_mode 必须是 legacy_zero、symmetric 或 replicate。');
end
if ~(islogical(options.mask_aware) && isscalar(options.mask_aware))
    error('tblR2:simple_gaussian_filter2:InvalidMaskAware', ...
        'mask_aware 必须是逻辑标量。');
end
if ~(isscalar(options.min_support_fraction) && ...
        isfinite(options.min_support_fraction) && ...
        options.min_support_fraction > 0 && options.min_support_fraction <= 1)
    error('tblR2:simple_gaussian_filter2:InvalidSupportFraction', ...
        'min_support_fraction 必须位于 (0,1] 区间内。');
end
end

function kernel = gaussian_kernel(options)
axis_x = -options.radius_x_cells:options.radius_x_cells;
axis_y = -options.radius_y_cells:options.radius_y_cells;
[dx, dy] = meshgrid(axis_x, axis_y);
kernel = exp(-0.5 .* ((dx ./ options.sigma_x_cells).^2 + ...
    (dy ./ options.sigma_y_cells).^2));
kernel = kernel ./ sum(kernel(:));
end

function out = convolve_with_boundary(in, kernel, boundary_mode)
mode = lower(char(boundary_mode));
if strcmp(mode, 'legacy_zero')
    out = conv2(in, kernel, 'same');
    return;
end
radius_y = floor(size(kernel, 1) / 2);
radius_x = floor(size(kernel, 2) / 2);
if strcmp(mode, 'symmetric')
    padded = padarray(in, [radius_y radius_x], 'symmetric', 'both');
elseif strcmp(mode, 'replicate')
    padded = padarray(in, [radius_y radius_x], 'replicate', 'both');
else
    error('tblR2:simple_gaussian_filter2:InvalidBoundaryMode', ...
        '不支持的边界模式：%s', boundary_mode);
end
out = conv2(padded, kernel, 'valid');
end

function positive_scalar(value, name)
if ~(isscalar(value) && isfinite(value) && value > 0)
    error('tblR2:simple_gaussian_filter2:InvalidParameter', ...
        '%s 必须是有限正标量。', name);
end
end

function positive_integer(value, name)
if ~(isscalar(value) && isfinite(value) && value >= 1 && value == fix(value))
    error('tblR2:simple_gaussian_filter2:InvalidParameter', ...
        '%s 必须是正整数标量。', name);
end
end
