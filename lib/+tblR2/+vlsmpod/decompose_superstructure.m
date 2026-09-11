function T = decompose_superstructure(T, identified, field, ctx, options)
%DECOMPOSE_SUPERSTRUCTURE 用 v' 零穿越找 VLSM 内部子结构界面。
%
% 依据 Deshpande & Marusic (2023) JFM 的 concatenation hypothesis：超结构不是
% 均匀长棒，而是多个较小的自相似 coherent motion 首尾拼接而成。只看 u' 分不出
% 内部子结构（整段 u' 同号），但 v' 在相邻子结构交界处改变符号——因为拼接点两侧
% 分别是上抛与下扫的诱导流动。
%
% 算法
%   1. 从标签图取该结构的像素集。
%   2. 逐流向列，在结构像素上对 v' 做行向平均，得到 1D 剖面 vbar(x)。
%   3. 找 vbar 的符号变化点。两道筛：
%      - 幅值筛：变号两侧的极值幅度都要超过 amplitude_factor * v_rms_ref，
%        否则是噪声在零附近抖动，不是物理界面。
%      - 间距筛：相邻界面间距要超过 min_sub_length_delta * delta99，否则是毛刺。
%   4. 界面把结构切成 N 段，输出段数与段长中位数。
%
% 只处理 IsVLSM 的行；其余行的新列为 NaN/空——LSM 尺度本身就在子结构量级，
% 对它再分解没有物理意义。
%
% amplitude_factor 尚未标定，默认 0.5 会压掉真界面
% --------------------------------------------------
% 2026-08-25 在 24 帧 / 17 个 VLSM（E=50%, r1 参数）上实测：
%
%   amplitude_factor   0.50   0.30   0.20   0.10   0.05
%   平均子结构数       1.29   2.06   2.53   3.00   3.24
%
% 逐 VLSM 看，vbar 的原始符号变化有 6-19 次，但 max|vbar| 只有 0.7-1.9 而门限
% 0.5*v_rms 约 0.6，三值化的零区吞掉了大部分变号——所以默认 0.5 下 17 个 VLSM
% 里 14 个只切出 1 段。**那个「1 段」是参数造成的，不是 concatenation 不成立。**
%
% 曲线没有干净的平台段，17 个样本也不足以定标定值。用法上：报告子结构数时必须
% 同时报 amplitude_factor，或跑一遍敏感性（tools/r2_diagnostics/
% run_vlsmpod_extension_audit.m 会自动输出该曲线）。正式标定应比照 alpha 的做法
% ——宽扫描 + bootstrap 找稳定区，样本量到数百个 VLSM。
%
% 另一处口径限制：Deshpande & Marusic 的 superstructure 定义是 Lx > 6*delta99，
% 而本数据的 VLSM 只到 3.0-5.2*delta99，尚未进入他们报告 concatenation 的尺度段。
%
% 输入
%   T          : structures 表（此时还没加 FrameID 等列）
%   identified : tblR2.vlsmpod.identify_frame 的输出（要用标签图）
%   field      : tblR2.vlsmpod.frame_field 的输出（要用 v_fluct）
%   ctx        : tblR2.vlsmpod.prepare_context 的输出
%   options    : .amplitude_factor      默认 0.5（未标定，见上表）
%                .min_sub_length_delta  默认 0.5，单位 delta99
%
% 输出：T 追加 3 列 NSubStructures / SubLengthMedian_over_delta / SubInterfaceX_mm

if nargin < 5 || isempty(options); options = struct(); end
amplitude_factor = pick(options, 'amplitude_factor', 0.5);
min_sub_length_delta = pick(options, 'min_sub_length_delta', 0.5);

nrows = height(T);
n_sub = nan(nrows, 1);
sub_len_median = nan(nrows, 1);
interfaces = cell(nrows, 1);
interfaces(:) = {zeros(0, 1)};

% 合并后标签图被置空（ID 已重编，对不上），此时无法做像素级分解。
labels_available = ~isempty(identified.positive_labels) && ...
    ~isempty(identified.negative_labels);

if nrows > 0 && labels_available
    n_positive = sum(T.Sign > 0);
    for i = 1:nrows
        if ~T.IsVLSM(i)
            continue;
        end
        pixels = structure_pixels(T, i, identified, n_positive);
        if isempty(pixels)
            continue;
        end
        [count, med_len, iface_x] = decompose_one(pixels, field.v_fluct, ...
            ctx, T.Delta99Ref_mm(i), amplitude_factor, min_sub_length_delta);
        n_sub(i) = count;
        sub_len_median(i) = med_len;
        interfaces{i} = iface_x;
    end
end

% 把实际用的 amplitude_factor 随行落表。子结构数强烈依赖它（0.5->1.29 段，
% 0.05->3.24 段），不带参数的子结构数是不可解释的数。
T = addvars(T, n_sub, sub_len_median, interfaces, ...
    repmat(amplitude_factor, nrows, 1), ...
    repmat(min_sub_length_delta, nrows, 1), 'NewVariableNames', ...
    {'NSubStructures', 'SubLengthMedian_over_delta', 'SubInterfaceX_mm', ...
    'SubAmplitudeFactor', 'SubMinLengthDelta'});
end

% =========================================================================
function pixels = structure_pixels(T, row, identified, n_positive)
%STRUCTURE_PIXELS 按 StructureID 从对应符号的标签图里取像素。
% identify_structures 里正负分别从 1 开始编号，拼表时正号在前，所以负号行的
% 表内 ID 要减掉正号总数才是它在负号标签图里的标签值。

if T.Sign(row) > 0
    label_image = identified.positive_labels;
    label_value = T.StructureID(row);
else
    label_image = identified.negative_labels;
    label_value = T.StructureID(row) - n_positive;
end
if label_value < 1
    pixels = [];
    return;
end
pixels = find(label_image == label_value);
end

% =========================================================================
function [n_sub, med_len_over_delta, interface_x] = decompose_one(pixels, ...
    v_fluct, ctx, delta_ref, amplitude_factor, min_sub_length_delta)
%DECOMPOSE_ONE 单个结构的 v' 剖面零穿越分解。

n_sub = NaN;
med_len_over_delta = NaN;
interface_x = zeros(0, 1);

[rows_idx, cols_idx] = ind2sub([ctx.J, ctx.I], pixels);
cols_unique = unique(cols_idx);
if numel(cols_unique) < 2
    return;
end

% 逐列在结构像素上对 v' 做行向平均。
vbar = nan(numel(cols_unique), 1);
for k = 1:numel(cols_unique)
    sel = cols_idx == cols_unique(k);
    vals = v_fluct(sub2ind([ctx.J, ctx.I], rows_idx(sel), cols_idx(sel)));
    vbar(k) = mean(vals, 'omitnan');
end

x_cols = ctx.X_mm(1, cols_unique).';
good = isfinite(vbar);
if nnz(good) < 2
    return;
end
vbar = vbar(good);
x_cols = x_cols(good);

% 幅值门限：用结构所在行范围的 v_rms 中位数作参考尺度。
v_ref = local_v_reference(ctx, rows_idx, cols_idx);
if ~isfinite(v_ref) || v_ref <= 0
    return;
end
threshold = amplitude_factor * v_ref;

candidates = sign_change_positions(vbar, x_cols, threshold);

% 间距筛：相邻界面间距需超过 min_sub_length_delta * delta99。
min_gap_mm = min_sub_length_delta * delta_ref;
interface_x = enforce_min_gap(candidates, min_gap_mm, x_cols(1), x_cols(end));

n_sub = numel(interface_x) + 1;
edges = [x_cols(1); interface_x(:); x_cols(end)];
seg_len = diff(edges);
if isfinite(delta_ref) && delta_ref > 0
    med_len_over_delta = median(seg_len) / delta_ref;
end
end

% =========================================================================
function v_ref = local_v_reference(ctx, rows_idx, cols_idx)
%LOCAL_V_REFERENCE 结构覆盖区域的 v_rms 中位数。
% 用局部值而非全场值：v_rms 随 y 变化一个量级，用全场中位数会让近壁结构的门限
% 过松、外层结构的门限过紧。

v_ref = NaN;
if ~isfield(ctx.stats, 'v_rms') || isempty(ctx.stats.v_rms)
    return;
end
idx = sub2ind([ctx.J, ctx.I], rows_idx, cols_idx);
vals = ctx.stats.v_rms(idx);
v_ref = median(vals(isfinite(vals) & vals > 0), 'omitnan');
end

% =========================================================================
function x_cross = sign_change_positions(vbar, x_cols, threshold)
%SIGN_CHANGE_POSITIONS 找满足幅值门限的符号变化位置。
%
% 只有当变号两侧都存在超过门限的极值时，这个变号才算物理界面。做法：先把剖面
% 按门限三值化（+1/0/-1），再找相邻非零段之间的符号翻转，界面取在两段之间的
% 零穿越处（线性插值）。这样零附近的噪声抖动被三值化的零区吸收，不产生界面。

x_cross = zeros(0, 1);
state = zeros(size(vbar));
state(vbar >= threshold) = 1;
state(vbar <= -threshold) = -1;

nz = find(state ~= 0);
if numel(nz) < 2
    return;
end

for k = 1:numel(nz) - 1
    a = nz(k);
    b = nz(k + 1);
    if state(a) == state(b)
        continue;
    end
    % 在 [a, b] 之间找 vbar 的零穿越点，线性插值取位置。
    seg_v = vbar(a:b);
    seg_x = x_cols(a:b);
    cross_idx = find(seg_v(1:end-1) .* seg_v(2:end) <= 0, 1, 'first');
    if isempty(cross_idx)
        x_cross(end + 1, 1) = mean([x_cols(a), x_cols(b)]); %#ok<AGROW>
        continue;
    end
    v1 = seg_v(cross_idx);
    v2 = seg_v(cross_idx + 1);
    x1 = seg_x(cross_idx);
    x2 = seg_x(cross_idx + 1);
    if v2 == v1
        x_cross(end + 1, 1) = x1; %#ok<AGROW>
    else
        x_cross(end + 1, 1) = x1 - v1 * (x2 - x1) / (v2 - v1); %#ok<AGROW>
    end
end
x_cross = unique(x_cross);
end

% =========================================================================
function kept = enforce_min_gap(candidates, min_gap_mm, x_first, x_last)
%ENFORCE_MIN_GAP 贪心保留满足最小间距的界面（含与两端的间距）。

kept = zeros(0, 1);
if isempty(candidates)
    return;
end
candidates = sort(candidates(:));
last_kept = x_first;
for k = 1:numel(candidates)
    if candidates(k) - last_kept < min_gap_mm
        continue;
    end
    if x_last - candidates(k) < min_gap_mm
        continue;
    end
    kept(end + 1, 1) = candidates(k); %#ok<AGROW>
    last_kept = candidates(k);
end
end

% =========================================================================
function value = pick(s, name, fallback)
value = fallback;
if isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
end
end
