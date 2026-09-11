function choice = select_section4_run(cfg, ctx, reuse_existing)
%SELECT_SECTION4_RUN Read-only selection; explicit resume always has priority.
% Does not create a run, alter old metadata, or compute any scientific arrays.
choice = struct('run_dir', '', 'reused', false, 'loaded', struct(), ...
    'compute_config', cfg, 'manifest', struct());
expected = tblR2.section4_run_contract(cfg, ctx);
if ~isempty(cfg.output.resume_run_dir)
    candidate = char(cfg.output.resume_run_dir);
    check_local(candidate, cfg.output.root);
    choice = inspect(candidate, cfg, expected, true);
    fprintf('[Section 4] explicit resume selected: %s; full compute/source contract matched.\n', candidate);
    return;
end
if ~reuse_existing || ~isfolder(cfg.output.root); return; end
listing = dir(cfg.output.root);
[~, order] = sort([listing.datenum], 'descend');
problems = {};
for k = order
    item = listing(k);
    if ~item.isdir || startsWith(item.name, '.'); continue; end
    candidate = fullfile(cfg.output.root, item.name);
    check_local(candidate, cfg.output.root);
    filename = fullfile(candidate, 'manifest.mat');
    if ~isfile(filename); continue; end
    saved = load(filename, 'manifest');
    if ~isfield(saved, 'manifest') || ~isfield(saved.manifest, 'case_id')
        problems{end+1} = [candidate ': manifest.case_id missing']; %#ok<AGROW>
        continue;
    end
    if ~strcmp(saved.manifest.case_id, cfg.case_id); continue; end
    try
        choice = inspect(candidate, cfg, expected, false);
        for j = 1:numel(problems); fprintf('[Section 4] rejected candidate: %s\n', problems{j}); end
        fprintf('[Section 4] complete run selected: %s; compute parameters, algorithms and source matched; current plot controls applied.\n', candidate);
        return;
    catch problem
        problems{end+1} = [candidate ': ' problem.message]; %#ok<AGROW>
    end
end
if ~isempty(problems)
    error('tblR2:section4:NoCompatibleRun', ...
        ['No compatible local run. No automatic 12000-frame recomputation.\n%s\n' ...
        'Read matching inputs/config; for intentional new computation explicitly set reuse_existing_run=false.'], ...
        strjoin(problems, newline));
end
end

function choice = inspect(run_dir, current, expected, allow_resume)
check_run_paths(run_dir);
file = fullfile(run_dir, 'r2_reuse_contract.mat');
if ~isfile(file)
    error('tblR2:section4:MissingIdentity', ...
        'Missing r2_reuse_contract.mat; legacy identity will not be assigned from current cfg.');
end
saved = load(file, 'contract', 'compute_config');
if ~all(isfield(saved, {'contract','compute_config'}))
    error('tblR2:section4:MissingIdentity', 'Run lacks contract/compute_config.');
end
difference = tblR2.contract_difference(saved.contract, expected, 'S4');
if ~isempty(difference)
    error('tblR2:section4:RunMismatch', '%s', difference);
end
m = load(fullfile(run_dir, 'manifest.mat'), 'manifest');
manifest = m.manifest;
if ~all(isfield(manifest, {'state','case_id','config_hash','source_fingerprint','ordered_frame_ordinals'}))
    error('tblR2:section4:MissingIdentity', 'Manifest lacks state/config/source/frame identity.');
end
if ~strcmp(manifest.config_hash, d23.config_hash(saved.compute_config)) || ...
        ~strcmp(manifest.source_fingerprint, expected.source.source_fingerprint) || ...
        ~strcmp(manifest.case_id, current.case_id) || ...
        ~isequal(double(manifest.ordered_frame_ordinals(:)), double(current.execution.frame_ordinals(:)))
    error('tblR2:section4:RunMismatch', 'manifest config_hash/source_fingerprint/case_id/ordered_frame_ordinals mismatch.');
end
complete = strcmp(manifest.state, 'COMPLETE');
if ~complete && ~allow_resume
    error('tblR2:section4:IncompleteRun', 'state=%s; explicitly select resume_run_dir to resume this run.', manifest.state);
end
loaded = struct();
if complete
    loaded = load(fullfile(run_dir, 'mat', 'final_results.mat'), ...
        'context','statistics','detection_statistics','catalog_index','frame_summary', ...
        'frame_performance','noss_pairs','conditional_spectra', ...
        'connectivity_comparison','gallery_selection','summary','config');
    required = {'context','statistics','detection_statistics','catalog_index','frame_summary', ...
        'frame_performance','noss_pairs','conditional_spectra','connectivity_comparison','config'};
    if ~all(isfield(loaded, required))
        error('tblR2:section4:IncompleteRun', 'final_results lacks required computed products.');
    end
    if ~strcmp(d23.config_hash(loaded.config), manifest.config_hash)
        error('tblR2:section4:RunMismatch', 'final_results.config does not match manifest.config_hash.');
    end
    difference = tblR2.contract_difference(saved.contract, ...
        tblR2.section4_run_contract(loaded.config, loaded.context), 'final_results');
    if ~isempty(difference); error('tblR2:section4:RunMismatch', '%s', difference); end
    perf = loaded.frame_performance;
    if ~istable(perf) || height(perf) ~= numel(current.execution.frame_ordinals) || ...
            ~ismember('FrameOrdinal', perf.Properties.VariableNames) || ...
            ~isequal(double(perf.FrameOrdinal(:)), double(current.execution.frame_ordinals(:)))
        error('tblR2:section4:RunMismatch', 'final_results.frame_performance.FrameOrdinal mismatch.');
    end
    det = loaded.detection_statistics;
    got_pod = isfield(det, 'pod_selected_rank') && det.pod_selected_rank > 0;
    if logical(current.preprocessing.pod.enabled) ~= got_pod
        error('tblR2:section4:RunMismatch', 'detection_statistics.pod_selected_rank contradicts config.');
    end
    if got_pod && strcmp(current.preprocessing.pod.rank.kind, 'energy_fraction') && ...
            (~isfield(det, 'pod_energy_target_fraction') || ...
            abs(double(det.pod_energy_target_fraction) - ...
            double(current.preprocessing.pod.rank.value)) > 1e-12)
        error('tblR2:section4:RunMismatch', 'detection_statistics.pod_energy_target_fraction mismatch.');
    end

end
compute_config = saved.compute_config;
% Keep its exact old hash for d23 POD/checkpoint contracts. Only the resume
% pointer is changed, and d23.config_hash explicitly excludes that pointer.
compute_config.output.resume_run_dir = run_dir;
choice = struct('run_dir', run_dir, 'reused', complete, 'loaded', loaded, ...
    'compute_config', compute_config, 'manifest', manifest);
end

function check_local(candidate, root)
physical = char(java.io.File(candidate).getCanonicalPath());
local = char(java.io.File(root).getCanonicalPath());
if ~startsWith(physical, [local filesep], 'IgnoreCase', ispc)
    error('tblR2:section4:OutsideCase', 'Run resolves outside this case run root: %s', candidate);
end
end

function check_run_paths(run_dir)
% Check metadata/checkpoint/POD and partition paths before any d23 resume I/O.
root = char(java.io.File(run_dir).getCanonicalPath());
folders = {'','mat','pod','checkpoints','catalog_mat','catalog_csv'};
for k = 1:numel(folders)
    folder = fullfile(run_dir, folders{k});
    if ~isfolder(folder); continue; end
    physical = char(java.io.File(folder).getCanonicalPath());
    if ~strcmp(physical, root) && ~startsWith(physical, [root filesep], 'IgnoreCase', ispc)
        error('tblR2:section4:OutsideCase', 'Run folder resolves outside selected run: %s', folder);
    end
    items = dir(fullfile(folder, '*.mat'));
    for j = 1:numel(items)
        file = fullfile(folder, items(j).name);
        physical = char(java.io.File(file).getCanonicalPath());
        if ~startsWith(physical, [root filesep], 'IgnoreCase', ispc)
            error('tblR2:section4:OutsideCase', 'Run MAT resolves outside selected run: %s', file);
        end
    end
end
end
