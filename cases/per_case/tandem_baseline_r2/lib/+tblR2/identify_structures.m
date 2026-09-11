function result = identify_structures(field, local_scale, X_mm, Y_mm, ...
    delta99_mm, valid_mask, opts)
%IDENTIFY_STRUCTURES Label positive/negative 2-D connected structures.

if ~isequal(size(field), size(local_scale), size(X_mm), size(Y_mm), size(valid_mask))
    error('tblR2:identify_structures:SizeMismatch', ...
        'field、local_scale、X_mm、Y_mm 和 valid_mask 必须具有相同尺寸。');
end
if ~islogical(valid_mask) || ~ismatrix(field)
    error('tblR2:identify_structures:InvalidMask', ...
        'valid_mask 必须是同尺寸的二维逻辑数组。');
end
% min_pixels is a resolution floor: a component with fewer than this many
% grid cells is discarded as a one-/two-point fragment.  It is not a proof
% that the surviving component is a dynamically independent structure.
% max_wall_normal_delta is an optional physical y/delta99 cap; Inf disables
% that cap, leaving only the external trusted-domain crop to define the mask.
% max_internal_hole_pixels fills fully enclosed sub-threshold/reverse-sign
% islands before labeling.  envelope_closing_radius_cells additionally closes
% narrow notches in the threshold mask, but retains only added patches no
% larger than max_internal_hole_pixels.  This changes only binary topology,
% never the measured velocity field.  seed_alpha optionally enables signed
% hysteresis connectivity: alpha is the relaxed envelope/growth threshold,
% while every retained component must contain at least one seed_alpha core
% point.  max_aspect_ratio rejects components
% whose physical bounding-box long/short side ratio is too large; Inf disables
% it.  reject_trusted_boundary_touching removes incomplete components that
% intersect the retained upstream/downstream or free-stream FOV boundary; the
% wall-side boundary is deliberately retained.
if ~isfield(opts, 'max_internal_hole_pixels') || ...
        isempty(opts.max_internal_hole_pixels)
    opts.max_internal_hole_pixels = 0;
end
if ~isfield(opts, 'max_aspect_ratio') || isempty(opts.max_aspect_ratio)
    opts.max_aspect_ratio = inf;
end
if ~isfield(opts, 'envelope_closing_radius_cells') || ...
        isempty(opts.envelope_closing_radius_cells)
    opts.envelope_closing_radius_cells = 0;
end
if ~isfield(opts, 'reject_trusted_boundary_touching') || ...
        isempty(opts.reject_trusted_boundary_touching)
    opts.reject_trusted_boundary_touching = false;
end
if ~isfield(opts, 'seed_alpha') || isempty(opts.seed_alpha)
    opts.seed_alpha = opts.alpha;
end
% min_abs_fluctuation is an absolute-amplitude floor (same units as field).
% A pixel must satisfy BOTH the normalised threshold and |u'| >= this floor to
% join a structure.  In the outer layer the local u_rms is small, so a weak
% absolute fluctuation can still exceed alpha*u_rms and bridge otherwise
% independent structures into one FOV-spanning cluster.  0 disables the floor.
if ~isfield(opts, 'min_abs_fluctuation') || isempty(opts.min_abs_fluctuation)
    opts.min_abs_fluctuation = 0;
end
% min_abs_seed_fluctuation is the same floor applied to the seed (core) mask;
% empty/absent falls back to min_abs_fluctuation.
if ~isfield(opts, 'min_abs_seed_fluctuation') || ...
        isempty(opts.min_abs_seed_fluctuation)
    opts.min_abs_seed_fluctuation = opts.min_abs_fluctuation;
end
required = {'alpha', 'min_pixels', 'connectivity', 'min_lsm_delta', ...
    'min_vlsm_delta', 'max_wall_normal_delta', 'sign_mode'};
missing = required(~isfield(opts, required));
if ~isempty(missing)
    error('tblR2:identify_structures:MissingOptions', ...
        '缺少结构选项：%s。', strjoin(missing, ', '));
end
if ~ismember(opts.connectivity, [4 8])
    error('tblR2:identify_structures:InvalidConnectivity', ...
        'connectivity 必须为 4 或 8。');
end
if ~ismember(char(opts.sign_mode), {'both', 'positive', 'negative'})
    error('tblR2:identify_structures:InvalidSignMode', ...
        'sign_mode 必须是 both、positive 或 negative。');
end
if ~(isnumeric(opts.alpha) && isscalar(opts.alpha) && ...
        isreal(opts.alpha) && isfinite(opts.alpha) && opts.alpha > 0 && ...
        isnumeric(opts.seed_alpha) && isscalar(opts.seed_alpha) && ...
        isreal(opts.seed_alpha) && isfinite(opts.seed_alpha) && ...
        opts.seed_alpha >= opts.alpha)
    error('tblR2:identify_structures:InvalidHysteresisThreshold', ...
        'alpha 必须为正数，seed_alpha 必须有限且不小于 alpha。');
end
if ~(isnumeric(opts.max_internal_hole_pixels) && ...
        isscalar(opts.max_internal_hole_pixels) && ...
        isfinite(opts.max_internal_hole_pixels) && ...
        opts.max_internal_hole_pixels >= 0 && ...
        opts.max_internal_hole_pixels == floor(opts.max_internal_hole_pixels))
    error('tblR2:identify_structures:InvalidHoleSize', ...
        'max_internal_hole_pixels 必须是非负整数。');
end
if ~(isnumeric(opts.max_aspect_ratio) && isscalar(opts.max_aspect_ratio) && ...
        isreal(opts.max_aspect_ratio) && ...
        (isinf(opts.max_aspect_ratio) || ...
        (isfinite(opts.max_aspect_ratio) && opts.max_aspect_ratio >= 1)))
    error('tblR2:identify_structures:InvalidAspectRatio', ...
        'max_aspect_ratio 必须是大于等于 1 的标量或 Inf。');
end
if ~(isnumeric(opts.envelope_closing_radius_cells) && ...
        isscalar(opts.envelope_closing_radius_cells) && ...
        isfinite(opts.envelope_closing_radius_cells) && ...
        opts.envelope_closing_radius_cells >= 0 && ...
        opts.envelope_closing_radius_cells == ...
        floor(opts.envelope_closing_radius_cells))
    error('tblR2:identify_structures:InvalidClosingRadius', ...
        'envelope_closing_radius_cells 必须是非负整数。');
end
if ~(isscalar(opts.reject_trusted_boundary_touching) && ...
        (islogical(opts.reject_trusted_boundary_touching) || ...
        ismember(opts.reject_trusted_boundary_touching, [0 1])))
    error('tblR2:identify_structures:InvalidBoundaryRejection', ...
        'reject_trusted_boundary_touching 必须是逻辑标量。');
end

delta_grid = expand_delta(delta99_mm, X_mm);
analysis_mask = valid_mask & isfinite(field) & isfinite(local_scale) & ...
    local_scale > 0 & isfinite(delta_grid) & delta_grid > 0 & ...
    (isinf(opts.max_wall_normal_delta) | ...
    Y_mm <= opts.max_wall_normal_delta .* delta_grid);
normalized = nan(size(field));
normalized(analysis_mask) = field(analysis_mask) ./ local_scale(analysis_mask);

growth_positive_mask = false(size(field));
growth_negative_mask = false(size(field));
seed_positive_mask = false(size(field));
seed_negative_mask = false(size(field));
if ismember(char(opts.sign_mode), {'both', 'positive'})
    growth_positive_mask = analysis_mask & normalized >= opts.alpha;
    seed_positive_mask = analysis_mask & normalized >= opts.seed_alpha;
end
if ismember(char(opts.sign_mode), {'both', 'negative'})
    growth_negative_mask = analysis_mask & normalized <= -opts.alpha;
    seed_negative_mask = analysis_mask & normalized <= -opts.seed_alpha;
end
% Absolute amplitude floor: exclude pixels whose physical |u'| is too weak,
% even if they pass the normalised threshold (prevents outer-layer bridging).
if opts.min_abs_fluctuation > 0
    abs_field = abs(field);
    growth_positive_mask = growth_positive_mask & abs_field >= opts.min_abs_fluctuation;
    growth_negative_mask = growth_negative_mask & abs_field >= opts.min_abs_fluctuation;
end
if opts.min_abs_seed_fluctuation > 0
    if ~exist('abs_field', 'var'), abs_field = abs(field); end
    seed_positive_mask = seed_positive_mask & abs_field >= opts.min_abs_seed_fluctuation;
    seed_negative_mask = seed_negative_mask & abs_field >= opts.min_abs_seed_fluctuation;
end

% Hysteresis keeps only relaxed-threshold components attached to at least one
% strict same-sign core.  Thus weak pixels can restore a physical envelope,
% whereas isolated low-amplitude PIV speckles cannot seed new structures.
threshold_positive_mask = retain_seeded_components( ...
    growth_positive_mask, seed_positive_mask, opts.connectivity);
threshold_negative_mask = retain_seeded_components( ...
    growth_negative_mask, seed_negative_mask, opts.connectivity);

% First close narrow boundary notches in the signed threshold masks.  Only
% small added patches are retained, so a long low-amplitude corridor cannot
% merge otherwise independent structures.  Fully enclosed holes are filled
% afterwards.  A small reverse-sign island is absorbed into the surrounding
% sign and removed from the competing mask.
[positive_closed, positive_closing] = close_small_envelope_gaps( ...
    threshold_positive_mask, analysis_mask, ...
    opts.envelope_closing_radius_cells, opts.max_internal_hole_pixels, ...
    opts.connectivity);
[negative_closed, negative_closing] = close_small_envelope_gaps( ...
    threshold_negative_mask, analysis_mask, ...
    opts.envelope_closing_radius_cells, opts.max_internal_hole_pixels, ...
    opts.connectivity);
[positive_mask, positive_cleanup] = fill_small_enclosed_holes( ...
    positive_closed, analysis_mask, ...
    opts.max_internal_hole_pixels, opts.connectivity);
[negative_mask, negative_cleanup] = fill_small_enclosed_holes( ...
    negative_closed, analysis_mask, ...
    opts.max_internal_hole_pixels, opts.connectivity);
positive_added = positive_mask & ~threshold_positive_mask;
negative_added = negative_mask & ~threshold_negative_mask;
negative_mask(positive_added & threshold_negative_mask) = false;
positive_mask(negative_added & threshold_positive_mask) = false;
overlap = positive_mask & negative_mask;
positive_mask(overlap) = normalized(overlap) >= 0;
negative_mask(overlap) = normalized(overlap) < 0;

dx = median(abs(diff(X_mm(1, :))), 'omitnan');
dy = median(abs(diff(Y_mm(:, 1))), 'omitnan');
trusted_boundary_mask = outer_trusted_boundary(analysis_mask, Y_mm);
[positive_labels, positive_rows, positive_aspect_rejected, ...
    positive_boundary_rejected] = ...
    label_sign(positive_mask, 1, dx, dy);
[negative_labels, negative_rows, negative_aspect_rejected, ...
    negative_boundary_rejected] = ...
    label_sign(negative_mask, -1, dx, dy);
rows = [positive_rows; negative_rows];
if isempty(rows)
    structures = empty_structure_table();
else
    structures = struct2table(rows);
    structures.StructureID = (1:height(structures))';
    structures = movevars(structures, 'StructureID', 'Before', 1);
end

result = struct();
result.normalized_field = normalized;
result.analysis_mask = analysis_mask;
result.threshold_positive_mask = threshold_positive_mask;
result.threshold_negative_mask = threshold_negative_mask;
result.growth_positive_mask = growth_positive_mask;
result.growth_negative_mask = growth_negative_mask;
result.seed_positive_mask = seed_positive_mask;
result.seed_negative_mask = seed_negative_mask;
result.positive_mask = positive_mask;
result.negative_mask = negative_mask;
result.positive_labels = positive_labels;
result.negative_labels = negative_labels;
result.structures = structures;
result.options = opts;
result.topology_cleanup = struct( ...
    'max_internal_hole_pixels', opts.max_internal_hole_pixels, ...
    'envelope_closing_radius_cells', ...
        opts.envelope_closing_radius_cells, ...
    'positive_closed_patches', positive_closing.closed_patches, ...
    'positive_closed_pixels', positive_closing.closed_pixels, ...
    'negative_closed_patches', negative_closing.closed_patches, ...
    'negative_closed_pixels', negative_closing.closed_pixels, ...
    'positive_filled_holes', positive_cleanup.filled_holes, ...
    'positive_filled_pixels', positive_cleanup.filled_pixels, ...
    'negative_filled_holes', negative_cleanup.filled_holes, ...
    'negative_filled_pixels', negative_cleanup.filled_pixels);
result.rejected_aspect_ratio_count = ...
    positive_aspect_rejected + negative_aspect_rejected;
result.rejected_trusted_boundary_count = ...
    positive_boundary_rejected + negative_boundary_rejected;
result.trusted_boundary_mask = trusted_boundary_mask;
result.method = sprintf([ ...
    '%d-neighbour signed hysteresis components (growth alpha %.6g, seed alpha %.6g); ' ...
    'envelope closing radius %d; ' ...
    'enclosed/closed patches <= %d pixels; bounding-box aspect ratio <= %.6g; ' ...
    'reject trusted-boundary touching = %d'], opts.connectivity, opts.alpha, ...
    opts.seed_alpha, opts.envelope_closing_radius_cells, ...
    opts.max_internal_hole_pixels, ...
    opts.max_aspect_ratio, logical(opts.reject_trusted_boundary_touching));

    function [labels, structure_rows, aspect_rejected, boundary_rejected] = ...
            label_sign(mask, sign_value, dx, dy)
        labels = zeros(size(mask), 'uint32');
        structure_rows = repmat(empty_structure_row(), 0, 1);
        aspect_rejected = 0;
        boundary_rejected = 0;
        if ~any(mask(:))
            return;
        end
        pixels = connected_pixels(mask, opts.connectivity);
        for ic = 1:numel(pixels)
            idx = pixels{ic};
            if numel(idx) < opts.min_pixels
                continue;
            end
            row = tblR2.vlsm.structure_geometry( ...
                X_mm, Y_mm, delta_grid, dx, dy, idx, sign_value, field);
            [weighted_x, weighted_y, weight_sum, weight_mean, fallback] = ...
                velocity_weighted_center(X_mm, Y_mm, field, idx, sign_value);
            row.CentroidVelWeightedX_mm = weighted_x;
            row.CentroidVelWeightedY_mm = weighted_y;
            row.CentroidVelWeightedOffsetX_mm = weighted_x - row.CentroidX_mm;
            row.CentroidVelWeightedOffsetY_mm = weighted_y - row.CentroidY_mm;
            row.VelocityWeightSum = weight_sum;
            row.VelocityWeightMean = weight_mean;
            row.CenterFallbackFlag = fallback;
            row.AspectRatio = max(row.LengthX_mm, row.HeightY_mm) / ...
                min(row.LengthX_mm, row.HeightY_mm);
            if ~isfinite(row.AspectRatio) || ...
                    row.AspectRatio > opts.max_aspect_ratio
                aspect_rejected = aspect_rejected + 1;
                continue;
            end
            if opts.reject_trusted_boundary_touching && ...
                    any(trusted_boundary_mask(idx))
                boundary_rejected = boundary_rejected + 1;
                continue;
            end
            label_id = numel(structure_rows) + 1;
            labels(idx) = uint32(label_id);
            row.IsLSM = row.LengthX_over_delta >= opts.min_lsm_delta;
            row.IsVLSM = row.LengthX_over_delta >= opts.min_vlsm_delta;
            row.Alpha = opts.alpha;
            row.Connectivity = opts.connectivity;
            row.Spacing_mm = NaN;              % filled below after same-sign sorting
            structure_rows(end + 1, 1) = row;  %#ok<AGROW>
        end
        if numel(structure_rows) > 1
            % Same-sign streamwise spacing: neighbour centroid distance in
            % mm after sorting by centroid x; leading structure is NaN.
            [~, ord] = sort([structure_rows.CentroidX_mm]);
            sorted_x = [structure_rows(ord).CentroidX_mm];
            spacing = nan(size(sorted_x));
            spacing(2:end) = diff(sorted_x);
            for k = 1:numel(ord)
                structure_rows(ord(k)).Spacing_mm = spacing(k);
            end
        end
    end

    function pixels = connected_pixels(mask, connectivity)
        if exist('bwconncomp', 'file') == 2
            try
                cc = bwconncomp(mask, connectivity);
                pixels = cc.PixelIdxList;
                return;
            catch
                % A missing/unlicensed toolbox falls through to the fallback.
            end
        end
        pixels = tblR2.vlsm.connected_components_2d(mask, connectivity);
    end

    function [x_center, y_center, weight_sum, weight_mean, fallback] = ...
            velocity_weighted_center(x_grid, y_grid, velocity_field, idx, sign_value)
        values = double(velocity_field(idx));
        x_values = double(x_grid(idx));
        y_values = double(y_grid(idx));
        if sign_value > 0
            weights = max(values, 0);
        else
            weights = max(-values, 0);
        end
        good = isfinite(weights) & isfinite(x_values) & isfinite(y_values);
        weights = weights(good);
        x_values = x_values(good);
        y_values = y_values(good);
        weight_sum = sum(weights);
        fallback = isempty(weights) || weight_sum <= 0;
        if fallback
            x_center = NaN;
            y_center = NaN;
            weight_mean = NaN;
            return;
        end
        x_center = sum(weights .* x_values) ./ weight_sum;
        y_center = sum(weights .* y_values) ./ weight_sum;
        weight_mean = mean(weights);
    end

    function retained = retain_seeded_components(growth_mask, seed_mask, ...
            connectivity)
        retained = false(size(growth_mask));
        if ~any(growth_mask(:)) || ~any(seed_mask(:))
            return;
        end
        components = connected_pixels(growth_mask, connectivity);
        for icomp = 1:numel(components)
            idx = components{icomp};
            if any(seed_mask(idx))
                retained(idx) = true;
            end
        end
    end

    function [filled_mask, cleanup] = fill_small_enclosed_holes( ...
            mask, valid_domain, max_hole_pixels, foreground_connectivity)
        filled_mask = mask;
        cleanup = struct('filled_holes', 0, 'filled_pixels', 0);
        if max_hole_pixels == 0 || ~any(mask(:))
            return;
        end
        % Use dual foreground/background connectivity (8/4 or 4/8) so a
        % diagonal contact is not simultaneously interpreted as connected in
        % both phases.  The full complement includes invalid/trusted-domain
        % exterior pixels; only components wholly inside valid_domain and not
        % touching the array border qualify as enclosed holes.
        background_connectivity = 12 - foreground_connectivity;
        background_components = connected_pixels( ...
            ~mask, background_connectivity);
        [n_rows, n_cols] = size(mask);
        for ih = 1:numel(background_components)
            idx = background_components{ih};
            if numel(idx) > max_hole_pixels || ~all(valid_domain(idx))
                continue;
            end
            [row_idx, col_idx] = ind2sub([n_rows n_cols], idx);
            touches_array_edge = any(row_idx == 1 | row_idx == n_rows | ...
                col_idx == 1 | col_idx == n_cols);
            if touches_array_edge
                continue;
            end
            filled_mask(idx) = true;
            cleanup.filled_holes = cleanup.filled_holes + 1;
            cleanup.filled_pixels = cleanup.filled_pixels + numel(idx);
        end
    end

    function [closed_mask, cleanup] = close_small_envelope_gaps( ...
            mask, valid_domain, radius, max_patch_pixels, connectivity)
        closed_mask = mask;
        cleanup = struct('closed_patches', 0, 'closed_pixels', 0);
        if radius == 0 || max_patch_pixels == 0 || ~any(mask(:))
            return;
        end
        kernel = ones(2 * radius + 1);
        dilated = conv2(double(mask), kernel, 'same') > 0;
        eroded = conv2(double(dilated), kernel, 'same') == numel(kernel);
        candidate = eroded & valid_domain & ~mask;
        patches = connected_pixels(candidate, connectivity);
        for ip = 1:numel(patches)
            idx = patches{ip};
            if numel(idx) > max_patch_pixels
                continue;
            end
            closed_mask(idx) = true;
            cleanup.closed_patches = cleanup.closed_patches + 1;
            cleanup.closed_pixels = cleanup.closed_pixels + numel(idx);
        end
    end

    function boundary = outer_trusted_boundary(domain, y_grid)
        % Mark only the retained upstream/downstream and maximum-y boundary.
        % Internal invalid holes are not treated as trusted-domain boundaries,
        % and the minimum-y wall-side boundary remains eligible for structures.
        boundary = false(size(domain));
        [n_rows, n_cols] = size(domain);
        for ir = 1:n_rows
            cols = find(domain(ir, :));
            if ~isempty(cols)
                boundary(ir, cols(1)) = true;
                boundary(ir, cols(end)) = true;
            end
        end
        for ic = 1:n_cols
            rows = find(domain(:, ic) & isfinite(y_grid(:, ic)));
            if isempty(rows)
                continue;
            end
            [~, pos] = max(y_grid(rows, ic));
            boundary(rows(pos), ic) = true;
        end
    end
end

function delta_grid = expand_delta(delta99_mm, X_mm)
if isscalar(delta99_mm)
    delta_grid = repmat(double(delta99_mm), size(X_mm));
elseif isvector(delta99_mm) && numel(delta99_mm) == size(X_mm, 2)
    delta_grid = repmat(reshape(double(delta99_mm), 1, []), size(X_mm, 1), 1);
elseif isequal(size(delta99_mm), size(X_mm))
    delta_grid = double(delta99_mm);
else
    error('tblR2:identify_structures:InvalidDelta99', ...
        'delta99_mm 必须是标量、每个 x 列一个值，或与网格同尺寸的完整数组。');
end
end

function row = empty_structure_row()
row = struct('Sign', 0, 'PixelCount', 0, 'Area_mm2', NaN, ...
    'CentroidX_mm', NaN, 'CentroidY_mm', NaN, ...
    'CentroidVelWeightedX_mm', NaN, 'CentroidVelWeightedY_mm', NaN, ...
    'CentroidVelWeightedOffsetX_mm', NaN, ...
    'CentroidVelWeightedOffsetY_mm', NaN, ...
    'VelocityWeightSum', NaN, 'VelocityWeightMean', NaN, ...
    'CenterFallbackFlag', false, ...
    'XMin_mm', NaN, 'XMax_mm', NaN, 'YMin_mm', NaN, 'YMax_mm', NaN, ...
    'LengthX_mm', NaN, 'HeightY_mm', NaN, 'Delta99Ref_mm', NaN, ...
    'AspectRatio', NaN, ...
    'LengthX_over_delta', NaN, 'HeightY_over_delta', NaN, ...
    'Area_over_delta2', NaN, 'uMean', NaN, 'peakAmp', NaN, ...
    'Spacing_mm', NaN, 'IsLSM', false, 'IsVLSM', false, ...
    'Alpha', NaN, 'Connectivity', 4);
end

function T = empty_structure_table()
row = empty_structure_row();
T = struct2table(repmat(row, 0, 1));
T.StructureID = zeros(0, 1);
T = movevars(T, 'StructureID', 'Before', 1);
end
