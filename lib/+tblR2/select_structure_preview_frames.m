function sel = select_structure_preview_frames(structure_result)
%SELECT_STRUCTURE_PREVIEW_FRAMES 从结构目录挑选 3 张"代表帧"。
%   本函数只"读"结构目录（results.structures.catalog），不修改、不保存任何结果。
%   挑选规则（按约定）：
%     1. vlsm：一张含有 VLSM 的帧 —— 取"本帧最大 VLSM 最长"的那张（画图时只框 VLSM）；
%     2. lsm ：一张只有 LSM、不含 VLSM 的帧 —— 取"最大 LSM 最长"的那张（画图时只框 LSM）；
%     3. none：一张没有大结构（既无 LSM 也无 VLSM）的帧 —— 优先"结构总数最少"；
%              若每个带结构的帧都有 LSM/VLSM，就找"本帧一个结构都没有"的帧；
%              若连这种帧都没有，则选"最大结构最短"的帧并给出警告。
%   返回 sel.vlsm / sel.lsm / sel.none 三个子结构，每个含：
%     frame_id             帧号（[] = 没找到符合条件的帧）；
%     structures          该帧对应的结构行（vlsm 只含 VLSM 行、lsm 只含 LSM 行、
%                         none 为该帧全部小结构行，可能为空表）；
%     count                该帧要展示的结构个数；
%     max_length_over_delta 该帧这些结构中最大的 Lx/δ（无量纲长度，δ 为边界层厚度）。

sel = struct();
sel.vlsm = struct('frame_id', [], 'structures', table(), 'count', 0, ...
    'max_length_over_delta', NaN);
sel.lsm = struct('frame_id', [], 'structures', table(), 'count', 0, ...
    'max_length_over_delta', NaN);
sel.none = struct('frame_id', [], 'structures', table(), 'count', 0, ...
    'max_length_over_delta', NaN);

% —— 结果里没有结构目录：直接返回空选择（调用方会提示"跳过预览"）——
if isempty(structure_result) || ~isstruct(structure_result) || ...
        ~isfield(structure_result, 'catalog')
    fprintf('[代表帧挑选] 结果中没有结构目录，无法挑选代表帧。\n');
    return;
end
T = structure_result.catalog;
if ~istable(T) || height(T) == 0
    fprintf('[代表帧挑选] 结构目录为空（没识别出任何结构），无法挑选代表帧。\n');
    return;
end
cols = T.Properties.VariableNames;
need = {'FrameID', 'IsLSM', 'IsVLSM', 'LengthX_over_delta'};
if ~all(ismember(need, cols))
    fprintf('[代表帧挑选] 结构目录缺少必要列（%s），跳过挑选。\n', ...
        strjoin(setdiff(need, cols), ', '));
    return;
end

% 只统计"总脉动"这一支（baseline 只有 total；controlled 的 random 支不参与挑选）。
if ismember('Branch', cols)
    pick = strcmp(T.Branch, 'total');
    if any(pick)
        T = T(pick, :);
    end
end
if height(T) == 0
    fprintf('[代表帧挑选] total 支结构目录为空，无法挑选代表帧。\n');
    return;
end

% —— 按帧汇总：每帧有哪些结构、多大（accumarray 按帧分组）——
[frame_ids, ~, frame_index] = unique(T.FrameID, 'stable');   % 出现过的帧号
n_struct  = accumarray(frame_index, 1);                      % 每帧结构总数
has_lsm   = accumarray(frame_index, double(T.IsLSM)) > 0;    % 每帧是否含 LSM
has_vlsm  = accumarray(frame_index, double(T.IsVLSM)) > 0;   % 每帧是否含 VLSM
max_lsm   = accumarray(frame_index, ...
    T.LengthX_over_delta .* double(T.IsLSM), [], @max, NaN); % 每帧最大 LSM 长度
max_vlsm  = accumarray(frame_index, ...
    T.LengthX_over_delta .* double(T.IsVLSM), [], @max, NaN);% 每帧最大 VLSM 长度
max_any   = accumarray(frame_index, T.LengthX_over_delta, [], @max, NaN);

% ① 含 VLSM 的帧：VLSM 最长者优先；并列取最早出现的帧（max 返回第一个最大者）。
idx = find(has_vlsm);
if ~isempty(idx)
    [~, best] = max(max_vlsm(idx));
    sel.vlsm = make_entry(T, frame_ids(idx(best)), 'vlsm');
end

% ② 只有 LSM（没有 VLSM）的帧：LSM 最长者优先。
idx = find(has_lsm & ~has_vlsm);
if ~isempty(idx)
    [~, best] = max(max_lsm(idx));
    sel.lsm = make_entry(T, frame_ids(idx(best)), 'lsm');
end

% ③ 没有大结构（既无 LSM 也无 VLSM）的帧：优先"结构总数最少"、并列取最早。
idx = find(~has_lsm & ~has_vlsm);
if ~isempty(idx)
    [~, best] = min(n_struct(idx));
    sel.none = make_entry(T, frame_ids(idx(best)), 'none');
else
    % 目录里每个带结构的帧都有 LSM/VLSM：再找"目录里根本没出现"的帧（= 本帧 0 个结构）。
    n_total = [];
    if isfield(structure_result, 'processed_frame_count')
        n_total = structure_result.processed_frame_count;
    end
    if isempty(n_total) || ~isnumeric(n_total) || ~isscalar(n_total) || ...
            isnan(n_total) || n_total < 1
        n_total = max(frame_ids);
    end
    present = false(1, double(n_total));
    present(frame_ids(double(frame_ids) <= double(n_total))) = true;
    zero_frames = find(~present);
    if ~isempty(zero_frames)
        fid = zero_frames(1);
        sel.none = struct('frame_id', double(fid), 'structures', table(), ...
            'count', 0, 'max_length_over_delta', NaN);
        fprintf(['[代表帧挑选] 所有带结构的帧都含 LSM/VLSM；' ...
            '改选"本帧一个结构都没有"的帧 %d。\n'], fid);
    else
        % 兜底：选"最大结构最短"的帧（最接近没有大结构），并给出警告。
        [~, best] = min(max_any);
        sel.none = make_entry(T, frame_ids(best), 'none');
        fprintf(['[代表帧挑选] 警告：每个帧都含 LSM 或 VLSM；' ...
            '已选"最大结构最短"的帧 %d 代替。\n'], frame_ids(best));
    end
end

% —— 播报挑选结果 ——
fprintf('[代表帧挑选] 完成：%s；%s；%s。\n', ...
    describe(sel.vlsm, 'VLSM'), describe(sel.lsm, 'LSM'), ...
    describe(sel.none, '无大结构'));

    function e = make_entry(T, fid, key)
        % 取出某帧的结构行；vlsm/lsm 只保留对应类型，none 保留全部（小结构）。
        rows = T(T.FrameID == fid, :);
        if strcmp(key, 'vlsm')
            rows = rows(logical(rows.IsVLSM), :);
        elseif strcmp(key, 'lsm')
            rows = rows(logical(rows.IsLSM), :);
        end
        if height(rows) == 0
            e = struct('frame_id', fid, 'structures', table(), ...
                'count', 0, 'max_length_over_delta', NaN);
        else
            e = struct('frame_id', fid, 'structures', rows, ...
                'count', height(rows), ...
                'max_length_over_delta', max(rows.LengthX_over_delta));
        end
    end

    function s = describe(e, kind)
        % 把挑选结果变成一句话，方便看命令行。
        if isempty(e.frame_id)
            s = sprintf('%s帧：未找到符合条件的帧', kind);
        elseif e.count == 0
            s = sprintf('%s帧：第 %d 帧（本帧 0 个结构）', kind, e.frame_id);
        else
            s = sprintf('%s帧：第 %d 帧（%d 个结构，最长 Lx/δ=%.2f）', ...
                kind, e.frame_id, e.count, e.max_length_over_delta);
        end
    end

end
