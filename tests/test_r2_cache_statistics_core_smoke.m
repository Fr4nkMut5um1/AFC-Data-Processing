% TEST_R2_CACHE_STATISTICS_CORE_SMOKE Exercise cache statistics without file parsing.
% This isolates the disk-cache and streaming-statistics path from the
% platform-specific MEMORY call used by the DAT parser.
repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repo_root, 'lib'), '-begin');
root = tempname; mkdir(root); cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
I = 6; J = 5; n_frames = 10;
[xx, yy] = meshgrid(1:I, 1:J);
U = single(reshape(4 + 0.2 * xx, 1, J, I) + reshape(0:n_frames-1, n_frames, 1, 1));
V = single(reshape(0.1 * yy, 1, J, I) + reshape(sin((1:n_frames) / 2), n_frames, 1, 1));
sampleValid = true(n_frames, J, I);
sampleValid(3, 2, 4) = false;
U(3, 2, 4) = NaN; V(3, 2, 4) = NaN;
X = repmat(1:I, J, 1); Y = repmat((1:J)', 1, I); h_mm = 1;
cache_meta = struct('schema_version', 1, 'source_role', 'synthetic');
cache_file = fullfile(root, 'cache.mat');
save(cache_file, 'U', 'V', 'sampleValid', 'X', 'Y', 'h_mm', 'cache_meta', '-v7.3');
stats = tblR2.mean_stats_cache(cache_file, 0.5, 3, 25);
assert(stats.n_frames == n_frames && isequal(size(stats.Uavex), [J I]));
assert(all(stats.valid_count(:) >= n_frames - 1));
chunk = tblR2.read_cache_chunk(cache_file, [1 3 5], 1:J, 1:I, 'raw');
assert(isequal(size(chunk.U), [3 J I]) && chunk.sampleValid(2, 2, 4) == false);
total = tblR2.read_cache_chunk(cache_file, [1 3 5], 1:J, 1:I, 'total', stats);
assert(isequal(size(total.U), [3 J I]) && all(total.sampleValid(:) | isnan(total.U(:))));
fprintf('test_r2_cache_statistics_core_smoke: PASS\n');
