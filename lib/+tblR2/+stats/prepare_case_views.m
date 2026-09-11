function [S_visual, S_drag, masks] = prepare_case_views(S_raw, x_max, region)
%PREPARE_CASE_VIEWS Crop the FOV and create visualization/drag statistics.
% An empty region means no artificial contamination mask.  This is the
% periodic-pipeline default; a nonempty region remains accepted only for
% legacy single-case callers.

if nargin < 3
    region = [];
end

stat_fields = {'Uavex', 'Vavex', 'u_rms', 'v_rms', ...
    'uv_rey', 'uu_rey', 'vv_rey', 'TKE'};
grid_fields = [stat_fields, {'X', 'Y', 'valid_count', 'valid_fraction'}];
if ~isstruct(S_raw) || ~isscalar(S_raw) || ...
        ~all(isfield(S_raw, grid_fields))
    error('tblR2:stats:prepare_case_views:InvalidStats', ...
        'S_raw 缺少必需的网格和统计字段。');
end

original_size = size(S_raw.X);
keep = S_raw.X(1, :) <= x_max;
if ~any(keep)
    error('tblR2:stats:prepare_case_views:EmptyDomain', ...
        'x_max 移除了所有流向列。');
end
S_visual = S_raw;
for k = 1:numel(grid_fields)
    name = grid_fields{k};
    if ~isequal(size(S_raw.(name)), original_size)
        error('tblR2:stats:prepare_case_views:SizeMismatch', ...
            'S_raw.%s 必须与 S_raw.X 尺寸一致。', name);
    end
    S_visual.(name) = S_raw.(name)(:, keep);
end
S_visual.x_max_applied = x_max;

masks = struct();
if isempty(region)
    masks.visualization = false(size(S_visual.X));
    masks.drag = false(size(S_visual.X));
else
    masks.visualization = tblR2.io.contamination_mask( ...
        S_visual.X, S_visual.Y, region, 'visualization');
    masks.drag = tblR2.io.contamination_mask( ...
        S_visual.X, S_visual.Y, region, 'drag');
end

S_drag = S_visual;
for k = 1:numel(stat_fields)
    name = stat_fields{k};
    visual_values = S_visual.(name);
    drag_values = S_drag.(name);
    visual_values(masks.visualization) = NaN;
    drag_values(masks.drag) = NaN;
    S_visual.(name) = visual_values;
    S_drag.(name) = drag_values;
end
end
