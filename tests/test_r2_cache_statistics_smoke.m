% TEST_R2_CACHE_STATISTICS_SMOKE Synthetic two-repeat r2 data path.
repo_root = fileparts(fileparts(mfilename('fullpath')));
library_root = fullfile(repo_root, 'lib');
addpath(library_root, '-begin');
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's'));

I = 8; J = 12; n = 12;
rep1 = fullfile(root, 'Rep1'); rep2 = fullfile(root, 'Rep2');
write_dat(rep1, n, I, J, 0.0);
write_dat(rep2, n, I, J, 3.0);
cfg = struct();
cfg.case_id = 'test/r2/cache'; cfg.case_type = 'baseline';
cfg.name = 'r2 synthetic'; cfg.script_file = mfilename('fullpath');
cfg.output_dir = fullfile(root, 'output'); cfg.data_root = rep1;
cfg.sources = struct('raw', struct('roots', {{rep1, rep2}}, ...
    'offsets', [0 0], 'ids', {{'1st','2nd'}}), ...
    'postproc', struct('roots', {{rep1, rep2}}, ...
    'offsets', [0 0], 'ids', {{'1st','2nd'}}));
cfg.grid_size = [I J]; cfg.n_frames = n; cfg.total_frames = 2*n;
cfg.formal_required_frames = n; cfg.allow_debug_snapshot = true;
cfg.frame_offset = 0; cfg.fs = 100; cfg.Uinf = 25; cfg.nu = 1.48e-5;
cfg.rho = 1.2; cfg.D_mm = 30; cfg.x_max = 7; cfg.chunk_frames = 4;
cfg.min_valid_fraction = 0.5; cfg.rebuild_cache = true; cfg.wall_side = 'bottom';
cfg.stages = struct('cache','compute','statistics','compute','mean_bl','skip', ...
    'phase','skip','structures','skip','transport','skip','temporal','skip', ...
    'spatial','skip','pod','skip','dmd','skip','spod','skip', ...
    'correlations','skip','harmonics','skip','figures','skip');
info = tblR2.build_paths(cfg.output_dir);
cache = tblR2.prepare_sequence_cache(cfg, info, 'raw');
assert(cache.n_frames == 2*n && isfile(cache.filename));
S = tblR2.mean_stats_cache(cache.filename, cfg.min_valid_fraction, 4, cfg.Uinf);
assert(S.n_frames == 2*n && all(isfinite(S.Uavex(:))));
chunk = tblR2.read_cache_chunk(cache.filename, [1 2 13 14], 1:J, 1:I, 'raw');
assert(isequal(size(chunk.U), [4 J I]) && all(chunk.sampleValid(:)));
fprintf('test_r2_cache_statistics_smoke: PASS\n');

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
            fprintf(fid, '%g %g %g %g 1\n', i-1, J-j, 5+bias+0.1*i, 0.01*j);
        end
    end
    fclose(fid);
end
end
