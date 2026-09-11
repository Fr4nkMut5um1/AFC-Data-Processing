function result = run_experiment(cfg)
%RUN_EXPERIMENT End-to-end isolated experiment orchestration.
% Normalize JSON-round-tripped contract vectors before validation.  MATLAB's
% jsondecode returns JSON arrays as columns, while several low-level loops
% intentionally iterate over row vectors (notably the [8 4] connectivity
% contract).  This normalization preserves the JSON/hash representation but
% prevents a decoded config from changing loop semantics on resume.
if isfield(cfg, 'data')
    if isfield(cfg.data, 'expected_cache_size')
        cfg.data.expected_cache_size = double(cfg.data.expected_cache_size(:).');
    end
    if isfield(cfg.data, 'reference_x_mm')
        cfg.data.reference_x_mm = double(cfg.data.reference_x_mm(:).');
    end
end
if isfield(cfg, 'detection')
    if isfield(cfg.detection, 'connectivities')
        cfg.detection.connectivities = double(cfg.detection.connectivities(:).');
    end
    if isfield(cfg.detection, 'length_thresholds')
        cfg.detection.length_thresholds = double(cfg.detection.length_thresholds(:).');
    end
end
if isfield(cfg, 'output') && isfield(cfg.output, 'field_clim')
    cfg.output.field_clim = double(cfg.output.field_clim(:).');
end
d23.validate_config(cfg);
ctx = d23.prepare_source(cfg);
is_full_run = strcmpi(cfg.execution.label, 'full') || ...
    endsWith(lower(string(cfg.execution.label)), "_full");
if is_full_run && ...
        ~isequal(double(cfg.execution.frame_ordinals(:)), (1:ctx.cache_size(1)).')
    error('d23:run_experiment:FullFrameContract', ...
        'The formal full run must process all 12,000 frames in source order.');
end
[run_dir, manifest] = d23.initialize_run(cfg, ctx);
manifest = d23.update_manifest_state(run_dir, manifest, 'RUNNING', struct( ...
    'message', 'global statistics and detection in progress'));
try
    stats = d23.compute_statistics(ctx, cfg, run_dir);
    ctx = d23.finalize_context(ctx, stats, cfg);
    d23.atomic_save(fullfile(run_dir, 'mat', 'context.mat'), ...
        struct('context', ctx, 'statistics', stats));
    pod_file = d23.build_pod_cache(ctx, stats, cfg, run_dir);
    detection_stats = d23.prepare_detection_statistics( ...
        ctx, stats, cfg, run_dir, pod_file);
    detection = d23.run_detection( ...
        ctx, stats, detection_stats, cfg, run_dir, pod_file);
    collected = d23.collect_detection(detection, run_dir);
    connectivity = d23.connectivity_comparison( ...
        collected.ss_catalog, ctx, cfg);
    pairs = d23.match_noss(collected.ss_catalog, ctx, cfg);
    spectra = d23.conditional_spectra(pairs, ctx, stats, cfg, pod_file);
    selection = d23.select_gallery(collected.ss_catalog, ctx.cache_size(1));
    if cfg.execution.make_figures
        figure_files = d23.plot_summary(ctx, stats, detection_stats, ...
            collected, connectivity, spectra, cfg, run_dir);
    else
        figure_files = strings(0,1);
    end
    gallery_files = d23.create_gallery(selection, collected.ss_catalog, ...
        ctx, stats, detection_stats, cfg, run_dir, pod_file);
    summary = d23.build_summary(ctx, detection_stats, collected, ...
        connectivity, pairs, spectra, cfg);
    d23.write_outputs(ctx, stats, detection_stats, collected, connectivity, ...
        pairs, spectra, selection, summary, cfg, run_dir, ...
        figure_files, gallery_files);
    manifest = d23.update_manifest_state(run_dir, manifest, 'COMPLETE', struct( ...
        'completed_utc', d23.utc_now(), ...
        'final_results', fullfile(run_dir, 'mat', 'final_results.mat')));
    result = struct('run_dir', run_dir, 'manifest', manifest, ...
        'summary', summary, 'summary_figure_files', figure_files, ...
        'gallery_files', gallery_files, ...
        'report_file', fullfile(run_dir, 'md', 'report.md'), ...
        'final_mat_file', fullfile(run_dir, 'mat', 'final_results.mat'));
catch problem
    detail = struct('identifier', problem.identifier, 'message', problem.message, ...
        'failed_utc', d23.utc_now());
    d23.update_manifest_state(run_dir, manifest, 'FAILED', detail);
    rethrow(problem);
end
end
