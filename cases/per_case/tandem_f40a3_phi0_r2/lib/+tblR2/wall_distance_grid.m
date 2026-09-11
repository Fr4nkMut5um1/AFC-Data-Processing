function [Y_wall_mm, info] = wall_distance_grid(Y_source_mm, h_mm, dy_h)
%WALL_DISTANCE_GRID Rebuild wall distance from the first retained flow row.
%
% load_tecplot_dat removes the contiguous zero-velocity rows on the wall
% side, and the periodic pipeline additionally remaps the cache Y to
% wall-based measurement coordinates (first retained row y = 0 + h).
% Independent of that remap, the established baseline_case/loglaw contract
% still assigns the first retained velocity row the manually specified
% distance dy_h*h and advances one h per row: y_wall(j) = ((j-1) + dy_h)*h.

if ~(isnumeric(Y_source_mm) && ismatrix(Y_source_mm) && ...
        ~isempty(Y_source_mm) && all(isfinite(Y_source_mm), 'all'))
    error('tblR2:wall_distance_grid:InvalidSourceGrid', ...
        'Y_source_mm 必须是非空且元素有限的数值矩阵。');
end
if ~(isscalar(h_mm) && isfinite(h_mm) && h_mm > 0)
    error('tblR2:wall_distance_grid:InvalidSpacing', ...
        'h_mm 必须是有限正标量。');
end
if ~(isscalar(dy_h) && isfinite(dy_h) && dy_h >= 0)
    error('tblR2:wall_distance_grid:InvalidWallOffset', ...
        'dy_h 必须是有限非负标量。');
end

[n_rows, n_cols] = size(Y_source_mm);
row_from_first_valid = (0:n_rows - 1)';
profile_mm = (row_from_first_valid + dy_h) .* h_mm;
Y_wall_mm = repmat(profile_mm, 1, n_cols);

info = struct();
info.method = 'first_retained_flow_row_plus_manual_dy_h';
info.equation = 'y_wall(j) = ((j-1) + dy_h) * h';
info.h_mm = h_mm;
info.dy_h = dy_h;
info.dy_mm = dy_h .* h_mm;
info.first_valid_row_index = 1;
info.first_valid_wall_distance_mm = profile_mm(1);
info.source_first_valid_y_mm = median(Y_source_mm(1, :), 'omitnan');
info.source_y_range_mm = [min(Y_source_mm, [], 'all'), ...
    max(Y_source_mm, [], 'all')];
info.wall_distance_range_mm = [profile_mm(1), profile_mm(end)];
info.source_Y_preserved = true;
info.input_contract = ['Rows below the wall were removed upstream from the ' ...
    'contiguous zero-velocity wall mask; the periodic pipeline remaps the ' ...
    'cache Y to wall distance (first retained row y = 0 + h), and this ' ...
    'grid keeps the independent manual dy_h wall-coordinate contract.'];
end
