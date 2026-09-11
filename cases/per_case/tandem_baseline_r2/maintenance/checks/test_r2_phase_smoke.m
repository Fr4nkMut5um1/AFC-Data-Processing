% TEST_R2_PHASE_SMOKE 检查 r2 相位阶段的受控分支和三重分解合同。
repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
library_root = fullfile(repo_root, 'lib');
addpath(library_root, '-begin');

root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>

I = 5;
J = 4;
n_frames = 32;
fs = 128;
f0_hz = 8;
n_bins = 16;
t = (0:n_frames - 1)';
[xx, yy] = meshgrid(1:I, 1:J);
U = zeros(n_frames, J, I, 'single');
V = zeros(n_frames, J, I, 'single');
for k = 1:n_frames
    U(k, :, :) = single(10 + 0.4 * sin(2 * pi * (k - 1) / n_bins) .* ...
        (1 + 0.1 * xx) + 0.03 * cos(0.2 * k + yy));
    V(k, :, :) = single(0.2 * cos(2 * pi * (k - 1) / n_bins) .* ...
        (1 + 0.05 * yy) + 0.02 * sin(0.3 * k + xx));
end
sampleValid = true(n_frames, J, I);
X = repmat(1:I, J, 1);
Y = repmat((1:J)', 1, I);
h_mm = 1;
cache_meta = struct('repeat_boundaries', n_frames / 2);
cache_file = fullfile(root, 'phase_cache.mat');
save(cache_file, 'U', 'V', 'sampleValid', 'X', 'Y', 'h_mm', ...
    'cache_meta', '-v7.3');

stats = struct();
stats.Uavex = squeeze(mean(double(U), 1));
stats.Vavex = squeeze(mean(double(V), 1));
stats.X = X;
stats.Y = Y;
stats.h = h_mm;

cfg = struct('case_type', 'controlled', 'fs', fs, 'chunk_frames', 3, ...
    'Uinf', 25, 'phase', struct('enabled', true, 'f0_hz', f0_hz, ...
    'n_bins', n_bins, 'phi0_user_deg', [], ...
    'minimum_samples_per_bin', 1));
phase = tblR2.phase_stats_cache(cache_file, cfg, stats);

assert(isequal(size(phase.U_phase), [n_bins J I]));
assert(isfield(phase, 'random_u_rms_phase') && ...
    isfield(phase, 'random_v_rms_phase'));
assert(isfield(phase, 'U_phase_rep') && size(phase.U_phase_rep, 1) == 2);
assert(phase.triple_reconstruction_max_abs_mps < 1e-10);
assert(strcmp(phase.assignment.assignment_mode, 'exact_frame_clock'));
cfg.case_id = 'test/r2/phase';
cfg.data_root = root;
cfg.n_frames = n_frames / 2;
cfg.total_frames = n_frames;
cfg.grid_size = [I J];
% Publication-only synthetic identities for the stricter S2/S3 MAT contract.
% The preceding phase arrays/formulas/assertions are unchanged; this fixture
% metadata is not a formal result or a migration of an old production MAT.
cfg.statistics_source = 'raw'; cfg.statistics_frame_mode = 'all';
cfg.wall_side = 'top'; cfg.frame_offset = 0; cfg.min_valid_fraction = 0.7;
cfg.sources.raw = struct('roots',{{fullfile(root,'fixture_3rd'),fullfile(root,'fixture_2nd')}}, ...
    'offsets',[0 0],'ids',{{'3rd','2nd'}});
spec = cfg.sources.raw;
source_grid_size = cfg.grid_size; j_wall_removed = 0; frame_ids = (1:n_frames)';
cache_meta = struct('schema_version',4,'case_id',cfg.case_id, ...
    'data_root',spec.roots{1},'source_root',spec.roots{1},'source_role','raw', ...
    'repeat_roots',{spec.roots},'repeat_ids',{spec.ids},'repeat_offsets',spec.offsets, ...
    'repeat_boundaries',cfg.n_frames,'repeat_means',zeros(2,2,J,I), ...
    'grid_size',cfg.grid_size,'cached_size',[n_frames J I], ...
    'n_frames',cfg.n_frames,'total_frames',n_frames,'fs',fs,'frame_offset',0, ...
    'source_first_file','B0001.dat','source_last_file',sprintf('B%04d.dat',cfg.n_frames), ...
    'wall_side','top','precision','single', ...
    'y_mapping',struct('version',1,'method','first_retained_row_0_plus_h','h_y_mm',1));
for repeat = 1:2
    ids = (repeat-1)*cfg.n_frames+(1:cfg.n_frames);
    cache_meta.repeat_means(1,repeat,:,:) = mean(double(U(ids,:,:)),1);
    cache_meta.repeat_means(2,repeat,:,:) = mean(double(V(ids,:,:)),1);
end
save(cache_file,'cache_meta','source_grid_size','j_wall_removed','frame_ids','-append');
statistics_file = fullfile(root,'synthetic_parent_statistics.mat');
tblR2.save_result(statistics_file,stats,cfg,'statistics',struct('cache',cache_file));
phase_inputs = struct('cache',cache_file,'statistics',statistics_file);
phase_file = fullfile(root, 'phase_result.mat');
tblR2.save_result(phase_file, phase, cfg, 'phase', phase_inputs);
loaded = tblR2.load_result(phase_file, cfg, 'phase', phase_inputs);
assert(max(abs(loaded.U_phase(:) - phase.U_phase(:)), [], 'omitnan') < 1e-12);

% 额外覆盖末尾 singleton 网格：matfile 会压缩末尾维度，读取辅助必须恢复形状。
small_root = fullfile(root, 'singleton');
mkdir(small_root);
small_n = 16;
small_U = single(reshape(1:small_n, [small_n 1 1]));
small_V = single(2 * small_U);
small_valid = true(small_n, 1, 1);
small_X = 1;
small_Y = 1;
small_h = 1;
small_meta = struct('repeat_boundaries', 8);
small_file = fullfile(small_root, 'cache.mat');
U = small_U; V = small_V; sampleValid = small_valid;
X = small_X; Y = small_Y; h_mm = small_h; cache_meta = small_meta;
save(small_file, 'U', 'V', 'sampleValid', 'X', 'Y', 'h_mm', ...
    'cache_meta', '-v7.3');
small_cfg = cfg;
small_cfg.fs = 16;
small_cfg.chunk_frames = 1;
small_cfg.phase.f0_hz = 2;
small_cfg.phase.n_bins = 8;
small_stats = struct('Uavex', mean(double(U), 1), ...
    'Vavex', mean(double(V), 1));
small_phase = tblR2.phase_stats_cache(small_file, small_cfg, small_stats);
assert(size(small_phase.U_phase, 1) == 8 && ...
    size(small_phase.U_phase, 2) == 1 && numel(small_phase.U_phase) == 8);
assert(small_phase.triple_reconstruction_max_abs_mps < 1e-10);
small_chunk = tblR2.read_cache_chunk(small_file, [1; 3; 9], 1, 1, ...
    'random', small_stats, small_phase);
assert(size(small_chunk.U, 1) == 3 && ...
    size(small_chunk.U, 2) == 1 && numel(small_chunk.U) == 3);
fprintf('test_r2_phase_smoke: PASS\n');
