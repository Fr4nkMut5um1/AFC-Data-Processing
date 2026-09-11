function result = section4_vlsm_analysis(cache_file, cfg, mean_bl_file, output_file)
%SECTION4_VLSM_ANALYSIS POD-E50 / Deshpande-style Section-4 adapter.
%
% This entry point is intentionally independent of the legacy
% structure_analysis_cache implementation.  It uses the isolated d23
% implementation for the source statistics, joint u/v POD, strict signed
% thresholding, 8/4 connected components, and per-sign SS retention.  The
% final object is then adapted to the r2 structures contract so that old
% readers can still load results.structures.catalog and instantaneous.
%
% The saved Section-2 mean_bl MAT is an explicit input for u_tau and wall
% distance. Section 4 recomputes its own PostProc mean, POD reconstruction,
% and detection RMS; the legacy Section-2 RMS is never used as a threshold.
% No statistics/phase/mean_bl workspace object is required.

if nargin < 4
    output_file = '';
end
if nargin < 3 || isempty(mean_bl_file)
    error('tblR2:section4_vlsm_analysis:MissingMeanBLInput', ...
        ['Section 4 requires the saved mean_bl MAT as argument 3. ' ...
        'Compute/read Section 2 and pass paths.mean_bl explicitly.']);
end

section_cfg = resolve_section4_config(cfg);
[nt, ny, nx] = cache_shape(cache_file);
if nt ~= cfg.total_frames || nt ~= 12000 || ny ~= 89 || nx ~= 640
    error('tblR2:section4_vlsm_analysis:CacheShape', ...
        'Section 4 requires the actual PostProc cache shape [12000 89 640]; got [%d %d %d].', ...
        nt, ny, nx);
end

validate_section4_paths(cfg, cache_file, mean_bl_file, output_file, section_cfg);
% Validate actual PostProc and frozen mean_bl inputs; no raw/DAT requirement.
tblR2.validate_sequence_cache(cache_file, cfg, 'postproc');
tblR2.load_result(mean_bl_file, cfg, 'mean_bl', struct(), true);

dcfg = make_d23_config(cfg, section_cfg, cache_file, mean_bl_file, nt, ny, nx);
d23.validate_config(dcfg);
ctx = d23.prepare_source(dcfg);

choice = tblR2.select_section4_run(dcfg, ctx, section_cfg.reuse_existing_run);
reused = choice.reused; run_dir = choice.run_dir; reused_data = choice.loaded;
compute_cfg = choice.compute_config;
if reused
    validate_reused_paths(reused_data, dcfg, run_dir);
    manifest = choice.manifest;
    if ~isempty(section_cfg.resume_run_dir)
        % Explicit resume must also satisfy d23's unchanged config/source contract.
        [run_dir, manifest] = d23.initialize_run(compute_cfg, ctx);
    end
else
    is_new = isempty(run_dir);
    [run_dir, manifest] = d23.initialize_run(compute_cfg, ctx);
    if is_new
        d23.atomic_save(fullfile(run_dir, 'r2_reuse_contract.mat'), struct( ...
            'contract', tblR2.section4_run_contract(compute_cfg, ctx), ...
            'compute_config', compute_cfg, 'created_utc', d23.utc_now()));
    end
    manifest = d23.update_manifest_state(run_dir, manifest, 'RUNNING', struct( ...
        'message', 'Section 4 POD/connected-component detection in progress', ...
        'case_id', cfg.case_id));
end

try
    if reused
        ctx = reused_data.context;
        stats = reused_data.statistics;
        detection_stats = reused_data.detection_statistics;
        detection = struct('catalog_index', reused_data.catalog_index);
        pod_file = fullfile(run_dir, 'pod', 'pod_reconstruction.mat');
        frame_summary_all = reused_data.frame_summary;
        frame_performance = reused_data.frame_performance;
        connectivity = reused_data.connectivity_comparison;
        pairs = reused_data.noss_pairs;
        spectra = reused_data.conditional_spectra;
    else
        stats = d23.compute_statistics(ctx, compute_cfg, run_dir);
        ctx = d23.finalize_context(ctx, stats, compute_cfg);
        d23.atomic_save(fullfile(run_dir, 'mat', 'context.mat'), ...
            struct('context', ctx, 'statistics', stats));

        pod_file = d23.build_pod_cache(ctx, stats, compute_cfg, run_dir);
        detection_stats = d23.prepare_detection_statistics( ...
            ctx, stats, compute_cfg, run_dir, pod_file);
        detection = d23.run_detection( ...
            ctx, stats, detection_stats, compute_cfg, run_dir, pod_file);
        frame_summary_all = [];
        frame_performance = [];
        connectivity = [];
        pairs = [];
        spectra = [];
    end
    ctx = ensure_spatial_exclusion_context(ctx, dcfg);
    detection_stats = ensure_detection_spatial_counts(detection_stats, pod_file);

    % Load every component (not only IsSS3) from the committed 48-frame
    % partitions.  This is the authoritative full catalog for r2.
    if ~reused || isempty(frame_summary_all)
        [catalog_d23, frame_summary_all, frame_performance] = ...
            load_detection_partitions(detection.catalog_index);
    else
        [catalog_d23, ~, ~] = load_detection_partitions(detection.catalog_index);
    end
    ss_catalog = catalog_d23(catalog_d23.IsSS3, :);
    censored_ss_catalog = ss_catalog(ss_catalog.IsCensored, :);
    complete_ss_catalog = ss_catalog(~ss_catalog.IsCensored, :);
    collected = struct('frame_summary', frame_summary_all, ...
        'frame_performance', frame_performance, ...
        'ss_catalog', ss_catalog, ...
        'censored_ss_catalog', censored_ss_catalog, ...
        'complete_ss_catalog', complete_ss_catalog, ...
        'catalog_index', detection.catalog_index);

    if isempty(connectivity)
        connectivity = d23.connectivity_comparison(ss_catalog, ctx, dcfg);
    end
    if isempty(pairs)
        pairs = d23.match_noss(ss_catalog, ctx, dcfg);
    end
    if isempty(spectra)
        spectra = empty_spectra();
        try
            spectra = d23.conditional_spectra(pairs, ctx, stats, dcfg, pod_file);
        catch problem
            warning('tblR2:section4_vlsm_analysis:SpectraLimited', ...
                '条件谱未完成，结构识别仍有效：%s', problem.message);
            spectra = empty_spectra();
        end
    end
    % Gallery metadata follows the explicitly selected figure connectivity.
    % Recompute it even for reused detection runs because older runs selected
    % connectivity 8 implicitly and did not record this presentation choice.
    selection = d23.select_gallery(ss_catalog, nt, ...
        section_cfg.figure_connectivity);

    % Adapt the complete D23 catalogs to the historical r2 schema.
    catalog8 = adapt_catalog(catalog_d23(catalog_d23.Connectivity == 8, :), ...
        ctx, cfg);
    catalog4 = adapt_catalog(catalog_d23(catalog_d23.Connectivity == 4, :), ...
        ctx, cfg);
    clear catalog_d23;
    frame_summary8 = frame_summary_all(frame_summary_all.Connectivity == 8, :);
    frame_summary4 = frame_summary_all(frame_summary_all.Connectivity == 4, :);

    instantaneous = build_instantaneous(ctx, stats, detection_stats, dcfg, ...
        pod_file, catalog8, catalog4, cfg);
    figure_manifest = table();
    figure_files = strings(0, 1);
    gallery_files = strings(0, 1);
    if section_cfg.make_figures
        [figure_manifest, figure_files, gallery_files] = ...
            tblR2.section4_vlsm_figures(catalog8, catalog4, ctx, stats, ...
            detection_stats, dcfg, pod_file, section_cfg.figure_root, selection);
    end

    summary = d23.build_summary(ctx, detection_stats, collected, ...
        connectivity, pairs, spectra, dcfg);
    summary = augment_summary(summary, catalog8, catalog4, figure_manifest, ...
        section_cfg, cfg);

    % Keep the isolated d23 package complete and auditable as well.  A reused
    % completed run is read-only; publishing it again would mutate its hash.
    if ~reused
        d23.write_outputs(ctx, stats, detection_stats, collected, connectivity, ...
            pairs, spectra, selection, summary, compute_cfg, run_dir, ...
            figure_files, gallery_files);
    end

    result = build_result_struct(catalog8, catalog4, frame_summary8, ...
        frame_summary4, frame_summary_all, frame_performance, ...
        detection.catalog_index, instantaneous, ctx, stats, detection_stats, ...
        connectivity, pairs, spectra, selection, figure_manifest, summary, ...
        dcfg, pod_file, run_dir, cfg);

    if isempty(output_file)
        output_file = fullfile(cfg.output_dir, 'mat', '09_structure_analysis.mat');
    end
    atomic_save_r2(output_file, result, cfg, 'structures', ...
        struct('cache', cache_file, 'mean_bl', mean_bl_file));
    write_compatibility_outputs(result, section_cfg, output_file);

    if ~reused
        manifest = d23.update_manifest_state(run_dir, manifest, 'COMPLETE', struct( ...
            'completed_utc', d23.utc_now(), 'r2_result_file', output_file, ...
            'catalog_rows_8', height(catalog8), 'catalog_rows_4', height(catalog4)));
    end
    result.section4_run_dir = run_dir;
    result.section4_manifest = manifest;
catch problem
    if ~reused
        d23.update_manifest_state(run_dir, manifest, 'FAILED', struct( ...
            'identifier', problem.identifier, 'message', problem.message, ...
            'failed_utc', d23.utc_now()));
    end
    rethrow(problem);
end
end

function section_cfg = resolve_section4_config(cfg)
% Resolve the new nested configuration while accepting a compact legacy call.
section_cfg = struct();
if isfield(cfg, 'structures') && isfield(cfg.structures, 'section4') && ...
        isstruct(cfg.structures.section4)
    section_cfg = cfg.structures.section4;
end
if ~isfield(section_cfg, 'source_mode') || isempty(section_cfg.source_mode)
    if isfield(cfg.structures, 'source_mode')
        section_cfg.source_mode = cfg.structures.source_mode;
    else
        section_cfg.source_mode = 'pod_e50';
    end
end
section_cfg.source_mode = lower(char(section_cfg.source_mode));
if ~ismember(section_cfg.source_mode, {'pod_e50','postproc_direct'})
    error('tblR2:section4_vlsm_analysis:SourceMode', ...
        'source_mode must be pod_e50 or postproc_direct.');
end
defaults = struct( ...
    'reference_x_mm', [100 220], 'chunk_frames', 48, 'amplitude_multiplier', 1.0, ...
    'connectivities', [8 4], 'primary_connectivity', 8, ...
    'length_thresholds', [3 3.8 4.5], ...
    'max_complete_ss_per_sign', 1, 'plot_colormap', 'ocean', ...
    'plot_normalization', 'u_over_Uinf', 'make_figures', true, ...
    'write_catalog_csv', true, 'max_figure_objects', Inf, ...
    'resume_run_dir', '', 'frame_ordinals', []);
names = fieldnames(defaults);
for i = 1:numel(names)
    name = names{i};
    if ~isfield(section_cfg, name) || isempty(section_cfg.(name))
        section_cfg.(name) = defaults.(name);
    end
end
if ~isfield(section_cfg, 'streamwise_edge_exclusion') || ...
        ~isstruct(section_cfg.streamwise_edge_exclusion) || ...
        ~isscalar(section_cfg.streamwise_edge_exclusion)
    section_cfg.streamwise_edge_exclusion = struct('enabled', false, ...
        'buffer_cells', 3);
else
    edge_defaults = struct('enabled', false, 'buffer_cells', 3);
    edge_names = fieldnames(edge_defaults);
    for i = 1:numel(edge_names)
        name = edge_names{i};
        if ~isfield(section_cfg.streamwise_edge_exclusion, name) || ...
                isempty(section_cfg.streamwise_edge_exclusion.(name))
            section_cfg.streamwise_edge_exclusion.(name) = edge_defaults.(name);
        end
    end
end
if ~isfield(section_cfg, 'figure_connectivity') || ...
        isempty(section_cfg.figure_connectivity)
    section_cfg.figure_connectivity = section_cfg.primary_connectivity;
end
section_cfg.figure_connectivity = double(section_cfg.figure_connectivity);
if ~isscalar(section_cfg.figure_connectivity) || ...
        ~ismember(section_cfg.figure_connectivity, [4 8]) || ...
        ~ismember(section_cfg.figure_connectivity, ...
        double(section_cfg.connectivities(:).'))
    error('tblR2:section4_vlsm_analysis:FigureConnectivity', ...
        ['figure_connectivity must be the scalar value 4 or 8 and must ' ...
        'also appear in connectivities.']);
end
if ~isfield(section_cfg, 'pod') || ~isstruct(section_cfg.pod)
    section_cfg.pod = struct();
end
if ~isfield(section_cfg.pod, 'spatial_block_dof'); section_cfg.pod.spatial_block_dof = 512; end
if ~isfield(section_cfg.pod, 'time_tile_frames'); section_cfg.pod.time_tile_frames = 128; end
if ~isfield(section_cfg.pod, 'min_valid_fraction') || ...
        isempty(section_cfg.pod.min_valid_fraction)
    section_cfg.pod.min_valid_fraction = 1.0;
end
if ~isfield(section_cfg.pod, 'rank') || ~isstruct(section_cfg.pod.rank)
    section_cfg.pod.rank = struct('kind', 'energy_fraction', 'value', 0.50);
end
if ~isfield(section_cfg.pod.rank, 'kind')
    section_cfg.pod.rank.kind = 'energy_fraction';
end
if ~isfield(section_cfg, 'reuse_existing_run') || isempty(section_cfg.reuse_existing_run)
    section_cfg.reuse_existing_run = true;
end
if ~isfield(section_cfg, 'spatial_exclusion') || ...
        ~isstruct(section_cfg.spatial_exclusion) || ...
        ~isscalar(section_cfg.spatial_exclusion)
    section_cfg.spatial_exclusion = struct('enabled', false, ...
        'x_start_mm', [], 'x_end_mm', [], 'wall_y_height_mm', []);
else
    exclusion_defaults = struct('enabled', false, 'x_start_mm', [], ...
        'x_end_mm', [], 'wall_y_height_mm', []);
    exclusion_names = fieldnames(exclusion_defaults);
    for i = 1:numel(exclusion_names)
        name = exclusion_names{i};
        if ~isfield(section_cfg.spatial_exclusion, name)
            section_cfg.spatial_exclusion.(name) = exclusion_defaults.(name);
        end
    end
end
if strcmp(char(section_cfg.pod.rank.kind), 'energy_fraction') && ...
        ~isfield(section_cfg.pod.rank, 'value')
    section_cfg.pod.rank.value = 0.50;
end
section_cfg.figure_root = fullfile(cfg.output_dir, 'section4_vlsm');
if isfield(section_cfg, 'output_dir') && ~isempty(section_cfg.output_dir)
    section_cfg.figure_root = char(section_cfg.output_dir);
end
end

function dcfg = make_d23_config(cfg, section_cfg, cache_file, mean_bl_file, nt, ny, nx)
% Build a strict d23 configuration from the case-specific r2 contract.
% default_config supplies unchanged scientific defaults. All of its legacy
% path templates are replaced here before any d23 consumer receives dcfg.
case_root = fileparts(cfg.script_file);
dcfg = d23.default_config(case_root);
dcfg.schema_version = 3;
dcfg.experiment_id = 'r2_section4_vlsm';
dcfg.case_id = cfg.case_id;
dcfg.repo_root = case_root; % Historical field name; no repository search.
dcfg.data.cache_file = cache_file;
dcfg.data.utau_result_file = mean_bl_file;
dcfg.data.expected_cache_size = [nt ny nx];
dcfg.data.reference_x_mm = section_cfg.reference_x_mm;
dcfg.data.nu_m2_s = cfg.nu;
dcfg.statistics.chunk_size = section_cfg.chunk_frames;
dcfg.statistics.frame_ordinals = (1:nt).';
dcfg.statistics.reuse_file = '';
dcfg.detection.connectivities = double(section_cfg.connectivities(:).');
dcfg.detection.primary_connectivity = double(section_cfg.primary_connectivity);
dcfg.detection.amplitude_multiplier = section_cfg.amplitude_multiplier;
dcfg.detection.length_thresholds = double(section_cfg.length_thresholds(:).');
dcfg.detection.max_complete_ss_per_sign = double(section_cfg.max_complete_ss_per_sign);
dcfg.detection.selection_rule = ...
    'longest_then_pixel_count_then_component_id_nonoverlapping_bbox';
dcfg.detection.streamwise_edge_exclusion = ...
    section_cfg.streamwise_edge_exclusion;
dcfg.preprocessing.pod.enabled = strcmp(section_cfg.source_mode, 'pod_e50');
dcfg.preprocessing.spatial_exclusion = section_cfg.spatial_exclusion;
dcfg.preprocessing.pod.min_valid_fraction = ...
    double(section_cfg.pod.min_valid_fraction);
dcfg.preprocessing.pod.rank = section_cfg.pod.rank;
dcfg.preprocessing.pod.rms_source = 'reconstruction';
dcfg.preprocessing.pod.spatial_block_dof = section_cfg.pod.spatial_block_dof;
dcfg.preprocessing.pod.time_tile_frames = section_cfg.pod.time_tile_frames;
% Full-size Section-4 runs use the exact in-memory method-of-snapshots path.
% This avoids multi-day compressed matfile writes while preserving the same
% centered double-precision covariance, E50 selection, and reconstruction.
dcfg.preprocessing.pod.fast_in_memory = true;
dcfg.preprocessing.gaussian.enabled = false;
dcfg.preprocessing.gaussian.sigma_cells = [];
dcfg.preprocessing.gaussian.filter_size = [];
dcfg.preprocessing.gaussian.padding = 'replicate';
dcfg.matching.require_full_valid_box = false;
dcfg.execution.label = sprintf('section4_%s', section_cfg.source_mode);
if isfield(section_cfg, 'frame_ordinals') && ~isempty(section_cfg.frame_ordinals)
    dcfg.execution.frame_ordinals = double(section_cfg.frame_ordinals(:));
else
    dcfg.execution.frame_ordinals = (1:nt).';
end
dcfg.execution.progress_every_batches = 5;
dcfg.execution.make_gallery = false;
dcfg.execution.make_figures = false;
dcfg.output.root = fullfile(section_cfg.figure_root, 'runs');
dcfg.output.resume_run_dir = char(section_cfg.resume_run_dir);
dcfg.output.write_catalog_csv = true;
dcfg.output.verify_catalog_csv = false;
dcfg.output.figure_dpi = cfg.figures.export_dpi;
dcfg.output.field_colormap = 'balance';
dcfg.output.field_colormap_levels = 257;
dcfg.output.field_clim = [-3 3];
dcfg.output.field_physical_aspect = true;
dcfg.Uinf = cfg.Uinf;
dcfg.plot_normalization = char(section_cfg.plot_normalization);
dcfg.section4_max_figure_objects = double(section_cfg.max_figure_objects);
dcfg.section4_figure_connectivity = ...
    double(section_cfg.figure_connectivity);
end

function ctx = ensure_spatial_exclusion_context(ctx, cfg)
if isfield(ctx, 'spatial_exclusion') && ...
        isfield(ctx, 'spatial_exclusion_mask')
    return;
end
[mask, info] = d23.resolve_spatial_exclusion(ctx.X_mm, ...
    ctx.wall_distance_mm, cfg.preprocessing.spatial_exclusion);
ctx.spatial_exclusion_mask = mask;
ctx.spatial_exclusion = info;
end

function stats = ensure_detection_spatial_counts(stats, pod_file)
required = {'pod_retained_spatial_count_before_exclusion', ...
    'pod_retained_spatial_count', 'pod_excluded_retained_spatial_count', ...
    'pod_joint_dof_count'};
if all(isfield(stats, required))
    return;
end
retained = 0;
joint = 0;
if ~isempty(pod_file)
    meta_file = fullfile(fileparts(pod_file), 'pod_metadata.mat');
    if isfile(meta_file)
        loaded = load(meta_file, 'pod_meta');
        retained = double(loaded.pod_meta.retained_spatial_count);
        joint = double(loaded.pod_meta.joint_dof_count);
    end
end
stats.pod_retained_spatial_count_before_exclusion = uint32(retained);
stats.pod_retained_spatial_count = uint32(retained);
stats.pod_excluded_retained_spatial_count = uint32(0);
stats.pod_joint_dof_count = uint32(joint);
end

function T = ensure_catalog_spatial_column(T)
% Expand historical d23 batch catalogs losslessly for compatibility reads.
if ~ismember('TouchesUserExclusion', T.Properties.VariableNames)
    T.TouchesUserExclusion = false(height(T), 1);
end
if ismember('IsCensored', T.Properties.VariableNames)
    T = movevars(T, 'TouchesUserExclusion', 'Before', 'IsCensored');
end
required = {'TouchesStreamwiseLeftBuffer', ...
    'TouchesStreamwiseRightBuffer','RejectedByStreamwiseEdge', ...
    'SuppressedByBBoxOverlap'};
for i = 1:numel(required)
    name = required{i};
    if ~ismember(name, T.Properties.VariableNames)
        T.(name) = false(height(T), 1);
    end
end
if ismember('CensorReasonCode', T.Properties.VariableNames)
    T = movevars(T, required, 'After', 'CensorReasonCode');
end
end

function [nt, ny, nx] = cache_shape(cache_file)
if ~isfile(cache_file)
    error('tblR2:section4_vlsm_analysis:MissingCache', ...
        ['Missing PostProc cache: %s. Compute Section 1 or explicitly ' ...
        'install the verified local cache; Section 4 does not rebuild it.'], cache_file);
end
cache = matfile(cache_file);
info = whos(cache, 'U');
if isempty(info) || numel(info.size) ~= 3
    error('tblR2:section4_vlsm_analysis:MissingCache', ...
        'PostProc cache lacks a 3-D U variable: %s', cache_file);
end
nt = info.size(1); ny = info.size(2); nx = info.size(3);
end

function validate_section4_paths(cfg, cache_file, mean_bl_file, output_file, section_cfg)
% Check physical input/output ownership without reading velocity arrays or DAT.
if ~isfield(cfg, 'script_file') || isempty(cfg.script_file)
    error('tblR2:section4_vlsm_analysis:MissingCaseScript', ...
        'Run Section 0 to define cfg.script_file for this case.');
end
case_root = char(java.io.File(fileparts(cfg.script_file)).getCanonicalPath());
output_root = char(java.io.File(fullfile(case_root, 'output')).getCanonicalPath());
configured_output = char(java.io.File(cfg.output_dir).getCanonicalPath());
if ~strcmp(configured_output, output_root) && ...
        ~(ispc && strcmpi(configured_output, output_root))
    error('tblR2:section4_vlsm_analysis:OutsideCase', ...
        'cfg.output_dir must be this case script''s output folder: %s; got %s.', ...
        output_root, cfg.output_dir);
end
paths = {char(cache_file), char(mean_bl_file), char(section_cfg.figure_root), ...
    fullfile(char(section_cfg.figure_root), 'runs')};
labels = {'PostProc cache', 'Section 2 mean_bl MAT', 'Section 4 figure root', ...
    'Section 4 run root'};
roots = {case_root, case_root, output_root, output_root};
if ~isempty(output_file)
    paths{end+1} = char(output_file);
    labels{end+1} = 'Section 4 result MAT';
    roots{end+1} = output_root;
end
if ~isempty(section_cfg.resume_run_dir)
    paths{end+1} = char(section_cfg.resume_run_dir);
    labels{end+1} = 'Section 4 resume run';
    roots{end+1} = output_root;
end
for i = 1:numel(paths)
    physical_path = char(java.io.File(paths{i}).getCanonicalPath());
    if ~startsWith(physical_path, [roots{i} filesep], 'IgnoreCase', ispc)
        error('tblR2:section4_vlsm_analysis:OutsideCase', ...
            ['%s is outside the current case: %s. Required parent: %s. ' ...
            'Import verified old paths explicitly; no historical fallback is used.'], ...
            labels{i}, paths{i}, roots{i});
    end
end
if ~isfile(mean_bl_file)
    error('tblR2:section4_vlsm_analysis:MissingMeanBLFile', ...
        ['Missing Section 2 mean_bl MAT: %s. Compute Section 2 or install its ' ...
        'verified saved result; Section 4 does not compute it automatically.'], mean_bl_file);
end
end

function validate_reused_paths(loaded, dcfg, run_dir)
% A local candidate must also use local files in its saved active references.
% Compute/source identities were checked by select_section4_run; audit active paths here.
ctx = loaded.context;
if ~all(isfield(ctx, {'cache_file','cache_source','utau_source'})) || ...
        ~isfield(ctx.cache_source, 'path') || ~isfield(ctx.utau_source, 'path')
    error('tblR2:section4_vlsm_analysis:LegacyPathIdentity', ...
        ['Run %s lacks saved active input paths. Use an explicit, reviewed ' ...
        'legacy migration; no identity is assigned automatically.'], run_dir);
end
saved_paths = {char(ctx.cache_file), char(ctx.cache_source.path), ...
    char(ctx.utau_source.path)};
expected_paths = {char(dcfg.data.cache_file), char(dcfg.data.cache_file), ...
    char(dcfg.data.utau_result_file)};
labels = {'context.cache_file', 'context.cache_source.path', ...
    'context.utau_source.path'};
for i = 1:numel(saved_paths)
    saved = char(java.io.File(saved_paths{i}).getCanonicalPath());
    expected = char(java.io.File(expected_paths{i}).getCanonicalPath());
    if ~strcmp(saved, expected) && ~(ispc && strcmpi(saved, expected))
        error('tblR2:section4_vlsm_analysis:LegacyPathIdentity', ...
            ['Run %s has %s=%s; current explicit input is %s. ' ...
            'Verify the data and migrate that reference explicitly before reuse.'], ...
            run_dir, labels{i}, saved_paths{i}, expected_paths{i});
    end
end
physical_run = char(java.io.File(run_dir).getCanonicalPath());
index = loaded.catalog_index;
for i = 1:height(index)
    filename = char(index.MatFile(i));
    physical_file = char(java.io.File(filename).getCanonicalPath());
    if ~startsWith(physical_file, [physical_run filesep], 'IgnoreCase', ispc) || ...
            ~isfile(filename)
        error('tblR2:section4_vlsm_analysis:LegacyCatalogPath', ...
            ['Run %s catalog_index.MatFile(%d) is missing or outside this run: %s. ' ...
            'Verify and explicitly migrate the original partition; no path is guessed.'], ...
            run_dir, i, filename);
    end
end
if dcfg.preprocessing.pod.enabled
    required_pod = {'pod_reconstruction.mat','pod_metadata.mat'};
    for i = 1:numel(required_pod)
        filename = fullfile(run_dir, 'pod', required_pod{i});
        physical_file = char(java.io.File(filename).getCanonicalPath());
        if ~startsWith(physical_file, [physical_run filesep], 'IgnoreCase', ispc) || ...
                ~isfile(filename)
            error('tblR2:section4_vlsm_analysis:MissingLocalPOD', ...
                ['Run %s POD file is missing or resolves outside this run: %s. ' ...
                'Install the verified original local file; Section 4 will not ' ...
                'substitute a historical POD path.'], ...
                run_dir, filename);
        end
    end
end
end

function [catalog, frame_summary, frame_performance] = load_detection_partitions(index)
if isempty(index)
    catalog = d23.empty_catalog();
    frame_summary = d23.empty_frame_summary();
    frame_performance = table(zeros(0,1,'uint32'), zeros(0,1,'uint32'), ...
        zeros(0,1), zeros(0,1,'uint32'), zeros(0,1), ...
        'VariableNames', {'FrameOrdinal','FrameID','Elapsed_s', ...
        'ComponentCount','MatlabMemoryBytes'});
    return;
end
n = height(index);
catalog_parts = cell(n,1);
summary_parts = cell(n,1);
performance_parts = cell(n,1);
for i = 1:n
    loaded = load(char(index.MatFile(i)), 'catalog', 'frame_summary', ...
        'frame_performance');
    catalog_parts{i} = ensure_catalog_spatial_column(loaded.catalog);
    summary_parts{i} = loaded.frame_summary;
    performance_parts{i} = loaded.frame_performance;
end
catalog = vertcat(catalog_parts{:});
frame_summary = vertcat(summary_parts{:});
frame_performance = vertcat(performance_parts{:});
end

function T = adapt_catalog(src, ctx, cfg)
% Map the full d23 component schema to the r2/legacy structure schema.
names = compatibility_names();
if isempty(src)
    T = empty_compatibility_catalog();
    return;
end
n = height(src);
lx = double(src.Lx_mm);
height_y = double(src.BBoxHeight_px) * ctx.dy_mm;
delta = double(ctx.delta99_mm);
lxod = double(src.Lx_over_delta);
area = double(src.Area_mm2);
cent_x = 0.5 * (double(src.XMin_mm) + double(src.XMax_mm));
cent_y = 0.5 * (double(src.YMin_mm) + double(src.YMax_mm));
is_lsm = lxod > 1;               % strict threshold by contract
is_vlsm = logical(src.IsSS3);    % retained primary complete SS only
branch = repmat("total", n, 1);
nanv = nan(n,1);
phase_bin = nanv;
phase_deg = nanv;
cycle = nanv;
T = table( ...
    uint32(src.FrameOrdinal), uint32(src.FrameID), branch, phase_bin, cycle, ...
    uint32(src.ComponentID), int8(src.Sign), uint32(src.PixelCount), area, ...
    cent_x, cent_y, cent_x, cent_y, nanv, nanv, nanv, nanv, ...
    true(n,1), double(src.XMin_mm), double(src.XMax_mm), ...
    double(src.YMin_mm), double(src.YMax_mm), lx, height_y, ...
    repmat(delta,n,1), lx ./ max(height_y, eps), lxod, ...
    height_y ./ max(delta, eps), area ./ max(delta.^2, eps), ...
    nanv, nanv, nanv, is_lsm, is_vlsm, ones(n,1), ...
    uint8(src.Connectivity), ...
    logical(src.PassLength3), logical(src.PassLength3p8), ...
    logical(src.PassLength4p5), double(src.YMin_plus), double(src.YMax_plus), ...
    logical(src.PassWallLower), logical(src.PassWallUpper), logical(src.IsSS3), ...
    logical(src.IsSS3p8), logical(src.IsSS4p5), ...
    logical(src.TouchesUpstream), logical(src.TouchesDownstream), ...
    logical(src.TouchesWall), logical(src.TouchesTop), logical(src.TouchesInvalid), ...
    logical(src.TouchesUserExclusion), ...
    logical(src.IsCensored), uint8(src.CensorReasonCode), ...
    logical(src.TouchesStreamwiseLeftBuffer), ...
    logical(src.TouchesStreamwiseRightBuffer), ...
    logical(src.RejectedByStreamwiseEdge), ...
    logical(src.SuppressedByBBoxOverlap), ...
    'VariableNames', names);
% Keep cfg visible in the generated code path and make the conversion fail
% loudly if a future schema accidentally changes the required dimensions.
if height(T) ~= n
    error('tblR2:section4_vlsm_analysis:CatalogAdapt', ...
        'Internal compatibility catalog construction failed.');
end
end

function names = compatibility_names()
names = {'FrameOrdinal','FrameID','Branch','PhaseBin','CycleIndex', ...
    'StructureID','Sign','PixelCount','Area_mm2','CentroidX_mm', ...
    'CentroidY_mm','CentroidVelWeightedX_mm','CentroidVelWeightedY_mm', ...
    'CentroidVelWeightedOffsetX_mm','CentroidVelWeightedOffsetY_mm', ...
    'VelocityWeightSum','VelocityWeightMean','CenterFallbackFlag', ...
    'XMin_mm','XMax_mm','YMin_mm','YMax_mm','LengthX_mm','HeightY_mm', ...
    'Delta99Ref_mm','AspectRatio','LengthX_over_delta','HeightY_over_delta', ...
    'Area_over_delta2','uMean','peakAmp','Spacing_mm','IsLSM','IsVLSM', ...
    'Alpha','Connectivity','PassLength3','PassLength3p8','PassLength4p5', ...
    'YMin_plus','YMax_plus','PassWallLower','PassWallUpper','IsSS3', ...
    'IsSS3p8','IsSS4p5','TouchesUpstream','TouchesDownstream','TouchesWall', ...
    'TouchesTop','TouchesInvalid','TouchesUserExclusion','IsCensored', ...
    'CensorReasonCode','TouchesStreamwiseLeftBuffer', ...
    'TouchesStreamwiseRightBuffer','RejectedByStreamwiseEdge', ...
    'SuppressedByBBoxOverlap'};
end

function T = empty_compatibility_catalog()
names = compatibility_names();
types = [{'uint32','uint32','string','double','double','uint32','int8','uint32'}, ...
    repmat({'double'},1,9), {'logical'}, repmat({'double'},1,14), ...
    {'logical','logical','double','uint8'}, repmat({'logical'},1,3), ...
    repmat({'double'},1,2), repmat({'logical'},1,12), {'uint8'}, ...
    repmat({'logical'},1,4)];
T = table('Size',[0 numel(names)],'VariableTypes',types, ...
    'VariableNames',names);
end

function instantaneous = build_instantaneous(ctx, stats, detection_stats, dcfg, ...
        pod_file, catalog8, catalog4, cfg)
ids = tblR2.instantaneous_frame_ids(cfg.instantaneous, ctx.cache_size(1));
instantaneous = repmat(empty_instantaneous_item(), numel(ids), 1);
for k = 1:numel(ids)
    ordinal = double(ids(k));
    fields = d23.fluctuation_chunk(ctx, stats, dcfg, ordinal, pod_file);
    raw = d23.read_chunk(ctx.cache_file, ordinal);
    up = squeeze(fields.up(1,:,:));
    vp = squeeze(fields.vp(1,:,:));
    valid = squeeze(fields.valid(1,:,:));
    urms = reshape(double(detection_stats.u_rms_y), [], 1);
    normalized = up ./ max(reshape(urms, [], 1), eps);
    normalized(~valid) = NaN;
    frame_id = double(ctx.frame_ids(ordinal));
    rows8 = catalog8.FrameID == frame_id;
    rows4 = catalog4.FrameID == frame_id;
    structures8 = catalog8(rows8,:);
    structures4 = catalog4(rows4,:);
    positive = valid & up > reshape(urms, [], 1);
    negative = valid & up < -reshape(urms, [], 1);
    labels8 = make_labels(structures8, size(up), ctx);
    st = struct('normalized_field', normalized, 'analysis_mask', valid, ...
        'user_exclusion_mask', ~d23.spatial_active_mask(ctx), ...
        'threshold_positive_mask', positive, ...
        'threshold_negative_mask', negative, ...
        'growth_positive_mask', positive, 'growth_negative_mask', negative, ...
        'seed_positive_mask', positive, 'seed_negative_mask', negative, ...
        'positive_mask', positive, 'negative_mask', negative, ...
        'positive_labels', labels8.positive, 'negative_labels', labels8.negative, ...
        'structures', structures8, 'structures_4', structures4, ...
        'options', dcfg.detection, 'topology_cleanup', struct('enabled',false), ...
        'rejected_aspect_ratio_count', 0, ...
        'rejected_trusted_boundary_count', 0, ...
        'trusted_boundary_mask', true(size(up)), ...
        'method', 'strict signed u''/u_rms(y) connected components');
    item = empty_instantaneous_item();
    item.frame_id = frame_id;
    item.phase_bin = NaN;
    item.U_raw = squeeze(raw.U(1,:,:));
    item.V_raw = squeeze(raw.V(1,:,:));
    item.u_prime = up; item.v_prime = vp;
    item.uv_prime = up .* vp;
    item.u_total = up; item.v_total = vp; item.uv_total = up .* vp;
    item.negative_uv_total = -(up .* vp);
    item.u_structure_input = up; item.v_structure_input = vp;
    item.structure_valid_mask = valid; item.frame_valid_mask = valid;
    item.u_random = []; item.v_random = []; item.uv_random = [];
    item.negative_uv_random = [];
    item.planar_input_U = up; item.planar_input_V = vp;
    item.planar_criteria = [];
    item.structures_total = st; item.structures_random = [];
    item.q2q4_total = []; item.preprocessing_total = fields.gaussian_metadata;
    item.preprocessing_planar = fields.gaussian_metadata;
    instantaneous(k) = item;
end
end

function item = empty_instantaneous_item()
item = struct('frame_id',NaN,'phase_bin',NaN,'U_raw',[],'V_raw',[], ...
    'u_prime',[],'v_prime',[],'uv_prime',[],'u_total',[],'v_total',[], ...
    'uv_total',[],'negative_uv_total',[],'u_structure_input',[], ...
    'v_structure_input',[],'structure_valid_mask',[],'frame_valid_mask',[], ...
    'u_random',[],'v_random',[],'uv_random',[],'negative_uv_random',[], ...
    'planar_input_U',[],'planar_input_V',[],'planar_criteria',[], ...
    'structures_total',[],'structures_random',[],'q2q4_total',[], ...
    'preprocessing_total',[],'preprocessing_planar',[]);
end

function labels = make_labels(T, sz, ctx)
labels.positive = zeros(sz, 'uint32');
labels.negative = zeros(sz, 'uint32');
for i = 1:height(T)
    cmin = max(1, min(sz(2), round((double(T.XMin_mm(i)) - ctx.x_mm(1))/ctx.dx_mm + 1)));
    cmax = max(cmin, min(sz(2), round((double(T.XMax_mm(i)) - ctx.x_mm(1))/ctx.dx_mm + 1)));
    rmin = max(1, min(sz(1), round(double(T.YMin_mm(i))/ctx.dy_mm + 1)));
    rmax = max(rmin, min(sz(1), round(double(T.YMax_mm(i))/ctx.dy_mm + 1)));
    if T.Sign(i) > 0
        labels.positive(rmin:rmax,cmin:cmax) = uint32(T.StructureID(i));
    else
        labels.negative(rmin:rmax,cmin:cmax) = uint32(T.StructureID(i));
    end
end
end

function result = build_result_struct(catalog8, catalog4, frame_summary8, ...
        frame_summary4, frame_summary_all, frame_performance, catalog_index, ...
        instantaneous, ctx, stats, detection_stats, connectivity, pairs, ...
        spectra, selection, figure_manifest, summary, dcfg, pod_file, run_dir, cfg)
result = struct();
result.instantaneous = instantaneous;
result.instantaneous_frame_range = [1 ctx.cache_size(1)];
result.instantaneous_frame_ids = [instantaneous.frame_id];
result.processed_frame_count = ctx.cache_size(1);
result.catalog_frame_count = numel(unique(double(catalog8.FrameOrdinal)));
result.catalog = catalog8;
result.catalog_4 = catalog4;
result.frame_summary = frame_summary8;
result.frame_summary_4 = frame_summary4;
result.frame_summary_all = frame_summary_all;
result.frame_performance = frame_performance;
result.catalog_index = catalog_index;
result.connectivity_comparison = connectivity;
result.connectivity_comparison_8_4 = connectivity;
result.noss_pairs = pairs;
result.conditional_spectra = spectra;
result.q2q4 = [];
result.paper_proxy = struct();
result.phase_coherent = [];
result.phase_distribution = [];
result.conditional_average = [];
result.conditional_average_random = [];
result.conditional_spectra_random = [];
result.tracking_benchmark = [];
result.threshold_calibration = [];
result.vlsm_gallery = [];
result.vlsm_gallery_frame_ids = [];
result.vlsm_gallery_selection = selection;
result.preprocessing_summary = make_preprocessing_summary(instantaneous);
result.preprocessing = struct('enabled', false, 'name', 'none', ...
    'pod_enabled', dcfg.preprocessing.pod.enabled, ...
    'gaussian_enabled', dcfg.preprocessing.gaussian.enabled, ...
    'order', 'POD then Gaussian', 'source_mode', ...
    char(resolve_section4_config(cfg).source_mode), ...
    'spatial_exclusion', ctx.spatial_exclusion);
result.planar_mean = struct('X', ctx.X_mm, 'Y', ctx.wall_distance_mm, ...
    'Uavex', stats.Ubar, 'Vavex', stats.Vbar, ...
    'u_rms_y', detection_stats.u_rms_y);
result.planar_phase = [];
result.delta99_grid_mm = repmat(ctx.delta99_mm, size(ctx.X_mm));
result.options = struct('alpha', 1.0, 'seed_alpha', 1.0, ...
    'min_pixels', 1, 'connectivity', 8, 'connectivities', [8 4], ...
    'min_lsm_delta', 1.0, 'min_vlsm_delta', 3.0, ...
    'length_thresholds', dcfg.detection.length_thresholds, ...
    'max_complete_ss_per_sign', dcfg.detection.max_complete_ss_per_sign, ...
    'sign_mode', 'both', 'source_mode', ...
    char(resolve_section4_config(cfg).source_mode), ...
    'selection_rule', dcfg.detection.selection_rule);
result.options.spatial_exclusion = ctx.spatial_exclusion;
result.options.streamwise_edge_exclusion = ...
    dcfg.detection.streamwise_edge_exclusion;
result.filter = struct('enabled', false, 'name', 'none', ...
    'gaussian', dcfg.preprocessing.gaussian);
result.definition = ['Section 4 uses PostProc 12000-frame statistics, optional ' ...
    'joint u/v POD cumulative-energy 50% reconstruction, strict signed ' ...
    'u'' > u_rms(y) / u'' < -u_rms(y), raw 8/4 connected components, ' ...
    'an optional user-defined static spatial exclusion, optional streamwise ' ...
    'edge rejection, and deterministic non-overlapping complete SS retention.'];
result.source_role = 'postproc';
result.source_definition = 'PostProc cache -> joint POD-E50 reconstruction -> strict signed connectivity';
result.planar_scope = 'total';
result.context = ctx;
result.spatial_exclusion = ctx.spatial_exclusion;
result.statistics = stats;
result.detection_statistics = detection_stats;
result.pod_metadata = load_pod_metadata(pod_file);
result.section4_run_dir = run_dir;
result.figure_manifest = figure_manifest;
result.summary = summary;
end

function T = make_preprocessing_summary(instantaneous)
n = numel(instantaneous);
T = table(zeros(n,1), strings(n,1), zeros(n,1), zeros(n,1), ...
    zeros(n,1), zeros(n,1), 'VariableNames', ...
    {'FrameID','Branch','InputValidCount','OutlierCount', ...
    'ReconstructedOutlierCount','OutputValidCount'});
for i = 1:n
    T.FrameID(i) = instantaneous(i).frame_id;
    T.Branch(i) = "total";
    valid = instantaneous(i).frame_valid_mask;
    T.InputValidCount(i) = nnz(valid);
    T.OutputValidCount(i) = nnz(valid & isfinite(instantaneous(i).u_prime));
end
end

function pod_meta = load_pod_metadata(pod_file)
pod_meta = struct();
if isempty(pod_file), return; end
meta_file = fullfile(fileparts(pod_file), 'pod_metadata.mat');
if isfile(meta_file)
    loaded = load(meta_file, 'pod_meta');
    if isfield(loaded, 'pod_meta'), pod_meta = loaded.pod_meta; end
end
end

function summary = augment_summary(summary, catalog8, catalog4, figure_manifest, ...
        section_cfg, cfg)
edge_config = section_cfg.streamwise_edge_exclusion;
summary.streamwise_edge_exclusion = struct( ...
    'enabled', logical(edge_config.enabled), ...
    'buffer_cells', double(edge_config.buffer_cells), ...
    'counts', edge_retention_counts(catalog8, catalog4));
summary.retention = struct( ...
    'max_complete_ss_per_sign', double(section_cfg.max_complete_ss_per_sign), ...
    'selection_rule', ...
    'longest_then_pixel_count_then_component_id_nonoverlapping_bbox', ...
    'bbox_overlap_definition', 'shared_grid_pixel');
summary.compatibility = struct( ...
    'catalog_rows_8', height(catalog8), ...
    'catalog_rows_4', height(catalog4), ...
    'complete_vlsm_8', nnz(catalog8.IsVLSM & ~catalog8.IsCensored), ...
    'complete_vlsm_4', nnz(catalog4.IsVLSM & ~catalog4.IsCensored), ...
    'figure_manifest_rows', height(figure_manifest), ...
    'figure_generated_rows', nnz(logical_column(figure_manifest,'Generated')),...
    'figure_connectivity', double(section_cfg.figure_connectivity), ...
    'figure_length_tier_semantics', 'highest_passed_threshold_only', ...
    'plot_colormap', char(section_cfg.plot_colormap), ...
    'plot_normalization', char(section_cfg.plot_normalization), ...
    'source_mode', char(section_cfg.source_mode), ...
    'streamwise_edge_exclusion_enabled', logical(edge_config.enabled), ...
    'streamwise_edge_buffer_cells', double(edge_config.buffer_cells), ...
    'spatial_exclusion_enabled', logical(ctx_field(summary, ...
    {'spatial_exclusion','enabled'}, false)), ...
    'case_script', cfg.script_file);
end

function counts = edge_retention_counts(catalog8, catalog4)
threshold_fields = {'PassLength3','PassLength3p8','PassLength4p5'};
thresholds = [3 3.8 4.5];
counts = repmat(struct('connectivity',0,'length_threshold',0, ...
    'rejected_by_streamwise_edge',0,'suppressed_by_bbox_overlap',0, ...
    'frames_with_multiple_complete_ss',0), 6, 1);
slot = 0;
for item = {catalog8, catalog4}
    T = item{1};
    if isempty(T)
        connectivity = NaN;
    else
        connectivity = double(T.Connectivity(1));
    end
    for k = 1:numel(thresholds)
        slot = slot + 1;
        valid_geometry = T.PassWallLower & T.PassWallUpper & ~T.IsCensored;
        counts(slot).connectivity = connectivity;
        counts(slot).length_threshold = thresholds(k);
        counts(slot).rejected_by_streamwise_edge = nnz(valid_geometry & ...
            T.(threshold_fields{k}) & T.RejectedByStreamwiseEdge);
        counts(slot).suppressed_by_bbox_overlap = nnz(valid_geometry & ...
            T.(threshold_fields{k}) & T.SuppressedByBBoxOverlap);
        selected = valid_geometry & T.(threshold_fields{k}) & T.IsVLSM;
        counts(slot).frames_with_multiple_complete_ss = ...
            count_multiple_frame_signs(T(selected,:));
    end
end
end

function count = count_multiple_frame_signs(T)
if isempty(T)
    count = 0;
    return;
end
[~,~,group] = unique([double(T.FrameOrdinal), double(T.Sign)], 'rows');
count = nnz(accumarray(group, 1) > 1);
end

function value = ctx_field(input, path, fallback)
value = input;
for i = 1:numel(path)
    if ~isstruct(value) || ~isfield(value, path{i})
        value = fallback;
        return;
    end
    value = value.(path{i});
end
end

function value = logical_column(T, name)
if istable(T) && ismember(name, T.Properties.VariableNames)
    value = logical(T.(name));
else
    value = false(0,1);
end
end

function S = empty_spectra()
S = struct('spectra_table', table(), 'energy_table', table(), ...
    'thresholds', [3;3.8;4.5], 'row_labels', strings(0,1), ...
    'definition', 'No conditional spectrum was computed.');
end

function atomic_save_r2(filename, data, cfg, stage, inputs)
parent = fileparts(filename);
if ~isfolder(parent), mkdir(parent); end
token = char(java.util.UUID.randomUUID());
tmp = fullfile(parent, ['.section4_tmp_' token '.mat']);
cleanup = onCleanup(@() delete_if_present(tmp));
tblR2.save_result(tmp, data, cfg, stage, inputs);
[ok, msg] = movefile(tmp, filename, 'f');
if ~ok
    error('tblR2:section4_vlsm_analysis:PublishFailed', '%s', msg);
end
clear cleanup;
end

function write_compatibility_outputs(result, section_cfg, output_file)
root = section_cfg.figure_root;
if ~isfolder(root), mkdir(root); end
if section_cfg.write_catalog_csv
    d23.atomic_writetable(fullfile(root, 'catalog_8.csv'), result.catalog);
    d23.atomic_writetable(fullfile(root, 'catalog_4.csv'), result.catalog_4);
    d23.atomic_writetable(fullfile(root, 'frame_summary_8.csv'), result.frame_summary);
    d23.atomic_writetable(fullfile(root, 'frame_summary_4.csv'), result.frame_summary_4);
    d23.atomic_writetable(fullfile(root, 'frame_performance.csv'), result.frame_performance);
    if istable(result.figure_manifest)
        d23.atomic_writetable(fullfile(root, 'figure_manifest.csv'), result.figure_manifest);
    end
end
summary = result.summary;
summary.result_file = output_file;
summary.created_utc = d23.utc_now();
d23.atomic_write_text(fullfile(root, 'summary.json'), jsonencode(summary, 'PrettyPrint', true));
lines = strings(0,1);
lines(end+1) = '# r2 Section 4 POD-E50 VLSM';
lines(end+1) = '';
lines(end+1) = sprintf('- source mode: `%s`', section_cfg.source_mode);
if result.spatial_exclusion.enabled
    lines(end+1) = sprintf(['- spatial exclusion: `x=[%.6g, %.6g] mm`, ' ...
        '`y_wall=[0, %.6g] mm`; realized grid points: %d'], ...
        result.spatial_exclusion.requested_x_start_mm, ...
        result.spatial_exclusion.requested_x_end_mm, ...
        result.spatial_exclusion.requested_wall_y_height_mm, ...
        result.spatial_exclusion.excluded_grid_point_count);
    lines(end+1) = sprintf('- POD retained spatial DOF: %d -> %d; joint DOF: %d', ...
        summary.spatial_exclusion.pod_retained_spatial_count_before_exclusion, ...
        summary.spatial_exclusion.pod_retained_spatial_count, ...
        summary.spatial_exclusion.pod_joint_dof_count);
else
    lines(end+1) = '- spatial exclusion: `disabled`';
end
lines(end+1) = sprintf('- primary catalog: %d rows; 4-neighbor catalog: %d rows', ...
    height(result.catalog), height(result.catalog_4));
if summary.streamwise_edge_exclusion.enabled
    lines(end+1) = sprintf(['- streamwise edge exclusion: enabled; boxes within ' ...
        '%d cells of either FOV edge are rejected before VLSM retention'], ...
        summary.streamwise_edge_exclusion.buffer_cells);
else
    lines(end+1) = sprintf(['- streamwise edge exclusion: disabled (configured ' ...
        'buffer: %d cells)'], summary.streamwise_edge_exclusion.buffer_cells);
end
lines(end+1) = sprintf(['- individual figures: connectivity %d; one image pair ' ...
    'per complete primary VLSM; highest passed length tier only'], ...
    section_cfg.figure_connectivity);
if isfield(summary, 'detection_statistics')
    lines(end+1) = sprintf('- POD rank: %d; joint retained energy: %.8g', ...
        summary.detection_statistics.pod_selected_rank, ...
        summary.detection_statistics.pod_joint_energy_retained_fraction);
end
lines(end+1) = '';
lines(end+1) = ['| connectivity | Lx/delta | complete VLSM | user exclusion | ' ...
    'streamwise-edge rejected | bbox-overlap suppressed |'];
lines(end+1) = '|---:|---:|---:|---:|---:|---:|';
for i = 1:numel(summary.counts)
    item = summary.counts(i);
    edge = summary.streamwise_edge_exclusion.counts(i);
    lines(end+1) = sprintf('| %d | > %.1f | %d | %d | %d | %d |', ...
        item.connectivity, item.length_threshold, item.complete_ss, ...
        item.touching_user_exclusion_complete, ...
        edge.rejected_by_streamwise_edge, edge.suppressed_by_bbox_overlap);
end
lines(end+1) = sprintf('- figures generated: %d (manifest rows: %d)', ...
    nnz(logical_column(result.figure_manifest,'Generated')), ...
    height(result.figure_manifest));
lines(end+1) = '';
lines(end+1) = ['The catalog retains every connected component. IsVLSM/IsSS3 marks ' ...
    'the retained non-overlapping complete components for each frame, sign, and connectivity.'];
d23.atomic_write_text(fullfile(root, 'report.md'), strjoin(lines, newline) + newline);
end

function delete_if_present(filename)
if isfile(filename), delete(filename); end
end
