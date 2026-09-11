function out = identify_quadrant_structures(u_prime, v_prime, u_rms, v_rms, ...
        X_mm, Y_mm, delta99_mm, valid_mask, total_identified, opts)
%IDENTIFY_QUADRANT_STRUCTURES Identify Q2/Q4 |u'v'| threshold objects.
% Q2 is the ejection quadrant (u'<0,v'>0); Q4 is the sweep quadrant
% (u'>0,v'<0).  The object criterion is |u'v'| > H*u_rms*v_rms, while
% the sign of u' selects the quadrant.  The returned catalog is explicitly
% a 2-D quadrant proxy and is never mixed with the signed velocity catalog.

if nargin < 9 || isempty(total_identified)
    total_identified = struct();
end
if nargin < 10 || isempty(opts)
    opts = struct();
end
required = {'H', 'connectivity', 'min_pixels', 'min_lsm_delta', ...
    'min_vlsm_delta'};
for i = 1:numel(required)
    if ~isfield(opts, required{i})
        error('tblR2:r2:identify_quadrant_structures:MissingOption', ...
            '缺少象限分析选项 %s。', required{i});
    end
end
if ~isequal(size(u_prime), size(v_prime), size(u_rms), size(v_rms), ...
        size(X_mm), size(Y_mm), size(valid_mask))
    error('tblR2:r2:identify_quadrant_structures:SizeMismatch', ...
        '所有象限字段和掩膜的尺寸必须完全一致。');
end

scale = double(u_rms) .* double(v_rms);
uv = double(u_prime) .* double(v_prime);
criterion = abs(uv) ./ max(scale, eps);
base_valid = valid_mask & isfinite(u_prime) & isfinite(v_prime) & ...
    isfinite(scale) & scale > 0;
threshold = double(opts.H);
% identify_structures requires a positive threshold. H=0 is represented by
% the smallest positive floating-point threshold and is labelled H=0 below.
alpha = max(threshold, eps);
common = struct('alpha', alpha, 'seed_alpha', alpha, ...
    'min_pixels', opts.min_pixels, 'connectivity', opts.connectivity, ...
    'max_internal_hole_pixels', 0, ...
    'envelope_closing_radius_cells', 0, 'max_aspect_ratio', Inf, ...
    'reject_trusted_boundary_touching', false, ...
    'min_lsm_delta', opts.min_lsm_delta, ...
    'min_vlsm_delta', opts.min_vlsm_delta, ...
    'max_wall_normal_delta', Inf);

q2_opts = common; q2_opts.sign_mode = 'negative';
q4_opts = common; q4_opts.sign_mode = 'positive';
q2 = tblR2.identify_structures(-criterion, ones(size(criterion)), ...
    X_mm, Y_mm, delta99_mm, base_valid & (u_prime < 0), q2_opts);
q4 = tblR2.identify_structures(criterion, ones(size(criterion)), ...
    X_mm, Y_mm, delta99_mm, base_valid & (u_prime > 0), q4_opts);
q2.structures = add_quadrant_fields(q2.structures, 'Q2');
q4.structures = add_quadrant_fields(q4.structures, 'Q4');
if ~isempty(q2.structures)
    q2.structures.H = repmat(threshold, height(q2.structures), 1);
end
if ~isempty(q4.structures)
    q4.structures.H = repmat(threshold, height(q4.structures), 1);
end

q2.structures = attach_to_velocity(q2.structures, q2.negative_labels, ...
    total_identified, -1, 'Q2');
q4.structures = attach_to_velocity(q4.structures, q4.positive_labels, ...
    total_identified, 1, 'Q4');

if isempty(q2.structures)
    catalog = q4.structures;
elseif isempty(q4.structures)
    catalog = q2.structures;
else
    catalog = [q2.structures; q4.structures];
end
if ~isempty(catalog)
    catalog = sortrows(catalog, {'Sign', 'CentroidX_mm'});
    catalog.StructureID = (1:height(catalog))';
    catalog = movevars(catalog, 'StructureID', 'Before', 1);
end
out = struct('H', threshold, 'criterion', criterion, ...
    'valid_mask', base_valid, 'q2', q2, 'q4', q4, 'structures', catalog, ...
    'definition', ['Q2/Q4 objects use |u''v''|/(u_rms v_rms) > H; ' ...
    'Q2 is attached to negative-u'' velocity objects and Q4 to positive-u'' ' ...
    'velocity objects. Unattached objects remain explicitly marked.']);

    function T = add_quadrant_fields(T, quadrant)
        n = height(T);
        if n == 0
            T.Quadrant = cell(0, 1);
            T.ParentStructureID = zeros(0, 1);
            T.AttachmentStatus = cell(0, 1);
            T.OverlapPixelCount = zeros(0, 1);
            T = movevars(T, 'Quadrant', 'Before', 1);
            return;
        end
        T = addvars(T, repmat({quadrant}, n, 1), ...
            nan(n, 1), repmat({'unattached'}, n, 1), zeros(n, 1), ...
            'Before', 1, 'NewVariableNames', {'Quadrant', ...
            'ParentStructureID', 'AttachmentStatus', 'OverlapPixelCount'});
    end

    function T = attach_to_velocity(T, labels, velocity_result, sign_value, quadrant)
        if isempty(T) || ~isfield(velocity_result, 'positive_labels')
            return;
        end
        if sign_value < 0
            velocity_labels = velocity_result.negative_labels;
            velocity_offset = count_rows(velocity_result, 1);
        else
            velocity_labels = velocity_result.positive_labels;
            velocity_offset = 0;
        end
        if isempty(velocity_labels)
            return;
        end
        for k = 1:height(T)
            q_label = labels == k;
            overlap = zeros(max(double(max(velocity_labels(:))), 1), 1);
            parent_label = velocity_labels(q_label);
            parent_label = double(parent_label(parent_label > 0));
            if isempty(parent_label)
                continue;
            end
            for j = 1:numel(parent_label)
                overlap(parent_label(j)) = overlap(parent_label(j)) + 1;
            end
            [best, best_label] = max(overlap);
            if best > 0
                T.ParentStructureID(k) = best_label + velocity_offset;
                T.OverlapPixelCount(k) = best;
                T.AttachmentStatus{k} = 'attached';
            else
                T.AttachmentStatus{k} = 'unattached';
            end
        end
        T.Quadrant(:) = {quadrant};
    end

    function n = count_rows(velocity_result, sign_value)
        if ~isfield(velocity_result, 'structures') || isempty(velocity_result.structures)
            n = 0;
        else
            n = nnz(velocity_result.structures.Sign == sign_value);
        end
    end
end
