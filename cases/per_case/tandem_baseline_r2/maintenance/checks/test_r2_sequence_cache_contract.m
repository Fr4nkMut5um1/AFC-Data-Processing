% TEST_R2_SEQUENCE_CACHE_CONTRACT Tiny metadata and independent S5 entry checks.
% Usage: run('maintenance/checks/test_r2_sequence_cache_contract.m') from this project/case.
% Requires MATLAB; does not use runtests, DAT, formal data, or old expected MATs.
repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(repo_root, 'lib'), '-begin');
root = tempname; mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
cfg = struct('case_id','test/sequence_contract','case_type','baseline', ...
    'n_frames',4,'total_frames',8,'grid_size',[3 5],'fs',16, ...
    'frame_offset',2,'wall_side','top','formal_required_frames',6000, ...
    'allow_debug_snapshot',true,'transport',struct('source','raw'));
cfg.sources.raw = struct('roots',{{fullfile(root,'offline_3rd'),fullfile(root,'offline_2nd')}}, ...
    'offsets',[2 7],'ids',{{'3rd','2nd'}});
file = fullfile(root,'selected.mat');
write_fixture(file,cfg,'raw');
before = dir(file);
info = tblR2.validate_sequence_cache(file,cfg,'raw');
assert(isequal(info.size,[8 3 3]) && isequal(info.repeat_offsets,[2 7]));
assert(isequal(info.repeat_boundaries,4) && isequal(info.repeat_ids,{'3rd','2nd'}));
assert(~isfolder(cfg.sources.raw.roots{1}) && ~isfield(cfg.sources,'postproc'));
after = dir(file);
assert(before.bytes == after.bytes && before.datenum == after.datenum, ...
    'Read-only validation must not modify the cache.');

changed = cfg; changed.fs = 17;
expect_error(@() tblR2.validate_sequence_cache(file,changed,'raw'), ...
    'tblR2:input:CacheContractMismatch','cache_meta.fs');
changed = cfg; changed.sources.raw.offsets(2) = 8;
expect_error(@() tblR2.validate_sequence_cache(file,changed,'raw'), ...
    'tblR2:input:CacheContractMismatch','repeat_offsets');
changed = cfg; changed.sources.raw.roots{2} = fullfile(root,'different_2nd');
expect_error(@() tblR2.validate_sequence_cache(file,changed,'raw'), ...
    'tblR2:input:CacheContractMismatch','repeat_roots');
changed = cfg; changed.sources.raw.ids = {'2nd','3rd'};
expect_error(@() tblR2.validate_sequence_cache(file,changed,'raw'), ...
    'tblR2:input:CacheContractMismatch','repeat_ids');

% A plausible metadata total cannot hide a truncated physical U/V/mask array.
saved = load(file); shorter = saved;
shorter.U = saved.U(1:7,:,:); shorter.V = saved.V(1:7,:,:);
shorter.sampleValid = saved.sampleValid(1:7,:,:);
save(file,'-struct','shorter','-v7.3');
expect_error(@() tblR2.validate_sequence_cache(file,cfg,'raw'), ...
    'tblR2:input:InvalidCacheSize','总帧数 8');
bad = saved; bad.cache_meta.repeat_boundaries = 3;
save(file,'-struct','bad','-v7.3');
expect_error(@() tblR2.validate_sequence_cache(file,cfg,'raw'), ...
    'tblR2:input:CacheContractMismatch','repeat_boundaries');
bad = saved; bad.cache_meta.total_frames = 7;
save(file,'-struct','bad','-v7.3');
expect_error(@() tblR2.validate_sequence_cache(file,cfg,'raw'), ...
    'tblR2:input:CacheContractMismatch','total_frames');
bad = saved; bad.Y(1,1) = 0;
save(file,'-struct','bad','-v7.3');
expect_error(@() tblR2.validate_sequence_cache(file,cfg,'raw'), ...
    'tblR2:input:InvalidCacheCoordinates','Y');
bad = saved; bad.U = double(bad.U);
save(file,'-struct','bad','-v7.3');
expect_error(@() tblR2.validate_sequence_cache(file,cfg,'raw'), ...
    'tblR2:input:InvalidCacheType','single');
save(file,'-struct','saved','-v7.3');

% Entry checks stop before outputs, provenance or statistics on invalid input.
paths = struct('root',fullfile(root,'should_not_be_created'),'sequence_cache',file);
changed = cfg; changed.allow_debug_snapshot = false;
expect_error(@() tblR2.section5_run(changed,paths,'compute',false), ...
    'tblR2:section5:InsufficientFormalFrames','6000');
changed = cfg; changed.fs = 17;
expect_error(@() tblR2.section5_run(changed,paths,'compute',false), ...
    'tblR2:input:CacheContractMismatch','cache_meta.fs');
missing = paths; missing.sequence_cache = fullfile(root,'absent.mat');
expect_error(@() tblR2.section5_run(cfg,missing,'compute',false), ...
    'tblR2:section5:MissingCache','absent.mat');
assert(~isfolder(paths.root),'Rejected entries must not create output folders.');

% PostProc-only validation must not look for raw or DAT on disk.
post_cfg = cfg; post_cfg.sources = struct('postproc',cfg.sources.raw);
post_cfg.transport.source = 'postproc';
write_fixture(file,post_cfg,'postproc');
post_info = tblR2.validate_sequence_cache(file,post_cfg,'postproc');
assert(strcmp(post_info.source_role,'postproc'));
post_paths = struct('root',paths.root,'sequence_cache_postproc',file);
changed = post_cfg; changed.fs = 17;
expect_error(@() tblR2.section5_run(changed,post_paths,'compute',false), ...
    'tblR2:input:CacheContractMismatch','cache_meta.fs');
assert(~isfolder(paths.root));
post_cfg.sources.raw = post_cfg.sources.postproc;
expect_error(@() tblR2.validate_sequence_cache(file,post_cfg,'raw'), ...
    'tblR2:input:CacheSourceRoleMismatch','source_role');
fprintf('test_r2_sequence_cache_contract: PASS\n');

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
