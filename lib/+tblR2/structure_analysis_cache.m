function result = structure_analysis_cache(cache_file, cfg, stats, phase_stats, mean_bl)
%STRUCTURE_ANALYSIS_CACHE Instantaneous, phase-coherent, LSM/VLSM catalogs.

J = size(stats.X, 1);
I = size(stats.X, 2);
Y_wall_mm = mean_bl.wall_distance_mm;
if ~isequal(size(Y_wall_mm), size(stats.Y))
    error('tblR2:structure_analysis_cache:WallGridSizeMismatch', ...
        'mean_bl.wall_distance_mm 必须与统计网格匹配。');
end
delta_grid = interp1(mean_bl.boundary_layer.x, ...
    mean_bl.boundary_layer.delta99, stats.X, 'linear', NaN);
valid_mask = stats.accepted_mask & isfinite(delta_grid) & delta_grid > 0;
opts = structure_opts(cfg.structures);
preprocess_spec = structure_preprocessing(cfg.structures);
trusted_domain = trusted_domain_spec(cfg.structures);
analysis_domain_mask = tblR2.trusted_domain_mask( ...
    valid_mask, Y_wall_mm, trusted_domain);
edge_only_domain = trusted_domain;
edge_only_domain.wall_normal_top_rows = 0;
top_only_domain = trusted_domain;
top_only_domain.streamwise_edge_columns = 0;
edge_rejected_mask = valid_mask & ~tblR2.trusted_domain_mask( ...
    valid_mask, Y_wall_mm, edge_only_domain);
top_rejected_mask = valid_mask & ~tblR2.trusted_domain_mask( ...
    valid_mask, Y_wall_mm, top_only_domain);
instantaneous_ids = tblR2.instantaneous_frame_ids( ...
    cfg.instantaneous, stats.n_frames);
catalog_ids = unique([1:cfg.structures.catalog_frame_stride:stats.n_frames, ...
    instantaneous_ids, stats.n_frames]);
dx = median(abs(diff(stats.X(1, :))), 'omitnan');
dy = median(abs(diff(Y_wall_mm(:, 1))), 'omitnan');
merge_enabled = isfield(cfg.structures, 'merge_gap_cells') && ...
    cfg.structures.merge_gap_cells > 0;
if merge_enabled
    merge_opts = struct( ...
        'merge_gap_cells', cfg.structures.merge_gap_cells, ...
        'merge_require_y_overlap', cfg.structures.merge_require_y_overlap, ...
        'min_lsm_delta', opts.min_lsm_delta, ...
        'min_vlsm_delta', opts.min_vlsm_delta);
end
catalog_cells = cell(0, 1);
q2q4_catalog_cells = cell(0, 1);
instantaneous_cells = cell(numel(instantaneous_ids), 1);
preprocessing_cells = cell(0, 1);
q2q4_spec = quadrant_spec(cfg.structures, opts);

catalog_batch = max(1, cfg.chunk_frames);
% —— 进度播报：开始逐帧识别（只打印，不影响任何结果数据）——
fprintf('[结构识别] 开始逐帧识别：共 %d 帧（每批 %d 帧）。\n', ...
    numel(catalog_ids), catalog_batch);
for first_position = 1:catalog_batch:numel(catalog_ids)
    positions = first_position:min(numel(catalog_ids), ...
        first_position + catalog_batch - 1);
    frame_batch = catalog_ids(positions);
    % Always read the PostProc instantaneous field.  LaVision has already
    % screened vectors; Section 4 applies only the optional ordinary Gaussian
    % blur before subtracting the corresponding mean field.
    raw_batch = tblR2.read_cache_chunk(cache_file, frame_batch, ...
        1:J, 1:I, 'raw', stats, phase_stats);

    for local_position = 1:numel(frame_batch)
        frame_id = frame_batch(local_position);
        raw_U = squeeze(raw_batch.U(local_position, :, :));
        raw_V = squeeze(raw_batch.V(local_position, :, :));
        raw_valid = valid_mask & squeeze(raw_batch.sampleValid(local_position, :, :));

        % Required Section 4 order:
        % PostProc instantaneous -> ordinary Gaussian -> subtract mean -> cluster.
        raw_preprocessed = tblR2.preprocess_structure_velocity( ...
            raw_U, raw_V, raw_valid, analysis_domain_mask, preprocess_spec);
        [mean_U, mean_V] = mean_field_for_frame(stats, frame_id, 1:J, 1:I);
        total_mask = valid_mask & raw_valid & isfinite(mean_U) & isfinite(mean_V);
        total_U = raw_U - mean_U;
        total_V = raw_V - mean_V;
        total_U(~total_mask) = NaN;
        total_V(~total_mask) = NaN;
        structure_mask = raw_preprocessed.output_valid_mask & ...
            isfinite(mean_U) & isfinite(mean_V);
        total_U_f = raw_preprocessed.U - mean_U;
        total_V_f = raw_preprocessed.V - mean_V;
        total_U_f(~structure_mask) = NaN;
        total_V_f(~structure_mask) = NaN;
        structures_total = tblR2.identify_structures( ...
            total_U_f, stats.u_rms, stats.X, Y_wall_mm, delta_grid, ...
            structure_mask, opts);
        if merge_enabled
            [structures_total.structures, ~] = ...
                tblR2.vlsm.merge_streamwise_neighbors( ...
                structures_total.structures, ...
                structures_total.positive_labels, ...
                structures_total.negative_labels, ...
                stats.X, Y_wall_mm, delta_grid, dx, dy, total_U_f, merge_opts);
        end
        catalog_cells{end + 1, 1} = annotate( ...
            structures_total.structures, frame_id, 'total'); %#ok<AGROW>
        q2q4_frame_results = struct();
        if q2q4_spec.enabled && mod(frame_id - 1, q2q4_spec.frame_stride) == 0
            q2q4_frame_results = quadrant_frame_results( ...
                total_U_f, total_V_f, structure_mask, structures_total);
            for ih = 1:numel(q2q4_frame_results)
                qtable = q2q4_frame_results(ih).structures;
                if ~isempty(qtable)
                    q2q4_catalog_cells{end + 1, 1} = annotate( ...
                        qtable, frame_id, sprintf('Q%d', q2q4_frame_results(ih).H)); %#ok<AGROW>
                end
            end
        end
        preprocessing_cells{end + 1, 1} = preprocessing_row( ...
            frame_id, 'total', raw_preprocessed); %#ok<AGROW>

        random_U = [];
        random_V = [];
        structures_random = [];
        phase_bin = NaN;
        if strcmp(cfg.case_type, 'controlled')
            phase_bin = phase_stats.assignment.bin_index(frame_id);
            [phase_U, phase_V] = phase_field_for_frame( ...
                phase_stats, frame_id, 1:J, 1:I);
            random_mask = valid_mask & raw_valid & ...
                isfinite(phase_U) & isfinite(phase_V);
            random_U = raw_U - phase_U;
            random_V = raw_V - phase_V;
            random_U(~random_mask) = NaN;
            random_V(~random_mask) = NaN;
            random_preprocessed = tblR2.preprocess_structure_velocity( ...
                raw_U, raw_V, random_mask, analysis_domain_mask, ...
                preprocess_spec);
            random_structure_mask = random_preprocessed.output_valid_mask;
            random_U_f = random_preprocessed.U - phase_U;
            random_U_f(~random_structure_mask) = NaN;
            structures_random = tblR2.identify_structures( ...
                random_U_f, phase_stats.random_global.u_rms, ...
                stats.X, Y_wall_mm, delta_grid, ...
                random_structure_mask, opts);
            if merge_enabled
                [structures_random.structures, ~] = ...
                    tblR2.vlsm.merge_streamwise_neighbors( ...
                    structures_random.structures, ...
                    structures_random.positive_labels, ...
                    structures_random.negative_labels, ...
                    stats.X, Y_wall_mm, delta_grid, dx, dy, ...
                    random_U_f, merge_opts);
            end
            catalog_cells{end + 1, 1} = annotate( ...
                structures_random.structures, frame_id, 'random'); %#ok<AGROW>
            preprocessing_cells{end + 1, 1} = preprocessing_row( ...
                frame_id, 'random', random_preprocessed); %#ok<AGROW>
        end

        selected_position = find(instantaneous_ids == frame_id, 1);
        if ~isempty(selected_position)
            criteria = tblR2.planar_criteria( ...
                raw_preprocessed.U, raw_preprocessed.V, stats.X, stats.Y, ...
                raw_preprocessed.output_valid_mask);
            item = struct();
            item.frame_id = frame_id;
            item.phase_bin = phase_bin;
            item.U_raw = raw_U;
            item.V_raw = raw_V;
            item.u_prime = total_U;
            item.v_prime = total_V;
            item.uv_prime = total_U .* total_V;
            item.u_total = total_U;
            item.v_total = total_V;
            item.uv_total = item.uv_prime;
            item.negative_uv_total = -item.uv_total;
            item.u_structure_input = total_U_f;
            item.v_structure_input = total_V_f;
            item.structure_valid_mask = structure_mask;
            item.frame_valid_mask = total_mask;
            item.u_random = random_U;
            item.v_random = random_V;
            if ~isempty(random_U)
                item.uv_random = random_U .* random_V;
                item.negative_uv_random = -item.uv_random;
            else
                item.uv_random = [];
                item.negative_uv_random = [];
            end
            item.planar_input_U = raw_preprocessed.U;
            item.planar_input_V = raw_preprocessed.V;
            item.planar_criteria = criteria;
            item.structures_total = structures_total;
            item.structures_random = structures_random;
            item.q2q4_total = q2q4_frame_results;
            item.preprocessing_total = compact_preprocessing(raw_preprocessed);
            item.preprocessing_total.order = ...
                'PostProc instantaneous -> ordinary Gaussian -> subtract mean';
            item.preprocessing_planar = compact_preprocessing(raw_preprocessed);
            instantaneous_cells{selected_position} = item;
        end
        % —— 进度播报：每处理完一批帧打印一次（只打印，不影响任何结果数据）——
        fprintf('[结构识别] 进度：已处理 %d / %d 帧\n', ...
            min(first_position + numel(frame_batch) - 1, numel(catalog_ids)), ...
            numel(catalog_ids));
    end
end

instantaneous = vertcat(instantaneous_cells{:});

if isempty(catalog_cells)
    catalog = table();
else
    catalog = vertcat(catalog_cells{:});
end
if isempty(q2q4_catalog_cells)
    q2q4_catalog = table();
else
    q2q4_catalog = vertcat(q2q4_catalog_cells{:});
end
phase_coherent = [];
mean_preprocess_spec = preprocess_spec;
mean_preprocess_spec.outlier.enabled = false;
mean_preprocessed = tblR2.preprocess_structure_velocity( ...
    stats.Uavex, stats.Vavex, valid_mask, analysis_domain_mask, ...
    mean_preprocess_spec);
planar_mean = tblR2.planar_criteria( ...
    mean_preprocessed.U, mean_preprocessed.V, stats.X, stats.Y, ...
    mean_preprocessed.output_valid_mask);
planar_phase = [];
if strcmp(cfg.case_type, 'controlled')
    phase_coherent = coherent_catalog();
    planar_phase = phase_planar_criteria();
end
phase_distribution = summarize_catalog(catalog);

result = struct();
result.instantaneous = instantaneous;
result.instantaneous_frame_range = double(reshape( ...
    cfg.instantaneous.frame_ids, 1, 2));
result.instantaneous_frame_ids = instantaneous_ids;
result.processed_frame_count = stats.n_frames;
result.catalog_frame_count = numel(catalog_ids);
result.catalog = catalog;
result.q2q4 = struct( ...
    'enabled', q2q4_spec.enabled, ...
    'options', q2q4_spec, ...
    'catalog', q2q4_catalog, ...
    'definition', ['Quadrant objects are 2-D connected components of ' ...
        '|u''v''|/(u_rms v_rms)>H, separated as Q2 (negative u'') and Q4 ' ...
        '(positive u'').']);
result.phase_coherent = phase_coherent;
result.phase_distribution = phase_distribution;
if isempty(preprocessing_cells)
    result.preprocessing_summary = table();
else
    result.preprocessing_summary = vertcat(preprocessing_cells{:});
end
result.preprocessing = struct( ...
    'options', preprocess_spec, ...
    'analysis_domain_mask', analysis_domain_mask, ...
    'trusted_domain_rejected_mask', valid_mask & ~analysis_domain_mask, ...
    'edge_rejected_mask', edge_rejected_mask, ...
    'wall_normal_top_rejected_mask', top_rejected_mask, ...
    'mean_planar', compact_preprocessing(mean_preprocessed), ...
    'validation_reference', struct( ...
    'method', 'LaVision-exported vectors accepted without a second UOD pass', ...
    'doi', ''), ...
    'implementation_reference', struct());
result.planar_mean = planar_mean;
result.planar_phase = planar_phase;
result.delta99_grid_mm = delta_grid;
result.options = opts;
result.filter = structure_filter(cfg.structures);
result.definition = ['PostProc instantaneous U/V fields are first validated with the ' ...
    'ordinary 2-D Gaussian convolution only (no additional UOD and no ' ...
    'mask-normalized or streamwise FFT filtering). The corresponding repeat or ' ...
    'phase mean is then subtracted before signed connected-component ' ...
    'identification. The trusted domain removes only the configured upstream/' ...
    'downstream columns and highest wall-normal rows; internal masks are not ' ...
    'eroded. Total u'' and controlled random u'''' catalogs remain separate; ' ...
    'a relaxed same-sign envelope threshold is retained only when connected ' ...
    'to a stricter core threshold. Small signed-mask notches/holes are closed only within the configured ' ...
    'pixel budget, while incomplete clusters touching the retained outer FOV ' ...
    'boundary can be rejected. LSM/VLSM labels use Lx/delta99. Raw ' ...
    'instantaneous, processed, and ' ...
    'mean-subtracted structure inputs are stored separately; statistics are ' ...
    'never overwritten.'];
result.source_role = 'postproc';
result.source_definition = ['Instantaneous fields, total u'', and random u'''' ' ...
    'structure inputs come from the PostProc sequence cache; time-mean and RMS ' ...
    'normalizations come from the PIV raw statistics.'];
result.planar_scope = ['Instantaneous, time-mean, and native-phase omega_z, ' ...
    'Q_planar, lambda2_planar, and lambda_ci are 2D-2C XOY surrogates only.'];

    function [mean_U, mean_V] = mean_field_for_frame(stats, frame_id, row_ids, col_ids)
        if isfield(stats, 'repeat_means') && ~isempty(stats.repeat_means) && ...
                isfield(stats, 'repeat_boundaries') && ...
                ~isempty(stats.repeat_boundaries)
            rep = frame_to_repeat_index(frame_id, stats.repeat_boundaries);
            mean_U = squeeze(stats.repeat_means(1, rep, row_ids, col_ids));
            mean_V = squeeze(stats.repeat_means(2, rep, row_ids, col_ids));
        else
            mean_U = squeeze(stats.Uavex(row_ids, col_ids));
            mean_V = squeeze(stats.Vavex(row_ids, col_ids));
        end
    end

    function [phase_U, phase_V] = phase_field_for_frame(phase_stats, ...
            frame_id, row_ids, col_ids)
        bins = phase_stats.assignment.bin_index(frame_id);
        if isfield(phase_stats, 'U_phase_rep') && ...
                ~isempty(phase_stats.U_phase_rep)
            rep = frame_to_repeat_index(frame_id, phase_stats.repeat_boundaries);
            phase_U = squeeze(phase_stats.U_phase_rep(rep, bins, row_ids, col_ids));
            phase_V = squeeze(phase_stats.V_phase_rep(rep, bins, row_ids, col_ids));
        else
            phase_U = squeeze(phase_stats.U_phase(bins, row_ids, col_ids));
            phase_V = squeeze(phase_stats.V_phase(bins, row_ids, col_ids));
        end
    end

    function rep = frame_to_repeat_index(frame_id, repeat_boundaries)
        rep = 1 + nnz(frame_id > repeat_boundaries(:)');
    end

    function T = annotate(T, frame_id, branch)
        n = height(T);
        if strcmp(cfg.case_type, 'controlled')
            bin = phase_stats.assignment.bin_index(frame_id);
            phi = phase_stats.assignment.phi_relative_deg(frame_id);
            cycle = phase_stats.assignment.cycle_index(frame_id);
        else
            bin = NaN;
            phi = NaN;
            cycle = NaN;
        end
        T = addvars(T, repmat(frame_id, n, 1), ...
            repmat({branch}, n, 1), repmat(bin, n, 1), ...
            repmat(phi, n, 1), repmat(cycle, n, 1), ...
            'Before', 1, 'NewVariableNames', ...
            {'FrameID', 'Branch', 'PhaseBin', 'PhaseRelativeDeg', 'CycleIndex'});
    end

    function frame_results = quadrant_frame_results(u_field, v_field, mask, velocity_result)
        frame_results = repmat(struct('H', NaN, 'structures', table(), ...
            'identified', struct()), numel(q2q4_spec.H_values), 1);
        for ih_local = 1:numel(q2q4_spec.H_values)
            qopts = q2q4_spec;
            qopts.H = q2q4_spec.H_values(ih_local);
            identified_q = tblR2.identify_quadrant_structures( ...
                u_field, v_field, stats.u_rms, stats.v_rms, stats.X, ...
                Y_wall_mm, delta_grid, mask, velocity_result, qopts);
            frame_results(ih_local).H = qopts.H;
            frame_results(ih_local).structures = identified_q.structures;
            frame_results(ih_local).identified = identified_q;
        end
    end

    function row = preprocessing_row(frame_id, branch, preprocessed)
        row = table(frame_id, {branch}, ...
            preprocessed.counts.input_valid, ...
            preprocessed.counts.outliers, ...
            preprocessed.counts.reconstructed_outliers, ...
            preprocessed.counts.output_valid, ...
            'VariableNames', {'FrameID', 'Branch', 'InputValidCount', ...
            'OutlierCount', 'ReconstructedOutlierCount', 'OutputValidCount'});
    end

    function compact = compact_preprocessing(preprocessed)
        compact = struct( ...
            'input_valid_mask', preprocessed.input_valid_mask, ...
            'source_valid_mask', preprocessed.source_valid_mask, ...
            'output_valid_mask', preprocessed.output_valid_mask, ...
            'outlier_mask', preprocessed.outlier_mask, ...
            'reconstructed_outlier_mask', ...
                preprocessed.reconstructed_outlier_mask, ...
            'counts', preprocessed.counts, ...
            'options', preprocessed.options, ...
            'method', preprocessed.method);
        if isfield(preprocessed.outlier, 'score')
            compact.normalized_median_score = preprocessed.outlier.score;
        else
            compact.normalized_median_score = nan(size(preprocessed.U));
        end
    end

    function coherent = coherent_catalog()
        n_bins = cfg.phase.n_bins;
        u_scale = squeeze(sqrt(mean(phase_stats.u_coherent .^ 2, 1, 'omitnan')));
        v_scale = squeeze(sqrt(mean(phase_stats.v_coherent .^ 2, 1, 'omitnan')));
        kc_scale = squeeze(mean(phase_stats.coherent_TKE, 1, 'omitnan'));
        coherent_cells = cell(n_bins * 3, 1);
        index = 0;
        for ib = 1:n_bins
            fields = {squeeze(phase_stats.u_coherent(ib, :, :)), ...
                squeeze(phase_stats.v_coherent(ib, :, :)), ...
                squeeze(phase_stats.coherent_TKE(ib, :, :))};
            scales = {u_scale, v_scale, kc_scale};
            names = {'utilde', 'vtilde', 'coherent_TKE'};
            for jf = 1:3
                local_opts = opts;
                if jf == 3
                    local_opts.sign_mode = 'positive';
                    if isfield(cfg.structures, 'coherent_energy_alpha')
                        local_opts.alpha = cfg.structures.coherent_energy_alpha;
                        local_opts.seed_alpha = local_opts.alpha;
                    end
                end
                [field_for_identification, coherent_mask] = ...
                    preprocess_scalar(fields{jf}, analysis_domain_mask);
                identified = tblR2.identify_structures( ...
                    field_for_identification, scales{jf}, stats.X, ...
                    Y_wall_mm, delta_grid, coherent_mask, local_opts);
                T = identified.structures;
                n = height(T);
                T = addvars(T, repmat(ib, n, 1), ...
                    repmat(phase_stats.assignment.bin_center_relative_deg(ib), n, 1), ...
                    repmat(names(jf), n, 1), ...
                    'Before', 1, 'NewVariableNames', ...
                    {'PhaseBin', 'PhaseRelativeDeg', 'Field'});
                index = index + 1;
                coherent_cells{index} = T;
            end
        end
        coherent = vertcat(coherent_cells{1:index});
    end

    function [processed, output_mask] = preprocess_scalar(field, target_mask)
        source_mask = target_mask & isfinite(field);
        if preprocess_spec.gaussian.enabled
            [processed, output_mask] = tblR2.simple_gaussian_filter2( ...
                field, source_mask, preprocess_spec.gaussian.sigma_cells, ...
                preprocess_spec.gaussian.radius_cells);
        else
            processed = double(field);
            output_mask = source_mask;
            processed(~output_mask) = NaN;
        end
    end

    function mapped = phase_planar_criteria()
        n_bins = cfg.phase.n_bins;
        omega_z = nan(n_bins, J, I, 'single');
        Q_planar = nan(n_bins, J, I, 'single');
        lambda2_planar = nan(n_bins, J, I, 'single');
        lambda_ci = nan(n_bins, J, I, 'single');
        for ib = 1:n_bins
            phase_preprocessed = tblR2.preprocess_structure_velocity( ...
                squeeze(phase_stats.U_phase(ib, :, :)), ...
                squeeze(phase_stats.V_phase(ib, :, :)), valid_mask, ...
                analysis_domain_mask, mean_preprocess_spec);
            criteria = tblR2.planar_criteria( ...
                phase_preprocessed.U, phase_preprocessed.V, ...
                stats.X, stats.Y, phase_preprocessed.output_valid_mask);
            omega_z(ib, :, :) = single(criteria.omega_z);
            Q_planar(ib, :, :) = single(criteria.Q_planar);
            lambda2_planar(ib, :, :) = single(criteria.lambda2_planar);
            lambda_ci(ib, :, :) = single(criteria.lambda_ci);
        end
        mapped = struct( ...
            'omega_z', omega_z, ...
            'omega_tilde_z', omega_z - single(reshape( ...
                planar_mean.omega_z, 1, J, I)), ...
            'Q_planar', Q_planar, ...
            'lambda2_planar', lambda2_planar, ...
            'lambda_ci', lambda_ci, ...
            'phase_bin_center_relative_deg', ...
                phase_stats.assignment.bin_center_relative_deg, ...
            'scope', ['All native relative-phase bins; planar 2D-2C ' ...
                'surrogates only, not full three-dimensional criteria.']);
    end

    function summary = summarize_catalog(T)
        if isempty(T) || height(T) == 0
            summary = table();
            return;
        end
        branches = unique(T.Branch, 'stable');
        if strcmp(cfg.case_type, 'controlled')
            bins = (1:cfg.phase.n_bins)';
        else
            bins = NaN;
        end
        rows = cell(0, 1);
        for jb = 1:numel(branches)
            for ib = 1:numel(bins)
                if isnan(bins(ib))
                    mask = strcmp(T.Branch, branches{jb});
                else
                    mask = strcmp(T.Branch, branches{jb}) & T.PhaseBin == bins(ib);
                end
                subset = T(mask, :);
                row = table(branches(jb), bins(ib), height(subset), ...
                    nnz(subset.IsLSM), nnz(subset.IsVLSM), ...
                    mean(subset.LengthX_over_delta, 'omitnan'), ...
                    mean(subset.Area_over_delta2, 'omitnan'), ...
                    'VariableNames', {'Branch', 'PhaseBin', 'StructureCount', ...
                    'LSMCount', 'VLSMCount', 'MeanLengthXOverDelta', ...
                    'MeanAreaOverDelta2'});
                rows{end + 1, 1} = row; %#ok<AGROW>
            end
        end
        summary = vertcat(rows{:});
    end

end

function opts = structure_opts(settings)
max_internal_hole_pixels = 0;
if isfield(settings, 'max_internal_hole_pixels') && ...
        ~isempty(settings.max_internal_hole_pixels)
    max_internal_hole_pixels = settings.max_internal_hole_pixels;
end
envelope_closing_radius_cells = 0;
if isfield(settings, 'envelope_closing_radius_cells') && ...
        ~isempty(settings.envelope_closing_radius_cells)
    envelope_closing_radius_cells = ...
        settings.envelope_closing_radius_cells;
end
max_aspect_ratio = inf;
if isfield(settings, 'max_aspect_ratio') && ...
        ~isempty(settings.max_aspect_ratio)
    max_aspect_ratio = settings.max_aspect_ratio;
end
reject_trusted_boundary_touching = false;
if isfield(settings, 'reject_trusted_boundary_touching') && ...
        ~isempty(settings.reject_trusted_boundary_touching)
    reject_trusted_boundary_touching = ...
        settings.reject_trusted_boundary_touching;
end
seed_alpha = settings.alpha;
if isfield(settings, 'seed_alpha') && ~isempty(settings.seed_alpha)
    seed_alpha = settings.seed_alpha;
end
min_abs_fluctuation = 0;
if isfield(settings, 'min_abs_fluctuation') && ...
        ~isempty(settings.min_abs_fluctuation)
    min_abs_fluctuation = settings.min_abs_fluctuation;
end
min_abs_seed_fluctuation = min_abs_fluctuation;
if isfield(settings, 'min_abs_seed_fluctuation') && ...
        ~isempty(settings.min_abs_seed_fluctuation)
    min_abs_seed_fluctuation = settings.min_abs_seed_fluctuation;
end
opts = struct('alpha', settings.alpha, 'min_pixels', settings.min_pixels, ...
    'seed_alpha', seed_alpha, ...
    'connectivity', settings.connectivity, ...
    'max_internal_hole_pixels', max_internal_hole_pixels, ...
    'envelope_closing_radius_cells', envelope_closing_radius_cells, ...
    'max_aspect_ratio', max_aspect_ratio, ...
    'reject_trusted_boundary_touching', ...
        reject_trusted_boundary_touching, ...
    'min_lsm_delta', settings.min_lsm_delta, ...
    'min_vlsm_delta', settings.min_vlsm_delta, ...
    'max_wall_normal_delta', settings.max_wall_normal_delta, ...
    'min_abs_fluctuation', min_abs_fluctuation, ...
    'min_abs_seed_fluctuation', min_abs_seed_fluctuation, ...
    'sign_mode', 'both');
end

function spec = trusted_domain_spec(settings)
%TRUSTED_DOMAIN_SPEC Resolve only the explicit outer-domain crop controls.
spec = struct('streamwise_edge_columns', 0, 'wall_normal_top_rows', 0);
if isfield(settings, 'trusted_domain') && ~isempty(settings.trusted_domain)
    supplied = settings.trusted_domain;
    names = fieldnames(spec);
    for i = 1:numel(names)
        if isfield(supplied, names{i})
            spec.(names{i}) = supplied.(names{i});
        end
    end
end
end

function spec = structure_filter(settings)
%STRUCTURE_FILTER Retain legacy metadata only; Section 4 does not apply FFT filtering.
if ~isfield(settings, 'filter')
    settings.filter = struct();
end
if ~isfield(settings.filter, 'filterType')
    settings.filter.filterType = 'none';
end
if ~isfield(settings.filter, 'lambdaMin')
    settings.filter.lambdaMin = 1.0;
end
if ~isfield(settings.filter, 'lambdaMax')
    settings.filter.lambdaMax = inf;
end
spec = settings.filter;
spec.requested_filter_type = spec.filterType;
spec.filterType = 'none';
spec.applied = false;
end


function spec = structure_preprocessing(settings)
%STRUCTURE_PREPROCESSING Resolve ordinary-Gaussian-only Section-4 options.
spec = struct();
spec.name = 'none';
spec.enabled = false;
spec.edge_buffer_cells = [0 0];
spec.outlier = struct('enabled', false, 'radius_cells', 1, ...
    'threshold', 2, 'residual_epsilon', 0.1, 'min_neighbors', 5);
spec.gaussian = struct( ...
    'enabled', false, ...
    'sigma_cells', 0.8, ...
    'radius_cells', 1, ...
    'kernel_type', 'gaussian', ...
    'kernel_normalization', 'sum1', ...
    'boundary_mode', 'legacy_zero', ...
    'mask_aware', false, ...
    'min_support_fraction', 0.5, ...
    'apply_to', {{'u', 'v'}}, ...
    'apply_stage', 'instantaneous_before_mean_subtraction');
if isfield(settings, 'preprocessing') && ~isempty(settings.preprocessing)
    supplied = settings.preprocessing;
    names = fieldnames(supplied);
    for i = 1:numel(names)
        if isstruct(supplied.(names{i})) && isfield(spec, names{i}) && ...
                isstruct(spec.(names{i}))
            nested_names = fieldnames(supplied.(names{i}));
            for j = 1:numel(nested_names)
                spec.(names{i}).(nested_names{j}) = ...
                    supplied.(names{i}).(nested_names{j});
            end
        else
            spec.(names{i}) = supplied.(names{i});
        end
    end
end
% Backwards-compatible scalar aliases remain the source of truth when the
% directional Gaussian fields were not supplied by an older case script.
if ~isfield(spec.gaussian, 'sigma_x_cells') || isempty(spec.gaussian.sigma_x_cells)
    spec.gaussian.sigma_x_cells = spec.gaussian.sigma_cells;
end
if ~isfield(spec.gaussian, 'sigma_y_cells') || isempty(spec.gaussian.sigma_y_cells)
    spec.gaussian.sigma_y_cells = spec.gaussian.sigma_cells;
end
if ~isfield(spec.gaussian, 'radius_x_cells') || isempty(spec.gaussian.radius_x_cells)
    spec.gaussian.radius_x_cells = spec.gaussian.radius_cells;
end
if ~isfield(spec.gaussian, 'radius_y_cells') || isempty(spec.gaussian.radius_y_cells)
    spec.gaussian.radius_y_cells = spec.gaussian.radius_cells;
end
if ~isfield(spec.gaussian, 'kernel_type') || isempty(spec.gaussian.kernel_type)
    spec.gaussian.kernel_type = 'gaussian';
end
if ~isfield(spec.gaussian, 'kernel_normalization') || isempty(spec.gaussian.kernel_normalization)
    spec.gaussian.kernel_normalization = 'sum1';
end
if ~isfield(spec.gaussian, 'boundary_mode') || isempty(spec.gaussian.boundary_mode)
    spec.gaussian.boundary_mode = 'legacy_zero';
end
if ~isfield(spec.gaussian, 'mask_aware') || isempty(spec.gaussian.mask_aware)
    spec.gaussian.mask_aware = false;
end
if ~isfield(spec.gaussian, 'apply_to') || isempty(spec.gaussian.apply_to)
    spec.gaussian.apply_to = {'u', 'v'};
end
if ~isfield(spec.gaussian, 'apply_stage') || isempty(spec.gaussian.apply_stage)
    spec.gaussian.apply_stage = 'instantaneous_before_mean_subtraction';
end
% The fields below remain accepted for compatibility with older case files,
% but the outlier detector is intentionally never enabled in Section 4.
spec.outlier.enabled = false;
if ~spec.enabled
    spec.name = 'none';
    spec.edge_buffer_cells = [0 0];
    spec.gaussian.enabled = false;
end
end


function spec = quadrant_spec(settings, nominal_opts)
%QUADRANT_SPEC Resolve optional Q2/Q4 object extraction settings.
spec = struct('enabled', false, 'H_values', [0 1 2], 'frame_stride', 1, ...
    'connectivity', nominal_opts.connectivity, ...
    'min_pixels', nominal_opts.min_pixels, ...
    'min_lsm_delta', nominal_opts.min_lsm_delta, ...
    'min_vlsm_delta', nominal_opts.min_vlsm_delta, ...
    'bootstrap_samples', 200, 'bootstrap_seed', 1731);
if isfield(settings, 'q2q4') && ~isempty(settings.q2q4)
    supplied = settings.q2q4;
    names = fieldnames(supplied);
    for i = 1:numel(names)
        spec.(names{i}) = supplied.(names{i});
    end
end
spec.H_values = double(spec.H_values(:)');
spec.H_values = spec.H_values(isfinite(spec.H_values) & spec.H_values >= 0);
if isempty(spec.H_values)
    spec.H_values = [0 1 2];
end
spec.frame_stride = max(1, round(double(spec.frame_stride)));
spec.connectivity = nominal_opts.connectivity;
spec.min_pixels = nominal_opts.min_pixels;
spec.min_lsm_delta = nominal_opts.min_lsm_delta;
spec.min_vlsm_delta = nominal_opts.min_vlsm_delta;
end
