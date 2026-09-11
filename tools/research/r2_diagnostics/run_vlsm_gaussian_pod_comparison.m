function report = run_vlsm_gaussian_pod_comparison(varargin)
%RUN_VLSM_GAUSSIAN_POD_COMPARISON 随机 N 帧对照：方向性高斯模糊 vs POD 低阶重构。
%
% 两个预处理条件走同一套聚类连通法识别参数，逐帧出瞬时流向脉动速度场 contourf +
% LSM/VLSM 包围盒，再出上下并排对照图。只读上游缓存，产物落 tmp/ 下。
%
%   条件 A：方向性高斯模糊。当前诊断工程默认 31x3（流向 31 格 x 法向 3 格），
%           以流向平滑为主，用于和原先的各向同性 9x9 及 POD 重构对照；
%           该参数不是通用文献标准，也不代表已经完成物理尺度标定。
%   条件 B：POD 低阶模态重构，默认累计能量 E=50%。
%
% 用法（两组参数都可改，改完直接出新的对照结果；输出目录按参数自动分开命名，
% 不会覆盖上一轮）
%   run_vlsm_gaussian_pod_comparison();                       % 默认 31x3 + E=50%
%   run_vlsm_gaussian_pod_comparison('gaussian_window', [15 3]);
%   run_vlsm_gaussian_pod_comparison('gaussian_window', [11 1]);   % 纯一维流向
%   run_vlsm_gaussian_pod_comparison('gaussian_sigma', [2.5 0.4]); % 直接给 sigma
%   run_vlsm_gaussian_pod_comparison('energy_target', 0.30);
%   run_vlsm_gaussian_pod_comparison('gaussian_window', [11 3], ...
%       'energy_target', 0.65, 'n_frames', 24);
%   run_vlsm_gaussian_pod_comparison('include_isotropic_baseline', true);
%       % 再加一条原先的各向同性 9x9，做三条件对照
%
% 参数
%   n_frames        抽帧数，默认 48
%   random_seed     抽帧随机种子，默认 20260825。同种子同帧集，结果可复现
%   frame_ids       直接指定帧号，给了就不随机抽（用于复现某一轮）
%   gaussian_window [流向 法向] 核尺寸，单位网格点，必须都是奇数。默认 [31 3]
%                   （当前诊断工程默认）
%   gaussian_sigma  [流向 法向] 高斯标准差。留空则按核尺寸自动取
%                   sigma = 0.375 * radius；默认 [31 3] 对应 [5.625 0.375]。
%                   该比例复刻本项目既有的 9x9/sigma=1.5 口径，并保持两方向
%                   相同的 radius/sigma 截断比；它用于维持现有产物可复现，
%                   不等同于通用文献标准或已验证的科学最优值
%   energy_target   POD 累计能量目标，默认 0.50。上限受已缓存基底的秩约束，
%                   超出会直接报错并给出可用上限，不静默截断
%   structure_overrides 识别参数覆盖。默认 r1 组（alpha=0.40/seed=0.70/conn=8）——
%                   实测只有这组能在本工况识别出 VLSM，缓存 cfg 里固化的 1.77/1.97
%                   会得到 VLSM=0
%
% 绘图用 contourf：项目约定（commit 1d63a31）瞬时场必须是填充等值线图，不得退化
% 成散点。框线约定见 plot_structure_field.m。

parser = inputParser;
parser.addParameter('case_name', 'tandem_baseline_r2', @(x) ischar(x) || isstring(x));
parser.addParameter('n_frames', 48, @(x) isscalar(x) && x >= 1 && x == fix(x));
parser.addParameter('random_seed', 20260825, @(x) isscalar(x) && x >= 0 && x == fix(x));
parser.addParameter('frame_ids', [], @(x) isempty(x) || (isnumeric(x) && isvector(x)));
parser.addParameter('gaussian_window', [31 3], @(x) isnumeric(x) && numel(x) == 2);
parser.addParameter('gaussian_sigma', [], @(x) isempty(x) || ...
    (isnumeric(x) && (isscalar(x) || numel(x) == 2)));
parser.addParameter('energy_target', 0.50, @(x) isscalar(x) && x > 0 && x <= 1);
parser.addParameter('include_isotropic_baseline', false, ...
    @(x) islogical(x) || isnumeric(x));
parser.addParameter('structure_overrides', ...
    struct('alpha', 0.40, 'seed_alpha', 0.70, 'connectivity', 8), @isstruct);
parser.addParameter('colorbar_abs_limit', 3.0, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
parser.addParameter('n_levels', 24, @(x) isscalar(x) && x >= 4);
parser.addParameter('output_dir', '', @(x) ischar(x) || isstring(x));
parser.parse(varargin{:});
opt = parser.Results;
case_name = char(opt.case_name);
% -------------------------------------------------- 高斯核参数解析与校验
window = double(opt.gaussian_window(:).');
if any(~isfinite(window)) || any(window < 1) || any(mod(window, 2) ~= 1)
    error('vlsmGP:InvalidWindow', ...
        ['gaussian_window 必须是两个 >= 1 的奇数 [流向 法向]，当前为 [%g %g]。\n' ...
        '核是对称的 2*radius+1，偶数核会引入半格中心偏移。'], window(1), window(2));
end
radius_xy = (window - 1) / 2;
if any(radius_xy < 1)
    error('vlsmGP:WindowTooSmall', ...
        ['gaussian_window 的两个分量都必须 >= 3（radius >= 1）：' ...
        'simple_gaussian_filter2 要求 radius >= 1，window=1 会被它拒绝。\n' ...
        '要在某个方向上「几乎不平滑」，用 window=3 配一个很小的 sigma。']);
end
if isempty(opt.gaussian_sigma)
    % 0.375 = 1.5/4，复刻项目既有的 9x9 -> sigma=1.5 口径。
    sigma_xy = 0.375 * radius_xy;
else
    sigma_xy = double(opt.gaussian_sigma(:).');
    if isscalar(sigma_xy); sigma_xy = [sigma_xy sigma_xy]; end
end
if any(~isfinite(sigma_xy)) || any(sigma_xy <= 0)
    error('vlsmGP:InvalidSigma', 'gaussian_sigma 的两个分量都必须是有限正数。');
end

% ------------------------------------------------------------------ 路径
script_dir = fileparts(mfilename('fullpath'));
if isempty(script_dir) || contains(script_dir, fullfile('Temp', 'Editor_'))
    script_dir = pwd;
end
addpath(script_dir);   % make_gaussian_spec / plot_structure_field 在同一目录
repo_root = fileparts(fileparts(fileparts(script_dir)));
per_case_root = fullfile(repo_root, 'cases', 'per_case');
addpath(fullfile(repo_root, 'lib'));
addpath(fullfile(repo_root, 'tools', 'research'));
case_root = fullfile(per_case_root, case_name);
% 输出目录按参数命名，改参数不会覆盖上一轮结果。
run_tag = sprintf('g%dx%d_s%s-%s_E%02d', window(1), window(2), ...
    num_tag(sigma_xy(1)), num_tag(sigma_xy(2)), round(100 * opt.energy_target));
if isempty(opt.output_dir)
    out_root = fullfile(repo_root, 'tmp', 'vlsm_gaussian_pod_comparison', run_tag);
else
    out_root = char(opt.output_dir);
end
dir_gauss = fullfile(out_root, 'gaussian_directional');
dir_pod = fullfile(out_root, 'pod_lowrank');
dir_iso = fullfile(out_root, 'gaussian_isotropic');
dir_cmp = fullfile(out_root, 'compare');
want_iso = logical(opt.include_isotropic_baseline);
dirs_needed = {out_root, dir_gauss, dir_pod, dir_cmp};
if want_iso; dirs_needed{end + 1} = dir_iso; end
for d = dirs_needed
    if ~isfolder(d{1}); mkdir(d{1}); end
end

% ------------------------------------------------------------- 上游结果
cfg = tblR2.vlsmpod.load_case_config(case_root, case_name);
paths = tblR2.build_paths(cfg.output_dir);
stats = tblR2.load_result(paths.statistics, cfg, 'statistics');
mean_bl = tblR2.load_result(paths.mean_bl, cfg, 'mean_bl');
resolved = tblR2.vlsmpod.resolve_settings(cfg.structures, opt.structure_overrides);
ctx = tblR2.vlsmpod.prepare_context(cfg, stats, mean_bl, resolved);

fprintf('=== 高斯模糊 vs POD 低阶重构：VLSM 聚类连通法对照 ===\n');
fprintf('识别参数 : alpha=%.2f seed=%.2f conn=%d min_px=%d（两条件完全相同）\n', ...
    resolved.opts.alpha, resolved.opts.seed_alpha, ...
    resolved.opts.connectivity, resolved.opts.min_pixels);
fprintf('LSM 判据 : Lx/d99 >= %g   VLSM 判据 : Lx/d99 >= %g\n', ...
    resolved.opts.min_lsm_delta, resolved.opts.min_vlsm_delta);
fprintf('网格间距 : dx=%.3f mm  dy=%.3f mm\n', ctx.dx_mm, ctx.dy_mm);
% ------------------------------------------------- 方向性高斯预处理规格
% resolve_settings 刻意不预填方向性字段，所以必须走 make_gaussian_spec 把四个
% 方向性字段一次填满——只改标量别名 sigma_cells 是无效的（见该函数注释）。
gauss_spec = make_gaussian_spec(resolved.preprocess_spec, sigma_xy, radius_xy);
ctx_gauss = ctx;
ctx_gauss.resolved.preprocess_spec = gauss_spec;

iso_spec = struct();
ctx_iso = struct();
if want_iso
    iso_spec = make_gaussian_spec(resolved.preprocess_spec, 1.5, 4);
    ctx_iso = ctx;
    ctx_iso.resolved.preprocess_spec = iso_spec;
end

fprintf('\n--- 高斯核（条件 A）---\n');
fprintf('核尺寸   : %d(流向) x %d(法向) 网格点 = %.2f x %.2f mm\n', ...
    window(1), window(2), window(1) * ctx.dx_mm, window(2) * ctx.dy_mm);
fprintf('sigma    : x=%.4g  y=%.4g 网格点 = %.3f x %.3f mm\n', ...
    sigma_xy(1), sigma_xy(2), sigma_xy(1) * ctx.dx_mm, sigma_xy(2) * ctx.dy_mm);
fprintf('spec.name: %s\n', gauss_spec.name);
print_kernel_weights('流向 x', radius_xy(1), sigma_xy(1));
print_kernel_weights('法向 y', radius_xy(2), sigma_xy(2));

% --------------------------------------------------------- POD 基底与秩
basis_cache = fullfile(repo_root, 'tmp', 'pod_energy_sweep', ...
    'pod_energy_sweep_basis.mat');
if ~isfile(basis_cache)
    error('vlsmGP:MissingBasis', ...
        ['找不到 POD 基底：%s\n请先运行 tools/research/r2_diagnostics/run_pod_energy_sweep.m。'], ...
        basis_cache);
end
loaded = load(basis_cache, 'denoise');
denoise = loaded.denoise;
cumulative = cumsum(denoise.eigenvalues) / sum(denoise.eigenvalues);
rank_r = find(cumulative >= opt.energy_target, 1, 'first');
if isempty(rank_r)
    error('vlsmGP:EnergyUnreachable', ...
        'energy_target=%.4f 超出全谱累计能量 %.4f。', ...
        opt.energy_target, cumulative(end));
end
if rank_r > denoise.rank
    % 缓存基底只算了前 denoise.rank 阶模态。静默截断会让图上标着 E=90% 而实际
    % 只重构了 E=80%——那是无法察觉的错误结论，所以这里硬报错。
    error('vlsmGP:EnergyExceedsCachedBasis', ...
        ['energy_target=%.2f 需要 rank=%d，但已缓存基底只有 %d 阶' ...
        '（对应累计能量 %.4f）。\n' ...
        '要跑更高能量档，请先用更高的 energy_target 重跑 ' ...
        'tools/research/r2_diagnostics/run_pod_energy_sweep.m 重建基底' ...
        '（一次 12000x12000 特征分解，约 8-12 分钟）。'], ...
        opt.energy_target, rank_r, denoise.rank, cumulative(denoise.rank));
end
fprintf('\n--- POD 低阶重构（条件 B）---\n');
fprintf('E=%.0f%% -> rank=%d（该秩处累计能量 %.4f，缓存基底秩 %d）\n', ...
    100 * opt.energy_target, rank_r, cumulative(rank_r), denoise.rank);
fprintf('可用上限 : E<=%.2f%%（缓存基底 %d 阶封顶），更高档需重建基底\n', ...
    100 * cumulative(denoise.rank), denoise.rank);
fprintf('基底缓存 : %s\n', basis_cache);

% ------------------------------------------------------------- 随机抽帧
available_ids = double(denoise.frame_ids(:).');
if isempty(opt.frame_ids)
    n_take = min(opt.n_frames, numel(available_ids));
    if n_take < opt.n_frames
        warning('vlsmGP:FewerFramesAvailable', ...
            '只有 %d 帧可用，少于请求的 %d 帧。', n_take, opt.n_frames);
    end
    rng(opt.random_seed, 'twister');
    picked = randperm(numel(available_ids), n_take);
    frame_ids = sort(available_ids(picked));
    sampling_note = sprintf('randperm，seed=%d', opt.random_seed);
else
    frame_ids = sort(unique(double(opt.frame_ids(:).')));
    unknown = setdiff(frame_ids, available_ids);
    if ~isempty(unknown)
        error('vlsmGP:UnknownFrameIds', ...
            'frame_ids 里有 %d 个帧号不在 POD 基底的帧集内（例如 %d）。', ...
            numel(unknown), unknown(1));
    end
    sampling_note = '调用方显式指定';
end
n = numel(frame_ids);
fprintf('\n帧集     : %d 帧（%s），帧号 %d..%d\n', n, sampling_note, ...
    frame_ids(1), frame_ids(end));
if isfield(stats, 'repeat_boundaries') && ~isempty(stats.repeat_boundaries)
    bnd = double(stats.repeat_boundaries(:).');
    counts = histcounts(frame_ids, [0 bnd inf]);
    fprintf('           跨 repeat 分布：%s（边界 %s）\n', ...
        strjoin(arrayfun(@(c) sprintf('%d', c), counts, 'UniformOutput', false), '/'), ...
        strjoin(arrayfun(@(b) sprintf('%d', b), bnd, 'UniformOutput', false), ','));
end

% 色标所有条件共用，否则同一帧不同条件的图颜色不可比。固定绝对范围，
% 并由 contour_levels_with_overflow 为超量程值补充外层等级，避免留白。
clim_val = double(opt.colorbar_abs_limit);
levels = contour_levels_with_overflow([], clim_val, opt.n_levels);
fprintf('色标     : +-%.3f m/s（固定绝对范围），%d 级\n', ...
    clim_val, opt.n_levels);
fprintf('输出目录 : %s\n\n', out_root);

% ------------------------------------------------------------- 条件定义
conditions = struct('tag', {}, 'label', {}, 'dir', {}, 'ctx', {}, 'spec', {});
conditions(end + 1) = struct( ...
    'tag', 'gaussian_directional', ...
    'label', sprintf('方向性高斯 %dx%d (sigma_x=%.4g, sigma_y=%.4g)', ...
        window(1), window(2), sigma_xy(1), sigma_xy(2)), ...
    'dir', dir_gauss, 'ctx', ctx_gauss, ...
    'spec', struct('preprocessing', 'gaussian', ...
        'cache_file', paths.sequence_cache_postproc));
conditions(end + 1) = struct( ...
    'tag', 'pod_lowrank', ...
    'label', sprintf('POD E=%.0f%% (rank=%d)', 100 * opt.energy_target, rank_r), ...
    'dir', dir_pod, 'ctx', ctx, ...
    'spec', struct('preprocessing', 'pod_denoise', 'denoise', denoise, ...
        'mode_indices', 1:rank_r, ...
        'cache_file', paths.sequence_cache_postproc));
if want_iso
    conditions(end + 1) = struct( ...
        'tag', 'gaussian_isotropic', ...
        'label', '各向同性高斯 9x9 (sigma=1.5)', ...
        'dir', dir_iso, 'ctx', ctx_iso, ...
        'spec', struct('preprocessing', 'gaussian', ...
            'cache_file', paths.sequence_cache_postproc));
end
% ------------------------------------------------------- 逐条件逐帧识别
n_cond = numel(conditions);
store = struct('tag', {}, 'label', {}, 'catalog', {}, 'per_frame', {}, ...
    'fields', {});
for si = 1:n_cond
    cnd = conditions(si);
    fprintf('--- [%d/%d] %s ---\n', si, n_cond, cnd.label);
    cells = cell(n, 1);
    fields = cell(n, 1);
    pf = struct('frame_id', num2cell(frame_ids(:)), ...
        'n_structures', num2cell(zeros(n, 1)), ...
        'n_lsm', num2cell(zeros(n, 1)), ...
        'n_vlsm', num2cell(zeros(n, 1)), ...
        'n_valid_px', num2cell(zeros(n, 1)));

    for k = 1:n
        fid = frame_ids(k);
        field = tblR2.vlsmpod.frame_field(cnd.ctx, fid, cnd.spec);
        identified = tblR2.vlsmpod.identify_frame(cnd.ctx, field, resolved);
        T = identified.structures;

        fields{k} = field.u_fluct;
        cells{k} = tblR2.vlsmpod.annotate(T, fid, 'total', cnd.tag);
        pf(k).n_structures = height(T);
        pf(k).n_lsm = sum(T.IsLSM);
        pf(k).n_vlsm = sum(T.IsVLSM);
        pf(k).n_valid_px = nnz(field.mask);

        fig = new_field_figure([24 6.5]);
        ax = axes(fig); %#ok<LAXES>
        plot_structure_field(ax, cnd.ctx, field.u_fluct, T, ...
            struct('levels', contour_levels_with_overflow(field.u_fluct, clim_val, opt.n_levels), ...
            'clim_val', clim_val, 'show_xlabel', true));
        title(ax, sprintf('%s   frame %d   结构 %d / LSM %d / VLSM %d', ...
            cnd.label, fid, height(T), sum(T.IsLSM), sum(T.IsVLSM)), ...
            'FontSize', 8, 'FontWeight', 'normal');
        export_fig(fig, fullfile(cnd.dir, sprintf('frame_%05d.png', fid)));

        if mod(k, max(1, floor(n / 6))) == 0 || k == n
            fprintf('  %2d/%d 帧（结构 %3d，LSM %2d，VLSM %2d）\n', k, n, ...
                pf(k).n_structures, pf(k).n_lsm, pf(k).n_vlsm);
        end
    end

    % 逐字段赋值，不用 struct(...)：pf 是 1xN struct 数组、catalog 是 table，
    % struct() 会把它们当成「多个元素」展开成 struct 数组而不是一个字段值。
    rec = struct();
    rec.tag = cnd.tag;
    rec.label = cnd.label;
    rec.catalog = vertcat(cells{:});
    rec.per_frame = pf;
    rec.fields = fields;
    store(si) = rec; %#ok<AGROW>
    fprintf('  图已保存：%s\n', cnd.dir);
end
% --------------------------------------------------------- 并排对照图
fprintf('\n--- 并排对照图（%d 条件上下并排）---\n', n_cond);
fig_height = 5.5 * n_cond;
for k = 1:n
    fid = frame_ids(k);
    fig = new_field_figure([24 fig_height]);
    for si = 1:n_cond
        ax = subplot(n_cond, 1, si, 'Parent', fig);
        T = store(si).catalog(store(si).catalog.FrameID == fid, :);
        plot_structure_field(ax, conditions(si).ctx, store(si).fields{k}, T, ...
            struct('levels', contour_levels_with_overflow(store(si).fields{k}, clim_val, opt.n_levels), ...
            'clim_val', clim_val, ...
            'show_xlabel', si == n_cond));
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
report.n_frames = n;
report.random_seed = opt.random_seed;
report.frame_sampling = sampling_note;
report.structure_opts = resolved.opts;
report.structure_overrides = opt.structure_overrides;
report.gaussian_window = window;
report.gaussian_sigma_cells = sigma_xy;
report.gaussian_radius_cells = radius_xy;
report.gaussian_spec = gauss_spec;
report.gaussian_window_mm = [window(1) * ctx.dx_mm, window(2) * ctx.dy_mm];
report.isotropic_spec = iso_spec;
report.pod_rank = rank_r;
report.pod_energy_target = opt.energy_target;
report.pod_energy_at_rank = cumulative(rank_r);
report.pod_basis_cache = basis_cache;
report.pod_basis_rank = denoise.rank;
report.dx_mm = ctx.dx_mm;
report.dy_mm = ctx.dy_mm;
report.clim_val = clim_val;
report.colorbar_abs_limit_m_per_s = clim_val;
report.output_dir = out_root;
report.conditions = {store.tag};
for si = 1:n_cond
    s = struct();
    s.label = store(si).label;
    s.catalog = store(si).catalog;
    s.per_frame = store(si).per_frame;
    s.summary = summarize(store(si).per_frame, store(si).catalog);
    report.(store(si).tag) = s;
end
report.definition = [ ...
    '随机 N 帧 VLSM 聚类连通法对照测试。所有条件使用完全相同的识别参数，' ...
    '差异只来自预处理：方向性（流向）高斯模糊 vs POD 低阶模态重构。' ...
    '瞬时流向脉动速度场用 contourf 绘制，叠加 LSM（蓝虚线）/VLSM（红实线）包围盒。' ...
    'u'' 场本身未落盘（每帧 J x I double），需要时按同一 seed 重跑即可复现。'];
report.reproduce_command = sprintf(['run_vlsm_gaussian_pod_comparison(' ...
    '''gaussian_window'', [%d %d], ''gaussian_sigma'', [%.6g %.6g], ' ...
    '''energy_target'', %.4g, ''n_frames'', %d, ''random_seed'', %d)'], ...
    window(1), window(2), sigma_xy(1), sigma_xy(2), ...
    opt.energy_target, opt.n_frames, opt.random_seed);

save(fullfile(out_root, 'vlsm_gaussian_pod_comparison.mat'), 'report', '-v7.3');
print_comparison(report, store);
fprintf('\n结果已保存：%s\n', ...
    fullfile(out_root, 'vlsm_gaussian_pod_comparison.mat'));
fprintf('复现命令：%s\n', report.reproduce_command);
fprintf('COMPARISON_DONE\n');
end

% =========================================================================
function fig = new_field_figure(size_cm)
fig = figure('Visible', 'off', 'Units', 'centimeters', ...
    'Position', [1 1 size_cm(1) size_cm(2)], 'Color', 'w');
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
function tag = num_tag(value)
tag = strrep(sprintf('%.4g', value), '.', 'p');
end

% =========================================================================
function levels = contour_levels_with_overflow(values, clim_val, n_levels)
%CONTOUR_LEVELS_WITH_OVERFLOW Keep values outside caxis visibly saturated.
levels = linspace(-double(clim_val), double(clim_val), n_levels);
if ~isempty(values)
    finite = double(values(isfinite(values)));
    if ~isempty(finite)
        vmin = min(finite); vmax = max(finite);
        if vmin < levels(1); levels = [vmin levels]; end
        if vmax > levels(end); levels = [levels vmax]; end
    end
end
levels = unique(levels, 'sorted');
if numel(levels) < 2
    levels = [-double(clim_val) double(clim_val)];
end
end

% =========================================================================
function print_kernel_weights(name, radius, sigma)
%PRINT_KERNEL_WEIGHTS 打出该方向的一维归一化权重。
% 目的是让「31x3 到底平滑了多少」可见：法向 radius=1 配一个很小的 sigma 时，
% 中心权重会接近 1，等于几乎只做流向平滑。这一点不打出来就只能靠猜。

ax = -radius:radius;
w = exp(-0.5 * (ax ./ sigma) .^ 2);
w = w ./ sum(w);
txt = strjoin(arrayfun(@(v) sprintf('%.3f', v), w, 'UniformOutput', false), ' ');
fprintf('%s 权重 (radius=%d): [%s]，中心占 %.1f%%\n', ...
    name, radius, txt, 100 * w(radius + 1));
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
s.mean_valid_px = mean([pf.n_valid_px]);
if isempty(catalog) || height(catalog) == 0
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
fprintf('\n=== 对照汇总（%d 帧，识别参数完全相同）===\n', report.n_frames);
fprintf('%-40s %9s %8s %8s %10s %10s %10s %9s\n', ...
    '条件', '每帧结构', '每帧LSM', '每帧VLSM', 'Lx中位/d', 'Lx_p90/d', ...
    'Lx最大/d', '像素中位');
for si = 1:numel(store)
    s = report.(store(si).tag).summary;
    fprintf('%-40s %9.2f %8.2f %8.2f %10.3f %10.3f %10.3f %9.0f\n', ...
        store(si).label, s.mean_structures_per_frame, ...
        s.mean_lsm_per_frame, s.mean_vlsm_per_frame, ...
        s.length_median_over_delta, s.length_p90_over_delta, ...
        s.length_max_over_delta, s.pixel_median);
end
fprintf('\n');
for si = 1:numel(store)
    s = report.(store(si).tag).summary;
    fprintf('%-40s 结构总数 %5d，LSM %4d，VLSM %3d，含 VLSM 的帧 %d/%d\n', ...
        store(si).label, s.total_structures, s.total_lsm, s.total_vlsm, ...
        s.frames_with_vlsm, s.n_frames);
end
end
