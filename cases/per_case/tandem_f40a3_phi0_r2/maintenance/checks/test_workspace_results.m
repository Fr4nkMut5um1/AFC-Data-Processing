function test_workspace_results()
%TEST_WORKSPACE_RESULTS Tiny workspace lifecycle test; no PIV/POD calculation.
% Call form: addpath('<this case>/lib'); addpath('<this case>/maintenance/checks'); test_workspace_results
% Requires MATLAB. This test does not validate Editor Run Section behavior.
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
cfg = struct('case_id','case_B','script_file',fullfile(root,'case_B.m'), ...
    'output_dir',fullfile(root,'output'),'case_type','baseline','fs',960, ...
    'n_frames',6000,'total_frames',12000,'grid_size',[640 91], ...
    'wall_side','top','formal_required_frames',6000,'allow_debug_snapshot',false, ...
    'frame_offset',0,'chunk_frames',48,'min_valid_fraction',0.7,'Uinf',25, ...
    'statistics_source','raw','statistics_frame_mode','all','nu',1.48e-5, ...
    'rho',1.2,'x_max',328,'profile',struct('params',[80 180]), ...
    'figures',struct('export_dpi',200));
spec = struct('roots',{{fullfile(root,'3rd'),fullfile(root,'2nd')}}, ...
    'offsets',[7 9],'ids',[3 2]);
cfg.sources = struct('raw',spec,'postproc',spec);
cfg.transport = struct('source','raw');
cfg.section4 = struct('spatial_exclusion',struct('enabled',false), ...
    'length_thresholds',[3 3.8 4.5],'pod',struct('rank',struct('kind','energy_fraction','value',0.5)));
r = tblR2.workspace_results('init', [], cfg);
r.statistics = struct('sentinel',42);
r = tblR2.workspace_results('record', r, cfg, {'statistics'}, 'compute');
assert(isequaln(tblR2.workspace_results('init', r, cfg), r));
tblR2.workspace_results('require', r, cfg, {'statistics'});
changed = cfg; changed.figures.export_dpi = 400;
tblR2.workspace_results('require', r, changed, {'statistics'}); % Display-only change.
changed = cfg; changed.sources.raw.offsets(2) = 10;
assert_error(@() tblR2.workspace_results('require', r, changed, {'statistics'}), ...
    'tblR2:workspace:StaleParameters');
changed = cfg; changed.fs = 961;
assert_error(@() tblR2.workspace_results('require', r, changed, {'statistics'}), ...
    'tblR2:workspace:StaleParameters');
r.mean_bl = struct('sentinel',17);
r = tblR2.workspace_results('record', r, cfg, {'mean_bl'}, 'compute');
changed = cfg; changed.profile.params = [90 180];
assert_error(@() tblR2.workspace_results('require', r, changed, {'mean_bl'}), ...
    'tblR2:workspace:StaleParameters');
r2 = tblR2.workspace_results('record', r, cfg, {'statistics'}, 'compute');
assert_error(@() tblR2.workspace_results('require', r2, cfg, {'mean_bl'}), ...
    'tblR2:workspace:ChangedParent');
r.structures = struct('sentinel',29);
r = tblR2.workspace_results('record', r, cfg, {'structures'}, 'compute');
changed = cfg; changed.section4.spatial_exclusion.enabled = true;
assert_error(@() tblR2.workspace_results('require', r, changed, {'structures'}), ...
    'tblR2:workspace:StaleParameters');
changed = cfg; changed.section4.pod.rank.value = 0.6;
assert_error(@() tblR2.workspace_results('require', r, changed, {'structures'}), ...
    'tblR2:workspace:StaleParameters');
forgotten = tblR2.workspace_results('forget', r, cfg, {'statistics'});
assert_error(@() tblR2.workspace_results('require', forgotten, cfg, {'statistics'}), ...
    'tblR2:workspace:MissingResult');
% Creating/replacing an input file after a record invalidates that record.
mkdir(fullfile(cfg.output_dir,'mat'));
sentinel = 1; %#ok<NASGU>
save(fullfile(cfg.output_dir,'mat','01_sequence_cache.mat'),'sentinel');
assert_error(@() tblR2.workspace_results('require', r, cfg, {'statistics'}), ...
    'tblR2:workspace:ChangedFile');
assert_error(@() tblR2.workspace_results('require', r, cfg, {}, '', ...
    fullfile(root,'copied','case_B.m')), 'tblR2:workspace:WrongScript');
other = cfg; other.case_id = 'case_C'; other.script_file = fullfile(root,'case_C.m');
switched = tblR2.workspace_results('init', r, other);
assert(isempty(switched.statistics));
assert_error(@() tblR2.workspace_results('require', r, other, {}), ...
    'tblR2:workspace:WrongOwner');
assert_error(@() tblR2.workspace_results('init', struct('statistics',1), cfg), ...
    'tblR2:workspace:UnknownOwner');
fprintf('test_workspace_results: PASS (workspace metadata only).\n');
end

function assert_error(action, identifier)
try
    action();
catch problem
    assert(strcmp(problem.identifier, identifier), ...
        'Expected %s; received %s: %s', identifier, problem.identifier, problem.message);
    return;
end
error('test_workspace_results:ExpectedError', 'Expected %s.', identifier);
end
