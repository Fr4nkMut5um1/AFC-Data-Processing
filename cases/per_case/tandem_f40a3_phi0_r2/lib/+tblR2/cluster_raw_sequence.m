function result = cluster_raw_sequence(cache_file, cfg, stats, phase_stats, ...
    sequence, branch_name)
%CLUSTER_RAW_SEQUENCE Independent raw PostProc u' connectivity baseline.

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
raw_scale = stats.u_rms(sequence.row_ids, sequence.col_ids);
frame_ids = double(sequence.frame_ids(:).');
representative_ids = representative_frame_ids(cfg, frame_ids);
representatives = cell(numel(representative_ids), 1);
catalog_cells = cell(0, 1);
batch_size = max(1, cfg.pod_cluster.chunk_frames);

for first = 1:batch_size:numel(frame_ids)
    local = first:min(numel(frame_ids), first + batch_size - 1);
    ids = frame_ids(local);
    chunk = tblR2.read_cache_chunk(cache_file, ids, sequence.row_ids, ...
        sequence.col_ids, 'total', stats, phase_stats);
    for k = 1:numel(ids)
        field = squeeze(chunk.U(k, :, :));
        field_mask = analysis_mask & squeeze(chunk.sampleValid(k, :, :)) & ...
            isfinite(field);
        field(~field_mask) = NaN;
        identified = tblR2.identify_structures(field, raw_scale, ...
            sequence.X_grid_mm, sequence.Y_grid_mm, ...
            sequence.delta99_grid_mm, field_mask, opts);
        if merge_enabled
            [identified.structures, ~] = tblR2.vlsm.merge_streamwise_neighbors( ...
                identified.structures, identified.positive_labels, ...
                identified.negative_labels, sequence.X_grid_mm, ...
                sequence.Y_grid_mm, sequence.delta99_grid_mm, dx, dy, ...
                field, merge_opts);
        end
        T = identified.structures;
        n = height(T);
        T = addvars(T, repmat(ids(k), n, 1), repmat({branch_name}, n, 1), ...
            repmat({'raw_u_rms'}, n, 1), 'Before', 1, ...
            'NewVariableNames', {'FrameID','Branch','RMSBasis'});
        catalog_cells{end + 1, 1} = T; %#ok<AGROW>
        rep_pos = find(representative_ids == ids(k), 1);
        if ~isempty(rep_pos)
            representatives{rep_pos} = struct('frame_id', ids(k), ...
                'rms_basis', 'raw_u_rms', 'u_prime', field, ...
                'analysis_mask', identified.analysis_mask, ...
                'positive_labels', identified.positive_labels, ...
                'negative_labels', identified.negative_labels, ...
                'structures', identified.structures);
        end
    end
end
catalog = vertcat_nonempty(catalog_cells);
result = tblR2.catalog_branch_metrics(catalog, frame_ids, nnz(analysis_mask), ...
    branch_name, 'raw_u_rms');
result.name = branch_name;
result.analysis_mask = analysis_mask;
result.representative = vertcat_nonempty(representatives);
result.threshold_contract = 'Unfiltered PostProc total u'' with unchanged statistics.u_rms.';
end

function opts = structure_options(settings)
names = {'alpha','min_pixels','connectivity','min_lsm_delta', ...
    'min_vlsm_delta','max_wall_normal_delta'};
opts = struct();
for k = 1:numel(names); opts.(names{k}) = settings.(names{k}); end
opts.sign_mode = 'both';
optional = {'seed_alpha','min_abs_fluctuation','min_abs_seed_fluctuation', ...
    'max_internal_hole_pixels','envelope_closing_radius_cells', ...
    'max_aspect_ratio','reject_trusted_boundary_touching'};
for k = 1:numel(optional)
    if isfield(settings, optional{k}); opts.(optional{k}) = settings.(optional{k}); end
end
end

function [enabled, merge_opts, dx, dy] = merge_options(settings, opts, X, Y)
enabled = isfield(settings, 'merge_gap_cells') && settings.merge_gap_cells > 0;
merge_opts = struct();
if enabled
    merge_opts = struct('merge_gap_cells', settings.merge_gap_cells, ...
        'merge_require_y_overlap', settings.merge_require_y_overlap, ...
        'min_lsm_delta', opts.min_lsm_delta, ...
        'min_vlsm_delta', opts.min_vlsm_delta);
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

function value = vertcat_nonempty(cells)
if isempty(cells)
    value = [];
    return;
end
keep = ~cellfun(@isempty, cells);
if any(keep); value = vertcat(cells{keep}); else; value = []; end
end
