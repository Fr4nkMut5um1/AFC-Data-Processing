function pod_file = build_pod_cache(ctx, stats, cfg, run_dir)
%BUILD_POD_CACHE Exact double out-of-core joint POD and reconstruction.
if ~cfg.preprocessing.pod.enabled
    pod_file = '';
    return;
end
pod_cfg = cfg.preprocessing.pod;
nt = ctx.cache_size(1);
ny = ctx.cache_size(2);
nx = ctx.cache_size(3);
m_full = ny * nx;
valid_fraction = double(stats.valid_count_xy) / nt;
retained_before_exclusion = valid_fraction >= pod_cfg.min_valid_fraction;
spatial_active = d23.spatial_active_mask(ctx);
retained = retained_before_exclusion & spatial_active;
m = nnz(retained);
if m == 0
    error('d23:build_pod_cache:NoDofs', ...
        'No spatial points pass min_valid_fraction.');
end
dof_count = 2 * m;
retained_before_count = nnz(retained_before_exclusion);
excluded_retained_count = nnz(retained_before_exclusion & ~spatial_active);
geometric_excluded_count = nnz(~spatial_active);
pod_file = fullfile(run_dir, 'pod', 'pod_reconstruction.mat');
meta_file = fullfile(run_dir, 'pod', 'pod_metadata.mat');
if isfile(pod_file) && isfile(meta_file)
    loaded = load(meta_file, 'pod_meta');
    if strcmp(loaded.pod_meta.state, 'COMPLETE') && ...
            strcmp(loaded.pod_meta.source_fingerprint, ctx.source_fingerprint) && ...
            strcmp(loaded.pod_meta.config_hash, d23.config_hash(cfg))
        return;
    end
    error('d23:build_pod_cache:ExistingMismatch', ...
        'An incomplete or mismatched POD cache already exists.');
end
snapshot_file = fullfile(run_dir, 'pod', 'pod_snapshot_matrix.mat');
partial_reconstruction = fullfile(run_dir, 'pod', 'pod_reconstruction.partial.mat');
if isfile(snapshot_file) || isfile(partial_reconstruction)
    error('d23:build_pod_cache:PartialExists', ...
        'Partial POD files exist; move them aside before retrying.');
end

rank_upper = min(dof_count, nt - 1);
if strcmp(char(pod_cfg.rank.kind), 'fixed_n')
    rank_estimate = double(pod_cfg.rank.n);
    if rank_estimate > rank_upper
        error('d23:build_pod_cache:RankUpperBound', ...
            'fixed_n=%d exceeds min(joint DOF count,Nt-1)=%d.', ...
            rank_estimate, rank_upper);
    end
else
    rank_estimate = rank_upper;
end
square_bytes = 8 * double(nt) ^ 2;
block_bytes = 8 * double(pod_cfg.spatial_block_dof) * double(nt);
coefficient_bytes_memory = 8 * double(rank_estimate) * double(nt);
eig_peak_bytes = 5 * square_bytes + 2 * block_bytes;
post_eig_peak_bytes = square_bytes + coefficient_bytes_memory + 4 * block_bytes;
required_memory = pod_cfg.memory_safety_factor * ...
    max(eig_peak_bytes, post_eig_peak_bytes);
try
    mem = memory;
    available_memory = min(double(mem.MaxPossibleArrayBytes), ...
        double(mem.MemAvailableAllArrays));
catch
    available_memory = Inf;
end
if available_memory < required_memory
    error('d23:build_pod_cache:MemoryPreflight', ...
        'Estimated POD allocation %.3f GiB exceeds available %.3f GiB.', ...
        required_memory / 2^30, available_memory / 2^30);
end
snapshot_bytes = 8 * double(dof_count) * double(nt);
reconstruction_bytes = 2 * 8 * double(nt) * double(ny) * double(nx);
mode_bytes = 8 * double(dof_count) * double(rank_estimate);
coefficient_bytes = 8 * double(rank_estimate) * double(nt);
required_disk = pod_cfg.disk_safety_factor * ...
    (snapshot_bytes + reconstruction_bytes + mode_bytes + coefficient_bytes);
disk_root = java.io.File(run_dir);
available_disk = double(disk_root.getUsableSpace());
if available_disk < required_disk
    error('d23:build_pod_cache:DiskPreflight', ...
        'Estimated POD disk %.3f GiB exceeds available %.3f GiB.', ...
        required_disk / 2^30, available_disk / 2^30);
end

% The Section-4 r2 adapter may request an in-memory implementation.  It is
% mathematically the same double-precision method-of-snapshots POD, but avoids
% the very slow column-wise gzip writes produced by matfile for the enormous
% temporary snapshot matrix.  Small/unit tests retain the historical
% out-of-core path unless this flag is explicitly enabled.
if isfield(pod_cfg, 'fast_in_memory') && logical(pod_cfg.fast_in_memory)
    pod_file = build_pod_cache_in_memory(ctx, stats, cfg, run_dir, ...
        pod_file, meta_file, partial_reconstruction, retained, ...
        valid_fraction, m, dof_count, m_full, nt, ny, nx, ...
        rank_estimate, required_memory, required_disk, ...
        retained_before_count, excluded_retained_count, ...
        geometric_excluded_count);
    return;
end

pod_meta = struct('schema_version', 1, 'state', 'RUNNING', ...
    'source_fingerprint', ctx.source_fingerprint, ...
    'config_hash', d23.config_hash(cfg), 'nt', nt, 'ny', ny, 'nx', nx, ...
    'retained_spatial_count_before_exclusion', retained_before_count, ...
    'retained_spatial_count', m, 'joint_dof_count', dof_count, ...
    'excluded_retained_spatial_count', excluded_retained_count, ...
    'geometric_excluded_spatial_count', geometric_excluded_count, ...
    'spatial_exclusion', spatial_exclusion_info(ctx), ...
    'min_valid_fraction', pod_cfg.min_valid_fraction, ...
    'missing_policy', 'nonfinite deviations replaced by zero', ...
    'memory_estimate_bytes', required_memory, ...
    'disk_estimate_bytes', required_disk, 'created_utc', d23.utc_now());
d23.atomic_save(meta_file, struct('pod_meta', pod_meta));

snapshot = matfile(snapshot_file, 'Writable', true);
snapshot.X(dof_count, nt) = 0;
snapshot_sum = zeros(dof_count, 1);
retained_linear = find(retained(:));
chunk_size = cfg.statistics.chunk_size;
for first = 1:chunk_size:nt
    ids = first:min(first + chunk_size - 1, nt);
    raw = d23.read_chunk(ctx.cache_file, ids);
    up = raw.U - reshape(stats.Ubar, 1, ny, nx);
    vp = raw.V - reshape(stats.Vbar, 1, ny, nx);
    valid = raw.valid;
    up(~valid) = 0;
    vp(~valid) = 0;
    u_flat = reshape(permute(up, [2 3 1]), m_full, numel(ids));
    v_flat = reshape(permute(vp, [2 3 1]), m_full, numel(ids));
    block = [u_flat(retained_linear, :); v_flat(retained_linear, :)];
    snapshot.X(:, ids) = block;
    snapshot_sum = snapshot_sum + sum(block, 2);
end

mu = snapshot_sum / nt;
snapshot.mu = mu;
snapshot.retained_spatial_mask = retained;
snapshot.valid_fraction = valid_fraction;

C = zeros(nt, nt, 'double');
spatial_block = double(pod_cfg.spatial_block_dof);
time_tile = double(pod_cfg.time_tile_frames);
for first_dof = 1:spatial_block:dof_count
    dofs = first_dof:min(first_dof + spatial_block - 1, dof_count);
    F = double(snapshot.X(dofs, :)) - mu(dofs);
    for first_time = 1:time_tile:nt
        times = first_time:min(first_time + time_tile - 1, nt);
        C(:, times) = C(:, times) + (F.' * F(:, times)) / dof_count;
    end
end
for first_i = 1:time_tile:nt
    ii = first_i:min(first_i + time_tile - 1, nt);
    for first_j = first_i:time_tile:nt
        jj = first_j:min(first_j + time_tile - 1, nt);
        average = 0.5 * (C(ii, jj) + C(jj, ii).');
        C(ii, jj) = average;
        C(jj, ii) = average.';
    end
end
[time_vectors, eigenvalues] = eig(C, 'vector');
[eigenvalues, order] = sort(real(eigenvalues), 'descend');
time_vectors = real(time_vectors(:, order));
clear C;
[rank_value, positive_rank, lambda_tol] = d23.select_pod_rank( ...
    eigenvalues, dof_count, pod_cfg);
time_vectors_r = time_vectors(:, 1:rank_value);

mode_norm_sq = zeros(1, rank_value);
for first_dof = 1:spatial_block:dof_count
    dofs = first_dof:min(first_dof + spatial_block - 1, dof_count);
    F = double(snapshot.X(dofs, :)) - mu(dofs);
    raw_modes = F * time_vectors_r;
    mode_norm_sq = mode_norm_sq + sum(raw_modes .^ 2, 1);
end
mode_norms = sqrt(mode_norm_sq);
if any(mode_norms <= 0 | ~isfinite(mode_norms))
    error('d23:build_pod_cache:ModeNormalization', ...
        'A selected POD mode has zero or nonfinite norm.');
end
snapshot.Phi(dof_count, rank_value) = 0;
coefficients = zeros(rank_value, nt);
for first_dof = 1:spatial_block:dof_count
    dofs = first_dof:min(first_dof + spatial_block - 1, dof_count);
    F = double(snapshot.X(dofs, :)) - mu(dofs);
    Phi_block = (F * time_vectors_r) ./ mode_norms;
    snapshot.Phi(dofs, :) = Phi_block;
    coefficients = coefficients + Phi_block.' * F;
end
snapshot.coefficients = coefficients;
snapshot.eigenvalues = eigenvalues;
snapshot.selected_rank = rank_value;

reconstruction = matfile(partial_reconstruction, 'Writable', true);
reconstruction.Uprime(nt, ny, nx) = 0;
reconstruction.Vprime(nt, ny, nx) = 0;
for first = 1:chunk_size:nt
    times = first:min(first + chunk_size - 1, nt);
    Xhat = zeros(dof_count, numel(times));
    for first_dof = 1:spatial_block:dof_count
        dofs = first_dof:min(first_dof + spatial_block - 1, dof_count);
        Phi_block = double(snapshot.Phi(dofs, :));
        Xhat(dofs, :) = mu(dofs) + Phi_block * coefficients(:, times);
    end
    u_grid = nan(m_full, numel(times));
    v_grid = nan(m_full, numel(times));
    u_grid(retained_linear, :) = Xhat(1:m, :);
    v_grid(retained_linear, :) = Xhat(m+1:end, :);
    reconstruction.Uprime(times, :, :) = permute(reshape(u_grid, ny, nx, []), [3 1 2]);
    reconstruction.Vprime(times, :, :) = permute(reshape(v_grid, ny, nx, []), [3 1 2]);
end
[ok, message] = movefile(partial_reconstruction, pod_file, 'f');
if ~ok
    error('d23:build_pod_cache:PublishFailed', '%s', message);
end
pod_meta.state = 'COMPLETE';
pod_meta.selected_rank = rank_value;
pod_meta.positive_rank = positive_rank;
pod_meta.lambda_tolerance = lambda_tol;
pod_meta.eigenvalues = eigenvalues;
pod_meta.completed_utc = d23.utc_now();
d23.atomic_save(meta_file, struct('pod_meta', pod_meta));
end

function pod_file = build_pod_cache_in_memory(ctx, stats, cfg, run_dir, ...
        pod_file, meta_file, partial_reconstruction, retained, ...
        valid_fraction, m, dof_count, m_full, nt, ny, nx, ...
        rank_estimate, required_memory, required_disk, ...
        retained_before_count, excluded_retained_count, ...
        geometric_excluded_count)
%BUILD_POD_CACHE_IN_MEMORY Exact POD without the pathological temporary MAT.
% The source/cache and all arithmetic remain double-accurate at the POD
% stage.  The only persistent large object is the reconstruction cache needed
% by fluctuation_chunk and the downstream detector.
pod_cfg = cfg.preprocessing.pod;
retained_linear = find(retained(:));

% Assemble the retained joint snapshot matrix in source chunks.  d23.read_chunk
% promotes the source to double before subtracting the PostProc mean, exactly
% matching the historical out-of-core arithmetic while avoiding compressed
% matfile writes for every 48-frame slab.
X = zeros(dof_count, nt, 'double');
chunk_size = cfg.statistics.chunk_size;
for first = 1:chunk_size:nt
    ids = first:min(first + chunk_size - 1, nt);
    raw = d23.read_chunk(ctx.cache_file, ids);
    up = raw.U - reshape(stats.Ubar, 1, ny, nx);
    vp = raw.V - reshape(stats.Vbar, 1, ny, nx);
    up(~raw.valid) = 0;
    vp(~raw.valid) = 0;
    u_flat = reshape(permute(up, [2 3 1]), m_full, numel(ids));
    v_flat = reshape(permute(vp, [2 3 1]), m_full, numel(ids));
    X(1:m, ids) = u_flat(retained_linear, :);
    X(m+1:end, ids) = v_flat(retained_linear, :);
end

% Center exactly as the historical path: first compute the mean snapshot of
% the PostProc fluctuations, then form the centered joint snapshots.
mu = sum(X, 2) / nt;
% Center in spatial blocks so the 10+ GiB formal snapshot matrix is not
% duplicated by one full-array implicit-expansion temporary.
spatial_block = double(pod_cfg.spatial_block_dof);
for first_dof = 1:spatial_block:dof_count
    dofs = first_dof:min(first_dof + spatial_block - 1, dof_count);
    X(dofs, :) = X(dofs, :) - mu(dofs);
end
F = X;
clear X;

% Method-of-snapshots covariance.  A single BLAS multiplication is much
% faster than thousands of compressed MAT-file slab reads, while preserving
% the same normalized double covariance definition.
C = (F.' * F) / dof_count;
C = 0.5 * (C + C.');
[time_vectors, eigenvalues] = eig(C, 'vector');
[eigenvalues, order] = sort(real(eigenvalues), 'descend');
time_vectors = real(time_vectors(:, order));
clear C;
[rank_value, positive_rank, lambda_tol] = d23.select_pod_rank( ...
    eigenvalues, dof_count, pod_cfg);
time_vectors_r = time_vectors(:, 1:rank_value);

raw_modes = F * time_vectors_r;
mode_norms = sqrt(sum(raw_modes .^ 2, 1));
if any(mode_norms <= 0 | ~isfinite(mode_norms))
    error('d23:build_pod_cache:ModeNormalization', ...
        'A selected POD mode has zero or nonfinite norm.');
end
Phi = raw_modes ./ mode_norms;
coefficients = Phi.' * F;
clear raw_modes time_vectors time_vectors_r F;

pod_meta = struct('schema_version', 1, 'state', 'RUNNING', ...
    'storage_mode', 'in_memory_exact', ...
    'source_fingerprint', ctx.source_fingerprint, ...
    'config_hash', d23.config_hash(cfg), 'nt', nt, 'ny', ny, 'nx', nx, ...
    'retained_spatial_count_before_exclusion', retained_before_count, ...
    'retained_spatial_count', m, 'joint_dof_count', dof_count, ...
    'excluded_retained_spatial_count', excluded_retained_count, ...
    'geometric_excluded_spatial_count', geometric_excluded_count, ...
    'spatial_exclusion', spatial_exclusion_info(ctx), ...
    'min_valid_fraction', pod_cfg.min_valid_fraction, ...
    'missing_policy', 'nonfinite deviations replaced by zero', ...
    'memory_estimate_bytes', required_memory, ...
    'disk_estimate_bytes', required_disk, 'created_utc', d23.utc_now());
d23.atomic_save(meta_file, struct('pod_meta', pod_meta));

% Reconstruct in 48-frame slabs.  This keeps the public MAT-file contract
% (double Uprime/Vprime) while avoiding a second full-size in-memory array.
reconstruction = matfile(partial_reconstruction, 'Writable', true);
reconstruction.Uprime(nt, ny, nx) = 0;
reconstruction.Vprime(nt, ny, nx) = 0;
chunk_size = cfg.statistics.chunk_size;
for first = 1:chunk_size:nt
    times = first:min(first + chunk_size - 1, nt);
    Xhat = mu + Phi * coefficients(:, times);
    u_grid = nan(m_full, numel(times));
    v_grid = nan(m_full, numel(times));
    u_grid(retained_linear, :) = Xhat(1:m, :);
    v_grid(retained_linear, :) = Xhat(m+1:end, :);
    reconstruction.Uprime(times, :, :) = ...
        permute(reshape(u_grid, ny, nx, []), [3 1 2]);
    reconstruction.Vprime(times, :, :) = ...
        permute(reshape(v_grid, ny, nx, []), [3 1 2]);
end
[ok, message] = movefile(partial_reconstruction, pod_file, 'f');
if ~ok
    error('d23:build_pod_cache:PublishFailed', '%s', message);
end

pod_meta.state = 'COMPLETE';
pod_meta.selected_rank = rank_value;
pod_meta.positive_rank = positive_rank;
pod_meta.lambda_tolerance = lambda_tol;
pod_meta.eigenvalues = eigenvalues;
pod_meta.completed_utc = d23.utc_now();
d23.atomic_save(meta_file, struct('pod_meta', pod_meta));
end

function value = spatial_exclusion_info(ctx)
if isfield(ctx, 'spatial_exclusion')
    value = ctx.spatial_exclusion;
else
    value = struct('enabled', false);
end
end
