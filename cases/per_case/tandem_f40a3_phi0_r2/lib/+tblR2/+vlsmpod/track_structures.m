function tracking = track_structures(frame_store, ctx, options)
%TRACK_STRUCTURES 跨帧 overlap 追踪，建立 birth/continuation/split/merge/death 事件图。
%
% 依据 Lozano-Duran & Jimenez (2014) JFM 759 的时间追踪方法。
%
% 两条实测约束改变了设计，不能照搬文献参数
% ------------------------------------------------
% 1) 帧间对流位移约 49.6 格（外层 U_c=24.5 m/s, fs=960 Hz, dx=0.515 mm），
%    是 0.75*delta99。未补偿时任何 overlap 阈值都失配，所以 Galilean shift 是
%    必需项而非可选项。且剪切下 y/delta99=0.05 与 1.0 之间位移差 19 格，用单一
%    全局 U_c 会让近壁结构过度补偿——这里逐结构按其速度加权重心高度取 Uavex 的
%    行平均，残余位移 < 0.5 格。
%
% 2) FOV 只有 640 格 = 9.7*delta99，穿越时间约 12.9 帧。一个 3*delta99 长的
%    VLSM 头尾在 FOV 内只有约 8.9 帧活动空间。**所以寿命分布必然被 FOV 截断
%    严重低估**。输出里的 TouchesFovBoundary 标记哪些 track 的寿命是截断值；
%    汇总统计把截断与未截断分开报告，不给出未加说明的平均寿命。
%
% overlap 定义用 |A∩B| / min(|A|,|B|)：用 min 而非 union，对分裂/合并不敏感
% ——一个大结构裂成两半时，每半与母体的 union 比会掉到 0.5 以下而漏判，min 比
% 仍接近 1。
%
% 输入
%   frame_store : cell 数组，每元素 struct('frame_id', 'structures',
%                 'positive_labels', 'negative_labels')。要求帧号连续。
%   ctx         : tblR2.vlsmpod.prepare_context 的输出
%   options     : .overlap_threshold      默认 0.2
%                 .galilean_shift         默认 true
%                 .min_pixels_for_track   默认 0，只追踪足够大的结构
%
% 输出 tracking 结构体
%   .tracks       table，每行一条 track
%   .events       table，每行一个帧间事件
%   .summary      分截断/未截断的寿命统计与事件率

if nargin < 3 || isempty(options); options = struct(); end
overlap_threshold = pick(options, 'overlap_threshold', 0.2);
use_shift = pick(options, 'galilean_shift', true);
min_pixels = pick(options, 'min_pixels_for_track', 0);

n_frames = numel(frame_store);
if n_frames < 2
    error('tblR2:vlsmpod:track_structures:TooFewFrames', ...
        '时间追踪至少需要 2 帧，当前 %d 帧。', n_frames);
end
if isempty(frame_store{1}) || isempty(frame_store{1}.positive_labels)
    error('tblR2:vlsmpod:track_structures:MissingLabels', ...
        ['时间追踪需要标签图，但 frame_store 里没有。注意流向合并生效时标签图会' ...
        '被置空（合并重编了 StructureID），此时无法追踪——请关闭 merge。']);
end

% ------------------------------------------------ 每帧提取像素集与对流位移
frames = cell(n_frames, 1);
for k = 1:n_frames
    frames{k} = extract_frame(frame_store{k}, ctx, use_shift, min_pixels);
end

% -------------------------------------------------------- 帧间 overlap 匹配
% node_id 全局编号：(帧序号, 帧内序号) -> 唯一整数，供 union-find 用。
offsets = zeros(n_frames + 1, 1);
for k = 1:n_frames
    offsets(k + 1) = offsets(k) + numel(frames{k}.pixels);
end
n_nodes = offsets(end);
parent = (1:n_nodes)';

event_rows = cell(n_frames - 1, 1);
for k = 1:n_frames - 1
    event_rows{k} = match_pair(frames{k}, frames{k + 1}, ...
        offsets(k), offsets(k + 1), overlap_threshold, ctx);
    % 只有 1<->1 的 continuation 才把两个节点并进同一条 track。split/merge
    % 记录为事件但不合并链——否则一次分裂会把两条后继链错误地并成一条。
    e = event_rows{k};
    for r = 1:height(e)
        if strcmp(e.EventType{r}, 'continuation')
            parent = union_nodes(parent, e.NodeFrom(r), e.NodeTo(r));
        end
    end
end
events = vertcat(event_rows{:});

% ------------------------------------------------------------ 汇总为 track
tracks = build_tracks(frames, parent, offsets, n_nodes, events, ctx);

tracking = struct();
tracking.tracks = tracks;
tracking.events = events;
tracking.summary = summarize(tracks, events, ctx, n_frames, ...
    overlap_threshold, use_shift);
end

% =========================================================================
function f = extract_frame(store, ctx, use_shift, min_pixels)
%EXTRACT_FRAME 取该帧全部结构的像素集，并算各自的整数格对流位移。

T = store.structures;
n_positive = sum(T.Sign > 0);
nrows = height(T);

pixels = {};
shift_cells = [];
rows_kept = [];
for i = 1:nrows
    if T.PixelCount(i) < min_pixels
        continue;
    end
    idx = structure_pixels(T, i, store, n_positive);
    if isempty(idx)
        continue;
    end
    pixels{end + 1, 1} = idx; %#ok<AGROW>
    shift_cells(end + 1, 1) = convection_shift_cells( ...
        T, i, ctx, use_shift); %#ok<AGROW>
    rows_kept(end + 1, 1) = i; %#ok<AGROW>
end

f = struct();
f.frame_id = store.frame_id;
f.pixels = pixels;
f.shift_cells = shift_cells;
f.rows = rows_kept;
f.table = T(rows_kept, :);
end

% =========================================================================
function pixels = structure_pixels(T, row, store, n_positive)
if T.Sign(row) > 0
    label_image = store.positive_labels;
    label_value = T.StructureID(row);
else
    label_image = store.negative_labels;
    label_value = T.StructureID(row) - n_positive;
end
if label_value < 1
    pixels = [];
    return;
end
pixels = find(label_image == label_value);
end

% =========================================================================
function shift = convection_shift_cells(T, row, ctx, use_shift)
%CONVECTION_SHIFT_CELLS 逐结构的整数格流向位移。
%
% 用结构速度加权重心所在行的 Uavex 行平均作为该结构的对流速度。为什么不用全局
% 平均：实测 y/delta99=0.05 处位移 31.5 格、y/delta99=1.0 处 50.8 格，差 19 格
% ——足以让近壁结构完全失配。

shift = 0;
if ~use_shift
    return;
end
if isempty(ctx.Uavex) || ~isfinite(ctx.dt_s) || ~isfinite(ctx.dx_mm) || ...
        ctx.dx_mm <= 0
    return;
end

y_c = T.CentroidVelWeightedY_mm(row);
if ~isfinite(y_c)
    y_c = T.CentroidY_mm(row);
end
if ~isfinite(y_c)
    return;
end
[~, j] = min(abs(ctx.Y_wall_mm(:, 1) - y_c));
row_valid = ctx.analysis_domain_mask(j, :);
if ~any(row_valid)
    return;
end
u_c = mean(ctx.Uavex(j, row_valid), 'omitnan');
if ~isfinite(u_c)
    return;
end
% U 是 m/s，dt 是 s，dx 是 mm。
shift = round(u_c * ctx.dt_s * 1e3 / ctx.dx_mm);
end

% =========================================================================
function E = match_pair(fa, fb, offset_a, offset_b, threshold, ctx)
%MATCH_PAIR 两帧之间的 overlap 匹配与事件判定。

na = numel(fa.pixels);
nb = numel(fb.pixels);
E = empty_event_table();
if na == 0 && nb == 0
    return;
end

% overlap 矩阵。fa 的像素集先按各自位移平移，再与 fb 求交。
ov = zeros(na, nb);
shifted = cell(na, 1);
for i = 1:na
    shifted{i} = shift_pixels(fa.pixels{i}, fa.shift_cells(i), ctx);
end
for i = 1:na
    if isempty(shifted{i}); continue; end
    for j = 1:nb
        inter = numel(intersect(shifted{i}, fb.pixels{j}));
        if inter == 0; continue; end
        ov(i, j) = inter / min(numel(shifted{i}), numel(fb.pixels{j}));
    end
end

linked = ov >= threshold;
out_deg = sum(linked, 2);
in_deg = sum(linked, 1);

rows = {};
for i = 1:na
    targets = find(linked(i, :));
    if isempty(targets)
        rows{end + 1, 1} = make_event(fa, fb, i, NaN, offset_a, offset_b, ...
            'death', NaN); %#ok<AGROW>
        continue;
    end
    for t = targets
        if out_deg(i) == 1 && in_deg(t) == 1
            type = 'continuation';
        elseif out_deg(i) > 1
            type = 'split';
        else
            type = 'merge';
        end
        rows{end + 1, 1} = make_event(fa, fb, i, t, offset_a, offset_b, ...
            type, ov(i, t)); %#ok<AGROW>
    end
end
for j = 1:nb
    if in_deg(j) == 0
        rows{end + 1, 1} = make_event(fa, fb, NaN, j, offset_a, offset_b, ...
            'birth', NaN); %#ok<AGROW>
    end
end

if ~isempty(rows)
    E = vertcat(rows{:});
end
end

% =========================================================================
function idx = shift_pixels(pixels, shift_cells, ctx)
%SHIFT_PIXELS 把像素集在流向平移整数格，越界的丢掉。

if shift_cells == 0
    idx = pixels;
    return;
end
[r, c] = ind2sub([ctx.J, ctx.I], pixels);
c = c + shift_cells;
keep = c >= 1 & c <= ctx.I;
if ~any(keep)
    idx = [];
    return;
end
idx = sub2ind([ctx.J, ctx.I], r(keep), c(keep));
end

% =========================================================================
function E = make_event(fa, fb, i, j, offset_a, offset_b, type, ov)
node_from = NaN;
node_to = NaN;
frame_from = fa.frame_id;
frame_to = fb.frame_id;
if isfinite(i); node_from = offset_a + i; end
if isfinite(j); node_to = offset_b + j; end
E = table(frame_from, frame_to, node_from, node_to, {type}, ov, ...
    'VariableNames', {'FrameFrom', 'FrameTo', 'NodeFrom', 'NodeTo', ...
    'EventType', 'Overlap'});
end

% =========================================================================
function E = empty_event_table()
E = table('Size', [0 6], 'VariableTypes', ...
    {'double', 'double', 'double', 'double', 'cell', 'double'}, ...
    'VariableNames', {'FrameFrom', 'FrameTo', 'NodeFrom', 'NodeTo', ...
    'EventType', 'Overlap'});
end

% =========================================================================
function parent = union_nodes(parent, a, b)
if ~isfinite(a) || ~isfinite(b); return; end
ra = find_root(parent, a);
rb = find_root(parent, b);
if ra ~= rb
    parent(rb) = ra;
end
end

% =========================================================================
function r = find_root(parent, x)
r = x;
while parent(r) ~= r
    r = parent(r);
end
end

% =========================================================================
function tracks = build_tracks(frames, parent, offsets, n_nodes, events, ctx)
%BUILD_TRACKS 把 union-find 的分组整理成 track 表。

if n_nodes == 0
    tracks = empty_track_table();
    return;
end

root_of = zeros(n_nodes, 1);
for k = 1:n_nodes
    root_of(k) = find_root(parent, k);
end
roots = unique(root_of);

n_tracks = numel(roots);
track_id = (1:n_tracks)';
first_frame = nan(n_tracks, 1);
last_frame = nan(n_tracks, 1);
lifetime = nan(n_tracks, 1);
max_pixels = nan(n_tracks, 1);
mean_pixels = nan(n_tracks, 1);
max_len_delta = nan(n_tracks, 1);
n_splits = zeros(n_tracks, 1);
n_merges = zeros(n_tracks, 1);
touches_fov = false(n_tracks, 1);
any_vlsm = false(n_tracks, 1);

% 事件按起点节点归到 track
split_nodes = events.NodeFrom(strcmp(events.EventType, 'split'));
merge_nodes = events.NodeTo(strcmp(events.EventType, 'merge'));

for t = 1:n_tracks
    members = find(root_of == roots(t));
    [frame_pos, local_idx] = node_to_frame(members, offsets);
    first_frame(t) = frames{min(frame_pos)}.frame_id;
    last_frame(t) = frames{max(frame_pos)}.frame_id;
    lifetime(t) = numel(unique(frame_pos));

    px = zeros(numel(members), 1);
    lx = nan(numel(members), 1);
    vl = false(numel(members), 1);
    touch = false;
    for m = 1:numel(members)
        f = frames{frame_pos(m)};
        px(m) = numel(f.pixels{local_idx(m)});
        row = f.table(local_idx(m), :);
        lx(m) = row.LengthX_over_delta;
        vl(m) = row.IsVLSM;
        [~, cols] = ind2sub([ctx.J, ctx.I], f.pixels{local_idx(m)});
        if any(cols <= 1) || any(cols >= ctx.I)
            touch = true;
        end
    end
    max_pixels(t) = max(px);
    mean_pixels(t) = mean(px);
    max_len_delta(t) = max(lx, [], 'omitnan');
    any_vlsm(t) = any(vl);
    touches_fov(t) = touch;
    n_splits(t) = numel(intersect(members, split_nodes));
    n_merges(t) = numel(intersect(members, merge_nodes));
end

% 起止帧落在窗口两端的 track 其寿命也是截断的（进窗前/出窗后不可见）。
window_first = frames{1}.frame_id;
window_last = frames{numel(frames)}.frame_id;
touches_window = first_frame == window_first | last_frame == window_last;

tracks = table(track_id, first_frame, last_frame, lifetime, max_pixels, ...
    mean_pixels, max_len_delta, n_splits, n_merges, touches_fov, ...
    touches_window, any_vlsm, ...
    'VariableNames', {'TrackID', 'FirstFrame', 'LastFrame', ...
    'LifetimeFrames', 'MaxPixels', 'MeanPixels', 'MaxLengthX_over_delta', ...
    'NSplits', 'NMerges', 'TouchesFovBoundary', 'TouchesWindowEdge', ...
    'AnyVLSM'});
end

% =========================================================================
function [frame_pos, local_idx] = node_to_frame(nodes, offsets)
frame_pos = zeros(numel(nodes), 1);
local_idx = zeros(numel(nodes), 1);
for k = 1:numel(nodes)
    p = find(offsets < nodes(k), 1, 'last');
    frame_pos(k) = p;
    local_idx(k) = nodes(k) - offsets(p);
end
end

% =========================================================================
function T = empty_track_table()
T = table('Size', [0 12], 'VariableTypes', ...
    {'double', 'double', 'double', 'double', 'double', 'double', ...
    'double', 'double', 'double', 'logical', 'logical', 'logical'}, ...
    'VariableNames', {'TrackID', 'FirstFrame', 'LastFrame', ...
    'LifetimeFrames', 'MaxPixels', 'MeanPixels', 'MaxLengthX_over_delta', ...
    'NSplits', 'NMerges', 'TouchesFovBoundary', 'TouchesWindowEdge', ...
    'AnyVLSM'});
end

% =========================================================================
function s = summarize(tracks, events, ctx, n_frames, threshold, use_shift)
%SUMMARIZE 分截断/未截断报告寿命，避免给出被 FOV 截断污染的平均值。

s = struct();
s.n_tracks = height(tracks);
s.n_frames = n_frames;
s.overlap_threshold = threshold;
s.galilean_shift = use_shift;

% FOV 穿越时间：位移多大就能穿多快，这个数决定寿命统计的上限。
s.fov_cells = ctx.I;
s.median_shift_cells = NaN;
if ~isempty(ctx.Uavex) && isfinite(ctx.dt_s) && isfinite(ctx.dx_mm)
    u_out = mean(ctx.Uavex(ctx.analysis_domain_mask), 'omitnan');
    s.median_shift_cells = u_out * ctx.dt_s * 1e3 / ctx.dx_mm;
    s.fov_transit_frames = ctx.I / s.median_shift_cells;
else
    s.fov_transit_frames = NaN;
end

if isempty(tracks)
    s.n_censored = 0;
    s.n_uncensored = 0;
    s.lifetime_median_uncensored = NaN;
    s.lifetime_median_all_lower_bound = NaN;
    s.event_counts = table();
    return;
end

censored = tracks.TouchesFovBoundary | tracks.TouchesWindowEdge;
s.n_censored = sum(censored);
s.n_uncensored = sum(~censored);
s.censored_fraction = s.n_censored / height(tracks);

% 未截断子集的寿命是真值，但只覆盖短寿命结构——有选择偏差，必须与覆盖范围一起看。
if s.n_uncensored > 0
    s.lifetime_median_uncensored = median(tracks.LifetimeFrames(~censored));
    s.lifetime_max_uncensored = max(tracks.LifetimeFrames(~censored));
    s.uncensored_pixel_range = [min(tracks.MaxPixels(~censored)), ...
        max(tracks.MaxPixels(~censored))];
else
    s.lifetime_median_uncensored = NaN;
    s.lifetime_max_uncensored = NaN;
    s.uncensored_pixel_range = [NaN NaN];
end
% 全体寿命只能作为下限报告。
s.lifetime_median_all_lower_bound = median(tracks.LifetimeFrames);

% 分裂/合并有两种计数口径，数值不同，必须分开命名否则无法解释：
%   节点口径：发生了分裂的结构个数。一个结构裂成 3 份记 1。
%   链接口径：帧间链接条数。同一个结构裂成 3 份记 2（对应 event_counts）。
% 事件率用链接口径——「每帧对发生多少次分裂」问的是链接数。
s.n_structures_splitting = sum(tracks.NSplits);
s.n_structures_merging = sum(tracks.NMerges);
s.total_split_links = sum(strcmp(events.EventType, 'split'));
s.total_merge_links = sum(strcmp(events.EventType, 'merge'));
s.splits_per_frame_pair = s.total_split_links / max(1, n_frames - 1);
s.merges_per_frame_pair = s.total_merge_links / max(1, n_frames - 1);

types = {'birth', 'continuation', 'split', 'merge', 'death'};
counts = zeros(numel(types), 1);
for k = 1:numel(types)
    counts(k) = sum(strcmp(events.EventType, types{k}));
end
s.event_counts = table(types.', counts, ...
    'VariableNames', {'EventType', 'Count'});

s.caveats = build_caveats(s, tracks, n_frames);
end

% =========================================================================
function c = build_caveats(s, tracks, n_frames)
%BUILD_CAVEATS 把寿命统计的两个口径限制做成字段。
%
% 不做成字段的话，lifetime_median 被单独引用时会被当成物理寿命，而它实际由
% 两个非物理因素主导。

c = struct();

% 限制 1：FOV 截断。穿越时间就是寿命的硬上限，与湍流本身无关。
c.fov_transit_frames = s.fov_transit_frames;
c.max_lifetime_observed = max(tracks.LifetimeFrames);
c.lifetime_ceiling_is_fov = isfinite(s.fov_transit_frames) && ...
    c.max_lifetime_observed >= 0.8 * s.fov_transit_frames;
if c.lifetime_ceiling_is_fov
    c.fov_note = sprintf(['观测最大寿命 %.0f 帧已达 FOV 穿越时间 %.1f 帧的 ' ...
        '80%%以上——寿命上限由 FOV 决定，不是物理寿命。T ~ V^(1/3) 不可在此' ...
        '数据上拟合。'], c.max_lifetime_observed, s.fov_transit_frames);
else
    c.fov_note = '';
end

% 限制 2：split/merge 断链是本实现的设计选择（Lozano-Duran 同样把分裂视为
% track 终止 + 新分支）。它会机械地压低寿命中位数，与结构是否真的消亡无关。
c.chain_breaks_at_split_merge = true;
n_cont = s.event_counts.Count(strcmp(s.event_counts.EventType, 'continuation'));
% 用链接口径与 continuation 相加才是全部帧间链接数。
n_break = s.total_split_links + s.total_merge_links;
c.continuation_links = n_cont;
c.chain_breaking_links = n_break;
if n_cont + n_break > 0
    c.chain_break_fraction = n_break / (n_cont + n_break);
else
    c.chain_break_fraction = NaN;
end
c.design_note = ['split/merge 处按设计断链，占全部链接的 ' ...
    sprintf('%.0f%%', 100 * c.chain_break_fraction) ...
    '。寿命中位数因此被机械压低，不等于结构消亡时间。'];

% 限制 3：窗口长度。48 帧窗口本身也截断长寿命结构。
c.window_frames = n_frames;
c.window_adequate = isfinite(s.fov_transit_frames) && ...
    n_frames >= 4 * s.fov_transit_frames;
end

% =========================================================================
function value = pick(s, name, fallback)
value = fallback;
if isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
end
end
