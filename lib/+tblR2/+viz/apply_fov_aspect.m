function ratio = apply_fov_aspect(ax, cfg)
%APPLY_FOV_ASPECT Match a physical x-y map to its displayed FOV ratio.
% An empty configured ratio uses the current x/y limits. A positive scalar
% means width/height; a two-element vector means [horizontal vertical].

configured = tblR2.figures_global(cfg, 'fov_aspect_ratio');
if isempty(configured) && isfield(cfg, 'viz_params') && ...
        isfield(cfg.viz_params, 'fov_aspect_ratio')
    configured = cfg.viz_params.fov_aspect_ratio;
end

if isempty(configured)
    x_limits = xlim(ax);
    y_limits = ylim(ax);
    dimensions = [abs(diff(x_limits)) abs(diff(y_limits))];
elseif isnumeric(configured) && isscalar(configured)
    dimensions = [configured 1];
elseif isnumeric(configured) && numel(configured) == 2
    dimensions = double(reshape(configured, 1, 2));
else
    error('tblR2:viz:apply_fov_aspect:InvalidRatio', ...
        'FOV 宽高比必须为空、为一个宽高标量，或为 [宽度 高度]。');
end
if any(~isfinite(dimensions)) || any(dimensions <= 0)
    error('tblR2:viz:apply_fov_aspect:InvalidRatio', ...
        'FOV 宽高尺寸必须是有限正数。');
end
pbaspect(ax, [dimensions 1]);
ratio = dimensions(1) / dimensions(2);
end
