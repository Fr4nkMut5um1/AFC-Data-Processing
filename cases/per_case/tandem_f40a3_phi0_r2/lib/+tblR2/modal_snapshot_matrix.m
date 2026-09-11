function sequence = modal_snapshot_matrix(cache_file, cfg, stats, phase_stats, ...
    mean_bl, branch, modal_cfg)
%MODAL_SNAPSHOT_MATRIX Assemble an explicitly sampled joint [u;v] sequence.
%
% Contract: all sampling knobs are read from modal_cfg (i.e. cfg.pod /
% cfg.dmd / cfg.spod) and never hard-coded: frame_stride and max_frames
% define the equal-time snapshot set (at least three frames), spatial_stride
% and x_range_mm define the retained grid, and max_y_over_delta defines the
% wall-normal mask scaled by the local delta99. The returned sequence is an
% equally spaced time series of joint [u;v] columns, with invalid samples
% replaced by zero so downstream eig/SVD remains finite.

if ~ismember(branch, {'total', 'random'})
    error('tblR2:modal_snapshot_matrix:InvalidBranch', ...
        'branch 必须是 total 或 random。');
end
if strcmp(branch, 'random') && isempty(phase_stats)
    error('tblR2:modal_snapshot_matrix:MissingPhaseStatistics', ...
        'random 模态分析需要相位统计结果。');
end
if ~(isscalar(modal_cfg.frame_stride) && modal_cfg.frame_stride >= 1 && ...
        modal_cfg.frame_stride == fix(modal_cfg.frame_stride))
    error('tblR2:modal_snapshot_matrix:InvalidFrameStride', ...
        'modal_cfg.frame_stride 必须是正整数。');
end

frame_ids = 1:modal_cfg.frame_stride:stats.n_frames;
if isfield(modal_cfg, 'max_frames') && ~isempty(modal_cfg.max_frames) && ...
        numel(frame_ids) > modal_cfg.max_frames
    frame_ids = frame_ids(1:modal_cfg.max_frames);
end
if numel(frame_ids) < 3
    error('tblR2:modal_snapshot_matrix:TooFewFrames', ...
        '模态采样后少于三个等间隔帧。');
end

row_ids = 1:modal_cfg.spatial_stride(1):size(stats.X, 1);
candidate_cols = find(stats.X(1, :) >= modal_cfg.x_range_mm(1) & ...
    stats.X(1, :) <= modal_cfg.x_range_mm(2));
if isempty(candidate_cols)
    error('tblR2:modal_snapshot_matrix:EmptyROI', ...
        '模态 x 范围内没有网格列。');
end
col_ids = candidate_cols(1:modal_cfg.spatial_stride(2):end);
X_sub = stats.X(row_ids, col_ids);
Y_sub = mean_bl.wall_distance_mm(row_ids, col_ids);
Y_source_sub = stats.Y(row_ids, col_ids);
delta_grid = interp1(mean_bl.boundary_layer.x, ...
    mean_bl.boundary_layer.delta99, X_sub, 'linear', NaN);
spatial_mask = stats.accepted_mask(row_ids, col_ids) & ...
    isfinite(delta_grid) & delta_grid > 0 & ...
    Y_sub <= modal_cfg.max_y_over_delta .* delta_grid;
linear_mask = spatial_mask(:);
n_spatial = nnz(linear_mask);
if n_spatial < modal_cfg.n_modes
    error('tblR2:modal_snapshot_matrix:InsufficientDOF', ...
        '模态 ROI 只有 %d 个有效空间点，但请求了 %d 个模态。', ...
        n_spatial, modal_cfg.n_modes);
end

n_frames = numel(frame_ids);
X_snap = zeros(2 * n_spatial, n_frames, 'single');
batch = max(1, floor(cfg.chunk_frames / max(1, modal_cfg.frame_stride)));
for first = 1:batch:n_frames
    local = first:min(n_frames, first + batch - 1);
    ids = frame_ids(local);
    chunk = tblR2.read_cache_chunk(cache_file, ids, row_ids, col_ids, ...
        branch, stats, phase_stats);
    U = reshape(chunk.U, numel(local), []);
    V = reshape(chunk.V, numel(local), []);
    U = U(:, linear_mask);
    V = V(:, linear_mask);
    U(~isfinite(U)) = 0;
    V(~isfinite(V)) = 0;
    X_snap(:, local) = single([U'; V']);
end

sequence = struct();
sequence.X = X_snap;
sequence.frame_ids = frame_ids(:);
sequence.dt_s = modal_cfg.frame_stride / cfg.fs;
sequence.branch = branch;
sequence.row_ids = row_ids;
sequence.col_ids = col_ids;
sequence.X_grid_mm = X_sub;
sequence.Y_grid_mm = Y_sub;
sequence.Y_source_grid_mm = Y_source_sub;
sequence.delta99_grid_mm = delta_grid;
sequence.spatial_mask = spatial_mask;
sequence.n_spatial = n_spatial;
sequence.original_grid_size = size(stats.X);
sequence.sampling = struct('frame_stride', modal_cfg.frame_stride, ...
    'spatial_stride', modal_cfg.spatial_stride, ...
    'x_range_mm', modal_cfg.x_range_mm, ...
    'max_y_over_delta', modal_cfg.max_y_over_delta, ...
    'n_frames', n_frames, 'n_joint_dof', 2 * n_spatial);
end
