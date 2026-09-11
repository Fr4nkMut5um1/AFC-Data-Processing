% TEST_R2_RESULT_REUSE_CONTRACT S2/S3 metadata/parent tests, no scientific recomputation.
% MATLAB: run('maintenance/checks/test_r2_result_reuse_contract.m') from project root.
repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(repo_root, 'lib'), '-begin');
root = tempname; mkdir(root); cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
cfg = struct('case_id','test/contracts','case_type','controlled','fs',16, ...
    'n_frames',4,'total_frames',8,'grid_size',[3 5],'wall_side','top', ...
    'frame_offset',2,'min_valid_fraction',0.7,'chunk_frames',4,'Uinf',25, ...
    'statistics_source','raw','statistics_frame_mode','all','data_root',root);
cfg.sources.raw = struct('roots',{{fullfile(root,'offline_3rd'),fullfile(root,'offline_2nd')}}, ...
    'offsets',[2 7],'ids',{{'3rd','2nd'}});
cfg.sources.postproc = cfg.sources.raw;
cfg.profile = struct('mode','range_avg','params',[80 180]);
cfg.loglaw = struct('params',struct('dy_h',1));
cfg.phase = struct('enabled',true,'f0_hz',4,'n_bins',2,'phi0_user_deg',0,'min_samples',2);
cache_file = fullfile(root,'cache.mat'); write_fixture(cache_file,cfg,'raw');
stats_file = fullfile(root,'stats.mat'); bl_file = fullfile(root,'bl.mat'); phase_file = fullfile(root,'phase.mat');
stats_inputs = struct('cache',cache_file); bl_inputs = struct('statistics',stats_file);
phase_inputs = struct('cache',cache_file,'statistics',stats_file);
data = struct('test_value',[1 NaN 3]);
tblR2.save_result(stats_file,data,cfg,'statistics',stats_inputs);
assert(isequaln(data,tblR2.load_result(stats_file,cfg,'statistics',stats_inputs)));
tblR2.save_result(bl_file,data,cfg,'mean_bl',bl_inputs);
tblR2.save_result(phase_file,data,cfg,'phase',phase_inputs);
assert(isequaln(data,tblR2.load_result(phase_file,cfg,'phase',phase_inputs)));
changed = cfg; changed.preview.enabled = true; changed.figures.export_dpi = 99;
assert(isequaln(data,tblR2.load_result(bl_file,changed,'mean_bl',bl_inputs)));
changed = cfg; changed.profile.params = [240 320];
expect_error(@() tblR2.load_result(bl_file,changed,'mean_bl',bl_inputs), ...
    'tblR2:load_result:ContractMismatch','profile.params');
changed = cfg; changed.sources.raw.offsets(2) = 8;
expect_error(@() tblR2.load_result(stats_file,changed,'statistics',stats_inputs), ...
    'tblR2:load_result:ContractMismatch','offsets');
changed = cfg; changed.statistics_source = 'postproc';
expect_error(@() tblR2.load_result(stats_file,changed,'statistics',stats_inputs), ...
    'tblR2:load_result:ContractMismatch','statistics_source');
changed = cfg; changed.phase.phi0_user_deg = 15;
expect_error(@() tblR2.load_result(phase_file,changed,'phase',phase_inputs), ...
    'tblR2:load_result:ContractMismatch','phi0_user_deg');
% The current cache must still pass fs and actual frame-count validation.
saved_cache = load(cache_file); bad = saved_cache; bad.cache_meta.fs = 99;
save(cache_file,'-struct','bad','-v7.3');
expect_error(@() tblR2.load_result(stats_file,cfg,'statistics',stats_inputs), ...
    'tblR2:input:CacheContractMismatch','cache_meta.fs');
bad = saved_cache; bad.U = bad.U(1:7,:,:);
save(cache_file,'-struct','bad','-v7.3');
expect_error(@() tblR2.load_result(stats_file,cfg,'statistics',stats_inputs), ...
    'tblR2:input:InvalidCacheSize','总帧数 8');
save(cache_file,'-struct','saved_cache','-v7.3');
% New production of a parent receives a new identity even for equal arrays.
tblR2.save_result(stats_file,data,cfg,'statistics',stats_inputs);
expect_error(@() tblR2.load_result(bl_file,cfg,'mean_bl',bl_inputs), ...
    'tblR2:load_result:ParentMismatch','result_id');
% Offline frozen BL input remains usable with recorded producer identity; S4
% must not require its old raw cache or statistics file online.
delete(cache_file); delete(stats_file);
assert(isequaln(data,tblR2.load_result(bl_file,cfg,'mean_bl')));
old = load(bl_file); old.meta = rmfield(old.meta,{'contract','parents','result_id'});
save(bl_file,'-struct','old','-v7.3');
expect_error(@() tblR2.load_result(bl_file,cfg,'mean_bl'), ...
    'tblR2:load_result:MissingProducerIdentity','lacks');
fprintf('test_r2_result_reuse_contract passed (metadata only).\n');

function write_fixture(file,cfg,source)
[X,Y] = meshgrid([0 2 4],1:3); J = size(Y,1); I = size(Y,2);
U = single(reshape(1:cfg.total_frames,[],1,1) + reshape(Y,1,J,I));
V = -U; sampleValid = true(size(U));
h_mm = 2; frame_ids = (1:cfg.total_frames)';
source_grid_size = cfg.grid_size; j_wall_removed = 2;
spec = cfg.sources.(source);
cache_meta = struct('schema_version',4,'case_id',cfg.case_id, ...
    'data_root',spec.roots{1},'source_root',spec.roots{1},'source_role',source, ...
    'repeat_roots',{spec.roots},'repeat_ids',{spec.ids},'repeat_offsets',spec.offsets, ...
    'repeat_boundaries',cfg.n_frames,'repeat_means',zeros(2,2,J,I), ...
    'grid_size',cfg.grid_size,'cached_size',[cfg.total_frames J I], ...
    'n_frames',cfg.n_frames,'total_frames',cfg.total_frames,'fs',cfg.fs, ...
    'frame_offset',spec.offsets(1), ...
    'source_first_file',sprintf('B%04d.dat',spec.offsets(1)+1), ...
    'source_last_file',sprintf('B%04d.dat',spec.offsets(1)+cfg.n_frames), ...
    'wall_side',cfg.wall_side,'precision','single', ...
    'y_mapping',struct('version',1,'method','first_retained_row_0_plus_h','h_y_mm',1));
save(file,'U','V','sampleValid','X','Y','h_mm','frame_ids','source_grid_size', ...
    'j_wall_removed','cache_meta','-v7.3');
end

function expect_error(action,id,fragment)
try
    action();
catch ME
    assert(strcmp(ME.identifier,id),'Expected %s, received %s: %s',id,ME.identifier,ME.message);
    assert(contains(ME.message,fragment),'Expected field/path in error: %s',fragment);
    return;
end
error('test:MissingExpectedError','Expected %s.',id);
end
