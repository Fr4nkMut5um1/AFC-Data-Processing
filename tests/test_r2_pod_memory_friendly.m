% TEST_R2_POD_MEMORY_FRIENDLY Exact-double equivalence without resident X.
repo_root = fileparts(fileparts(mfilename('fullpath')));
library_root = fullfile(repo_root, 'lib');
addpath(library_root, '-begin');

rng(42);
D = 36; N = 11; requested = 5;
X_numeric = randn(D, N) + linspace(-0.3, 0.4, D)';
blocks = {1:7, 8:19, 20:28, 29:D};
source = struct('dof_count',D,'n_frames',N,'n_blocks',numel(blocks), ...
    'max_block_dof',max(cellfun(@numel,blocks)), ...
    'read_block',@(k) numeric_block(X_numeric, blocks, k));
memory_pod = tblR2.pod.snapshot_decomposition_memory_friendly(source, struct( ...
    'rank_method','fixed_n','n_modes',requested,'progress',false, ...
    'covariance_update_columns',3));
reference = tblR2.pod.snapshot_decomposition(X_numeric, requested);

assert(isa(memory_pod.modes,'double') && isa(memory_pod.coefficients,'double'));
assert(norm(memory_pod.mean_snapshot-reference.mean_snapshot) < 1e-12);
assert(norm(memory_pod.lambda_all-reference.lambda_all) / ...
    norm(reference.lambda_all) < 1e-11);
reference_reconstruction = reference.modes * reference.coefficients + ...
    reference.mean_snapshot;
memory_reconstruction = memory_pod.modes * memory_pod.coefficients + ...
    memory_pod.mean_snapshot;
assert(norm(memory_reconstruction-reference_reconstruction,'fro') / ...
    norm(reference_reconstruction,'fro') < 1e-10);
assert(memory_pod.memory_diagnostics.full_snapshot_bytes_avoided == 8*D*N);

root = tempname; mkdir(root); cleanup = onCleanup(@() rmdir(root,'s'));
J = 5; I = 7; N = 10;
[X_grid, Y_grid] = meshgrid(1:I,1:J);
U = zeros(N,J,I,'double'); V = zeros(size(U));
for k = 1:N
    U(k,:,:) = 8 + 0.7*sin(2*pi*k/N).*cos(pi*X_grid/I) + ...
        0.13*cos(4*pi*k/N).*sin(pi*Y_grid/J);
    V(k,:,:) = 0.2*cos(2*pi*k/N).*sin(pi*X_grid/I) + ...
        0.07*sin(6*pi*k/N).*cos(pi*Y_grid/J);
end
sampleValid = true(size(U));
cache_file = fullfile(root,'cache.mat');
save(cache_file,'U','V','sampleValid','X_grid','Y_grid','-v7.3');
% read_cache_chunk uses variables X and Y to recover the cached grid size.
cache = matfile(cache_file,'Writable',true);
cache.X = X_grid; cache.Y = Y_grid;

stats = struct('accepted_mask',true(J,I),'n_frames',N);
cfg = struct('total_frames',N);
options = struct('rank_method','fixed_n','n_modes',4, ...
    'row_block_size',2,'covariance_update_columns',3,'progress',false, ...
    'cache_path','','use_cache',false,'write_cache',false);
denoise = tblR2.pod_denoise_prepare_memory_friendly( ...
    cache_file,cfg,stats,options);
U_matrix = reshape(U,N,[]);
V_matrix = reshape(V,N,[]);
joint = [U_matrix'; V_matrix'];
reference_cache = tblR2.pod.snapshot_decomposition(joint,4);
cache_reconstruction = denoise.Phi_trunc*denoise.A_trunc + ...
    denoise.mean_snapshot;
reference_cache_reconstruction = reference_cache.modes* ...
    reference_cache.coefficients + reference_cache.mean_snapshot;
assert(norm(cache_reconstruction-reference_cache_reconstruction,'fro') / ...
    norm(reference_cache_reconstruction,'fro') < 1e-10);
assert(strcmp(denoise.implementation,'memory_friendly_spatial_block_double_v1'));

[U_frame,V_frame] = tblR2.pod_denoise_reconstruct_frame(denoise,3);
expected = cache_reconstruction(:,3);
assert(norm(U_frame(:)-expected(1:J*I)) < 1e-10);
assert(norm(V_frame(:)-expected(J*I+1:end)) < 1e-10);
fprintf('test_r2_pod_memory_friendly: PASS\n');

function [values,indices] = numeric_block(X,blocks,k)
indices = blocks{k}(:);
values = X(indices,:);
end
