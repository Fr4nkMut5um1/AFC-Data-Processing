% TEST_R2_SECTION4_REUSE_CONTRACT Tiny candidate-run metadata; no POD/detection.
% MATLAB: run('tests/test_r2_section4_reuse_contract.m') from project root.
repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repo_root, 'lib'), '-begin');
root = tempname; mkdir(root); cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
cfg = d23.default_config(root); cfg.output.root = fullfile(root,'runs'); mkdir(cfg.output.root);
cfg.data.expected_cache_size = [8 3 3]; cfg.statistics.frame_ordinals = (1:8)';
cfg.execution.frame_ordinals = (1:8)'; cfg.preprocessing.pod.enabled = false;
cfg.Uinf = 25; cfg.plot_normalization = 'u_over_Uinf';
cfg.section4_max_figure_objects = Inf; cfg.section4_figure_connectivity = 8;
ctx = struct('cache_meta',struct('fs',16,'repeat_offsets',[2 7], ...
    'repeat_roots',{{'offline_3rd','offline_2nd'}},'repeat_boundaries',4), ...
    'cache_size',[8 3 3],'frame_ids',(1:8)','X_mm',ones(3),'Y_mm',ones(3), ...
    'wall_distance_mm',ones(3),'u_tau_m_s',1,'cache_source',struct('path','local_cache'), ...
    'utau_source',struct('path','local_bl','loaded_utc','earlier'), ...
    'source_fingerprint','tiny-source-metadata');
first = fullfile(cfg.output.root,'A_complete'); write_candidate(first,cfg,ctx,'COMPLETE');
choice = tblR2.select_section4_run(cfg,ctx,true);
assert(choice.reused && strcmp(choice.run_dir,first));
changed = cfg; changed.output.figure_dpi = 300; changed.plot_normalization = 'u_over_urms_y';
changed.section4_max_figure_objects = 1; changed.section4_figure_connectivity = 4;
choice = tblR2.select_section4_run(changed,ctx,true);
assert(choice.reused && strcmp(choice.run_dir,first));
assert(strcmp(d23.config_hash(choice.compute_config),d23.config_hash(cfg)), ...
    'Plot changes must preserve the actual POD/checkpoint configuration hash.');
newctx = ctx; newctx.utau_source.loaded_utc = 'later';
assert(tblR2.select_section4_run(cfg,newctx,true).reused);
changed = cfg; changed.detection.length_thresholds(2) = 4;
expect_error(@() tblR2.select_section4_run(changed,ctx,true),'tblR2:section4:NoCompatibleRun','length_thresholds');
changed = cfg; changed.detection.connectivities = 8;
expect_error(@() tblR2.select_section4_run(changed,ctx,true),'tblR2:section4:NoCompatibleRun','connectivities');
changed = cfg; changed.preprocessing.spatial_exclusion.enabled = true;
expect_error(@() tblR2.select_section4_run(changed,ctx,true),'tblR2:section4:NoCompatibleRun','spatial_exclusion');
changedctx = ctx; changedctx.cache_meta.repeat_offsets(2) = 8;
expect_error(@() tblR2.select_section4_run(cfg,changedctx,true),'tblR2:section4:NoCompatibleRun','repeat_offsets');
changedctx = ctx; changedctx.source_fingerprint = 'different_source';
expect_error(@() tblR2.select_section4_run(cfg,changedctx,true),'tblR2:section4:NoCompatibleRun','source_fingerprint');
% Explicit incomplete resume wins even when a completed equivalent run exists.
second = fullfile(cfg.output.root,'B_explicit'); write_candidate(second,cfg,ctx,'FAILED');
changed = cfg; changed.output.resume_run_dir = second; changed.output.figure_dpi = 300;
choice = tblR2.select_section4_run(changed,ctx,true);
assert(strcmp(choice.run_dir,second) && ~choice.reused);
[actual, ~] = d23.initialize_run(choice.compute_config,ctx);
assert(strcmp(actual,second),'The original d23 resume validator must use this exact run.');
changed.detection.length_thresholds(1) = 3.1;
expect_error(@() tblR2.select_section4_run(changed,ctx,true),'tblR2:section4:RunMismatch','length_thresholds');
% Missing identity must not be retroactively signed or trigger a new run.
delete(fullfile(first,'r2_reuse_contract.mat'));
changed = cfg; changed.output.resume_run_dir = first;
expect_error(@() tblR2.select_section4_run(changed,ctx,true),'tblR2:section4:MissingIdentity','r2_reuse_contract');
assert(~isfile(fullfile(first,'r2_reuse_contract.mat')));
fprintf('test_r2_section4_reuse_contract passed (metadata only).\n');

function write_candidate(run_dir,cfg,ctx,state)
mkdir(run_dir); mkdir(fullfile(run_dir,'mat'));
contract = tblR2.section4_run_contract(cfg,ctx); compute_config = cfg;
save(fullfile(run_dir,'r2_reuse_contract.mat'),'contract','compute_config');
manifest = struct('state',state,'case_id',cfg.case_id,'config_hash',d23.config_hash(cfg), ...
    'source_fingerprint',ctx.source_fingerprint,'ordered_frame_ordinals',cfg.execution.frame_ordinals);
save(fullfile(run_dir,'manifest.mat'),'manifest');
if strcmp(state,'COMPLETE')
    context = ctx; statistics = struct(); detection_statistics = struct('pod_selected_rank',0);
    catalog_index = table(); frame_summary = table();
    frame_performance = table(cfg.execution.frame_ordinals,'VariableNames',{'FrameOrdinal'});
    noss_pairs = table(); conditional_spectra = struct(); connectivity_comparison = struct(); config = cfg;
    save(fullfile(run_dir,'mat','final_results.mat'),'context','statistics','detection_statistics', ...
        'catalog_index','frame_summary','frame_performance','noss_pairs','conditional_spectra', ...
        'connectivity_comparison','config');
end
end

function expect_error(action,id,fragment)
try; action(); catch problem
    assert(strcmp(problem.identifier,id),'Expected %s, received %s: %s',id,problem.identifier,problem.message);
    assert(contains(problem.message,fragment),'Expected field: %s',fragment); return;
end
error('test:ExpectedFailure','Expected %s.',id);
end
