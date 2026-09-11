function result = cluster_pod_reconstruction(cache_file, cfg, stats, phase_stats, ...
    mean_bl, sequence, pod_result, mode_indices, branch_name)
%CLUSTER_POD_RECONSTRUCTION Cluster u' reconstructed from selected POD modes.
%
% Reconstruction is delegated to tblR2.pod_reconstruction in frame chunks.
% The primary catalog always uses the unchanged raw statistics u_rms field.
% A second catalog uses the POD branch's own reconstructed RMS only as a
% separately labelled sensitivity result.

mode_indices = double(mode_indices(:).');
if isempty(mode_indices)
    error('tblR2:cluster_pod_reconstruction:NoModes', ...
        'POD 聚类至少需要一个模态。');
end
required = {'row_ids','col_ids','frame_ids','spatial_mask','X_grid_mm', ...
    'Y_grid_mm','delta99_grid_mm'};
if ~all(isfield(sequence, required))
    error('tblR2:cluster_pod_reconstruction:InvalidSequence', ...
        'sequence 缺少 POD 聚类所需的网格、帧或掩膜字段。');
end

row_ids = sequence.row_ids;
col_ids = sequence.col_ids;
raw_scale = double(stats.u_rms(row_ids, col_ids));
analysis_mask = sequence.spatial_mask & isfinite(sequence.delta99_grid_mm) & ...
    sequence.delta99_grid_mm > 0;
trusted_applied = isfield(sequence, 'sampling') && ...
    isfield(sequence.sampling, 'trusted_domain_applied') && ...
    logical(sequence.sampling.trusted_domain_applied);
if ~trusted_applied && isfield(cfg.structures, 'trusted_domain')
    analysis_mask = tblR2.trusted_domain_mask(analysis_mask, ...
        sequence.Y_grid_mm, cfg.structures.trusted_domain);
end
opts = structure_options(cfg.structures);
[merge_enabled, merge_opts, dx, dy] = merge_options( ...
    cfg.structures, opts, sequence.X_grid_mm, sequence.Y_grid_mm);
frame_positions = 1:numel(sequence.frame_ids);
batch_size = max(1, cfg.pod_cluster.chunk_frames);
representative_ids = representative_frame_ids(cfg, sequence.frame_ids);

% First pass: primary raw-RMS catalog and reconstructed-RMS accumulation.
sum_sq = zeros(size(analysis_mask));
sample_count = zeros(size(analysis_mask));
main_catalog = cell(0, 1);
main_metrics = cell(0, 1);
representatives = cell(numel(representative_ids), 1);
for first = 1:batch_size:numel(frame_positions)
    positions = frame_positions(first:min(end, first + batch_size - 1));
    recon = reconstruct_positions(positions);
    for local = 1:numel(positions)
        frame_id = recon.frame_ids(local);
        u_prime = squeeze(recon.reconstructed_fluctuation_U(local, :, :));
        field_mask = analysis_mask & isfinite(u_prime);
        values = u_prime;
        values(~field_mask) = NaN;
        finite_values = field_mask & isfinite(values);
        sum_sq(finite_values) = sum_sq(finite_values) + values(finite_values) .^ 2;
        sample_count(finite_values) = sample_count(finite_values) + 1;

        identified = identify(values, raw_scale, field_mask);
        main_catalog{end + 1, 1} = annotate( ...
            identified.structures, frame_id, branch_name, 'raw_u_rms'); %#ok<AGROW>
        main_metrics{end + 1, 1} = frame_metrics( ...
            identified.structures, field_mask, frame_id, branch_name, 'raw_u_rms'); %#ok<AGROW>
        rep_pos = find(representative_ids == frame_id, 1);
        if ~isempty(rep_pos)
            representatives{rep_pos} = compact_frame( ...
                frame_id, values, identified, 'raw_u_rms');
        end
    end
end
own_rms = nan(size(sum_sq));
valid_rms = sample_count > 0;
own_rms(valid_rms) = sqrt(sum_sq(valid_rms) ./ sample_count(valid_rms));

% Second pass: same reconstructed fields, POD-branch own RMS sensitivity.
own_catalog = cell(0, 1);
own_metrics = cell(0, 1);
for first = 1:batch_size:numel(frame_positions)
    positions = frame_positions(first:min(end, first + batch_size - 1));
    recon = reconstruct_positions(positions);
    for local = 1:numel(positions)
        frame_id = recon.frame_ids(local);
        u_prime = squeeze(recon.reconstructed_fluctuation_U(local, :, :));
        field_mask = analysis_mask & isfinite(u_prime) & isfinite(own_rms) & own_rms > 0;
        u_prime(~field_mask) = NaN;
        identified = identify(u_prime, own_rms, field_mask);
        own_catalog{end + 1, 1} = annotate( ...
            identified.structures, frame_id, branch_name, 'pod_branch_u_rms'); %#ok<AGROW>
        own_metrics{end + 1, 1} = frame_metrics( ...
            identified.structures, field_mask, frame_id, branch_name, ...
            'pod_branch_u_rms'); %#ok<AGROW>
    end
end

result = struct();
result.name = branch_name;
result.mode_indices = mode_indices(:);
result.n_modes = numel(mode_indices);
result.primary = package_result(main_catalog, main_metrics);
result.own_rms_sensitivity = package_result(own_catalog, own_metrics);
result.own_rms_sensitivity.u_rms = own_rms;
result.representative = vertcat_nonempty(representatives);
result.analysis_mask = analysis_mask;
result.sampling = sequence.sampling;
result.threshold_contract = ['Primary: unchanged statistics.u_rms. Sensitivity: ' ...
    'RMS recomputed from the same POD-reconstructed u'' sequence. Results are ' ...
    'stored separately and are never pooled.'];
result.definition = ['Selected POD modes are reconstructed with ' ...
    'tblR2.pod_reconstruction and the instantaneous reconstructed u'' field is ' ...
    'passed to tblR2.identify_structures; no POD Q2/Q4 catalog is computed.'];

    function recon = reconstruct_positions(positions)
        recon = tblR2.pod_reconstruction(cache_file, cfg, stats, phase_stats, ...
            mean_bl, 'total', pod_result, 'frame_positions', positions, ...
            'mode_indices', mode_indices, 'add_mean', true, ...
            'include_raw', false, 'sequence', sequence);
    end

    function identified = identify(field, scale, valid)
        identified = tblR2.identify_structures(field, scale, ...
            sequence.X_grid_mm, sequence.Y_grid_mm, ...
            sequence.delta99_grid_mm, valid, opts);
        if merge_enabled
            [identified.structures, ~] = tblR2.vlsm.merge_streamwise_neighbors( ...
                identified.structures, identified.positive_labels, ...
                identified.negative_labels, sequence.X_grid_mm, ...
                sequence.Y_grid_mm, sequence.delta99_grid_mm, dx, dy, ...
                field, merge_opts);
        end
    end
end

function opts = structure_options(settings)
names = {'alpha','min_pixels','connectivity','min_lsm_delta', ...
    'min_vlsm_delta','max_wall_normal_delta'};
opts = struct();
for k = 1:numel(names)
    opts.(names{k}) = settings.(names{k});
end
opts.sign_mode = 'both';
optional = {'seed_alpha','min_abs_fluctuation','min_abs_seed_fluctuation', ...
    'max_internal_hole_pixels','envelope_closing_radius_cells', ...
    'max_aspect_ratio','reject_trusted_boundary_touching'};
for k = 1:numel(optional)
    if isfield(settings, optional{k})
        opts.(optional{k}) = settings.(optional{k});
    end
end
end

function [enabled, merge_opts, dx, dy] = merge_options(settings, opts, X, Y)
enabled = isfield(settings, 'merge_gap_cells') && settings.merge_gap_cells > 0;
merge_opts = struct();
if enabled
    merge_opts.merge_gap_cells = settings.merge_gap_cells;
    merge_opts.merge_require_y_overlap = settings.merge_require_y_overlap;
    merge_opts.min_lsm_delta = opts.min_lsm_delta;
    merge_opts.min_vlsm_delta = opts.min_vlsm_delta;
end
dx = median(abs(diff(X(1, :))), 'omitnan');
dy = median(abs(diff(Y(:, 1))), 'omitnan');
end

function ids = representative_frame_ids(cfg, available)
ids = [];
if isfield(cfg.pod_cluster, 'representative_frame_ids') && ...
        ~isempty(cfg.pod_cluster.representative_frame_ids)
    ids = double(cfg.pod_cluster.representative_frame_ids(:).');
elseif isfield(cfg, 'instantaneous') && isfield(cfg.instantaneous, 'frame_ids')
    requested = double(cfg.instantaneous.frame_ids(:).');
    if numel(requested) == 2 && requested(2) >= requested(1)
        ids = unique(round(linspace(requested(1), requested(2), ...
            max(1, cfg.instantaneous.n_output_frames))));
    else
        ids = requested;
    end
end
ids = intersect(ids, double(available(:).'), 'stable');
end

function T = annotate(T, frame_id, branch, rms_basis)
n = height(T);
T = addvars(T, repmat(frame_id, n, 1), repmat({branch}, n, 1), ...
    repmat({rms_basis}, n, 1), 'Before', 1, ...
    'NewVariableNames', {'FrameID','Branch','RMSBasis'});
end

function T = frame_metrics(structures, analysis_mask, frame_id, branch, rms_basis)
lengths = double(structures.LengthX_over_delta);
pixel_count = double(structures.PixelCount);
T = table(frame_id, {branch}, {rms_basis}, height(structures), ...
    nnz(structures.IsLSM), nnz(structures.IsVLSM), ...
    sum(pixel_count, 'omitnan') / max(nnz(analysis_mask), 1), ...
    percentile(lengths, 0.50), percentile(lengths, 0.90), ...
    'VariableNames', {'FrameID','Branch','RMSBasis','StructureCount', ...
    'LSMCount','VLSMCount','OccupiedAreaFraction', ...
    'MedianLengthXOverDelta','P90LengthXOverDelta'});
end

function value = percentile(values, probability)
values = sort(values(isfinite(values)));
if isempty(values)
    value = NaN;
    return;
end
position = 1 + (numel(values) - 1) * probability;
lo = floor(position); hi = ceil(position);
if lo == hi
    value = values(lo);
else
    value = values(lo) + (position - lo) * (values(hi) - values(lo));
end
end

function item = compact_frame(frame_id, field, identified, rms_basis)
item = struct('frame_id', frame_id, 'rms_basis', rms_basis, ...
    'u_prime', field, 'analysis_mask', identified.analysis_mask, ...
    'positive_labels', identified.positive_labels, ...
    'negative_labels', identified.negative_labels, ...
    'structures', identified.structures);
end

function packaged = package_result(catalog_cells, metric_cells)
packaged = struct();
packaged.catalog = vertcat_nonempty(catalog_cells);
packaged.frame_metrics = vertcat_nonempty(metric_cells);
packaged.length_cdf = length_cdf(packaged.catalog);
end

function value = vertcat_nonempty(cells)
if isempty(cells)
    value = [];
    return;
end
keep = ~cellfun(@isempty, cells);
if ~any(keep)
    value = [];
else
    value = vertcat(cells{keep});
end
end

function cdf = length_cdf(catalog)
cdf = struct('x', zeros(0,1), 'F', zeros(0,1), 'n', 0);
if isempty(catalog) || ~istable(catalog) || height(catalog) == 0
    return;
end
values = sort(double(catalog.LengthX_over_delta));
values = values(isfinite(values));
cdf.x = values(:);
cdf.n = numel(values);
cdf.F = ((1:numel(values))' ./ max(numel(values), 1));
end
