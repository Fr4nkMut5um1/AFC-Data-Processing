function handle = draw_spatial_exclusion(ax, ctx)
%DRAW_SPATIAL_EXCLUSION Overlay the requested exclusion rectangle in grey.
handle = gobjects(0);
if ~isfield(ctx, 'spatial_exclusion') || ...
        ~isfield(ctx.spatial_exclusion, 'enabled') || ...
        ~logical(ctx.spatial_exclusion.enabled)
    return;
end
info = ctx.spatial_exclusion;
x0 = double(info.requested_x_start_mm);
x1 = double(info.requested_x_end_mm);
y1 = double(info.requested_wall_y_height_mm);
handle = patch(ax, [x0 x1 x1 x0], [0 0 y1 y1], [0.86 0.86 0.86], ...
    'FaceAlpha', 1, 'EdgeColor', [0.25 0.25 0.25], ...
    'LineStyle', '--', 'LineWidth', 1.2, ...
    'Tag', 'UserSpatialExclusion', 'DisplayName', 'user exclusion');
end
