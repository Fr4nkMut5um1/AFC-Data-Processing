function stats = mean_stats_cache(cache_file, min_valid_fraction, chunk_frames, Uinf, stats_frame_range)
%MEAN_STATS_CACHE Streaming per-sample time statistics from the disk cache.
% =========================================================================
% 【合同（Section 2 statistics 阶段，与 mat/02_statistics.mat 一致）】
%   - 输入：mat/01_sequence_cache.mat（schema_version=2 双 repeat 或 v1）。
%     U/V/sampleValid 为 n_frames×J×I（单精度/逻辑），X/Y 为 J×I mm 网格，
%     h_mm 为标量 mm。可选第 5 参 stats_frame_range=[start,end]（闭区间，
%     缓存内绝对帧号）只对子区间统计；缺省或为空则统计整个缓存序列。
%   - 输出字段固定：Uavex/Vavex/u_rms/v_rms/uu_rey/vv_rey/uv_rey/TKE/
%     valid_count/valid_fraction/accepted_mask/X/Y/h/n_frames/definition。
%     tblR2.stats.prepare_case_views 与 Section 3-8 依赖这些字段名，不得改名。
%     n_frames 语义=本次实际参与统计的帧数（有子区间时为区间长度）。
%   - 双 repeat（v2）口径：
%       * 平均场拼接：Uavex/Vavex 直接对拼接后的 2*n_frames 帧整体平均
%         （等价于两 repeat 数据前后拼接成 12000 帧后处理）。
%       * 脉动场拼接：uu/vv/uv/TKE/u_rms 先对每个 repeat 分别取平均、再
%         各自减去其平均得到该 repeat 的脉动量，最后将两 repeat 的脉动量
%         前后拼接成 12000 帧序列统一统计（消除 repeat 间系统偏移）。
%     v1 单 repeat 缓存无 repeat_means，两口径自动退化为同一结果。
%   - 逐块读取：每批 chunk_frames 帧，任何时刻内存至多一个数据块，
%     绝不一次载入全部帧（12000 帧单精度缓存约 2-4 GB）。
%   - 每点只使用其自身有效样本（sampleValid 且有限）计算总体矩：
%     uu=M2_u/count、uv=-M_uv/count（负的雷诺剪切应力）；count<2 或
%     valid_fraction<min_valid_fraction 的点统计量置 NaN（等于阈值保留）。
%   - 数值口径：块间合并用 Chan-Golub-LeVeque（Welford 家族）恒等式
%     M2' = M2 + M2_c + nA*nB/(nA+nB)*(mB-mA)^2（协方差同构），
%     避免 sum(X^2)/n - mean^2 的灾难性抵消；与旧的 sum-of-squares
%     总体矩口径在精确算术下完全等价。chunk_frames 只影响 I/O 粒度，
%     不改变结果。
% =========================================================================

if ~(isscalar(min_valid_fraction) && min_valid_fraction > 0 && ...
        min_valid_fraction <= 1)
    error('tblR2:mean_stats_cache:InvalidValidFraction', ...
        'min_valid_fraction 必须位于 (0,1] 内。');
end
if ~(isscalar(chunk_frames) && chunk_frames == fix(chunk_frames) && ...
        chunk_frames >= 1)
    error('tblR2:mean_stats_cache:InvalidChunkSize', ...
        'chunk_frames 必须是正整数。');
end
if nargin < 4 || isempty(Uinf)
    Uinf = 25;  % 名义来流速度，用于 TKE 无量纲化（对齐 averagedU_TKE）。
end
if ~(isnumeric(Uinf) && isscalar(Uinf) && isfinite(Uinf) && Uinf > 0)
    error('tblR2:mean_stats_cache:InvalidUinf', ...
        'Uinf 必须是有限正标量。');
end

cache = matfile(cache_file);
required_vars = {'U', 'V', 'sampleValid', 'X', 'Y', 'h_mm'};
missing = required_vars(~cellfun(@(name) has_variable(cache, name), ...
    required_vars));
if ~isempty(missing)
    error('tblR2:mean_stats_cache:MissingCacheVariable', ...
        ['序列缓存缺少变量：%s。缓存可能过期或不完整；请将 ' ...
         'cfg.stages.cache 设为 compute 后重新构建。'], ...
        strjoin(missing, ', '));
end

item = whos(cache, 'U');
cache_size = item.size;
cache_size(end + 1:3) = 1;
n_frames = cache_size(1);
J = cache_size(2);
I = cache_size(3);
if ~isequal(size(cache.X), [J I]) || ~isequal(size(cache.Y), [J I])
    error('tblR2:mean_stats_cache:GridSizeMismatch', ...
        ['cache.X/cache.Y 必须是与 U/V 匹配的 %d×%d 网格；当前缓存网格不符。'], ...
        J, I);
end
if ~(isscalar(cache.h_mm) && isfinite(cache.h_mm) && cache.h_mm > 0)
    error('tblR2:mean_stats_cache:InvalidSpacing', ...
        'cache.h_mm 必须是有限正标量。');
end

% --- 可选统计帧范围 [start,end]（缓存内绝对帧号，闭区间） ---------------------
if nargin < 5 || isempty(stats_frame_range)
    stats_frame_range = [];   % 空 = 统计整个缓存序列（4 参调用与旧行为一致）。
end
if isempty(stats_frame_range)
    frame_start = 1;
    frame_end = n_frames;
else
    if ~(isnumeric(stats_frame_range) && numel(stats_frame_range) == 2 && ...
            all(stats_frame_range == fix(stats_frame_range)) && ...
            all(stats_frame_range > 0))
        error('tblR2:mean_stats_cache:InvalidFrameRange', ...
            'stats_frame_range 必须是两个正整数组成的 [start,end]。');
    end
    frame_start = double(stats_frame_range(1));
    frame_end = double(stats_frame_range(2));
    if frame_start > frame_end || frame_start > n_frames || frame_end > n_frames
        error('tblR2:mean_stats_cache:FrameRangeOutOfBounds', ...
            '统计帧范围 [%d,%d] 超出缓存帧数 %d。', ...
            frame_start, frame_end, n_frames);
    end
end
% 本次实际参与统计的帧数（valid_fraction 与 stats.n_frames 的除数）。
stats_frame_count = frame_end - frame_start + 1;

% --- repeat-aware fluctuation detrending (v2) ------------------------------
repeat_means = [];
repeat_boundaries = [];
if has_variable(cache, 'cache_meta')
    meta = cache.cache_meta;
    if isfield(meta, 'repeat_means') && ~isempty(meta.repeat_means) && ...
            isfield(meta, 'repeat_boundaries') && ~isempty(meta.repeat_boundaries)
        repeat_means = double(meta.repeat_means);
        repeat_boundaries = double(meta.repeat_boundaries);
        if size(repeat_means, 1) == 2 && size(repeat_means, 2) > 0 && ...
                size(repeat_means, 3) == J && size(repeat_means, 4) == I
            frame_to_repeat = ones(n_frames, 1);
            for r = 2:size(repeat_means, 2)
                frame_to_repeat(repeat_boundaries(r - 1) + 1:end) = r;
            end
        else
            repeat_means = [];
        end
    end
end

count = zeros(J, I);
M_u = zeros(J, I);
M_v = zeros(J, I);
M2_u = zeros(J, I);
M2_v = zeros(J, I);
M_uv = zeros(J, I);
% 脉动场（各自去均值）累加器；单 repeat 时与整体累加器同结果。
F2_u = zeros(J, I);
F2_v = zeros(J, I);
F_uv = zeros(J, I);

% 只统计 [frame_start, frame_end] 内的帧（默认为整个缓存序列）。
for first = frame_start:chunk_frames:frame_end
    last = min(frame_end, first + chunk_frames - 1);
    n_local = last - first + 1;
    U = double(tblR2.read_cache_frames(cache, 'U', first:last, J, I));
    V = double(tblR2.read_cache_frames(cache, 'V', first:last, J, I));
    valid = logical(tblR2.read_cache_frames(cache, 'sampleValid', ...
        first:last, J, I)) & ...
        isfinite(U) & isfinite(V);
    U(~valid) = 0;
    V(~valid) = 0;

    % 脉动场：每帧减去其所属 repeat 的时间平均（repeat_means），
    % 无效点已置零（不参与统计）。
    if ~isempty(repeat_means)
        rep_idx = frame_to_repeat(first:last);
        Uf = U - reshape(repeat_means(1, rep_idx, :, :), size(U, 1), J, I);
        Vf = V - reshape(repeat_means(2, rep_idx, :, :), size(V, 1), J, I);
    else
        Uf = U;
        Vf = V;
    end
    Uf(~valid) = 0;
    Vf(~valid) = 0;

    % 本块有效样本数与本块均值（population）。
    n_c = squeeze(sum(valid, 1));
    mean_u = squeeze(sum(U, 1)) ./ max(n_c, 1);
    mean_v = squeeze(sum(V, 1)) ./ max(n_c, 1);

    % 本块相对自身均值的中心化平方和/叉积（整体）。
    d_u = U - reshape(mean_u, 1, J, I);
    d_v = V - reshape(mean_v, 1, J, I);
    d_u(~valid) = 0;
    d_v(~valid) = 0;
    M2_u_c = squeeze(sum(d_u .* d_u, 1));
    M2_v_c = squeeze(sum(d_v .* d_v, 1));
    M_uv_c = squeeze(sum(d_u .* d_v, 1));

    % 本块脉动场平方和/叉积：仅双 repeat 有意义（Uf 已逐帧减去精确
    % repeat 均值，E[Uf]=0，uu=mean(Uf.^2) 即脉动方差，无需再对块均值
    % 中心化；若再中心化会把跨 repeat 的系统偏移重新计入方差）。
    % 单 repeat 缓存不计算 F 项（uu 走整体中心化 M2 路径）。
    if ~isempty(repeat_means)
        F2_u_c = squeeze(sum(Uf .* Uf, 1));
        F2_v_c = squeeze(sum(Vf .* Vf, 1));
        F_uv_c = squeeze(sum(Uf .* Vf, 1));
    else
        F2_u_c = zeros(J, I);
        F2_v_c = zeros(J, I);
        F_uv_c = zeros(J, I);
    end

    % Chan-Golub-LeVeque 块合并；空块 n_c=0 时权重为零，全局量不变。
    n_new = count + n_c;
    delta_u = mean_u - M_u;
    delta_v = mean_v - M_v;
    weight = n_c ./ max(n_new, 1);
    M_u = M_u + weight .* delta_u;
    M_v = M_v + weight .* delta_v;
    cross = count .* n_c ./ max(n_new, 1);
    M2_u = M2_u + M2_u_c + delta_u .^ 2 .* cross;
    M2_v = M2_v + M2_v_c + delta_v .^ 2 .* cross;
    M_uv = M_uv + M_uv_c + delta_u .* delta_v .* cross;
    % 脉动累加器：Uf 已逐帧减去精确 repeat 均值（E[Uf]=0），
    % 跨块合并无均值差项，直接累加平方和/叉积即可。
    F2_u = F2_u + F2_u_c;
    F2_v = F2_v + F2_v_c;
    F_uv = F_uv + F_uv_c;
    count = n_new;
end

valid_fraction = count ./ stats_frame_count;
denominator = max(count, 1);
U_mean = M_u;
V_mean = M_v;
if ~isempty(repeat_means)
    % 双 repeat：uu/vv/uv/TKE 用脉动场（各自去均值后拼接）统计。
    uu = max(0, F2_u ./ denominator);
    vv = max(0, F2_v ./ denominator);
    uv = -F_uv ./ denominator;
else
    uu = max(0, M2_u ./ denominator);
    vv = max(0, M2_v ./ denominator);
    uv = -M_uv ./ denominator;
end
accepted = count >= 2 & valid_fraction >= min_valid_fraction;

fields = {U_mean, V_mean, uu, vv, uv};
for i = 1:numel(fields)
    value = fields{i};
    value(~accepted) = NaN;
    fields{i} = value;
end
[U_mean, V_mean, uu, vv, uv] = fields{:};
u_rms = sqrt(uu);
v_rms = sqrt(vv);

stats = struct();
stats.Uavex = U_mean;
stats.Vavex = V_mean;
stats.u_rms = u_rms;
stats.v_rms = v_rms;
stats.uu_rey = uu;
stats.vv_rey = vv;
stats.uv_rey = uv;
stats.TKE = 0.5 .* (uu + vv) ./ (Uinf .* Uinf);
stats.valid_count = count;
stats.valid_fraction = valid_fraction;
stats.accepted_mask = accepted;
stats.X = double(cache.X);
stats.Y = double(cache.Y);
stats.h = double(cache.h_mm);
stats.n_frames = stats_frame_count;
stats.definition = ['u''=u-<u>, v''=v-<v>; population moments use each ' ...
    'sample point''s own valid-frame count. Here the apostrophe denotes the ' ...
    'total Reynolds fluctuation, not the controlled random double-prime branch.'];
if ~isempty(repeat_means)
    stats.mean_definition = ['mean field: overall average of the ' ...
        'concatenated 2-repeat sequence (12000 frames).'];
    stats.fluctuation_definition = ['fluctuation field: per-repeat ' ...
        'detrending (each repeat minus its own temporal mean) then ' ...
        'concatenation, so u''/v''/uu/vv/uv/TKE remove repeat-to-repeat ' ...
        'systematic offsets.'];
    stats.repeat_means = repeat_means;
    stats.repeat_boundaries = repeat_boundaries;
else
    stats.mean_definition = ['single-repeat cache: overall temporal mean.'];
    stats.fluctuation_definition = ['single-repeat cache: overall temporal ' ...
        'fluctuation (identical to per-repeat detrending).'];
end
stats.moments_definition = ['population moments (divide by the point''s own ' ...
    'valid count); uu/vv/uv/TKE are the total Reynolds fluctuation fields.'];
stats.algorithm = ['chunked Chan-Golub-LeVeque/Welford merge over the disk ' ...
    'cache; chunk_frames controls I/O granularity only and does not change ' ...
    'the result.'];
end

function tf = has_variable(cache, name)
info = whos(cache, name);
tf = ~isempty(info);
end
