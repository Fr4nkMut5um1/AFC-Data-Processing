function reconstruction = pod_reconstruction(cache_file, cfg, stats, ...
    phase_stats, mean_bl, branch, pod_result, varargin)
%POD_RECONSTRUCTION Reconstruct sampled POD snapshots and add the physical mean.
%
% This is the array/cache equivalent of the legacy
% velocity_reconstrction_POD helper.  The legacy helper accepted cell arrays
% and silently assumed a full rectangular grid.  r2 keeps the sampled ROI
% mask and returns frame-major arrays with dimensions [frame row column].

parser = inputParser;
parser.addParameter('frame_positions', [], @(x) isempty(x) || ...
    (isnumeric(x) && isvector(x)));
parser.addParameter('frame_start', [], @(x) isempty(x) || ...
    (isnumeric(x) && isscalar(x) && isfinite(x) && x == fix(x)));
parser.addParameter('frame_count', [], @(x) isempty(x) || ...
    (isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1 && x == fix(x)));
parser.addParameter('n_modes', [], @(x) isempty(x) || ...
    (isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1 && x == fix(x)));
parser.addParameter('mode_indices', [], @(x) isempty(x) || ...
    (isnumeric(x) && isvector(x)));
parser.addParameter('add_mean', true, @(x) islogical(x) || isnumeric(x));
parser.addParameter('include_raw', true, @(x) islogical(x) || isnumeric(x));
parser.addParameter('sequence', [], @(x) isempty(x) || isstruct(x));
parser.parse(varargin{:});
opts = parser.Results;
branch = lower(char(branch));
if ~ismember(branch, {'total', 'random'})
    error('tblR2:pod_reconstruction:InvalidBranch', ...
        'POD 重构 branch 必须是 total 或 random。');
end

if ~isstruct(pod_result) || ~all(isfield(pod_result, ...
        {'joint_modes','temporal_coefficients','sampling'}))
    error('tblR2:pod_reconstruction:InvalidPOD', ...
        'pod_result 必须包含 joint_modes、temporal_coefficients 和 sampling。');
end

% Rebuild exactly the sequence used by pod_cache.  This prevents a caller
% from accidentally applying modes to a different ROI or frame decimation.
if isempty(opts.sequence)
    sequence = tblR2.modal_snapshot_matrix(cache_file, cfg, stats, ...
        phase_stats, mean_bl, branch, cfg.pod);
else
    sequence = opts.sequence;
end
required_sequence = {'X','frame_ids','row_ids','col_ids','n_spatial', ...
    'spatial_mask','X_grid_mm','Y_grid_mm','sampling'};
if ~all(isfield(sequence, required_sequence))
    error('tblR2:pod_reconstruction:InvalidSequence', ...
        'sequence 缺少 POD 重构所需的采样、网格或帧字段。');
end
n_frames = size(sequence.X, 2);
if isempty(opts.frame_positions) && ~isempty(opts.frame_start)
    first = double(opts.frame_start);
    count = 1;
    if ~isempty(opts.frame_count); count = double(opts.frame_count); end
    positions = first:(first + count - 1);
elseif isempty(opts.frame_positions)
    positions = unique([1, ceil(n_frames / 2), n_frames]);
else
    positions = unique(double(opts.frame_positions(:).'));
end
if any(~isfinite(positions) | positions < 1 | positions > n_frames | ...
        positions ~= fix(positions))
    error('tblR2:pod_reconstruction:InvalidFramePositions', ...
        'frame_positions 必须是 sequence 中的整数位置。');
end

n_available = min([size(pod_result.joint_modes, 2), ...
    size(pod_result.temporal_coefficients, 2)]);
if isempty(opts.mode_indices)
    if isempty(opts.n_modes)
        mode_indices = 1:n_available;
    else
        mode_indices = 1:min(double(opts.n_modes), n_available);
    end
else
    mode_indices = unique(double(opts.mode_indices(:).'), 'stable');
    if any(~isfinite(mode_indices) | mode_indices < 1 | ...
            mode_indices > n_available | mode_indices ~= fix(mode_indices))
        error('tblR2:pod_reconstruction:InvalidModeIndices', ...
            'mode_indices 必须是 POD 结果范围内的正整数。');
    end
end
n_modes = numel(mode_indices);
if n_modes < 1
    error('tblR2:pod_reconstruction:InvalidModeCount', ...
        '至少需要保留一个 POD 模态。');
end

positions = positions(:).';
frame_ids = sequence.frame_ids(positions);
frame_ids = double(frame_ids(:).');
if any(~isfinite(frame_ids) | frame_ids < 1 | frame_ids ~= fix(frame_ids))
    error('tblR2:pod_reconstruction:InvalidFrameIds', ...
        'sequence.frame_ids 必须是正整数帧号。');
end
row_ids = sequence.row_ids;
col_ids = sequence.col_ids;
n_rows = numel(row_ids);
n_cols = numel(col_ids);
n_spatial = sequence.n_spatial;
n_selected = numel(positions);
if size(pod_result.joint_modes, 1) ~= 2 * n_spatial
    error('tblR2:pod_reconstruction:JointModeSizeMismatch', ...
        'joint_modes 行数必须等于 2*sequence.n_spatial。');
end

% Raw data is read only for the selected frames.  It is retained in the
% output by default because it is useful for residual and quality plots.
raw_U = nan(n_selected, n_rows, n_cols);
raw_V = nan(n_selected, n_rows, n_cols);
if logical(opts.include_raw)
    raw_chunk = tblR2.read_cache_chunk(cache_file, frame_ids, row_ids, ...
        col_ids, 'raw', [], []);
    raw_U = raw_chunk.U;
    raw_V = raw_chunk.V;
end

% The modal input is a fluctuation field.  Build its physical mean per
% frame: total branch uses repeat means when available; random branch uses
% the phase mean; legacy/single-repeat data falls back to statistics mean.
mean_U = zeros(n_selected, n_rows, n_cols);
mean_V = zeros(n_selected, n_rows, n_cols);
for k = 1:n_selected
    mean_pair = branch_mean(frame_ids(k), branch, stats, phase_stats, ...
        row_ids, col_ids);
    mean_U(k, :, :) = mean_pair.U;
    mean_V(k, :, :) = mean_pair.V;
end

joint_modes = double(pod_result.joint_modes(:, mode_indices));
coefficients = double(pod_result.temporal_coefficients(positions, mode_indices));
modal_mean_snapshot = zeros(size(joint_modes, 1), 1);
if isfield(pod_result, 'mean_snapshot') && ~isempty(pod_result.mean_snapshot)
    if ~isequal(size(pod_result.mean_snapshot), size(modal_mean_snapshot))
        error('tblR2:pod_reconstruction:MeanSnapshotMismatch', ...
            'pod_result.mean_snapshot 尺寸必须与 joint_modes 的自由度一致。');
    end
    modal_mean_snapshot = double(pod_result.mean_snapshot);
end
fluctuation = joint_modes * coefficients.' + modal_mean_snapshot;
reconstructed_U = nan(n_selected, n_rows, n_cols);
reconstructed_V = nan(n_selected, n_rows, n_cols);
for k = 1:n_selected
    u_vec = fluctuation(1:n_spatial, k);
    v_vec = fluctuation(n_spatial + 1:end, k);
    u_field = nan(n_rows, n_cols);
    v_field = nan(n_rows, n_cols);
    u_field(sequence.spatial_mask) = u_vec;
    v_field(sequence.spatial_mask) = v_vec;
    reconstructed_U(k, :, :) = u_field;
    reconstructed_V(k, :, :) = v_field;
end

if logical(opts.add_mean)
    reconstructed_U = reconstructed_U + mean_U;
    reconstructed_V = reconstructed_V + mean_V;
end

raw_fluctuation_U = raw_U - mean_U;
raw_fluctuation_V = raw_V - mean_V;
residual_U = raw_fluctuation_U - (reconstructed_U - mean_U);
residual_V = raw_fluctuation_V - (reconstructed_V - mean_V);
relative_error = nan(n_selected, 1);
for k = 1:n_selected
    target = [reshape(raw_fluctuation_U(k, :, :), [], 1); ...
        reshape(raw_fluctuation_V(k, :, :), [], 1)];
    estimate = [reshape(reconstructed_U(k, :, :) - mean_U(k, :, :), [], 1); ...
        reshape(reconstructed_V(k, :, :) - mean_V(k, :, :), [], 1)];
    valid = isfinite(target) & isfinite(estimate);
    if any(valid)
        relative_error(k) = norm(target(valid) - estimate(valid)) / ...
            max(norm(target(valid)), eps);
    end
end

reconstruction = struct();
reconstruction.frame_positions = positions(:);
reconstruction.frame_ids = double(frame_ids(:));
reconstruction.n_modes = n_modes;
reconstruction.mode_indices = mode_indices(:);
reconstruction.added_mean = logical(opts.add_mean);
reconstruction.mean_U = mean_U;
reconstruction.mean_V = mean_V;
reconstruction.modal_mean_snapshot = modal_mean_snapshot;
reconstruction.raw_U = raw_U;
reconstruction.raw_V = raw_V;
reconstruction.raw_fluctuation_U = raw_fluctuation_U;
reconstruction.raw_fluctuation_V = raw_fluctuation_V;
reconstruction.reconstructed_fluctuation_U = reconstructed_U - mean_U;
reconstruction.reconstructed_fluctuation_V = reconstructed_V - mean_V;
reconstruction.reconstructed_U = reconstructed_U;
reconstruction.reconstructed_V = reconstructed_V;
reconstruction.residual_U = residual_U;
reconstruction.residual_V = residual_V;
reconstruction.relative_error = relative_error;
reconstruction.sampling = sequence.sampling;
reconstruction.X_grid_mm = sequence.X_grid_mm;
reconstruction.Y_grid_mm = sequence.Y_grid_mm;
reconstruction.mask = sequence.spatial_mask;
if isfield(sequence, 'original_grid_size')
    original_size = sequence.original_grid_size;
    full_U = nan(n_selected, original_size(1), original_size(2));
    full_V = nan(size(full_U));
    % Use an explicit frame loop here.  MATLAB's multi-vector indexing on a
    % 3-D array can collapse singleton dimensions differently across releases;
    % the loop keeps the [frame,row,col] contract unambiguous.
    for k = 1:n_selected
        u_full = reshape(full_U(k, :, :), original_size);
        v_full = reshape(full_V(k, :, :), original_size);
        u_full(row_ids, col_ids) = reshape(reconstructed_U(k, :, :), ...
            [n_rows n_cols]);
        v_full(row_ids, col_ids) = reshape(reconstructed_V(k, :, :), ...
            [n_rows n_cols]);
        full_U(k, :, :) = reshape(u_full, [1 original_size]);
        full_V(k, :, :) = reshape(v_full, [1 original_size]);
    end
    reconstruction.full_grid_U = full_U;
    reconstruction.full_grid_V = full_V;
    reconstruction.full_grid_mask = false(original_size);
    reconstruction.full_grid_mask(row_ids, col_ids) = sequence.spatial_mask;
end
reconstruction.definition = ['POD reconstruction on the modal ROI: ' ...
    'sum_k a_k(t) phi_k plus the physical branch mean. ' ...
    'Invalid PIV samples remain NaN in raw fields and outside the ROI.'];
end

function pair = branch_mean(frame_id, branch, stats, phase_stats, row_ids, col_ids)
pair = struct('U', zeros(1, numel(row_ids), numel(col_ids)), ...
    'V', zeros(1, numel(row_ids), numel(col_ids)));
if strcmp(branch, 'random')
    if isempty(phase_stats) || ~isfield(phase_stats, 'assignment')
        error('tblR2:pod_reconstruction:MissingPhaseStatistics', ...
            'random 分支需要 phase_stats。');
    end
    if ~isfield(phase_stats.assignment, 'bin_index')
        error('tblR2:pod_reconstruction:InvalidPhaseAssignment', ...
            'phase_stats.assignment 缺少 bin_index。');
    end
    bin_index = phase_stats.assignment.bin_index;
    if isa(bin_index, 'function_handle')
        bin = bin_index(frame_id);
    elseif isnumeric(bin_index) && isvector(bin_index) && ...
            frame_id <= numel(bin_index)
        bin = bin_index(frame_id);
    else
        error('tblR2:pod_reconstruction:InvalidPhaseAssignment', ...
            'phase_stats.assignment.bin_index 必须是帧索引向量或函数句柄。');
    end
    validate_phase_bin(bin, phase_stats, frame_id);
    if isfield(phase_stats, 'U_phase_rep') && ...
            ~isempty(phase_stats.U_phase_rep)
        if ~isfield(phase_stats, 'V_phase_rep') || ...
                ~isequal(size(phase_stats.U_phase_rep), size(phase_stats.V_phase_rep))
            error('tblR2:pod_reconstruction:PhaseMeanSizeMismatch', ...
                'U_phase_rep/V_phase_rep 尺寸不一致或 V_phase_rep 缺失。');
        end
        if ~isfield(phase_stats, 'repeat_boundaries')
            error('tblR2:pod_reconstruction:MissingRepeatMetadata', ...
                '双 repeat 相位结果缺少 repeat_boundaries。');
        end
        boundaries = validate_repeat_boundaries(phase_stats.repeat_boundaries, ...
            size(phase_stats.U_phase_rep, 1));
        rep = 1 + sum(frame_id > boundaries);
        pair.U = reshape(phase_stats.U_phase_rep(rep, bin, row_ids, col_ids), ...
            [1 numel(row_ids) numel(col_ids)]);
        pair.V = reshape(phase_stats.V_phase_rep(rep, bin, row_ids, col_ids), ...
            [1 numel(row_ids) numel(col_ids)]);
    else
        pair.U = reshape(phase_stats.U_phase(bin, row_ids, col_ids), ...
            [1 numel(row_ids) numel(col_ids)]);
        pair.V = reshape(phase_stats.V_phase(bin, row_ids, col_ids), ...
            [1 numel(row_ids) numel(col_ids)]);
    end
    return;
end
if strcmp(branch, 'total') && isfield(stats, 'repeat_means') && ...
        ~isempty(stats.repeat_means)
    if ~isfield(stats, 'repeat_boundaries')
        error('tblR2:pod_reconstruction:MissingRepeatMetadata', ...
            '双 repeat statistics 缺少 repeat_boundaries。');
    end
    boundaries = validate_repeat_boundaries(stats.repeat_boundaries, ...
        size(stats.repeat_means, 2));
    rep = 1 + sum(frame_id > boundaries);
    pair.U = reshape(stats.repeat_means(1, rep, row_ids, col_ids), ...
        [1 numel(row_ids) numel(col_ids)]);
    pair.V = reshape(stats.repeat_means(2, rep, row_ids, col_ids), ...
        [1 numel(row_ids) numel(col_ids)]);
else
    if ~isfield(stats, 'Uavex') || ~isfield(stats, 'Vavex')
        error('tblR2:pod_reconstruction:MissingStatistics', ...
            'POD 重构需要 statistics.Uavex/Vavex。');
    end
    pair.U = reshape(stats.Uavex(row_ids, col_ids), ...
        [1 numel(row_ids) numel(col_ids)]);
    pair.V = reshape(stats.Vavex(row_ids, col_ids), ...
        [1 numel(row_ids) numel(col_ids)]);
end
end

function validate_phase_bin(bin, phase_stats, frame_id)
if ~(isscalar(bin) && isfinite(bin) && bin == fix(bin) && bin >= 1)
    error('tblR2:pod_reconstruction:InvalidPhaseBin', ...
        '帧 %d 映射到了无效的相位箱。', frame_id);
end
if isfield(phase_stats, 'U_phase') && ~isempty(phase_stats.U_phase)
    n_bins = size(phase_stats.U_phase, 1);
elseif isfield(phase_stats, 'U_phase_rep') && ~isempty(phase_stats.U_phase_rep)
    n_bins = size(phase_stats.U_phase_rep, 2);
else
    error('tblR2:pod_reconstruction:MissingPhaseMean', ...
        'phase_stats 缺少 U_phase/U_phase_rep。');
end
if bin > n_bins
    error('tblR2:pod_reconstruction:InvalidPhaseBin', ...
        '帧 %d 的相位箱 %d 超出结果范围 %d。', frame_id, bin, n_bins);
end
if isfield(phase_stats, 'U_phase') && ~isempty(phase_stats.U_phase)
    if ~isfield(phase_stats, 'V_phase') || ...
            ~isequal(size(phase_stats.U_phase), size(phase_stats.V_phase))
        error('tblR2:pod_reconstruction:PhaseMeanSizeMismatch', ...
            'U_phase/V_phase 尺寸不一致或 V_phase 缺失。');
    end
end
end

function boundaries = validate_repeat_boundaries(raw, n_repeats)
boundaries = double(raw(:).');
if isempty(boundaries)
    if n_repeats ~= 1
        error('tblR2:pod_reconstruction:InvalidRepeatMetadata', ...
            'repeat_means 的 repeat 数与 repeat_boundaries 不一致。');
    end
    return;
end
if numel(boundaries) ~= n_repeats - 1 || any(~isfinite(boundaries)) || ...
        any(boundaries < 1) || any(diff(boundaries) <= 0)
    error('tblR2:pod_reconstruction:InvalidRepeatMetadata', ...
        'repeat_boundaries 必须是严格递增且长度为 nRepeats-1。');
end
end
