% TEST_R2_OFFLINE_CACHE_REUSE 验证缓存脱离原始数据盘后仍可复用。
repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
library_root = fullfile(repo_root, 'lib');
addpath(library_root, '-begin');
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>

I = 8; J = 12; n = 6;
rep1 = fullfile(root, 'Rep1');
rep2 = fullfile(root, 'Rep2');
write_dat(rep1, n, I, J, 0.0);
write_dat(rep2, n, I, J, 3.0);

cfg = struct();
cfg.case_id = 'test/r2/offline_reuse';
cfg.case_type = 'baseline';
cfg.name = 'r2 offline reuse';
cfg.script_file = mfilename('fullpath');
cfg.output_dir = fullfile(root, 'output');
cfg.data_root = rep1;
cfg.sources = struct('raw', struct('roots', {{rep1, rep2}}, ...
    'offsets', [0 0], 'ids', {{'1st','2nd'}}), ...
    'postproc', struct('roots', {{rep1, rep2}}, ...
    'offsets', [0 0], 'ids', {{'1st','2nd'}}));
cfg.grid_size = [I J];
cfg.n_frames = n;
cfg.total_frames = 2 * n;
cfg.formal_required_frames = n;
cfg.allow_debug_snapshot = true;
cfg.frame_offset = 0;
cfg.fs = 100;
cfg.Uinf = 25;
cfg.nu = 1.48e-5;
cfg.rho = 1.2;
cfg.D_mm = 30;
cfg.x_max = 7;
cfg.chunk_frames = 4;
cfg.min_valid_fraction = 0.5;
cfg.rebuild_cache = true;
cfg.wall_side = 'bottom';
cfg.stages = struct('cache','compute');
paths = tblR2.build_paths(cfg.output_dir);

raw = tblR2.prepare_sequence_cache(cfg, paths, 'raw');
post = tblR2.prepare_sequence_cache(cfg, paths, 'postproc');
raw_source_root = raw.cache_meta.source_root;
post_source_root = post.cache_meta.source_root;

% 模拟原始数据盘卸载：保留 MAT 缓存，删除两个 DAT 源目录。
rmdir(rep1, 's');
rmdir(rep2, 's');
cfg.rebuild_cache = false;
cfg.stages.cache = 'reuse';
raw_reuse = tblR2.prepare_sequence_cache(cfg, paths, 'raw');
post_reuse = tblR2.prepare_sequence_cache(cfg, paths, 'postproc');

assert(raw_reuse.reused && post_reuse.reused);
assert(strcmp(raw_reuse.cache_meta.source_root, raw_source_root));
assert(strcmp(post_reuse.cache_meta.source_root, post_source_root));
assert(isfile(raw_reuse.filename) && isfile(post_reuse.filename));
fprintf('test_r2_offline_cache_reuse: PASS\n');

function write_dat(root, n, I, J, bias)
mkdir(root);
for frame = 1:n
    fid = fopen(fullfile(root, sprintf('B%04d.dat', frame)), 'w');
    fprintf(fid, 'TITLE = "synthetic"\n');
    fprintf(fid, 'VARIABLES = "x", "y", "u", "v", "isValid"\n');
    fprintf(fid, 'ZONE I=%d, J=%d, F=POINT\n', I, J);
    fprintf(fid, 'STRANDID=1\n');
    for j = 1:J
        for i = 1:I
            fprintf(fid, '%g %g %g %g 1\n', i-1, J-j, ...
                5+bias+0.1*i, 0.01*j);
        end
    end
    fclose(fid);
end
end
