function contract = section4_run_contract(cfg, ctx)
%SECTION4_RUN_CONTRACT Effective compute parameters and full input identities.
% Presentation/output controls do not require POD or detection recomputation.
parameters = cfg;
remove = {'output','repo_root','plot_normalization', ...
    'section4_max_figure_objects','section4_figure_connectivity'};
for k = 1:numel(remove)
    if isfield(parameters, remove{k}); parameters = rmfield(parameters, remove{k}); end
end
remove = {'label','make_gallery','make_figures','progress_every_batches'};
for k = 1:numel(remove)
    if isfield(parameters.execution, remove{k})
        parameters.execution = rmfield(parameters.execution, remove{k});
    end
end
required = {'cache_meta','cache_size','frame_ids','X_mm','Y_mm', ...
    'wall_distance_mm','u_tau_m_s','cache_source','utau_source','source_fingerprint'};
if ~all(isfield(ctx, required))
    error('tblR2:section4:MissingIdentity', 'S4 context lacks full source/grid/mean_bl identity.');
end
identity = struct();
for k = 1:numel(required); identity.(required{k}) = ctx.(required{k}); end
if isfield(identity.utau_source, 'loaded_utc')
    identity.utau_source = rmfield(identity.utau_source, 'loaded_utc');
end
% Hash computational d23 sources; actual plotting files are deliberately absent.
algorithms = {'apply_gaussian','build_pod_cache','compute_statistics', ...
    'conditional_spectra','connectivity_comparison','delta99_from_profile', ...
    'empty_catalog','empty_frame_summary','empty_pairs','finalize_context', ...
    'fluctuation_chunk','identify_frame','load_utau','match_noss', ...
    'prepare_detection_statistics','prepare_source','read_chunk', ...
    'resolve_spatial_exclusion','retain_nonoverlapping_complete_ss', ...
    'retain_one_complete_ss','run_detection','select_pod_rank', ...
    'spatial_active_mask','spatial_periodogram','summarize_frame'};
implementation = struct('file', {}, 'sha256', {});
root = fullfile(fileparts(fileparts(mfilename('fullpath'))), '+d23');
for k = 1:numel(algorithms)
    implementation(k) = struct('file', [algorithms{k} '.m'], ...
        'sha256', d23.sha256_text(fileread(fullfile(root, [algorithms{k} '.m']))));
end
contract = struct('schema_version', 1, 'parameters', parameters, ...
    'source', identity, 'implementation', implementation);
end
