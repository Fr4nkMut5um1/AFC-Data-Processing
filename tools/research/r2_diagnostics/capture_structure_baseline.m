function results = capture_structure_baseline(varargin)
%CAPTURE_STRUCTURE_BASELINE 固化重构前的结构识别数值输出，作为回归基线。
%
% 为什么需要这个工具：本项目的测试全是合成数据的合同检查与解析参考值，没有
% 「跑一次存下来、下次比对」的机制。而 POD-VLSM 模块重构的验收标准是「数值
% 结果与重构前完全一致」——没有基线就无法证明这一点。
%
% 本工具**只读**，只写 tmp/refactor_baseline/，不碰 cases/*/output/ 下的正式产物。
%
% 两组帧集：
%   sampled    : stride=500 共 24 帧，与已有 pod_energy_sweep 同帧集，可与已导出
%                的 192 张审核图交叉核对。
%   continuous : frames 1..48，在 repeat 1 内（repeat 边界在 6000，第 6000/6001
%                帧之间不是物理连续的），给时间追踪功能用。
%
% 两个预处理条件：
%   gaussian    : 直接调用未改动的 run_structure_pod_denoise，走真正的生产入口。
%   pod_denoise : E=50%（rank=382）。复用已有的 E80 基底取前 382 阶——POD 模态与
%                 截断秩无关，E=50% 就是它的前缀，省掉一次 12000x12000 特征分解
%                 与约 11 GB 的峰值内存。这也正是 run_pod_energy_sweep 产出用户
%                 已认可的 E=50% 那一行时用的路径。
%
% 识别参数：r1 组（alpha=0.40 / seed=0.70 / conn=8）。实测只有这组能识别出 VLSM。
% 流向合并：关闭——缓存 cfg 里没有 merge_gap_cells 字段，与 E=50% 那组数同口径。

parser = inputParser;
parser.addParameter('case_name', 'tandem_baseline_r2', @(x) ischar(x) || isstring(x));
parser.addParameter('sampled_stride', 500, @(x) isscalar(x) && x >= 1 && x == fix(x));
parser.addParameter('sampled_max_frames', 24, @(x) isscalar(x) && x >= 1 && x == fix(x));
parser.addParameter('continuous_frames', 48, @(x) isscalar(x) && x >= 2 && x == fix(x));
parser.addParameter('energy_target', 0.50, @(x) isscalar(x) && x > 0 && x <= 1);
parser.addParameter('structure_overrides', ...
    struct('alpha', 0.40, 'seed_alpha', 0.70, 'connectivity', 8), @isstruct);
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
library_root = fullfile(repo_root, 'lib');
addpath(library_root);
addpath(fullfile(repo_root, 'tools', 'research'));
case_root = fullfile(per_case_root, case_name);

if isempty(opt.output_dir)
    out_dir = fullfile(repo_root, 'tmp', 'refactor_baseline');
else
    out_dir = char(opt.output_dir);
end
if ~isfolder(out_dir); mkdir(out_dir); end

fprintf('=== 重构前基线固化 ===\n');
fprintf('输出目录 : %s\n', out_dir);
fprintf('识别参数 : alpha=%.2f seed=%.2f conn=%d\n', ...
    opt.structure_overrides.alpha, opt.structure_overrides.seed_alpha, ...
    opt.structure_overrides.connectivity);

results = struct();

% ============================================================ 高斯基线
% 直接调用未改动的生产入口。这是最诚实的基线：重构后同样调用它，输出必须逐位相同。
fprintf('\n--- [1/3] gaussian / sampled（走 run_structure_pod_denoise 生产入口）---\n');
gauss_sampled_dir = fullfile(out_dir, 'gaussian_sampled');
if ~isfolder(gauss_sampled_dir); mkdir(gauss_sampled_dir); end
results.gaussian_sampled = run_structure_pod_denoise( ...
    'case_name', case_name, ...
    'preprocessing', 'gaussian', ...
    'frame_stride', opt.sampled_stride, ...
    'max_frames', opt.sampled_max_frames, ...
    'structure_overrides', opt.structure_overrides, ...
    'output_dir', gauss_sampled_dir);

fprintf('\n--- [2/3] gaussian / continuous（frames 1..%d）---\n', opt.continuous_frames);
gauss_cont_dir = fullfile(out_dir, 'gaussian_continuous');
if ~isfolder(gauss_cont_dir); mkdir(gauss_cont_dir); end
results.gaussian_continuous = run_structure_pod_denoise( ...
    'case_name', case_name, ...
    'preprocessing', 'gaussian', ...
    'frame_stride', 1, ...
    'max_frames', opt.continuous_frames, ...
    'structure_overrides', opt.structure_overrides, ...
    'output_dir', gauss_cont_dir);

% ========================================================= POD E=50% 基线
fprintf('\n--- [3/3] pod_denoise E=%.0f%% / sampled + continuous ---\n', ...
    100 * opt.energy_target);
results.pod = capture_pod_baseline(repo_root, case_root, case_name, opt, out_dir);

% -------------------------------------------------------------- 汇总落盘
baseline_path = fullfile(out_dir, 'refactor_baseline.mat');
save(baseline_path, 'results', '-v7.3');

fprintf('\n=== 基线固化完成 ===\n');
print_summary('gaussian/sampled', results.gaussian_sampled);
print_summary('gaussian/continuous', results.gaussian_continuous);
print_summary('pod_E50/sampled', results.pod.sampled);
print_summary('pod_E50/continuous', results.pod.continuous);
fprintf('基线已保存 : %s\n', baseline_path);
end

% =========================================================================
function out = capture_pod_baseline(repo_root, case_root, case_name, opt, out_dir)
%CAPTURE_POD_BASELINE 用已有 E80 基底的前 382 阶做 E=50% 的逐帧识别基线。
%
% 这里逐字复刻 run_pod_energy_sweep 的 evaluate_condition 里 pod_denoise 分支的
% 调用序列——那是当前生产代码产出用户已认可的 E=50% 那一行时走的路径。所有算术
% 都在未改动的 tblR2 函数里，本函数只负责把它们按同样顺序串起来。

basis_cache = fullfile(repo_root, 'tmp', 'pod_energy_sweep', ...
    'pod_energy_sweep_basis.mat');
if ~isfile(basis_cache)
    error('captureBaseline:MissingBasis', ...
        ['找不到 E80 基底缓存：%s\n' ...
        '请先运行 tools/research/r2_diagnostics/run_pod_energy_sweep.m。'], basis_cache);
end
fprintf('加载 E80 基底：%s\n', basis_cache);
loaded = load(basis_cache, 'denoise');
denoise = loaded.denoise;

% E=50% 对应的秩：累计能量首次达标的阶数，与 run_pod_energy_sweep 同一算法。
cumulative = cumsum(denoise.eigenvalues) / sum(denoise.eigenvalues);
rank_e50 = find(cumulative >= opt.energy_target, 1, 'first');
if isempty(rank_e50); rank_e50 = numel(cumulative); end
rank_e50 = min(rank_e50, denoise.rank);
mode_indices = 1:rank_e50;
fprintf('E=%.0f%% -> rank=%d（基底秩 %d，累计能量 %.4f）\n', ...
    100 * opt.energy_target, rank_e50, denoise.rank, cumulative(rank_e50));

% ---------------------------------------------- 几何与选项（复刻生产代码口径）
cfg = load_case_config(case_root, case_name);
paths = tblR2.build_paths(cfg.output_dir);
stats = tblR2.load_result(paths.statistics, cfg, 'statistics');
mean_bl = tblR2.load_result(paths.mean_bl, cfg, 'mean_bl');

J = size(stats.X, 1);
I = size(stats.X, 2);
Y_wall_mm = mean_bl.wall_distance_mm;
delta_grid = interp1(mean_bl.boundary_layer.x, ...
    mean_bl.boundary_layer.delta99, stats.X, 'linear', NaN);
valid_mask = stats.accepted_mask & isfinite(delta_grid) & delta_grid > 0;
structure_settings = apply_overrides(cfg.structures, opt.structure_overrides);
opts = structure_opts(structure_settings);
trusted_domain = trusted_domain_spec(structure_settings);
analysis_domain_mask = tblR2.trusted_domain_mask( ...
    valid_mask, Y_wall_mm, trusted_domain);

% 两组帧集
sampled_ids = denoise.frame_ids(1:opt.sampled_stride:end).';
sampled_ids = sampled_ids(1:min(numel(sampled_ids), opt.sampled_max_frames));
continuous_ids = denoise.frame_ids(1:opt.continuous_frames).';

out = struct();
out.rank = rank_e50;
out.energy_target = opt.energy_target;
out.energy_at_rank = cumulative(rank_e50);
out.basis_cache = basis_cache;
out.basis_rank = denoise.rank;
out.structure_opts = opts;
out.trusted_domain = trusted_domain;

fprintf('  sampled：%d 帧\n', numel(sampled_ids));
out.sampled = pod_catalog(sampled_ids, denoise, mode_indices, ...
    analysis_domain_mask, stats, Y_wall_mm, delta_grid, opts, J, I);
fprintf('  continuous：%d 帧\n', numel(continuous_ids));
out.continuous = pod_catalog(continuous_ids, denoise, mode_indices, ...
    analysis_domain_mask, stats, Y_wall_mm, delta_grid, opts, J, I);

pod_path = fullfile(out_dir, 'pod_e50_baseline.mat');
save(pod_path, 'out', '-v7.3');
fprintf('  POD 基线已保存：%s\n', pod_path);
end

% =========================================================================
function res = pod_catalog(frame_ids, denoise, mode_indices, ...
    analysis_domain_mask, stats, Y_wall_mm, delta_grid, opts, J, I)
%POD_CATALOG 逐帧 POD 重构 + 识别，累积 catalog。

n = numel(frame_ids);
cells = cell(n, 1);
per_frame = struct('frame_id', num2cell(frame_ids(:)), ...
    'n_structures', num2cell(nan(n, 1)), ...
    'n_lsm', num2cell(nan(n, 1)), ...
    'n_vlsm', num2cell(nan(n, 1)));

for k = 1:n
    frame_id = frame_ids(k);
    [proc_U, proc_V] = tblR2.pod_denoise_reconstruct_frame( ...
        denoise, frame_id, mode_indices);
    source_valid = analysis_domain_mask;

    [mean_U, mean_V] = mean_field_for_frame(stats, frame_id, 1:J, 1:I);
    structure_mask = source_valid & isfinite(proc_U) & isfinite(proc_V) & ...
        isfinite(mean_U) & isfinite(mean_V);
    total_U_f = proc_U - mean_U;
    total_V_f = proc_V - mean_V;
    total_U_f(~structure_mask) = NaN;
    total_V_f(~structure_mask) = NaN;

    identified = tblR2.identify_structures(total_U_f, stats.u_rms, ...
        stats.X, Y_wall_mm, delta_grid, structure_mask, opts);
    T = identified.structures;
    nrows = height(T);
    T = addvars(T, repmat(frame_id, nrows, 1), repmat({'total'}, nrows, 1), ...
        repmat({'pod_denoise'}, nrows, 1), 'Before', 1, ...
        'NewVariableNames', {'FrameID', 'Branch', 'Preprocessing'});
    cells{k} = T;
    per_frame(k).n_structures = nrows;
    per_frame(k).n_lsm = sum(T.IsLSM);
    per_frame(k).n_vlsm = sum(T.IsVLSM);
    if mod(k, max(1, floor(n / 10))) == 0 || k == n
        fprintf('    %d/%d 帧（结构 %d，LSM %d，VLSM %d）\n', k, n, ...
            per_frame(k).n_structures, per_frame(k).n_lsm, per_frame(k).n_vlsm);
    end
end

res = struct();
res.catalog = vertcat(cells{:});
res.per_frame = per_frame;
res.frame_ids = frame_ids(:);
res.preprocessing = 'pod_denoise';
res.summary = struct( ...
    'n_frames', n, ...
    'total_structures', height(res.catalog), ...
    'mean_structures_per_frame', mean([per_frame.n_structures], 'omitnan'), ...
    'mean_lsm_per_frame', mean([per_frame.n_lsm], 'omitnan'), ...
    'mean_vlsm_per_frame', mean([per_frame.n_vlsm], 'omitnan'), ...
    'total_lsm', sum([per_frame.n_lsm], 'omitnan'), ...
    'total_vlsm', sum([per_frame.n_vlsm], 'omitnan'));
end

% =========================================================================
function print_summary(label, r)
if ~isstruct(r) || ~isfield(r, 'summary')
    fprintf('  %-22s <无>\n', label);
    return;
end
s = r.summary;
fprintf('  %-22s 帧 %4d | 结构 %6d | 每帧 %6.2f | LSM %5.2f | VLSM %5.2f\n', ...
    label, s.n_frames, s.total_structures, s.mean_structures_per_frame, ...
    s.mean_lsm_per_frame, s.mean_vlsm_per_frame);
end

% =========================================================================
% 以下 6 个函数是当前生产代码（run_pod_energy_sweep.m / run_structure_pod_denoise.m）
% 里同名局部函数的**逐字副本**。刻意复制而非调用重构后的 +vlsmpod：基线必须独立于
% 被验证的代码，否则就是拿新模块验证新模块。本工具在重构验收后即可删除。
% =========================================================================
function cfg = load_case_config(case_root, case_name)
config_file = fullfile(case_root, 'output', 'mat', '00_case_configuration.mat');
if ~isfile(config_file)
    error('captureBaseline:MissingConfig', ...
        '找不到工况配置：%s（请先运行 %s_case.m）', config_file, case_name);
end
loaded = load(config_file);
if isfield(loaded, 'data') && isstruct(loaded.data) && isfield(loaded.data, 'cfg')
    cfg = loaded.data.cfg;
elseif isfield(loaded, 'cfg')
    cfg = loaded.cfg;
else
    error('captureBaseline:InvalidConfig', '配置文件结构无法识别：%s', config_file);
end
end

% =========================================================================
function [mean_U, mean_V] = mean_field_for_frame(stats, frame_id, row_ids, col_ids)
if isfield(stats, 'repeat_means') && ~isempty(stats.repeat_means) && ...
        isfield(stats, 'repeat_boundaries') && ~isempty(stats.repeat_boundaries)
    rep = 1 + sum(frame_id > double(stats.repeat_boundaries(:).'));
    mean_U = squeeze(stats.repeat_means(1, rep, row_ids, col_ids));
    mean_V = squeeze(stats.repeat_means(2, rep, row_ids, col_ids));
else
    mean_U = squeeze(stats.Uavex(row_ids, col_ids));
    mean_V = squeeze(stats.Vavex(row_ids, col_ids));
end
end

% =========================================================================
function settings = apply_overrides(settings, overrides)
names = fieldnames(overrides);
for i = 1:numel(names)
    if ~isfield(settings, names{i})
        error('captureBaseline:UnknownOverride', ...
            'cfg.structures 中不存在字段 %s，无法覆盖。', names{i});
    end
    settings.(names{i}) = overrides.(names{i});
end
end

% =========================================================================
function opts = structure_opts(settings)
max_internal_hole_pixels = pick(settings, 'max_internal_hole_pixels', 0);
envelope_closing_radius_cells = pick(settings, 'envelope_closing_radius_cells', 0);
max_aspect_ratio = pick(settings, 'max_aspect_ratio', inf);
reject_trusted_boundary_touching = pick(settings, ...
    'reject_trusted_boundary_touching', false);
seed_alpha = pick(settings, 'seed_alpha', settings.alpha);
min_abs_fluctuation = pick(settings, 'min_abs_fluctuation', 0);
min_abs_seed_fluctuation = pick(settings, 'min_abs_seed_fluctuation', ...
    min_abs_fluctuation);

opts = struct('alpha', settings.alpha, 'min_pixels', settings.min_pixels, ...
    'seed_alpha', seed_alpha, 'connectivity', settings.connectivity, ...
    'max_internal_hole_pixels', max_internal_hole_pixels, ...
    'envelope_closing_radius_cells', envelope_closing_radius_cells, ...
    'max_aspect_ratio', max_aspect_ratio, ...
    'reject_trusted_boundary_touching', reject_trusted_boundary_touching, ...
    'min_lsm_delta', settings.min_lsm_delta, ...
    'min_vlsm_delta', settings.min_vlsm_delta, ...
    'max_wall_normal_delta', settings.max_wall_normal_delta, ...
    'min_abs_fluctuation', min_abs_fluctuation, ...
    'min_abs_seed_fluctuation', min_abs_seed_fluctuation, ...
    'sign_mode', 'both');
end

% =========================================================================
function spec = trusted_domain_spec(settings)
spec = struct('streamwise_edge_columns', 0, 'wall_normal_top_rows', 0);
if isfield(settings, 'trusted_domain') && ~isempty(settings.trusted_domain)
    names = fieldnames(spec);
    for i = 1:numel(names)
        if isfield(settings.trusted_domain, names{i})
            spec.(names{i}) = settings.trusted_domain.(names{i});
        end
    end
end
end

% =========================================================================
function value = pick(settings, name, fallback)
value = fallback;
if isfield(settings, name) && ~isempty(settings.(name))
    value = settings.(name);
end
end
