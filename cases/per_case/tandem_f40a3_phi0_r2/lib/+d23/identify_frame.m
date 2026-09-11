function catalog = identify_frame(up, valid, u_rms_y, frame_ordinal, ...
    frame_id, connectivity, sign_value, ctx, cfg)
%IDENTIFY_FRAME Threshold one sign and catalog every connected component.
up = double(up);
valid = logical(valid);
if ~isequal(size(up), size(valid)) || ...
        numel(u_rms_y) ~= size(up, 1)
    error('d23:identify_frame:ShapeMismatch', ...
        'up, valid, and u_rms_y dimensions are inconsistent.');
end
threshold = cfg.detection.amplitude_multiplier * double(u_rms_y(:));
if sign_value == 1
    mask = valid & up > threshold;
elseif sign_value == -1
    mask = valid & up < -threshold;
else
    error('d23:identify_frame:InvalidSign', 'sign_value must be +1 or -1.');
end
cc = bwconncomp(mask, connectivity);
if cc.NumObjects == 0
    catalog = d23.empty_catalog();
    return;
end
props = regionprops(cc, 'Area', 'BoundingBox', 'PixelIdxList');
n = numel(props);
bb = vertcat(props.BoundingBox);
pixel_count = uint32(round(vertcat(props.Area)));
col_min = uint16(round(bb(:,1) + 0.5));
row_min = uint16(round(bb(:,2) + 0.5));
col_max = uint16(round(bb(:,1) + bb(:,3) - 0.5));
row_max = uint16(round(bb(:,2) + bb(:,4) - 0.5));
nx = size(up, 2);
ny = size(up, 1);
user_exclusion = ~d23.spatial_active_mask(ctx);
invalid_adjacent = conv2(double(~valid & ~user_exclusion), ones(3), 'same') > 0;
exclusion_adjacent = conv2(double(user_exclusion), ones(3), 'same') > 0;
y_min_mm = zeros(n, 1);
y_max_mm = zeros(n, 1);
touch_invalid = false(n, 1);
touch_exclusion = false(n, 1);
for i = 1:n
    idx = props(i).PixelIdxList;
    y_values = ctx.wall_distance_mm(idx);
    y_min_mm(i) = min(y_values) - 0.5 * ctx.dy_mm;
    y_max_mm(i) = max(y_values) + 0.5 * ctx.dy_mm;
    touch_invalid(i) = any(invalid_adjacent(idx));
    touch_exclusion(i) = any(exclusion_adjacent(idx));
end
y_min_mm = max(y_min_mm, 0);
cmin = double(col_min);
cmax = double(col_max);
x_min_mm = ctx.x_mm(cmin).' - 0.5 * ctx.dx_mm;
x_max_mm = ctx.x_mm(cmax).' + 0.5 * ctx.dx_mm;
lx_mm = bb(:,3) * ctx.dx_mm;
lx_over_delta = lx_mm / ctx.delta99_mm;
y_min_plus = y_min_mm / 1000 * ctx.u_tau_m_s / ctx.nu_m2_s;
y_max_plus = y_max_mm / 1000 * ctx.u_tau_m_s / ctx.nu_m2_s;
pass_length = lx_over_delta > cfg.detection.length_thresholds;
pass_lower = y_min_plus <= ctx.lower_plus_limit;
pass_upper = y_max_plus >= ctx.upper_plus_limit;
is_ss = pass_length & pass_lower & pass_upper;
touch_upstream = col_min == 1;
touch_downstream = col_max == nx;
touch_wall = row_min == 1;
touch_top = row_max == ny;
is_censored = touch_upstream | touch_downstream | touch_top;
reason = uint8(touch_upstream) + 2 * uint8(touch_downstream) + ...
    4 * uint8(touch_top);
edge_cfg = cfg.detection.streamwise_edge_exclusion;
buffer_cells = double(edge_cfg.buffer_cells);
% buffer_cells counts cell intervals from the outer FOV boundary.  Thus a
% three-cell rim includes the component whose bbox starts in column 4 (or
% ends in column nx-3), as its bbox is three cell widths from the boundary.
touch_left_buffer = double(col_min) <= 1 + buffer_cells;
touch_right_buffer = double(col_max) >= nx - buffer_cells;
rejected_by_streamwise_edge = logical(edge_cfg.enabled) & ...
    (touch_left_buffer | touch_right_buffer);
area_mm2 = double(pixel_count) * ctx.dx_mm * ctx.dy_mm;
fill_fraction = double(pixel_count) ./ (bb(:,3) .* bb(:,4));

catalog = table(repmat(uint32(frame_ordinal), n, 1), ...
    repmat(uint32(frame_id), n, 1), repmat(int8(sign_value), n, 1), ...
    repmat(uint8(connectivity), n, 1), uint32((1:n).'), pixel_count, ...
    bb(:,1), bb(:,2), bb(:,3), bb(:,4), col_min, col_max, row_min, row_max, ...
    x_min_mm, x_max_mm, y_min_mm, y_max_mm, area_mm2, fill_fraction, ...
    lx_mm, lx_over_delta, y_min_plus, y_max_plus, ...
    pass_length(:,1), pass_length(:,2), pass_length(:,3), ...
    pass_lower, pass_upper, is_ss(:,1), is_ss(:,2), is_ss(:,3), ...
    touch_upstream, touch_downstream, touch_wall, touch_top, touch_invalid, ...
    touch_exclusion, ...
    is_censored, reason, touch_left_buffer, touch_right_buffer, ...
    rejected_by_streamwise_edge, false(n,1), ...
    'VariableNames', d23.empty_catalog().Properties.VariableNames);
catalog = d23.retain_nonoverlapping_complete_ss(catalog, cfg);
end
