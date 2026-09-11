function [up_out, vp_out, metadata] = apply_gaussian(up, vp, valid, gaussian_cfg)
%APPLY_GAUSSIAN Explicit 2-D imgaussfilt stage, preserving invalid samples.
if ~gaussian_cfg.enabled
    up_out = up;
    vp_out = vp;
    metadata = struct('enabled', false, 'sigma_cells', [], ...
        'filter_size', [], 'padding', '');
    return;
end
sigma = double(gaussian_cfg.sigma_cells);
if isempty(gaussian_cfg.filter_size)
    filter_size = 2 * ceil(2 * sigma) + 1;
else
    filter_size = double(gaussian_cfg.filter_size);
end
if ~isscalar(filter_size) || filter_size < 1 || ...
        filter_size ~= fix(filter_size) || mod(filter_size, 2) ~= 1
    error('d23:apply_gaussian:FilterSize', ...
        'Gaussian FilterSize must be a positive odd integer.');
end
padding = char(gaussian_cfg.padding);
up_out = nan(size(up));
vp_out = nan(size(vp));
for i = 1:size(up, 1)
    ui = squeeze(up(i, :, :));
    vi = squeeze(vp(i, :, :));
    valid_i = squeeze(valid(i, :, :));
    ui(~valid_i) = 0;
    vi(~valid_i) = 0;
    ui = imgaussfilt(ui, sigma, 'FilterSize', filter_size, 'Padding', padding);
    vi = imgaussfilt(vi, sigma, 'FilterSize', filter_size, 'Padding', padding);
    ui(~valid_i) = NaN;
    vi(~valid_i) = NaN;
    up_out(i, :, :) = ui;
    vp_out(i, :, :) = vi;
end
metadata = struct('enabled', true, 'sigma_cells', sigma, ...
    'filter_size', filter_size, 'padding', padding, ...
    'invalid_policy', 'zero before filtering, restore NaN after filtering');
end
