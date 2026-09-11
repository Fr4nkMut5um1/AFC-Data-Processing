function [merged_table, merge_log] = merge_streamwise_neighbors( ...
    structures_table, positive_labels, negative_labels, ...
    X_mm, Y_mm, delta_grid, dx_mm, dy_mm, field, opts)
%MERGE_STREAMWISE_NEIGHBORS Merge same-sign structures close in streamwise direction.

merge_log = struct('n_merges', 0, 'n_before', 0, 'n_after', 0);

if isempty(structures_table) || ~isfield(opts, 'merge_gap_cells') || ...
        opts.merge_gap_cells <= 0
    merged_table = structures_table;
    return;
end

gap_tol_mm = opts.merge_gap_cells * dx_mm;
n_before = height(structures_table);
merge_log.n_before = n_before;

require_y_overlap = true;
if isfield(opts, 'merge_require_y_overlap')
    require_y_overlap = opts.merge_require_y_overlap;
end

parent = (1:n_before)';

pos_idx = find(structures_table.Sign > 0);
neg_idx = find(structures_table.Sign < 0);

merge_sign_group(pos_idx);
merge_sign_group(neg_idx);

groups = resolve_groups(parent);
unique_groups = unique(groups);
n_merges = n_before - numel(unique_groups);
merge_log.n_merges = n_merges;

if n_merges == 0
    merged_table = structures_table;
    merge_log.n_after = n_before;
    return;
end

new_rows = cell(numel(unique_groups), 1);
for ig = 1:numel(unique_groups)
    members = find(groups == unique_groups(ig));
    if numel(members) == 1
        new_rows{ig} = structures_table(members, :);
    else
        new_rows{ig} = merge_group(members);
    end
end

merged_table = vertcat(new_rows{:});
merged_table.StructureID = (1:height(merged_table))';

for sign_val = [1, -1]
    idx_s = find(merged_table.Sign == sign_val);
    if numel(idx_s) < 2, continue; end
    cx = merged_table.CentroidX_mm(idx_s);
    [~, ord] = sort(cx);
    sorted_cx = cx(ord);
    sp = nan(size(sorted_cx));
    sp(2:end) = diff(sorted_cx);
    for kk = 1:numel(ord)
        merged_table.Spacing_mm(idx_s(ord(kk))) = sp(kk);
    end
end

merge_log.n_after = height(merged_table);

% --- nested helpers ---

    function merge_sign_group(idx)
        if numel(idx) < 2, return; end
        xmin = structures_table.XMin_mm(idx);
        xmax = structures_table.XMax_mm(idx);
        ymin = structures_table.YMin_mm(idx);
        ymax = structures_table.YMax_mm(idx);
        [~, ord] = sort(xmin);
        sorted_idx = idx(ord);
        sorted_xmin = xmin(ord);
        sorted_xmax = xmax(ord);
        sorted_ymin = ymin(ord);
        sorted_ymax = ymax(ord);
        running_xmax = sorted_xmax(1);
        running_ymin = sorted_ymin(1);
        running_ymax = sorted_ymax(1);
        running_rep = sorted_idx(1);
        for k = 2:numel(sorted_idx)
            gap = sorted_xmin(k) - running_xmax;
            if gap <= gap_tol_mm
                y_overlaps = max(running_ymin, sorted_ymin(k)) <= ...
                    min(running_ymax, sorted_ymax(k));
                if ~require_y_overlap || y_overlaps
                    union_pair(running_rep, sorted_idx(k));
                    running_xmax = max(running_xmax, sorted_xmax(k));
                    running_ymin = min(running_ymin, sorted_ymin(k));
                    running_ymax = max(running_ymax, sorted_ymax(k));
                    continue;
                end
                % y does not overlap but gap is within tolerance: skip this
                % element without resetting running state — later elements
                % may still merge with the running group.
                continue;
            end
            % gap exceeds tolerance: start a new running group
            running_xmax = sorted_xmax(k);
            running_ymin = sorted_ymin(k);
            running_ymax = sorted_ymax(k);
            running_rep = sorted_idx(k);
        end
    end

    function union_pair(a, b)
        ra = find_root(a);
        rb = find_root(b);
        if ra ~= rb
            parent(rb) = ra;
        end
    end

    function r = find_root(x)
        r = x;
        while parent(r) ~= r
            parent(r) = parent(parent(r));
            r = parent(r);
        end
    end

    function g = resolve_groups(p)
        g = zeros(size(p));
        for ii = 1:numel(p)
            g(ii) = find_root(ii);
        end
    end

    function row_table = merge_group(members)
        sign_value = structures_table.Sign(members(1));
        if sign_value > 0
            lbl_img = positive_labels;
            label_offset = 0;
        else
            lbl_img = negative_labels;
            label_offset = sum(structures_table.Sign > 0);
        end
        all_pixels = [];
        for im = 1:numel(members)
            label_in_img = structures_table.StructureID(members(im)) - label_offset;
            pix = find(lbl_img == label_in_img);
            all_pixels = [all_pixels; pix]; %#ok<AGROW>
        end
        if isempty(all_pixels)
            all_pixels = collect_pixels_from_bbox(members, sign_value, lbl_img);
        end
        geom = tblR2.vlsm.structure_geometry( ...
            X_mm, Y_mm, delta_grid, dx_mm, dy_mm, all_pixels, sign_value, field);
        [wx, wy, wsum, wmean, fallback] = velocity_weighted_center( ...
            X_mm, Y_mm, field, all_pixels, sign_value);
        geom.CentroidVelWeightedX_mm = wx;
        geom.CentroidVelWeightedY_mm = wy;
        geom.CentroidVelWeightedOffsetX_mm = wx - geom.CentroidX_mm;
        geom.CentroidVelWeightedOffsetY_mm = wy - geom.CentroidY_mm;
        geom.VelocityWeightSum = wsum;
        geom.VelocityWeightMean = wmean;
        geom.CenterFallbackFlag = fallback;
        geom.AspectRatio = max(geom.LengthX_mm, geom.HeightY_mm) / ...
            min(geom.LengthX_mm, geom.HeightY_mm);
        geom.IsLSM = geom.LengthX_over_delta >= opts.min_lsm_delta;
        geom.IsVLSM = geom.LengthX_over_delta >= opts.min_vlsm_delta;
        geom.Alpha = structures_table.Alpha(members(1));
        geom.Connectivity = structures_table.Connectivity(members(1));
        geom.Spacing_mm = NaN;
        geom.StructureID = 0;
        row_table = struct2table(geom);
    end

    function pixels = collect_pixels_from_bbox(members, sign_value, lbl_img)
        pixels = [];
        lbl_offset = 0;
        if sign_value < 0
            lbl_offset = sum(structures_table.Sign > 0);
        end
        for im = 1:numel(members)
            label_in_img = structures_table.StructureID(members(im)) - lbl_offset;
            if any(lbl_img(:) == label_in_img)
                pixels = [pixels; find(lbl_img == label_in_img)]; %#ok<AGROW>
            end
        end
    end


    function [x_center, y_center, weight_sum, weight_mean, fallback] = ...
            velocity_weighted_center(x_grid, y_grid, vel_field, pix, sv)
        values = double(vel_field(pix));
        x_values = double(x_grid(pix));
        y_values = double(y_grid(pix));
        if sv > 0
            weights = max(values, 0);
        else
            weights = max(-values, 0);
        end
        weight_sum = sum(weights, 'omitnan');
        weight_mean = mean(weights, 'omitnan');
        fallback = false;
        if weight_sum > 0
            x_center = sum(weights .* x_values, 'omitnan') / weight_sum;
            y_center = sum(weights .* y_values, 'omitnan') / weight_sum;
        else
            x_center = mean(x_values, 'omitnan');
            y_center = mean(y_values, 'omitnan');
            fallback = true;
        end
    end

end
