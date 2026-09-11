function report = run_vlsm_24frame_comparison(varargin)
%RUN_VLSM_24FRAME_COMPARISON 24 帧 VLSM 聚类连通法测试：高斯 vs POD E=50%。
%
% 产出瞬时流向脉动速度场云图 + LSM/VLSM 包围盒，两个预处理条件各一套，再加一套
% 上下并排的对照图。只读上游缓存，产物落 tmp/vlsm_24frame_test/。
%
% 帧集：stride=500 取 24 帧（1, 501, ..., 11501），跨两个 repeat。与已有的
% pod_energy_sweep / vlsmpod_audit 同帧集，结果可直接交叉核对。
%
% 两个条件用**完全相同的识别参数**（alpha=0.40/seed=0.70/conn=8，实测只有这组
% 能识别出 VLSM）。否则「POD 好还是高斯好」会被识别参数的差异污染。
%
% E=50% 基底复用已有的 E80 基底取前 382 阶——POD 模态与截断秩无关，低档就是高档
% 的前缀，省掉一次 12000x12000 特征分解。
%
% 绘图用 contourf：项目约定（commit 1d63a31）瞬时场必须是填充等值线图，不得退化
% 成散点——散点会让实测场看起来像一堆圆点而非速度场。

parser = inputParser;
parser.addParameter('case_name', 'tandem_baseline_r2', @(x) ischar(x) || isstring(x));
parser.addParameter('frame_stride', 500, @(x) isscalar(x) && x >= 1 && x == fix(x));
parser.addParameter('n_frames', 24, @(x) isscalar(x) && x >= 1 && x == fix(x));
parser.addParameter('energy_target', 0.50, @(x) isscalar(x) && x > 0 && x <= 1);
parser.addParameter('structure_overrides', ...
    struct('alpha', 0.40, 'seed_alpha', 0.70, 'connectivity', 8), @isstruct);
parser.addParameter('clim_sigma', 3, @(x) isscalar(x) && x > 0);
parser.addParameter('n_levels', 24, @(x) isscalar(x) && x >= 4);
parser.addParameter('output_dir', '', @(x) ischar(x) || isstring(x));
parser.parse(varargin{:});
opt = parser.Results;
case_name = char(opt.case_name);

% ------------------------------------------------------------------ 路径
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
    out_root = fullfile(repo_root, 'tmp', 'vlsm_24frame_test');
else
    out_root = char(opt.output_dir);
end
dir_gauss = fullfile(out_root, 'gaussian');
dir_pod = fullfile(out_root, 'e50');
dir_cmp = fullfile(out_root, 'compare');
for d = {out_root, dir_gauss, dir_pod, dir_cmp}
    if ~isfolder(d{1}); mkdir(d{1}); end
end

% ------------------------------------------------------------- 上游结果
cfg = tblR2.vlsmpod.load_case_config(case_root, case_name);
paths = tblR2.build_paths(cfg.output_dir);
stats = tblR2.load_result(paths.statistics, cfg, 'statistics');
mean_bl = tblR2.load_result(paths.mean_bl, cfg, 'mean_bl');
resolved = tblR2.vlsmpod.resolve_settings(cfg.structures, opt.structure_overrides);
ctx = tblR2.vlsmpod.prepare_context(cfg, stats, mean_bl, resolved);

fprintf('=== 24 帧 VLSM 聚类连通法对照测试 ===\n');
fprintf('识别参数 : alpha=%.2f seed=%.2f conn=%d min_px=%d\n', ...
    resolved.opts.alpha, resolved.opts.seed_alpha, ...
    resolved.opts.connectivity, resolved.opts.min_pixels);
fprintf('LSM 判据 : Lx/d99 >= %g   VLSM 判据 : Lx/d99 >= %g\n', ...
    resolved.opts.min_lsm_delta, resolved.opts.min_vlsm_delta);

% --------------------------------------------------------- POD E=50% 基底
basis_cache = fullfile(repo_root, 'tmp', 'pod_energy_sweep', ...
    'pod_energy_sweep_basis.mat');
if ~isfile(basis_cache)
    error('vlsm24:MissingBasis', ...
        ['找不到 POD 基底：%s\n请先运行 tools/research/r2_diagnostics/run_pod_energy_sweep.m。'], ...
        basis_cache);
end
loaded = load(basis_cache, 'denoise');
denoise = loaded.denoise;
cumulative = cumsum(denoise.eigenvalues) / sum(denoise.eigenvalues);
rank_r = find(cumulative >= opt.energy_target, 1, 'first');
if isempty(rank_r); rank_r = numel(cumulative); end
rank_r = min(rank_r, denoise.rank);
fprintf('POD E=%.0f%% -> rank=%d（累计能量 %.4f，基底秩 %d）\n', ...
    100 * opt.energy_target, rank_r, cumulative(rank_r), denoise.rank);

% ------------------------------------------------------------- 帧集
frame_ids = denoise.frame_ids(1:opt.frame_stride:end).';
frame_ids = frame_ids(1:min(numel(frame_ids), opt.n_frames));
fprintf('帧集     : %d 帧（stride=%d，%d..%d）\n', ...
    numel(frame_ids), opt.frame_stride, frame_ids(1), frame_ids(end));

sources = struct( ...
    'label', {'高斯 9x9', sprintf('POD E=%.0f%% (rank=%d)', ...
        100 * opt.energy_target, rank_r)}, ...
    'tag', {'gaussian', 'e50'}, ...
    'dir', {dir_gauss, dir_pod}, ...
    'spec', { ...
        struct('preprocessing', 'gaussian', ...
            'cache_file', paths.sequence_cache_postproc), ...
        struct('preprocessing', 'pod_denoise', 'denoise', denoise, ...
            'mode_indices', 1:rank_r, ...
            'cache_file', paths.sequence_cache_postproc)});

% 颜色范围两个条件共用，否则同一帧的两张图颜色不可比。
clim_val = opt.clim_sigma * median(stats.u_rms(ctx.valid_mask), 'omitnan');
levels = linspace(-clim_val, clim_val, opt.n_levels);
fprintf('色标     : +-%.3f m/s（%g x u_rms 空间中位数），%d 级\n\n', ...
    clim_val, opt.clim_sigma, opt.n_levels);

% ------------------------------------------------------- 逐条件逐帧
n = numel(frame_ids);
store = struct('tag', {}, 'label', {}, 'catalog', {}, 'per_frame', {}, ...
    'fields', {});
for si = 1:numel(sources)
    src = sources(si);
    fprintf('--- [%d/%d] %s ---\n', si, numel(sources), src.label);
    cells = cell(n, 1);
    pf = struct('frame_id', num2cell(frame_ids(:)), ...
        'n_structures', num2cell(zeros(n, 1)), ...
        'n_lsm', num2cell(zeros(n, 1)), ...
        'n_vlsm', num2cell(zeros(n, 1)));
    fields = cell(n, 1);

    for k = 1:n
        fid = frame_ids(k);
        field = tblR2.vlsmpod.frame_field(ctx, fid, src.spec);
        identified = tblR2.vlsmpod.identify_frame(ctx, field, resolved);
        T = identified.structures;

        fields{k} = field.u_fluct;
        cells{k} = tblR2.vlsmpod.annotate(T, fid, 'total', src.tag);
        pf(k).n_structures = height(T);
        pf(k).n_lsm = sum(T.IsLSM);
        pf(k).n_vlsm = sum(T.IsVLSM);

        % 单条件图
        fig = new_field_figure([24 6.5]);
        ax = axes(fig); %#ok<LAXES>
        draw_field(ax, ctx, field.u_fluct, levels, clim_val);
        draw_boxes(ax, T);
        finish_axes(ax, true);
        title(ax, sprintf('%s   frame %d   结构 %d / LSM %d / VLSM %d', ...
            src.label, fid, height(T), sum(T.IsLSM), sum(T.IsVLSM)), ...
            'FontSize', 8, 'FontWeight', 'normal');
        export_fig(fig, fullfile(src.dir, sprintf('frame_%05d.png', fid)));

        if mod(k, max(1, floor(n / 6))) == 0 || k == n
            fprintf('  %2d/%d 帧（结构 %3d，LSM %2d，VLSM %2d）\n', k, n, ...
                pf(k).n_structures, pf(k).n_lsm, pf(k).n_vlsm);
        end
    end

    rec = struct();
    rec.tag = src.tag;
    rec.label = src.label;
    rec.catalog = vertcat(cells{:});
    rec.per_frame = pf;
    rec.fields = fields;
    store(si) = rec; %#ok<AGROW>
    fprintf('  图已保存：%s\n', src.dir);
end

% ------------------------------------------------------- 并排对照图
fprintf('\n--- 并排对照图 ---\n');
for k = 1:n
    fid = frame_ids(k);
    fig = new_field_figure([24 11]);
    for si = 1:2
        ax = subplot(2, 1, si, 'Parent', fig);
        T = store(si).catalog(store(si).catalog.FrameID == fid, :);
        draw_field(ax, ctx, store(si).fields{k}, levels, clim_val);
        draw_boxes(ax, T);
        finish_axes(ax, si == 2);
        title(ax, sprintf('%s   结构 %d / LSM %d / VLSM %d', ...
            store(si).label, height(T), sum(T.IsLSM), sum(T.IsVLSM)), ...
            'FontSize', 8, 'FontWeight', 'normal');
    end
    sgtitle(fig, sprintf(['frame %d   识别参数 alpha=%.2f seed=%.2f conn=%d' ...
        '   （蓝虚线 LSM，红实线 VLSM）'], fid, resolved.opts.alpha, ...
        resolved.opts.seed_alpha, resolved.opts.connectivity), 'FontSize', 9);
    export_fig(fig, fullfile(dir_cmp, sprintf('frame_%05d.png', fid)));
end
fprintf('  %d 张已保存：%s\n', n, dir_cmp);

% -------------------------------------------------------------- 汇总
report = struct();
report.case_name = case_name;
report.frame_ids = frame_ids(:);
report.structure_opts = resolved.opts;
report.structure_overrides = opt.structure_overrides;
report.pod_rank = rank_r;
report.pod_energy_target = opt.energy_target;
report.pod_energy_at_rank = cumulative(rank_r);
report.pod_basis_cache = basis_cache;
report.clim_val = clim_val;
report.output_dir = out_root;
for si = 1:numel(store)
    s = struct();
    s.label = store(si).label;
    s.catalog = store(si).catalog;
    s.per_frame = store(si).per_frame;
    s.summary = summarize(store(si).per_frame, store(si).catalog);
    report.(store(si).tag) = s;
end
report.definition = ['24 帧 VLSM 聚类连通法对照测试。两个预处理条件（高斯 9x9 与 ' ...
    'POD E=50% 低秩重构）使用完全相同的识别参数，瞬时流向脉动场云图叠加 ' ...
    'LSM/VLSM 包围盒。fields 未落盘（每帧 89x640 double，24 帧两条件约 22 MB ' ...
    '可按需重算）。'];

save(fullfile(out_root, 'vlsm_24frame_test.mat'), 'report', '-v7.3');
print_comparison(report, store);
fprintf('\n结果已保存：%s\n', fullfile(out_root, 'vlsm_24frame_test.mat'));
fprintf('COMPARISON_DONE\n');
end

% =========================================================================
function fig = new_field_figure(size_cm)
fig = figure('Visible', 'off', 'Units', 'centimeters', ...
    'Position', [1 1 size_cm(1) size_cm(2)], 'Color', 'w');
end

% =========================================================================
function draw_field(ax, ctx, u_fluct, levels, clim_val)
%DRAW_FIELD 瞬时流向脉动场填充等值线图。
%
% 用 contourf 而非 pcolor/scatter：项目约定（commit 1d63a31）。contourf 对内部
% NaN 区域留空，保持场的拓扑；散点渲染会把实测场画成一堆圆点。

contourf(ax, ctx.X_mm, ctx.Y_wall_mm, u_fluct, levels, 'LineStyle', 'none');
colormap(ax, blue_white_red(256));
caxis(ax, [-clim_val clim_val]);
hold(ax, 'on');
end

% =========================================================================
function draw_boxes(ax, T)
%DRAW_BOXES LSM 蓝虚线、VLSM 红实线加粗。
% VLSM 后画，保证与 LSM 重叠时红框可见。

draw_class(ax, T, T.IsLSM & ~T.IsVLSM, [0.10 0.35 0.95], '--', 1.0);
draw_class(ax, T, T.IsVLSM, [0.90 0.05 0.05], '-', 1.8);
end

% =========================================================================
function draw_class(ax, T, mask, color, style, lw)
idx = find(mask);
for i = 1:numel(idx)
    w = T.XMax_mm(idx(i)) - T.XMin_mm(idx(i));
    h = T.YMax_mm(idx(i)) - T.YMin_mm(idx(i));
    if w <= 0 || h <= 0; continue; end
    rectangle(ax, 'Position', ...
        [T.XMin_mm(idx(i)) T.YMin_mm(idx(i)) w h], ...
        'EdgeColor', color, 'LineStyle', style, 'LineWidth', lw);
end
end

% =========================================================================
function finish_axes(ax, show_xlabel)
axis(ax, 'tight');
set(ax, 'YDir', 'normal', 'FontSize', 7, 'TickDir', 'out', 'Layer', 'top');
if show_xlabel
    xlabel(ax, 'x (mm)', 'FontSize', 8);
end
ylabel(ax, 'y_{wall} (mm)', 'FontSize', 8);
cb = colorbar(ax);
ylabel(cb, "u' (m/s)", 'FontSize', 8);
set(cb, 'FontSize', 7);
end

% =========================================================================
function export_fig(fig, fname)
if exist('exportgraphics', 'file') == 2
    exportgraphics(fig, fname, 'Resolution', 200);
else
    print(fig, fname, '-dpng', '-r200');
end
close(fig);
end

% =========================================================================
function cmap = blue_white_red(n)
half = floor(n / 2);
blue = [linspace(0, 1, half)', linspace(0, 1, half)', ones(half, 1)];
red = [ones(half, 1), linspace(1, 0, half)', linspace(1, 0, half)'];
if mod(n, 2) == 1
    cmap = [blue; 1 1 1; red];
else
    cmap = [blue; red];
end
end

% =========================================================================
function s = summarize(pf, catalog)
s = struct();
s.n_frames = numel(pf);
s.total_structures = height(catalog);
s.total_lsm = sum([pf.n_lsm]);
s.total_vlsm = sum([pf.n_vlsm]);
s.mean_structures_per_frame = mean([pf.n_structures]);
s.mean_lsm_per_frame = mean([pf.n_lsm]);
s.mean_vlsm_per_frame = mean([pf.n_vlsm]);
s.frames_with_vlsm = nnz([pf.n_vlsm] > 0);
if isempty(catalog)
    s.length_median_over_delta = NaN;
    s.length_p90_over_delta = NaN;
    s.length_max_over_delta = NaN;
    s.pixel_median = NaN;
    return;
end
lx = catalog.LengthX_over_delta;
s.length_median_over_delta = median(lx, 'omitnan');
s.length_p90_over_delta = prctile(lx, 90);
s.length_max_over_delta = max(lx, [], 'omitnan');
s.pixel_median = median(double(catalog.PixelCount), 'omitnan');
end

% =========================================================================
function print_comparison(report, store)
fprintf('\n=== 对照汇总（%d 帧，识别参数完全相同）===\n', ...
    numel(report.frame_ids));
fprintf('%-26s %9s %8s %8s %10s %10s %10s %9s\n', ...
    '条件', '每帧结构', '每帧LSM', '每帧VLSM', 'Lx中位/d', 'Lx_p90/d', ...
    'Lx最大/d', '像素中位');
for si = 1:numel(store)
    s = report.(store(si).tag).summary;
    fprintf('%-26s %9.2f %8.2f %8.2f %10.3f %10.3f %10.3f %9.0f\n', ...
        store(si).label, s.mean_structures_per_frame, ...
        s.mean_lsm_per_frame, s.mean_vlsm_per_frame, ...
        s.length_median_over_delta, s.length_p90_over_delta, ...
        s.length_max_over_delta, s.pixel_median);
end
fprintf('\n');
for si = 1:numel(store)
    s = report.(store(si).tag).summary;
    fprintf('%-26s 结构总数 %5d，LSM %4d，VLSM %3d，含 VLSM 的帧 %d/%d\n', ...
        store(si).label, s.total_structures, s.total_lsm, s.total_vlsm, ...
        s.frames_with_vlsm, s.n_frames);
end
end
