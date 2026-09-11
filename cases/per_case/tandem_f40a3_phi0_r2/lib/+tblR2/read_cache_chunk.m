function chunk = read_cache_chunk(cache_file, frame_ids, row_ids, col_ids, ...
    branch, stats, phase_stats)
%READ_CACHE_CHUNK 读取原始、总脉动或随机脉动分支的数据块。
% =========================================================================
% 【合同（Section 3-8 逐块数据访问）】
%   - branch：'raw'（原始 U/V）、'total'（u'=u-Uavex，需要 stats）、
%     'random'（u''=u-U_phi，需要 stats 与 phase_stats 的 assignment/
%     U_phase/V_phase）。字段名 total/random 与 Section 3 分支命名一致。
%   - 输出 chunk.U/V 为 double（无效样本置 NaN），chunk.sampleValid 与
%     U/V 严格一致：分支变换后只要 U 或 V 非有限，sampleValid 即为 false
%     （例如随机分支中相位箱被拒绝、或 total 分支中均值点为 NaN）。
%   - frame_ids/row_ids/col_ids 必须为 1 到缓存尺寸内的正整数索引。
% =========================================================================

if nargin < 5 || isempty(branch)
    branch = 'raw';
end
if nargin < 6
    stats = [];
end
if nargin < 7
    phase_stats = [];
end
branch = char(branch);
if ~ismember(branch, {'raw', 'total', 'random'})
    error('tblR2:read_cache_chunk:InvalidBranch', ...
        'branch 必须是 raw、total 或 random。');
end

cache = matfile(cache_file);
inventory = whos(cache, 'U');
grid_size = size(cache.X);
grid_size(end + 1:2) = 1;
J = grid_size(1);
I = grid_size(2);
cache_size = inventory.size;
cache_size(end + 1:3) = 1;
validate_indices(frame_ids, cache_size(1), 'frame_ids');
validate_indices(row_ids, cache_size(2), 'row_ids');
validate_indices(col_ids, cache_size(3), 'col_ids');

if is_regular_index(frame_ids)
    U = double(tblR2.read_cache_frames(cache, 'U', frame_ids, J, I));
    V = double(tblR2.read_cache_frames(cache, 'V', frame_ids, J, I));
    source_valid = logical(tblR2.read_cache_frames( ...
        cache, 'sampleValid', frame_ids, J, I));
    U = U(:, row_ids, col_ids);
    V = V(:, row_ids, col_ids);
    source_valid = source_valid(:, row_ids, col_ids);
else
    U = nan(numel(frame_ids), numel(row_ids), numel(col_ids));
    V = nan(size(U));
    source_valid = false(size(U));
    for i = 1:numel(frame_ids)
        frame = tblR2.read_cache_frames(cache, 'U', frame_ids(i), J, I);
        U(i, :, :) = frame(1, row_ids, col_ids);
        frame = tblR2.read_cache_frames(cache, 'V', frame_ids(i), J, I);
        V(i, :, :) = frame(1, row_ids, col_ids);
        frame = tblR2.read_cache_frames(cache, 'sampleValid', ...
            frame_ids(i), J, I);
        source_valid(i, :, :) = frame(1, row_ids, col_ids);
    end
end
valid = source_valid & ...
    isfinite(U) & isfinite(V);
U(~valid) = NaN;
V(~valid) = NaN;

switch branch
    case 'total'
        require_stats(stats);
        if isfield(stats, 'repeat_means') && ~isempty(stats.repeat_means) && ...
                isfield(stats, 'repeat_boundaries') && ...
                ~isempty(stats.repeat_boundaries)
            % 双 repeat 脉动场：每帧减所属 repeat 的时间平均。
            rep = frame_to_repeat(frame_ids, stats.repeat_boundaries);
            U = U - reshape(stats.repeat_means(1, rep, row_ids, col_ids), ...
                size(U));
            V = V - reshape(stats.repeat_means(2, rep, row_ids, col_ids), ...
                size(V));
        else
            U = U - reshape(stats.Uavex(row_ids, col_ids), ...
                1, numel(row_ids), numel(col_ids));
            V = V - reshape(stats.Vavex(row_ids, col_ids), ...
                1, numel(row_ids), numel(col_ids));
        end
    case 'random'
        require_stats(stats);
        has_native_phase = ~isempty(phase_stats) && ...
            isfield(phase_stats, 'U_phase') && isfield(phase_stats, 'V_phase');
        has_repeat_phase = ~isempty(phase_stats) && ...
            isfield(phase_stats, 'U_phase_rep') && ...
            isfield(phase_stats, 'V_phase_rep') && ...
            ~isempty(phase_stats.U_phase_rep);
        if isempty(phase_stats) || ~isfield(phase_stats, 'assignment') || ...
                (~has_native_phase && ~has_repeat_phase)
            error('tblR2:read_cache_chunk:MissingPhaseStatistics', ...
                'random 分支需要相位均值和帧到相位箱的分配结果。');
        end
        bins = phase_bins_for_frames(phase_stats, frame_ids);
        if has_repeat_phase
            % 双 repeat 随机脉动场：每帧减所属 repeat 的相位平均。
            if ~isfield(phase_stats, 'repeat_boundaries') || ...
                    (isempty(phase_stats.repeat_boundaries) && ...
                    size(phase_stats.U_phase_rep, 1) > 1)
                error('tblR2:read_cache_chunk:MissingRepeatMetadata', ...
                    '双 repeat 相位结果缺少 repeat_boundaries 元数据。');
            end
            rep = frame_to_repeat(frame_ids, phase_stats.repeat_boundaries);
            U_phase = zeros(size(U));
            V_phase = zeros(size(V));
            for r = 1:size(phase_stats.U_phase_rep, 1)
                sel = rep == r;
                if ~any(sel)
                    continue;
                end
                n_selected = nnz(sel);
                phase_u = phase_stats.U_phase_rep(r, bins(sel), row_ids, col_ids);
                phase_v = phase_stats.V_phase_rep(r, bins(sel), row_ids, col_ids);
                % 明确恢复 [选中帧数,行数,列数]，避免 singleton 维度被压缩。
                phase_u = reshape(phase_u, [n_selected, numel(row_ids), numel(col_ids)]);
                phase_v = reshape(phase_v, [n_selected, numel(row_ids), numel(col_ids)]);
                U_phase(sel, :, :) = phase_u;
                V_phase(sel, :, :) = phase_v;
            end
        else
            U_phase = reshape(phase_stats.U_phase(bins, row_ids, col_ids), ...
                [numel(frame_ids), numel(row_ids), numel(col_ids)]);
            V_phase = reshape(phase_stats.V_phase(bins, row_ids, col_ids), ...
                [numel(frame_ids), numel(row_ids), numel(col_ids)]);
        end
        U = U - U_phase;
        V = V - V_phase;
end

% 分支变换后重新同步有效掩膜：NaN 均值点/拒绝相位箱的样本一并视为无效。
valid = valid & isfinite(U) & isfinite(V);
U(~valid) = NaN;
V(~valid) = NaN;

chunk = struct('U', U, 'V', V, 'sampleValid', valid, ...
    'frame_ids', double(frame_ids(:)), 'branch', branch);
end

function tf = is_regular_index(value)
value = double(value(:));
if numel(value) == 1
    tf = true;
else
    step = diff(value(1:2));
    tf = step == 1 && all(diff(value) == step);
end
end

function require_stats(stats)
if isempty(stats) || ~isfield(stats, 'Uavex') || ~isfield(stats, 'Vavex')
    error('tblR2:read_cache_chunk:MissingStatistics', ...
        'total/random 分支需要时间平均 statistics 结构。');
end
end

function validate_indices(value, upper, name)
if ~(isnumeric(value) && isvector(value) && ~isempty(value) && ...
        all(isfinite(value)) && all(value == fix(value)) && ...
        all(value >= 1) && all(value <= upper))
    error('tblR2:read_cache_chunk:InvalidIndices', ...
        '%s 必须是 1 到 %d 范围内的整数索引。', name, upper);
end
end

function rep = frame_to_repeat(frame_ids, repeat_boundaries)
%FRAME_TO_REPEAT Map frame indices to their repeat number.
rep = ones(numel(frame_ids), 1);
for r = 2:numel(repeat_boundaries) + 1
    rep(frame_ids > repeat_boundaries(r - 1)) = r;
end
end

function bins = phase_bins_for_frames(phase_stats, frame_ids)
%PHASE_BINS_FOR_FRAMES Accept both assign_phase vectors and function handles.
if ~isfield(phase_stats, 'assignment') || ...
        ~isfield(phase_stats.assignment, 'bin_index')
    error('tblR2:read_cache_chunk:InvalidPhaseAssignment', ...
        'phase_stats.assignment 必须包含 bin_index。');
end
source = phase_stats.assignment.bin_index;
if isa(source, 'function_handle')
    bins = source(frame_ids);
elseif isnumeric(source) && isvector(source) && ...
        all(frame_ids >= 1) && all(frame_ids <= numel(source))
    bins = source(frame_ids);
else
    error('tblR2:read_cache_chunk:InvalidPhaseAssignment', ...
        'bin_index 必须是帧索引向量或函数句柄，且覆盖请求帧。');
end
bins = double(bins(:));
if isfield(phase_stats, 'U_phase') && ~isempty(phase_stats.U_phase)
    n_bins = size(phase_stats.U_phase, 1);
elseif isfield(phase_stats, 'U_phase_rep') && ~isempty(phase_stats.U_phase_rep)
    n_bins = size(phase_stats.U_phase_rep, 2);
else
    error('tblR2:read_cache_chunk:MissingPhaseMean', ...
        'phase_stats 必须包含 U_phase 或 U_phase_rep。');
end
if any(~isfinite(bins) | bins < 1 | bins > n_bins | bins ~= fix(bins))
    error('tblR2:read_cache_chunk:InvalidPhaseBin', ...
        '请求帧包含超出相位均值范围的相位箱。');
end
end
