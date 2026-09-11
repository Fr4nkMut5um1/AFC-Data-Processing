function denoise = pod_denoise_prepare_memory_friendly( ...
    cache_file, cfg, stats, options)
%POD_DENOISE_PREPARE_MEMORY_FRIENDLY Full-grid out-of-core POD denoise basis.
%
% This is an independent, memory-friendly alternative to pod_denoise_prepare.
% It preserves double-precision snapshot-POD arithmetic but never materializes
% the complete joint [U;V] snapshot matrix.  The output intentionally keeps the
% same Phi_trunc/A_trunc fields so pod_denoise_reconstruct_frame remains usable.

if nargin < 4 || isempty(options)
    options = struct();
end
options = merge_options(default_options(), options);
if ~isfield(stats, 'accepted_mask')
    error('tblR2:podDenoiseMemoryFriendly:MissingMask', ...
        'stats 缺少 accepted_mask。');
end
spatial_mask = logical(stats.accepted_mask);
[J, I] = size(spatial_mask);
n_spatial = nnz(spatial_mask);
if n_spatial < 2
    error('tblR2:podDenoiseMemoryFriendly:EmptyMask', ...
        'accepted_mask 中有效空间点不足。');
end

frame_ids = options.frame_ids;
if isempty(frame_ids)
    if isfield(cfg, 'total_frames') && ~isempty(cfg.total_frames)
        frame_ids = 1:cfg.total_frames;
    elseif isfield(stats, 'n_frames') && ~isempty(stats.n_frames)
        frame_ids = 1:stats.n_frames;
    else
        error('tblR2:podDenoiseMemoryFriendly:MissingFrameCount', ...
            'cfg.total_frames 与 stats.n_frames 均不可用。');
    end
end
frame_ids = double(frame_ids(:).');
if numel(frame_ids) < 2 || any(~isfinite(frame_ids) | frame_ids < 1 | ...
        frame_ids ~= fix(frame_ids))
    error('tblR2:podDenoiseMemoryFriendly:InvalidFrames', ...
        'frame_ids 必须包含至少两个正整数帧号。');
end

if ~isempty(options.cache_path) && options.use_cache && isfile(options.cache_path)
    loaded = load(options.cache_path, 'denoise');
    if isfield(loaded, 'denoise') && cache_is_compatible( ...
            loaded.denoise, cache_file, frame_ids, spatial_mask, options)
        denoise = loaded.denoise;
        fprintf('[memory-friendly POD] reuse %s\n', options.cache_path);
        return;
    end
end

position_grid = zeros(J, I);
position_grid(spatial_mask) = 1:n_spatial;
row_starts = 1:options.row_block_size:J;
candidate_blocks = cell(numel(row_starts), 1);
keep_block = false(numel(row_starts), 1);
max_block_dof = 0;
for k = 1:numel(row_starts)
    rows = row_starts(k):min(J, row_starts(k) + ...
        options.row_block_size - 1);
    if ~any(spatial_mask(rows, :), 'all')
        continue;
    end
    candidate_blocks{k} = rows;
    keep_block(k) = true;
    max_block_dof = max(max_block_dof, ...
        2 * nnz(spatial_mask(rows, :)));
end
row_blocks = candidate_blocks(keep_block);

source = struct();
source.dof_count = 2 * n_spatial;
source.n_frames = numel(frame_ids);
source.n_blocks = numel(row_blocks);
source.max_block_dof = max_block_dof;
source.read_block = @(block_id) read_cache_block(cache_file, frame_ids, ...
    row_blocks{block_id}, I, spatial_mask, position_grid, n_spatial);

core_options = struct( ...
    'rank_method', options.rank_method, ...
    'energy_target', options.energy_target, ...
    'n_modes', options.n_modes, ...
    'mode_indices', options.mode_indices, ...
    'covariance_update_columns', options.covariance_update_columns, ...
    'progress', options.progress, ...
    'memory_guard', options.memory_guard, ...
    'memory_safety_factor', options.memory_safety_factor);
POD = tblR2.pod.snapshot_decomposition_memory_friendly(source, core_options);

denoise = struct();
denoise.Phi_trunc = POD.modes;
denoise.A_trunc = POD.coefficients;
denoise.mean_snapshot = POD.mean_snapshot;
denoise.spatial_mask = spatial_mask;
denoise.grid_size = [J I];
denoise.n_spatial = n_spatial;
denoise.frame_ids = frame_ids(:);
denoise.rank = POD.n_modes;
denoise.mode_indices = POD.mode_indices;
denoise.eigenvalues = POD.lambda_all;
denoise.mode_norms = POD.mode_norms;
denoise.rank_method = options.rank_method;
denoise.diagnostics = POD.rank_diagnostics;
denoise.memory_diagnostics = POD.memory_diagnostics;
denoise.source_cache = cache_file;
denoise.options = options;
denoise.implementation = 'memory_friendly_spatial_block_double_v1';
denoise.definition = ['Full-grid POD denoise basis generated without a resident ' ...
    'D-by-N snapshot matrix. All arithmetic uses double; C=Xf''*Xf/D, modes ' ...
    'use actual accumulated norms, and A_trunc is explicitly Phi''*Xf.'];

if ~isempty(options.cache_path) && options.write_cache
    cache_dir = fileparts(options.cache_path);
    if ~isempty(cache_dir) && ~isfolder(cache_dir); mkdir(cache_dir); end
    save(options.cache_path, 'denoise', '-v7.3');
    fprintf('[memory-friendly POD] basis saved: %s\n', options.cache_path);
end
end

function options = default_options()
options = struct();
options.rank_method = 'energy_fraction';
options.energy_target = 0.95;
options.n_modes = [];
options.mode_indices = [];
options.frame_ids = [];
options.row_block_size = 2;
options.covariance_update_columns = 64;
options.progress = true;
options.memory_guard = true;
options.memory_safety_factor = 1.25;
options.cache_path = '';
options.use_cache = true;
options.write_cache = true;
end

function options = merge_options(options, user)
fields = fieldnames(user);
for k = 1:numel(fields)
    if ~isfield(options, fields{k})
        error('tblR2:podDenoiseMemoryFriendly:UnknownOption', ...
            '未知选项 %s。', fields{k});
    end
    options.(fields{k}) = user.(fields{k});
end
if ~(isscalar(options.row_block_size) && isfinite(options.row_block_size) && ...
        options.row_block_size >= 1 && options.row_block_size == fix(options.row_block_size))
    error('tblR2:podDenoiseMemoryFriendly:InvalidRowBlock', ...
        'row_block_size 必须是正整数。');
end
options.use_cache = logical(options.use_cache);
options.write_cache = logical(options.write_cache);
options.progress = logical(options.progress);
end

function [values, indices] = read_cache_block(cache_file, frame_ids, rows, I, ...
    spatial_mask, position_grid, n_spatial)
chunk = tblR2.read_cache_chunk(cache_file, frame_ids, rows, 1:I, ...
    'raw', [], []);
local_mask = spatial_mask(rows, :);
positions = position_grid(rows, :);
positions = positions(local_mask);
U = reshape(chunk.U, numel(frame_ids), []);
V = reshape(chunk.V, numel(frame_ids), []);
U = U(:, local_mask(:));
V = V(:, local_mask(:));
U(~isfinite(U)) = 0;
V(~isfinite(V)) = 0;
values = [U.'; V.'];
indices = [positions(:); n_spatial + positions(:)];
end

function tf = cache_is_compatible(cached, cache_file, frame_ids, mask, options)
tf = false;
required = {'Phi_trunc','A_trunc','mean_snapshot','spatial_mask', ...
    'frame_ids','source_cache','options','implementation'};
if ~isstruct(cached) || ~all(isfield(cached, required))
    return;
end
if ~strcmp(cached.implementation, 'memory_friendly_spatial_block_double_v1') || ...
        ~strcmp(cached.source_cache, cache_file) || ...
        ~isequal(cached.spatial_mask, mask) || ...
        ~isequal(double(cached.frame_ids(:)), double(frame_ids(:)))
    return;
end
names = {'rank_method','energy_target','n_modes','mode_indices','row_block_size'};
for k = 1:numel(names)
    if ~isequaln(cached.options.(names{k}), options.(names{k}))
        return;
    end
end
tf = true;
end
