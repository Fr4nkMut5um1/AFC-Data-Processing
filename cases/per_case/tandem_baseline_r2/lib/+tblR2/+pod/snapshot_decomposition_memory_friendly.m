function POD = snapshot_decomposition_memory_friendly(source, options)
%SNAPSHOT_DECOMPOSITION_MEMORY_FRIENDLY Exact-double out-of-core snapshot POD.
%
% SOURCE is a deterministic spatial-block provider:
%   source.dof_count       total number of joint spatial degrees of freedom D
%   source.n_frames        number of snapshots N
%   source.n_blocks        number of disjoint spatial blocks
%   source.read_block(k)   -> [values, dof_indices]
%       values is numel(dof_indices)-by-N and contains finite samples in the
%       exact joint-DOF ordering.  It is converted to double before arithmetic.
%
% The numerical contract matches snapshot_decomposition:
%   mean_snapshot = mean(X,2)
%   C = Xf'*Xf / D
%   Phi = Xf*eigvec, normalized with its actually accumulated 2-norm
%   Ac = Phi'*Xf
%
% No D-by-N snapshot matrix and no full D-by-N mode matrix are materialized.
% The unavoidable N-by-N covariance/eigensystem remains in double precision.

if nargin < 2 || isempty(options)
    options = struct();
end
options = merge_options(default_options(), options);
validate_source(source);
D = double(source.dof_count);
N = double(source.n_frames);
check_memory(memory_diagnostics(D, N, 0, source, options), options, ...
    'covariance/eigensystem');

mean_snapshot = zeros(D, 1, 'double');
covered = false(D, 1);
C = zeros(N, N, 'double');
for block_id = 1:source.n_blocks
    [values, indices] = read_valid_block(source, block_id, D, N);
    if any(covered(indices))
        error('tblR2:pod:snapshotMemoryFriendly:DuplicateDOF', ...
            '空间块 %d 与之前的块包含重复自由度。', block_id);
    end
    covered(indices) = true;
    local_mean = mean(values, 2);
    mean_snapshot(indices) = local_mean;
    Xf = values - local_mean;
    gram_increment = Xf' * Xf;
    C = add_matrix_in_stripes(C, gram_increment, ...
        options.covariance_update_columns);
    if options.progress
        fprintf('[memory-friendly POD] covariance block %d/%d\n', ...
            block_id, source.n_blocks);
    end
    clear values indices local_mean Xf gram_increment;
end
if ~all(covered)
    error('tblR2:pod:snapshotMemoryFriendly:MissingDOF', ...
        '空间块没有覆盖全部 D=%d 个自由度。', D);
end
C = scale_matrix_in_stripes(C, 1 / D, options.covariance_update_columns);

if options.progress
    fprintf('[memory-friendly POD] eig(%d x %d, double)\n', N, N);
end
[vectors, lambda_all] = eig(C, 'vector');
clear C;
lambda_all = real(lambda_all);
[lambda_all, order] = sort(lambda_all, 'descend');
vectors = vectors(:, order);

total_energy = sum(lambda_all);
if ~isfinite(total_energy) || total_energy <= 0
    error('tblR2:pod:snapshotMemoryFriendly:DegenerateEnergy', ...
        '快照脉动的总能量必须是有限正值。');
end
[mode_indices, rank_diagnostics] = resolve_modes( ...
    lambda_all, D, N, options);
selected_vectors = vectors(:, mode_indices);
clear vectors;

n_selected = numel(mode_indices);
check_memory(memory_diagnostics(D, N, n_selected, source, options), options, ...
    'selected basis output');
modes = zeros(D, n_selected, 'double');
for block_id = 1:source.n_blocks
    [values, indices] = read_valid_block(source, block_id, D, N);
    Xf = values - mean_snapshot(indices);
    modes(indices, :) = Xf * selected_vectors;
    if options.progress
        fprintf('[memory-friendly POD] mode block %d/%d\n', ...
            block_id, source.n_blocks);
    end
    clear values indices Xf;
end
mode_norms = vecnorm(modes, 2, 1);
zero_norm = ~(isfinite(mode_norms) & mode_norms > 0);
safe_norms = mode_norms;
safe_norms(zero_norm) = 1;
modes = modes ./ safe_norms;

% Deliberately evaluate the original expression Ac=Phi'*Xf in a third scan.
% The algebraic shortcut sqrt(D*lambda)*eigvec' would use less I/O, but this
% explicit accumulation more closely preserves the reference floating path.
coefficients = zeros(n_selected, N, 'double');
for block_id = 1:source.n_blocks
    [values, indices] = read_valid_block(source, block_id, D, N);
    Xf = values - mean_snapshot(indices);
    coefficients = coefficients + modes(indices, :)' * Xf;
    if options.progress
        fprintf('[memory-friendly POD] coefficient block %d/%d\n', ...
            block_id, source.n_blocks);
    end
    clear values indices Xf;
end
coefficients(zero_norm, :) = 0;

lambda = lambda_all(mode_indices);
POD = struct();
POD.modes = modes;
POD.coefficients = coefficients;
POD.lambda = lambda;
POD.lambda_all = lambda_all;
POD.energy_ratio = cumsum(lambda) / total_energy;
POD.total_energy = total_energy;
POD.mean_snapshot = mean_snapshot;
POD.n_modes = n_selected;
POD.mode_indices = mode_indices(:);
POD.mode_norms = mode_norms(:);
POD.rank_diagnostics = rank_diagnostics;
POD.options = options;
POD.memory_diagnostics = memory_diagnostics(D, N, n_selected, source, options);
POD.definition = ['Memory-friendly exact-double snapshot POD: spatial-block ' ...
    'C=Xf''*Xf/D accumulation, full eig(C), selected Phi=Xf*eigvec with ' ...
    'actual 2-norm normalization, and an explicit spatial-block Ac=Phi''*Xf ' ...
    'scan. No D-by-N snapshot or full D-by-N modal matrix is materialized.'];
end

function options = default_options()
options = struct();
options.rank_method = 'energy_fraction';
options.energy_target = 0.95;
options.n_modes = [];
options.mode_indices = [];
options.covariance_update_columns = 64;
options.progress = true;
options.memory_guard = true;
options.memory_safety_factor = 1.25;
end

function options = merge_options(options, user)
fields = fieldnames(user);
for k = 1:numel(fields)
    if ~isfield(options, fields{k})
        error('tblR2:pod:snapshotMemoryFriendly:UnknownOption', ...
            '未知选项 %s。', fields{k});
    end
    options.(fields{k}) = user.(fields{k});
end
valid_methods = {'energy_fraction','fixed_n','mode_indices','gavish_donoho'};
if ~ismember(options.rank_method, valid_methods)
    error('tblR2:pod:snapshotMemoryFriendly:InvalidRankMethod', ...
        'rank_method 必须是 %s。', strjoin(valid_methods, ', '));
end
if ~(isscalar(options.energy_target) && isfinite(options.energy_target) && ...
        options.energy_target > 0 && options.energy_target <= 1)
    error('tblR2:pod:snapshotMemoryFriendly:InvalidEnergyTarget', ...
        'energy_target 必须位于 (0,1]。');
end
if ~(isscalar(options.covariance_update_columns) && ...
        isfinite(options.covariance_update_columns) && ...
        options.covariance_update_columns >= 1 && ...
        options.covariance_update_columns == fix(options.covariance_update_columns))
    error('tblR2:pod:snapshotMemoryFriendly:InvalidStripeSize', ...
        'covariance_update_columns 必须是正整数。');
end
options.progress = logical(options.progress);
options.memory_guard = logical(options.memory_guard);
if ~(isscalar(options.memory_safety_factor) && ...
        isfinite(options.memory_safety_factor) && options.memory_safety_factor >= 1)
    error('tblR2:pod:snapshotMemoryFriendly:InvalidMemorySafety', ...
        'memory_safety_factor 必须是不小于 1 的有限标量。');
end
end

function validate_source(source)
required = {'dof_count','n_frames','n_blocks','read_block'};
if ~isstruct(source) || ~all(isfield(source, required)) || ...
        ~isa(source.read_block, 'function_handle')
    error('tblR2:pod:snapshotMemoryFriendly:InvalidSource', ...
        'source 必须提供 dof_count、n_frames、n_blocks 和 read_block。');
end
values = [source.dof_count source.n_frames source.n_blocks];
if any(~isfinite(values) | values < 1 | values ~= fix(values)) || ...
        source.n_frames < 2
    error('tblR2:pod:snapshotMemoryFriendly:InvalidSourceSize', ...
        'source 尺寸必须是正整数且至少包含两个快照。');
end
end

function [values, indices] = read_valid_block(source, block_id, D, N)
[values, indices] = source.read_block(block_id);
values = double(values);
indices = double(indices(:));
if isempty(indices) || size(values, 1) ~= numel(indices) || size(values, 2) ~= N
    error('tblR2:pod:snapshotMemoryFriendly:BlockSizeMismatch', ...
        '空间块 %d 的 values/indices 尺寸不符合合同。', block_id);
end
if any(~isfinite(indices) | indices < 1 | indices > D | indices ~= fix(indices)) || ...
        numel(unique(indices)) ~= numel(indices)
    error('tblR2:pod:snapshotMemoryFriendly:InvalidDOFIndices', ...
        '空间块 %d 包含无效或重复自由度索引。', block_id);
end
if any(~isfinite(values), 'all')
    error('tblR2:pod:snapshotMemoryFriendly:NonFiniteBlock', ...
        '空间块 %d 含 NaN/Inf；数据源必须先按既定合同处理无效样本。', block_id);
end
end

function target = add_matrix_in_stripes(target, increment, stripe_width)
n = size(target, 2);
for first = 1:stripe_width:n
    cols = first:min(n, first + stripe_width - 1);
    target(:, cols) = target(:, cols) + increment(:, cols);
end
end

function target = scale_matrix_in_stripes(target, scale, stripe_width)
n = size(target, 2);
for first = 1:stripe_width:n
    cols = first:min(n, first + stripe_width - 1);
    target(:, cols) = target(:, cols) .* scale;
end
end

function [indices, diagnostics] = resolve_modes(lambda_all, D, N, options)
positive = max(lambda_all, 0);
total = sum(positive);
if ~(isfinite(total) && total > 0)
    error('tblR2:pod:snapshotMemoryFriendly:ZeroEnergy', ...
        '非负 POD 能量为零。');
end
cumulative = cumsum(positive) / total;
max_rank = min(N - 1, nnz(positive > 0));
max_rank = max(1, max_rank);
diagnostics = struct('method', options.rank_method, ...
    'cumulative_energy', cumulative, 'max_rank', max_rank);
switch options.rank_method
    case 'energy_fraction'
        rank_r = find(cumulative >= options.energy_target, 1, 'first');
        rank_r = min(max(rank_r, 1), max_rank);
        indices = 1:rank_r;
        diagnostics.energy_target = options.energy_target;
    case 'fixed_n'
        if ~(isscalar(options.n_modes) && isfinite(options.n_modes) && ...
                options.n_modes >= 1 && options.n_modes == fix(options.n_modes))
            error('tblR2:pod:snapshotMemoryFriendly:InvalidModeCount', ...
                'fixed_n 要求 options.n_modes 为正整数。');
        end
        indices = 1:min(options.n_modes, max_rank);
    case 'mode_indices'
        indices = unique(double(options.mode_indices(:).'), 'stable');
        if isempty(indices) || any(~isfinite(indices) | indices < 1 | ...
                indices > max_rank | indices ~= fix(indices))
            error('tblR2:pod:snapshotMemoryFriendly:InvalidModeIndices', ...
                'mode_indices 必须位于 1:max_rank。');
        end
    case 'gavish_donoho'
        singular_values = sqrt(positive * D);
        beta = min(D, N) / max(D, N);
        omega = 0.56 * beta^3 - 0.95 * beta^2 + 1.82 * beta + 1.43;
        nonzero = singular_values(singular_values > 0);
        threshold = omega * median(nonzero);
        rank_r = max(1, min(nnz(singular_values > threshold), max_rank));
        indices = 1:rank_r;
        diagnostics.beta = beta;
        diagnostics.omega = omega;
        diagnostics.threshold = threshold;
end
indices = indices(:).';
diagnostics.mode_indices = indices(:);
diagnostics.energy_at_last_selected = cumulative(max(indices));
end

function diagnostics = memory_diagnostics(D, N, r, source, options)
block_dof = NaN;
if isfield(source, 'max_block_dof'); block_dof = source.max_block_dof; end
covariance_bytes = 16 * N^2;
eigensystem_bytes = 32 * N^2;
output_bytes = 8 * (D * r + r * N + D);
block_bytes = 0;
if isfinite(block_dof); block_bytes = 16 * block_dof * N; end
diagnostics = struct();
diagnostics.full_snapshot_bytes_avoided = 8 * D * N;
diagnostics.full_mode_bytes_avoided = 8 * D * N;
diagnostics.covariance_phase_core_bytes = covariance_bytes + block_bytes;
diagnostics.eigensystem_phase_estimate_bytes = eigensystem_bytes;
diagnostics.selected_output_bytes = output_bytes;
diagnostics.estimated_core_peak_bytes = max([ ...
    covariance_bytes + block_bytes, eigensystem_bytes, output_bytes + block_bytes]);
diagnostics.estimated_core_peak_gib = diagnostics.estimated_core_peak_bytes / 2^30;
diagnostics.note = ['Estimate excludes MATLAB eig workspace and cache-reader ' ...
    'temporary arrays; all arithmetic arrays are double.'];
diagnostics.covariance_update_columns = options.covariance_update_columns;
end

function check_memory(diagnostics, options, phase)
if ~options.memory_guard
    return;
end
available = Inf;
try
    info = memory;
    available = double(info.MemAvailableAllArrays);
catch
end
required = options.memory_safety_factor * diagnostics.estimated_core_peak_bytes;
if isfinite(available) && required > available
    error('tblR2:pod:snapshotMemoryFriendly:InsufficientMemory', ...
        ['%s 阶段预计核心峰值 %.2f GiB，乘安全系数 %.3g 后超过当前 MATLAB ' ...
        '可用 %.2f GiB。计算已在大数组分配前停止，未降低精度。'], ...
        phase, diagnostics.estimated_core_peak_gib, ...
        options.memory_safety_factor, available / 2^30);
end
end
