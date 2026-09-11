function report = run_vlsmpod_extension_audit(varargin)
%RUN_VLSMPOD_EXTENSION_AUDIT 三个新功能在真实数据上的小样本抽查。
%
% 只读上游缓存，产物落 tmp/vlsmpod_audit/，不碰 cases/*/output/ 的正式产物。
%
% 配置：E=50%（rank=382，复用已有 E80 基底的前缀），r1 识别参数
% （alpha=0.40/seed=0.70/conn=8，实测只有这组能识别出 VLSM）。
%
% 两组帧集：
%   sampled    24 帧（stride=500），给 wall-attached 与超结构分解——这两个是
%              逐帧独立量，抽样帧即可。
%   continuous 48 帧（frames 1..48，repeat 1 内），给时间追踪——追踪要连续帧。

parser = inputParser;
parser.addParameter('case_name', 'tandem_baseline_r2', @(x) ischar(x) || isstring(x));
parser.addParameter('energy_target', 0.50, @(x) isscalar(x) && x > 0 && x <= 1);
parser.addParameter('sampled_stride', 500, @(x) isscalar(x) && x >= 1);
parser.addParameter('sampled_max_frames', 24, @(x) isscalar(x) && x >= 1);
parser.addParameter('continuous_frames', 48, @(x) isscalar(x) && x >= 2);
parser.addParameter('structure_overrides', ...
    struct('alpha', 0.40, 'seed_alpha', 0.70, 'connectivity', 8), @isstruct);
parser.addParameter('output_dir', '', @(x) ischar(x) || isstring(x));
parser.parse(varargin{:});
opt = parser.Results;
case_name = char(opt.case_name);

script_dir = fileparts(mfilename('fullpath'));
if isempty(script_dir) || contains(script_dir, fullfile('Temp', 'Editor_'))
    script_dir = pwd;
end
repo_root = fileparts(fileparts(fileparts(script_dir)));
per_case_root = fullfile(repo_root, 'cases', 'per_case');
addpath(fullfile(repo_root, 'lib'));
addpath(fullfile(repo_root, 'tools', 'research'));
case_root = fullfile(per_case_root, case_name);

if isempty(opt.output_dir)
    out_dir = fullfile(repo_root, 'tmp', 'vlsmpod_audit');
else
    out_dir = char(opt.output_dir);
end
if ~isfolder(out_dir); mkdir(out_dir); end

% ------------------------------------------------------------- 上游结果
cfg = tblR2.vlsmpod.load_case_config(case_root, case_name);
paths = tblR2.build_paths(cfg.output_dir);
stats = tblR2.load_result(paths.statistics, cfg, 'statistics');
mean_bl = tblR2.load_result(paths.mean_bl, cfg, 'mean_bl');

resolved = tblR2.vlsmpod.resolve_settings(cfg.structures, opt.structure_overrides);
ctx = tblR2.vlsmpod.prepare_context(cfg, stats, mean_bl, resolved);

fprintf('=== +vlsmpod 三功能真实数据抽查 ===\n');
fprintf('u_tau=%.4g  nu=%.4g  dx=%.4g mm  dy=%.4g mm  dt=%.4g s\n', ...
    ctx.u_tau, ctx.nu, ctx.dx_mm, ctx.dy_mm, ctx.dt_s);
fprintf('最低有效行 y+ = %.4g（Hwang&Sung 内尺度判据在此不可用，改外尺度）\n', ...
    min(ctx.Y_wall_mm(ctx.analysis_domain_mask)) * 1e-3 * ctx.u_tau / ctx.nu);

% --------------------------------------------------------- POD E=50% 基底
basis_cache = fullfile(repo_root, 'tmp', 'pod_energy_sweep', ...
    'pod_energy_sweep_basis.mat');
if ~isfile(basis_cache)
    error('vlsmpodAudit:MissingBasis', '找不到 E80 基底：%s', basis_cache);
end
loaded = load(basis_cache, 'denoise');
denoise = loaded.denoise;
cumulative = cumsum(denoise.eigenvalues) / sum(denoise.eigenvalues);
rank_r = find(cumulative >= opt.energy_target, 1, 'first');
if isempty(rank_r); rank_r = numel(cumulative); end
rank_r = min(rank_r, denoise.rank);
fprintf('POD E=%.0f%% -> rank=%d（累计能量 %.4f）\n', ...
    100 * opt.energy_target, rank_r, cumulative(rank_r));

source = struct('preprocessing', 'pod_denoise', 'denoise', denoise, ...
    'mode_indices', 1:rank_r, 'cache_file', paths.sequence_cache_postproc);

% ============================================ (a)+(b) sampled 24 帧
sampled_ids = denoise.frame_ids(1:opt.sampled_stride:end).';
sampled_ids = sampled_ids(1:min(numel(sampled_ids), opt.sampled_max_frames));
fprintf('\n--- (a) wall-attached + (b) 超结构分解：%d 帧 ---\n', numel(sampled_ids));
sampled = tblR2.vlsmpod.run_catalog(ctx, source, resolved, struct( ...
    'frame_ids', sampled_ids, ...
    'wall_attached', struct('enabled', true), ...
    'superstructure', struct('enabled', true), ...
    'progress_steps', 4));

% ================================================= (c) continuous 48 帧
continuous_ids = denoise.frame_ids(1:opt.continuous_frames).';
fprintf('\n--- (c) 时间追踪：%d 连续帧 ---\n', numel(continuous_ids));
continuous = tblR2.vlsmpod.run_catalog(ctx, source, resolved, struct( ...
    'frame_ids', continuous_ids, ...
    'wall_attached', struct('enabled', true), ...
    'tracking', struct('enabled', true), ...
    'progress_steps', 4));

% -------------------------------------------------------------- 汇总打印
report = struct();
report.sampled = sampled;
report.continuous = continuous;
report.rank = rank_r;
report.energy_target = opt.energy_target;
report.structure_opts = resolved.opts;
report.case_name = case_name;

print_wall_attached(sampled);
print_superstructure(sampled);
print_tracking(continuous);

save(fullfile(out_dir, 'vlsmpod_extension_audit.mat'), 'report', '-v7.3');
fprintf('\n结果已保存：%s\n', fullfile(out_dir, 'vlsmpod_extension_audit.mat'));
fprintf('AUDIT_DONE\n');
end

% =========================================================================
function print_wall_attached(r)
w = r.wall_attached;
fprintf('\n(a) Wall-Attached 分类（判据：YMin/delta99 < %.3g，外尺度）\n', ...
    r.catalog.AttachedDeltaThreshold(1));
fprintf('    结构总数        : %d\n', w.n_total);
fprintf('    attached        : %d（%.1f%%）\n', w.n_attached, ...
    100 * w.attached_fraction);
fprintf('    detached        : %d（%.1f%%）\n', w.n_detached, ...
    100 * (1 - w.attached_fraction));
fprintf('    attached 面积占比: %.1f%%\n', 100 * w.attached_area_fraction);
fprintf('    -> 对照 Hwang&Sung: attached 数量占比 20%%、体积占比 67%%\n');

att = r.catalog(r.catalog.IsWallAttached, :);
det = r.catalog(~r.catalog.IsWallAttached, :);
fprintf('    YMin_plus 范围   : attached %.1f-%.1f | detached %.1f-%.1f\n', ...
    min(att.YMin_plus), max(att.YMin_plus), ...
    min(det.YMin_plus), max(det.YMin_plus));
if ~isempty(att)
    fprintf('    attached 中 VLSM : %d / %d\n', sum(att.IsVLSM), height(att));
end

pd = w.population_density;
if height(pd) > 0
    fprintf('    population density n_s(l_y)（检验 attached-eddy 的 1/l_y 预言）:\n');
    fprintf('      %10s %8s %12s\n', 'l_y中心(mm)', '计数', '密度');
    for k = 1:height(pd)
        if pd.Count(k) == 0; continue; end
        fprintf('      %10.3g %8d %12.4g\n', pd.BinCenter(k), pd.Count(k), ...
            pd.Density(k));
    end
end
end

% =========================================================================
function print_superstructure(r)
s = r.superstructure;
fprintf('\n(b) 超结构自相似分解（v'' 零穿越找拼接点）\n');
fprintf('    分解的 VLSM 数   : %d\n', s.n_vlsm_analyzed);
if s.n_vlsm_analyzed == 0
    fprintf('    （本帧集无 VLSM，无法分解）\n');
    return;
end
fprintf('    子结构数 均值/中位: %.2f / %.1f\n', s.n_sub_mean, s.n_sub_median);
fprintf('    子结构段长中位   : %.3f delta99\n', s.sub_length_median_over_delta);
fprintf('    总长-段长相关    : %.3f\n', s.total_vs_sub_correlation);
fprintf('    -> 相关接近 0 支持 concatenation（子结构尺度不随总长变化）；\n');
fprintf('       接近 1 说明只是按比例切分，没揭示物理拼接单元。\n');
h = s.n_sub_histogram;
fprintf('    子结构数分布     : ');
for k = 1:height(h)
    fprintf('%d段×%d ', h.NSub(k), h.Count(k));
end
fprintf('\n');

vlsm = r.catalog(r.catalog.IsVLSM & isfinite(r.catalog.NSubStructures), :);
if ~isempty(vlsm)
    fprintf('    VLSM 总长范围    : %.2f - %.2f delta99\n', ...
        min(vlsm.LengthX_over_delta), max(vlsm.LengthX_over_delta));
end
end

% =========================================================================
function print_tracking(r)
t = r.tracking.summary;
fprintf('\n(c) 时间分辨追踪（逐结构 Galilean 补偿 + overlap 匹配）\n');
fprintf('    帧数            : %d（连续）\n', t.n_frames);
fprintf('    overlap 阈值     : %.2f，Galilean 补偿 = %d\n', ...
    t.overlap_threshold, t.galilean_shift);
fprintf('    实测帧间位移     : %.1f 格（FOV %d 格 -> 穿越 %.1f 帧）\n', ...
    t.median_shift_cells, t.fov_cells, t.fov_transit_frames);
fprintf('    track 总数       : %d\n', t.n_tracks);
fprintf('    截断 track       : %d（%.1f%%）<- 寿命是下限，不是真值\n', ...
    t.n_censored, 100 * t.censored_fraction);
fprintf('    未截断 track     : %d\n', t.n_uncensored);
if t.n_uncensored > 0
    fprintf('    未截断寿命 中位/最大: %.1f / %.1f 帧\n', ...
        t.lifetime_median_uncensored, t.lifetime_max_uncensored);
    fprintf('    未截断像素范围   : %g - %g（注意选择偏差：只覆盖小/短结构）\n', ...
        t.uncensored_pixel_range(1), t.uncensored_pixel_range(2));
else
    fprintf('    （无未截断样本 -> 本窗口内无法给出真实寿命）\n');
end
fprintf('    全体寿命中位下限 : %.1f 帧\n', t.lifetime_median_all_lower_bound);
% 两种口径都打出来并标明，否则事件表里的 split 数与这里的速率换算不上，
% 读者会以为其中一个错了。
fprintf('    split/merge 链接 : %d / %d（事件表口径）-> %.2f / %.2f 每帧对\n', ...
    t.total_split_links, t.total_merge_links, ...
    t.splits_per_frame_pair, t.merges_per_frame_pair);
fprintf('    发生分裂/合并的结构数: %d / %d（节点口径，一裂为三记 1）\n', ...
    t.n_structures_splitting, t.n_structures_merging);
if t.total_split_links + t.total_merge_links > 0
    fprintf('    -> direct/inverse cascade 之比 = %.2f\n', ...
        t.total_split_links / max(1, t.total_merge_links));
end
c = t.caveats;
fprintf('    [口径限制] 断链链接占比 %.0f%%（split/merge 按设计断链）\n', ...
    100 * c.chain_break_fraction);
if c.lifetime_ceiling_is_fov
    fprintf('    [口径限制] 最大寿命 %d 帧已达 FOV 穿越 %.1f 帧的 80%%以上：\n', ...
        c.max_lifetime_observed, c.fov_transit_frames);
    fprintf('               寿命上限由 FOV 决定，T~V^(1/3) 不可在此数据上拟合。\n');
end
if ~c.window_adequate
    fprintf('    [口径限制] 窗口 %d 帧 < 4x FOV 穿越时间，长寿命结构被窗口截断。\n', ...
        c.window_frames);
end
disp(t.event_counts);
end
