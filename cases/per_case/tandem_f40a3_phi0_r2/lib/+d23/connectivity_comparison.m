function comparison = connectivity_comparison(ss_catalog, ctx, cfg)
%CONNECTIVITY_COMPARISON Compare 8/4-neighbor SS without a one-object limit.
% Each row remains a frame x sign unit. ObjectCount8/ObjectCount4 preserve
% multi-object information; geometry columns describe the deterministic
% longest representative in that unit.
thresholds = double(cfg.detection.length_thresholds(:));
frame_ordinals = uint32(cfg.execution.frame_ordinals(:));
frame_ids = uint32(ctx.frame_ids(double(frame_ordinals)));
n_frames = numel(frame_ordinals);
unit_frames = repelem(frame_ordinals, 2); unit_frames = unit_frames(:);
unit_ids = repelem(frame_ids, 2); unit_ids = unit_ids(:);
unit_signs = repmat(int8([1; -1]), n_frames, 1);
unit_keys = make_keys(unit_frames, unit_signs);

parts = cell(numel(thresholds), 1);
summary_parts = cell(numel(thresholds), 1);
flag_names = {'IsSS3','IsSS3p8','IsSS4p5'};
for k = 1:numel(thresholds)
    eligible = ss_catalog.(flag_names{k}) & ~ss_catalog.IsCensored;
    [count8, rep8] = summarize_connectivity(ss_catalog, ...
        eligible & ss_catalog.Connectivity == 8, unit_keys);
    [count4, rep4] = summarize_connectivity(ss_catalog, ...
        eligible & ss_catalog.Connectivity == 4, unit_keys);
    present8 = count8 > 0;
    present4 = count4 > 0;
    both = present8 & present4;
    only8 = present8 & ~present4;
    only4 = ~present8 & present4;
    neither = ~present8 & ~present4;
    bbox_iou = nan(numel(unit_keys), 1);
    bbox_iou(both) = box_iou(rep8.col_min(both), rep8.col_max(both), ...
        rep8.row_min(both), rep8.row_max(both), rep4.col_min(both), ...
        rep4.col_max(both), rep4.row_min(both), rep4.row_max(both));
    category = repmat("neither", numel(unit_keys), 1);
    category(both) = "both";
    category(only8) = "only_8";
    category(only4) = "only_4";
    representative_policy = repmat( ...
        "longest_then_pixel_count_then_component_id", numel(unit_keys), 1);
    delta_lx = rep8.lx - rep4.lx;
    parts{k} = table(repmat(thresholds(k), numel(unit_keys), 1), ...
        unit_frames, unit_ids, unit_signs, uint32(count8), uint32(count4), ...
        present8, present4, category, rep8.component, rep4.component, ...
        rep8.lx, rep4.lx, delta_lx, ...
        rep8.col_min, rep8.col_max, rep8.row_min, rep8.row_max, ...
        rep4.col_min, rep4.col_max, rep4.row_min, rep4.row_max, bbox_iou, ...
        representative_policy, 'VariableNames', ...
        {'LengthThreshold','FrameOrdinal','FrameID','Sign','ObjectCount8', ...
        'ObjectCount4','Has8','Has4','Category','ComponentID8','ComponentID4', ...
        'LxOverDelta8','LxOverDelta4','DeltaLxOverDelta8Minus4', ...
        'ColMin8','ColMax8','RowMin8','RowMax8','ColMin4','ColMax4', ...
        'RowMin4','RowMax4','BBoxIoU','RepresentativePolicy'});

    union_count = nnz(present8 | present4);
    both_count = nnz(both);
    summary_parts{k} = table(thresholds(k), uint32(numel(unit_keys)), ...
        uint32(nnz(present8)), uint32(nnz(present4)), ...
        uint32(sum(count8)), uint32(sum(count4)), uint32(both_count), ...
        uint32(nnz(only8)), uint32(nnz(only4)), uint32(nnz(neither)), ...
        uint32(union_count), ratio_or_nan(both_count, union_count), ...
        ratio_or_nan(both_count, nnz(present8)), ...
        ratio_or_nan(both_count, nnz(present4)), mean_or_nan(bbox_iou(both)), ...
        median_or_nan(bbox_iou(both)), mean_or_nan(delta_lx(both)), ...
        median_or_nan(abs(delta_lx(both))), ...
        'VariableNames', {'LengthThreshold','FrameSignUnits','Detected8', ...
        'Detected4','ObjectCount8','ObjectCount4','Both','Only8','Only4', ...
        'Neither','Union','FrameSignJaccard','Fraction8Also4', ...
        'Fraction4Also8','MeanBBoxIoU','MedianBBoxIoU', ...
        'MeanDeltaLxOverDelta8Minus4','MedianAbsDeltaLxOverDelta'});
end

frame_sign_table = vertcat(parts{:});
comparison = struct('schema_version', 2, ...
    'unit_definition', ['frame x fluctuation sign; complete uncensored SS ' ...
    'counts with longest representative geometry'], ...
    'selection_definition', cfg.detection.selection_rule, ...
    'frame_sign_table', frame_sign_table, ...
    'paired_table', frame_sign_table(frame_sign_table.Category == "both", :), ...
    'summary_table', vertcat(summary_parts{:}));
end

function [counts, representative] = summarize_connectivity(catalog, eligible, unit_keys)
n = numel(unit_keys);
counts = zeros(n, 1, 'uint32');
representative = empty_representative(n);
rows = find(eligible);
if isempty(rows)
    return;
end
keys = make_keys(catalog.FrameOrdinal(rows), catalog.Sign(rows));
[found, locations] = ismember(keys, unit_keys);
if ~all(found)
    error('d23:connectivity_comparison:FrameCoverage', ...
        'The SS catalog contains a frame outside execution.frame_ordinals.');
end
counts = uint32(accumarray(locations, 1, [n 1], @sum, 0));
sort_key = [double(locations), -double(catalog.Lx_over_delta(rows)), ...
    -double(catalog.PixelCount(rows)), double(catalog.ComponentID(rows))];
[~, order] = sortrows(sort_key, [1 2 3 4]);
sorted_rows = rows(order);
sorted_locations = locations(order);
is_first = [true; diff(sorted_locations) ~= 0];
first_rows = sorted_rows(is_first);
first_locations = sorted_locations(is_first);
representative.component(first_locations) = catalog.ComponentID(first_rows);
representative.lx(first_locations) = catalog.Lx_over_delta(first_rows);
representative.col_min(first_locations) = catalog.ColMin(first_rows);
representative.col_max(first_locations) = catalog.ColMax(first_rows);
representative.row_min(first_locations) = catalog.RowMin(first_rows);
representative.row_max(first_locations) = catalog.RowMax(first_rows);
end

function value = empty_representative(n)
value = struct('component', zeros(n,1,'uint32'), 'lx', nan(n,1), ...
    'col_min', zeros(n,1,'uint16'), 'col_max', zeros(n,1,'uint16'), ...
    'row_min', zeros(n,1,'uint16'), 'row_max', zeros(n,1,'uint16'));
end

function keys = make_keys(frames, signs)
keys = uint64(frames) * 2 + uint64(signs == -1);
end

function value = box_iou(cmin1, cmax1, rmin1, rmax1, cmin2, cmax2, rmin2, rmax2)
intersection_width = max(0, double(min(cmax1, cmax2)) - ...
    double(max(cmin1, cmin2)) + 1);
intersection_height = max(0, double(min(rmax1, rmax2)) - ...
    double(max(rmin1, rmin2)) + 1);
intersection = intersection_width .* intersection_height;
area1 = (double(cmax1) - double(cmin1) + 1) .* ...
    (double(rmax1) - double(rmin1) + 1);
area2 = (double(cmax2) - double(cmin2) + 1) .* ...
    (double(rmax2) - double(rmin2) + 1);
value = intersection ./ (area1 + area2 - intersection);
end

function value = ratio_or_nan(numerator, denominator)
if denominator == 0
    value = NaN;
else
    value = double(numerator) / double(denominator);
end
end

function value = mean_or_nan(values)
if isempty(values)
    value = NaN;
else
    value = mean(values);
end
end

function value = median_or_nan(values)
if isempty(values)
    value = NaN;
else
    value = median(values);
end
end
