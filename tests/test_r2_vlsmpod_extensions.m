% TEST_R2_VLSMPOD_EXTENSIONS 合成数据验证 +vlsmpod 的三个功能扩展。
%
% 全部用手工构造的场，每个断言都对着一个解析可算的期望值——不拿真实数据的输出
% 当期望值，那样只能证明「代码跑通了」，证明不了「算对了」。

repo_root = fileparts(fileparts(mfilename('fullpath')));
library_root = fullfile(repo_root, 'lib');
addpath(library_root, '-begin');

test_resolve_settings_matches_production_opts();
test_resolve_settings_rejects_unknown_override();
test_wall_attached_thresholds();
test_wall_attached_statistics_fractions();
test_superstructure_counts_known_interfaces();
test_superstructure_amplitude_and_gap_filters();
test_superstructure_caveats_are_reported();
test_tracking_caveats_expose_design_choices();
test_tracking_shift_compensation_is_required();
test_tracking_event_classification();
test_tracking_censoring_flags();
test_run_catalog_rejects_noncontiguous_tracking();
fprintf('test_r2_vlsmpod_extensions: PASS\n');


% =========================================================================
function test_resolve_settings_matches_production_opts()
% resolve_settings 必须与被它替换的生产局部函数逐字段一致。这里把
% structure_analysis_cache.m 的 structure_opts 期望字段集写死，任何字段增删或
% 默认值漂移都会被这条测试挡住——那等于改了主管线的识别口径。

settings = struct('alpha', 0.40, 'seed_alpha', 0.70, 'min_pixels', 3, ...
    'connectivity', 8, 'min_lsm_delta', 1, 'min_vlsm_delta', 3, ...
    'max_wall_normal_delta', inf, 'max_internal_hole_pixels', 64, ...
    'envelope_closing_radius_cells', 2, 'max_aspect_ratio', inf, ...
    'reject_trusted_boundary_touching', true);
r = tblR2.vlsmpod.resolve_settings(settings);

expected_fields = {'alpha', 'min_pixels', 'seed_alpha', 'connectivity', ...
    'max_internal_hole_pixels', 'envelope_closing_radius_cells', ...
    'max_aspect_ratio', 'reject_trusted_boundary_touching', ...
    'min_lsm_delta', 'min_vlsm_delta', 'max_wall_normal_delta', ...
    'min_abs_fluctuation', 'min_abs_seed_fluctuation', 'sign_mode'};
assert(isequal(fieldnames(r.opts), expected_fields.'), ...
    'resolve_settings 的 opts 字段集与生产 structure_opts 不一致。');
assert(r.opts.alpha == 0.40 && r.opts.seed_alpha == 0.70);
assert(r.opts.connectivity == 8);
assert(r.opts.min_abs_fluctuation == 0, '缺省绝对幅值下限必须是 0。');
assert(strcmp(r.opts.sign_mode, 'both'));

% seed_alpha 缺失时必须回落到 alpha，而不是报错或用别的默认值。
s2 = rmfield(settings, 'seed_alpha');
r2 = tblR2.vlsmpod.resolve_settings(s2);
assert(r2.opts.seed_alpha == r2.opts.alpha);

% 没有 merge_gap_cells 字段时合并必须关闭——缓存 cfg 就是这个情形。
assert(~r.merge_enabled, '缺少 merge_gap_cells 时合并必须关闭。');
s3 = settings;
s3.merge_gap_cells = 40;
s3.merge_require_y_overlap = true;
r3 = tblR2.vlsmpod.resolve_settings(s3);
assert(r3.merge_enabled);
assert(r3.merge_opts.merge_gap_cells == 40);
assert(r3.merge_opts.min_vlsm_delta == 3);

% 预处理规格不得预填方向性字段：预填过 sigma_x_cells 曾让 9x9 核退化成 3x3。
s4 = settings;
s4.preprocessing = struct('enabled', true, 'gaussian', ...
    struct('enabled', true, 'sigma_cells', 1.5, 'radius_cells', 4));
r4 = tblR2.vlsmpod.resolve_settings(s4);
assert(~isfield(r4.preprocess_spec.gaussian, 'sigma_x_cells'), ...
    '不得预填 sigma_x_cells，否则 sigma_cells 传不到卷积核。');
assert(r4.preprocess_spec.gaussian.sigma_cells == 1.5);
end


% =========================================================================
function test_resolve_settings_rejects_unknown_override()
% 打错字段名必须立刻报错。静默新增一个永不被读的字段会让人以为参数生效了。
settings = struct('alpha', 1, 'seed_alpha', 1, 'min_pixels', 1, ...
    'connectivity', 4, 'min_lsm_delta', 1, 'min_vlsm_delta', 3, ...
    'max_wall_normal_delta', inf);
assert_error(@() tblR2.vlsmpod.resolve_settings(settings, ...
    struct('alpah', 0.4)), ...
    'tblR2:vlsmpod:resolve_settings:UnknownOverride');
end


% =========================================================================
function test_wall_attached_thresholds()
% 判据是外尺度 YMin_over_delta < 0.05。这里三个结构的 y_min/delta99 分别是
% 0.02（attached）、0.05（正好在阈值上，按严格小于应为 detached）、0.20（detached）。

delta = 34;    % mm
T = table([1; 2; 3], [1; 1; -1], ...
    [0.02; 0.05; 0.20] * delta, repmat(delta, 3, 1), ...
    'VariableNames', {'StructureID', 'Sign', 'YMin_mm', 'Delta99Ref_mm'});

ctx = struct('u_tau', 0.9675, 'nu', 1.48e-5);
out = tblR2.vlsmpod.classify_wall_attached(T, ctx, struct());

assert(isequal(out.IsWallAttached, [true; false; false]), ...
    '阈值必须是严格小于：y_min/delta99 == 0.05 不算 attached。');
assert(abs(out.YMin_over_delta(1) - 0.02) < 1e-12);

% y+ = y_mm * 1e-3 * u_tau / nu，解析可算。
expected_yplus = 0.02 * delta * 1e-3 * 0.9675 / 1.48e-5;
assert(abs(out.YMin_plus(1) - expected_yplus) < 1e-9, ...
    'YMin_plus 的换算不对。');
assert(all(out.AttachedDeltaThreshold == 0.05));

% 阈值可调，且只影响二值列，不影响两个连续列。
out2 = tblR2.vlsmpod.classify_wall_attached(T, ctx, ...
    struct('attached_delta_threshold', 0.25));
assert(all(out2.IsWallAttached), '阈值放宽到 0.25 后三个都该是 attached。');
assert(isequaln(out.YMin_over_delta, out2.YMin_over_delta), ...
    '改阈值不该改动连续列。');

% u_tau 不可用时 YMin_plus 给 NaN，但外尺度判据仍然有效——这正是选外尺度的理由。
ctx_bad = struct('u_tau', NaN, 'nu', NaN);
out3 = tblR2.vlsmpod.classify_wall_attached(T, ctx_bad, struct());
assert(all(isnan(out3.YMin_plus)));
assert(isequal(out3.IsWallAttached, [true; false; false]), ...
    'u_tau 缺失不应影响外尺度 attached 判据。');

% 空表不能报错，且列必须齐全（下游 vertcat 依赖列一致）。
empty_T = T([], :);
out4 = tblR2.vlsmpod.classify_wall_attached(empty_T, ctx, struct());
assert(height(out4) == 0);
assert(all(ismember({'YMin_plus', 'YMin_over_delta', 'IsWallAttached', ...
    'AttachedDeltaThreshold'}, out4.Properties.VariableNames)));
end


% =========================================================================
function test_wall_attached_statistics_fractions()
% 计数占比与面积占比要分开算：Hwang & Sung 的核心结论正是「attached 数量少但
% 占据大部分体积」，如果两个占比算成一个数就看不出这件事。

catalog = table([true; false; false; false], [100; 10; 10; 10], ...
    [5; 1; 1; 1], [1; 1; 1; 1], ...
    'VariableNames', {'IsWallAttached', 'Area_mm2', 'HeightY_mm', 'Delta99Ref_mm'});
s = tblR2.vlsmpod.wall_attached_statistics(catalog);

assert(s.n_total == 4 && s.n_attached == 1 && s.n_detached == 3);
assert(abs(s.attached_fraction - 0.25) < 1e-12);
% 面积占比 100/130，明显高于计数占比 0.25。
assert(abs(s.attached_area_fraction - 100/130) < 1e-12);

% 缺列必须报错，而不是静默返回空统计。
bad = catalog;
bad.IsWallAttached = [];
assert_error(@() tblR2.vlsmpod.wall_attached_statistics(bad), ...
    'tblR2:vlsmpod:wall_attached_statistics:MissingColumn');
end


% =========================================================================
function test_superstructure_caveats_are_reported()
% caveats 是防误读的机制：n_sub_mean 单独被引用时会被当成物理结论，而它强烈
% 依赖未标定的 amplitude_factor。这条测试锁住这些字段不被后续改动去掉。

[ctx, resolved] = synthetic_context();
u = zeros(ctx.J, ctx.I);
u(3:6, :) = 2.0;
v = zeros(ctx.J, ctx.I);
v(3:6, 1:20) = 1.0;
v(3:6, 21:40) = -1.0;
v(3:6, 41:end) = 1.0;
field = struct('u_fluct', u, 'v_fluct', v, 'mask', true(ctx.J, ctx.I), ...
    'frame_id', 1, 'preprocessing', 'synthetic');
identified = tblR2.vlsmpod.identify_frame(ctx, field, resolved);
T = tblR2.vlsmpod.decompose_superstructure(identified.structures, ...
    identified, field, ctx, struct('amplitude_factor', 0.3));
T = tblR2.vlsmpod.annotate(T, 1, 'total', 'synthetic');

s = tblR2.vlsmpod.superstructure_statistics(T);
assert(isfield(s, 'caveats'), 'superstructure_statistics 必须输出 caveats。');
c = s.caveats;
assert(~c.amplitude_factor_calibrated, ...
    'amplitude_factor 尚未标定，不得标为已标定。');
assert(c.amplitude_factor_used == 0.3, ...
    'caveats 必须记录实际生效的 amplitude_factor。');
assert(~c.sample_adequate, '1 个 VLSM 的样本量不应被标为充足。');
% 合成场的 VLSM 只有 6*delta99 边界附近，检查尺度口径字段存在且自洽。
assert(isfield(c, 'reaches_superstructure_scale'));
assert(islogical(c.reaches_superstructure_scale));
if ~c.reaches_superstructure_scale
    assert(~isempty(c.scale_note), '未达 superstructure 尺度时必须给出说明。');
end
end


% =========================================================================
function test_tracking_caveats_expose_design_choices()
% 寿命中位数由两个非物理因素主导：FOV 截断与 split/merge 断链的设计选择。
% 两者都必须在 caveats 里显式暴露，否则寿命数会被当成物理寿命引用。

[ctx, resolved] = synthetic_context();
ctx.Uavex = zeros(ctx.J, ctx.I);
ctx.dt_s = 1e-3;

u1 = zeros(ctx.J, ctx.I);
u1(3:6, 10:40) = 2.0;
u2 = zeros(ctx.J, ctx.I);
u2(3:6, 10:20) = 2.0;
u2(3:6, 30:40) = 2.0;
store = {frame_record(ctx, resolved, u1, 1), frame_record(ctx, resolved, u2, 2)};
tr = tblR2.vlsmpod.track_structures(store, ctx, struct('overlap_threshold', 0.2));

assert(isfield(tr.summary, 'caveats'), 'track_structures 必须输出 caveats。');
c = tr.summary.caveats;
assert(c.chain_breaks_at_split_merge, ...
    'split/merge 断链是设计选择，必须显式声明。');
assert(c.chain_breaking_links >= 1, ...
    '本场景有 split，断链链接数应 >= 1。');
assert(isfinite(c.chain_break_fraction) && c.chain_break_fraction > 0);
assert(~isempty(c.design_note));
assert(isfield(c, 'fov_transit_frames') && isfield(c, 'window_adequate'));
assert(~c.window_adequate, '2 帧窗口不应被标为充足。');
end


% =========================================================================
function test_superstructure_counts_known_interfaces()
% 构造一个长条 VLSM，其 v' 沿流向符号翻转 2 次 -> 应得 3 段子结构。

[ctx, resolved] = synthetic_context();

% u' 全正的长条，横跨全部 60 列，占第 3-6 行。
u = zeros(ctx.J, ctx.I);
u(3:6, :) = 2.0;

% v' 分三段：+ / - / +，翻转点在列 20/21 与 40/41 之间。
v = zeros(ctx.J, ctx.I);
v(3:6, 1:20) = 1.0;
v(3:6, 21:40) = -1.0;
v(3:6, 41:end) = 1.0;

field = struct('u_fluct', u, 'v_fluct', v, 'mask', true(ctx.J, ctx.I), ...
    'frame_id', 1, 'preprocessing', 'synthetic');
identified = tblR2.vlsmpod.identify_frame(ctx, field, resolved);
T = identified.structures;
assert(height(T) == 1, '合成场应只识别出 1 个结构。');
assert(T.IsVLSM(1), '该结构应被判为 VLSM，否则不会被分解。');

out = tblR2.vlsmpod.decompose_superstructure(T, identified, field, ctx, struct());
assert(out.NSubStructures(1) == 3, ...
    'v'' 翻转 2 次应切出 3 段子结构，实得 %g。', out.NSubStructures(1));
assert(numel(out.SubInterfaceX_mm{1}) == 2);

% 实际用的参数必须随行落表：子结构数强烈依赖 amplitude_factor
% （实测 0.5->1.29 段、0.05->3.24 段），不带参数的子结构数无法解释。
assert(all(ismember({'SubAmplitudeFactor', 'SubMinLengthDelta'}, ...
    out.Properties.VariableNames)), ...
    '必须把 amplitude_factor / min_sub_length_delta 随行记录。');
assert(out.SubAmplitudeFactor(1) == 0.5, '默认 amplitude_factor 应为 0.5。');
out_af = tblR2.vlsmpod.decompose_superstructure(T, identified, field, ctx, ...
    struct('amplitude_factor', 0.2));
assert(out_af.SubAmplitudeFactor(1) == 0.2, '落表的参数必须是实际生效值。');

% 界面位置应落在翻转处附近（列 20-21 与 40-41 的坐标之间）。
iface = sort(out.SubInterfaceX_mm{1});
x = ctx.X_mm(1, :);
assert(iface(1) > x(19) && iface(1) < x(22), '第一个界面位置不对。');
assert(iface(2) > x(39) && iface(2) < x(42), '第二个界面位置不对。');

% v' 全同号时不应有界面 -> 1 段。
v_uniform = zeros(ctx.J, ctx.I);
v_uniform(3:6, :) = 1.0;
field2 = field;
field2.v_fluct = v_uniform;
out2 = tblR2.vlsmpod.decompose_superstructure(T, identified, field2, ctx, struct());
assert(out2.NSubStructures(1) == 1, 'v'' 不变号时应为单段。');

% 非 VLSM 行不做分解，列为 NaN。
[ctx3, resolved3] = synthetic_context();
u3 = zeros(ctx3.J, ctx3.I);
u3(3:4, 1:5) = 2.0;     % 很短，不是 VLSM
field3 = struct('u_fluct', u3, 'v_fluct', v, 'mask', true(ctx3.J, ctx3.I), ...
    'frame_id', 1, 'preprocessing', 'synthetic');
id3 = tblR2.vlsmpod.identify_frame(ctx3, field3, resolved3);
out3 = tblR2.vlsmpod.decompose_superstructure(id3.structures, id3, field3, ...
    ctx3, struct());
assert(~any(id3.structures.IsVLSM));
assert(all(isnan(out3.NSubStructures)), '非 VLSM 不该被分解。');
end


% =========================================================================
function test_superstructure_amplitude_and_gap_filters()
% 两道筛各自要能压掉伪界面：幅值筛压噪声抖动，间距筛压毛刺。

[ctx, resolved] = synthetic_context();
u = zeros(ctx.J, ctx.I);
u(3:6, :) = 2.0;

% v' 主体为 +1，但在列 30 处插入一个幅值仅 0.01 的负值抖动。
% v_rms 合成为 1.0，默认 amplitude_factor=0.5 -> 门限 0.5，0.01 应被压掉。
v = zeros(ctx.J, ctx.I);
v(3:6, :) = 1.0;
v(3:6, 30) = -0.01;
field = struct('u_fluct', u, 'v_fluct', v, 'mask', true(ctx.J, ctx.I), ...
    'frame_id', 1, 'preprocessing', 'synthetic');
identified = tblR2.vlsmpod.identify_frame(ctx, field, resolved);
out = tblR2.vlsmpod.decompose_superstructure(identified.structures, ...
    identified, field, ctx, struct());
assert(out.NSubStructures(1) == 1, ...
    '幅值 0.01 的抖动低于门限 0.5，不该产生界面。');

% 把门限降到 0.005 后同一个抖动就该被当成界面 -> 证明确实是幅值筛在起作用，
% 而不是这个抖动因为别的原因被忽略了。
out_low = tblR2.vlsmpod.decompose_superstructure(identified.structures, ...
    identified, field, ctx, struct('amplitude_factor', 0.005, ...
    'min_sub_length_delta', 0.01));
assert(out_low.NSubStructures(1) > 1, ...
    '门限降到 0.005 后该抖动应产生界面（验证幅值筛真的在起作用）。');

% 间距筛：v' 在相邻两列各翻一次（列 30、31），间距 1 格远小于 0.5*delta99。
v2 = zeros(ctx.J, ctx.I);
v2(3:6, :) = 1.0;
v2(3:6, 30) = -1.0;
field2 = field;
field2.v_fluct = v2;
out2 = tblR2.vlsmpod.decompose_superstructure(identified.structures, ...
    identified, field2, ctx, struct('min_sub_length_delta', 0.5));
% 单列翻转产生两个候选界面，间距 1 格 -> 间距筛后最多留 1 个。
assert(out2.NSubStructures(1) <= 2, ...
    '间距 1 格的两个候选界面应被间距筛压到最多 1 个。');
end


% =========================================================================
function test_tracking_shift_compensation_is_required()
% 这是本数据最关键的一条：帧间位移约 50 格，不补偿时 overlap 必然失配。
% 构造一个已知位移的结构，验证补偿开/关的结果相反。

[ctx, resolved] = synthetic_context();
% Uavex 设成让位移正好 10 格：shift = U*dt*1e3/dx。
% dx=1mm, dt=1e-3 s -> U = 10 m/s 给 10 格。
ctx.Uavex = repmat(10.0, ctx.J, ctx.I);
ctx.dt_s = 1e-3;

u1 = zeros(ctx.J, ctx.I);
u1(3:6, 5:20) = 2.0;
u2 = zeros(ctx.J, ctx.I);
u2(3:6, 15:30) = 2.0;      % 同一结构右移 10 格

store = cell(2, 1);
store{1} = frame_record(ctx, resolved, u1, 1);
store{2} = frame_record(ctx, resolved, u2, 2);

% 开补偿：应匹配成 1 条 track，寿命 2 帧。
tr_on = tblR2.vlsmpod.track_structures(store, ctx, ...
    struct('galilean_shift', true, 'overlap_threshold', 0.2));
assert(height(tr_on.tracks) == 1, ...
    '开 Galilean 补偿后两帧的同一结构应连成 1 条 track，实得 %d 条。', ...
    height(tr_on.tracks));
assert(tr_on.tracks.LifetimeFrames(1) == 2);
assert(any(strcmp(tr_on.events.EventType, 'continuation')));

% 关补偿：位移 10 格 > 结构长度的一半，overlap = 6/16 = 0.375 仍过阈值 0.2，
% 所以这里用更大的位移来证明不补偿会断。
ctx_far = ctx;
ctx_far.Uavex = repmat(20.0, ctx.J, ctx.I);   % 20 格位移
u3 = zeros(ctx.J, ctx.I);
u3(3:6, 25:40) = 2.0;                          % 右移 20 格，与原位置无交集
store_far = cell(2, 1);
store_far{1} = frame_record(ctx_far, resolved, u1, 1);
store_far{2} = frame_record(ctx_far, resolved, u3, 2);

tr_off = tblR2.vlsmpod.track_structures(store_far, ctx_far, ...
    struct('galilean_shift', false, 'overlap_threshold', 0.2));
assert(height(tr_off.tracks) == 2, ...
    '不补偿时位移 20 格的结构无交集，应断成 2 条 track。');

tr_far_on = tblR2.vlsmpod.track_structures(store_far, ctx_far, ...
    struct('galilean_shift', true, 'overlap_threshold', 0.2));
assert(height(tr_far_on.tracks) == 1, ...
    '补偿 20 格后应重新连成 1 条 track。');
assert(tr_far_on.summary.galilean_shift == true);
end


% =========================================================================
function test_tracking_event_classification()
% 四类事件各自要能被正确识别。位移设为 0（Uavex=0）以便精确控制几何。

[ctx, resolved] = synthetic_context();
ctx.Uavex = zeros(ctx.J, ctx.I);
ctx.dt_s = 1e-3;

% 帧 1：一个长条。帧 2：裂成两段（中间挖空）-> split。
u1 = zeros(ctx.J, ctx.I);
u1(3:6, 10:40) = 2.0;
u2 = zeros(ctx.J, ctx.I);
u2(3:6, 10:20) = 2.0;
u2(3:6, 30:40) = 2.0;

store = {frame_record(ctx, resolved, u1, 1), frame_record(ctx, resolved, u2, 2)};
tr = tblR2.vlsmpod.track_structures(store, ctx, struct('overlap_threshold', 0.2));
assert(any(strcmp(tr.events.EventType, 'split')), '应识别出 split 事件。');
% 两种计数口径必须同时可用且自洽：本场景 1 个结构裂成 2 份 =
% 节点口径 1、链接口径 2。
assert(tr.summary.n_structures_splitting == 1, ...
    '节点口径：1 个结构发生分裂。');
assert(tr.summary.total_split_links == 2, ...
    '链接口径：一裂为二对应 2 条 split 链接。');
n_ev = tr.summary.event_counts.Count( ...
    strcmp(tr.summary.event_counts.EventType, 'split'));
assert(tr.summary.total_split_links == n_ev, ...
    '链接口径必须与 event_counts 的 split 计数一致。');

% 反向即 merge。
store_m = {frame_record(ctx, resolved, u2, 1), frame_record(ctx, resolved, u1, 2)};
tr_m = tblR2.vlsmpod.track_structures(store_m, ctx, ...
    struct('overlap_threshold', 0.2));
assert(any(strcmp(tr_m.events.EventType, 'merge')), '应识别出 merge 事件。');

% birth / death：帧 2 出现一个帧 1 没有的结构。
u_empty = zeros(ctx.J, ctx.I);
u_new = zeros(ctx.J, ctx.I);
u_new(3:6, 10:30) = 2.0;
store_b = {frame_record(ctx, resolved, u_empty, 1), ...
    frame_record(ctx, resolved, u_new, 2)};
tr_b = tblR2.vlsmpod.track_structures(store_b, ctx, ...
    struct('overlap_threshold', 0.2));
assert(any(strcmp(tr_b.events.EventType, 'birth')), '应识别出 birth 事件。');

store_d = {frame_record(ctx, resolved, u_new, 1), ...
    frame_record(ctx, resolved, u_empty, 2)};
tr_d = tblR2.vlsmpod.track_structures(store_d, ctx, ...
    struct('overlap_threshold', 0.2));
assert(any(strcmp(tr_d.events.EventType, 'death')), '应识别出 death 事件。');

% 事件计数表应含全部五类，缺的记 0 而不是漏行。
assert(height(tr.summary.event_counts) == 5);
assert(isequal(tr.summary.event_counts.EventType, ...
    {'birth'; 'continuation'; 'split'; 'merge'; 'death'}));
end


% =========================================================================
function test_tracking_censoring_flags()
% FOV 截断必须被标出来。本数据 FOV 只够 12.9 帧驻留，不标截断的寿命统计是错的。

[ctx, resolved] = synthetic_context();
ctx.Uavex = zeros(ctx.J, ctx.I);
ctx.dt_s = 1e-3;

% 触及流向边界（列 1）的结构。
u_edge = zeros(ctx.J, ctx.I);
u_edge(3:6, 1:20) = 2.0;
store = {frame_record(ctx, resolved, u_edge, 1), ...
    frame_record(ctx, resolved, u_edge, 2)};
tr = tblR2.vlsmpod.track_structures(store, ctx, struct());
assert(tr.tracks.TouchesFovBoundary(1), ...
    '触及列 1 的结构必须被标为 FOV 截断。');

% 起止落在窗口两端也算截断（进窗前/出窗后不可见）。
assert(tr.tracks.TouchesWindowEdge(1));
assert(tr.summary.n_censored == 1 && tr.summary.n_uncensored == 0);
assert(isnan(tr.summary.lifetime_median_uncensored), ...
    '没有未截断样本时不该给出未截断寿命中位数。');
assert(isfinite(tr.summary.lifetime_median_all_lower_bound), ...
    '全体寿命下限仍应给出。');

% 不触边的结构不应被标 FOV 截断。
u_mid = zeros(ctx.J, ctx.I);
u_mid(3:6, 20:35) = 2.0;
store2 = {frame_record(ctx, resolved, u_mid, 1), ...
    frame_record(ctx, resolved, u_mid, 2)};
tr2 = tblR2.vlsmpod.track_structures(store2, ctx, struct());
assert(~tr2.tracks.TouchesFovBoundary(1), '不触边不该标 FOV 截断。');

% 缺标签图时必须明确报错——合并生效时标签图会被置空。
bad = store2;
bad{1}.positive_labels = [];
assert_error(@() tblR2.vlsmpod.track_structures(bad, ctx, struct()), ...
    'tblR2:vlsmpod:track_structures:MissingLabels');
end


% =========================================================================
function test_run_catalog_rejects_noncontiguous_tracking()
% 跳帧 + 追踪必须报错而不是给出无意义的结果：位移约 50 格，跳帧后不可能重叠。

[ctx, resolved] = synthetic_context();
source = struct('preprocessing', 'gaussian', 'cache_file', 'unused');
assert_error(@() tblR2.vlsmpod.run_catalog(ctx, source, resolved, ...
    struct('frame_ids', [1 3 5], 'tracking', struct('enabled', true), ...
    'progress', false)), ...
    'tblR2:vlsmpod:run_catalog:TrackingNeedsContiguous');

% 未知选项必须报错，防止打错名字后参数静默失效。
assert_error(@() tblR2.vlsmpod.run_catalog(ctx, source, resolved, ...
    struct('frame_ids', [1 2], 'wall_atached', struct('enabled', true))), ...
    'tblR2:vlsmpod:run_catalog:UnknownOption');
end


% =========================================================================
function [ctx, resolved] = synthetic_context()
%SYNTHETIC_CONTEXT 构造一个 10x60 的合成几何上下文。
% dx=dy=1mm，delta99=10mm -> 60 列 = 6*delta99，足以让长条超过 VLSM 阈值 3。

J = 10;
I = 60;
[X, Y] = meshgrid(1:I, 1:J);
delta = 10;

settings = struct('alpha', 0.5, 'seed_alpha', 0.5, 'min_pixels', 2, ...
    'connectivity', 4, 'min_lsm_delta', 1, 'min_vlsm_delta', 3, ...
    'max_wall_normal_delta', inf);
resolved = tblR2.vlsmpod.resolve_settings(settings);

ctx = struct();
ctx.J = J;
ctx.I = I;
ctx.X_mm = X;
ctx.Y_wall_mm = Y;
ctx.delta_grid = repmat(delta, J, I);
ctx.u_rms = ones(J, I);
ctx.valid_mask = true(J, I);
ctx.analysis_domain_mask = true(J, I);
ctx.dx_mm = 1;
ctx.dy_mm = 1;
ctx.u_tau = 1;
ctx.nu = 1e-5;
ctx.dt_s = 1e-3;
ctx.Uavex = zeros(J, I);
ctx.n_frames = 2;
ctx.cfg = struct('nu', 1e-5, 'fs', 1000);
ctx.stats = struct('v_rms', ones(J, I), 'Uavex', zeros(J, I), ...
    'Vavex', zeros(J, I));
ctx.mean_bl = struct();
ctx.resolved = resolved;
end


% =========================================================================
function rec = frame_record(ctx, resolved, u_field, frame_id)
%FRAME_RECORD 跑一帧识别，打包成 track_structures 要的 frame_store 元素。

field = struct('u_fluct', u_field, 'v_fluct', zeros(ctx.J, ctx.I), ...
    'mask', true(ctx.J, ctx.I), 'frame_id', frame_id, ...
    'preprocessing', 'synthetic');
identified = tblR2.vlsmpod.identify_frame(ctx, field, resolved);
rec = struct('frame_id', frame_id, ...
    'structures', identified.structures, ...
    'positive_labels', identified.positive_labels, ...
    'negative_labels', identified.negative_labels);
end


% =========================================================================
function assert_error(fh, expected_id)
try
    fh();
    error('test_r2_vlsmpod_extensions:MissingError', ...
        '期望抛出 %s，但没有报错。', expected_id);
catch err
    if strcmp(err.identifier, 'test_r2_vlsmpod_extensions:MissingError')
        rethrow(err);
    end
    assert(strcmp(err.identifier, expected_id), ...
        '期望 %s，实得 %s（%s）', expected_id, err.identifier, err.message);
end
end
