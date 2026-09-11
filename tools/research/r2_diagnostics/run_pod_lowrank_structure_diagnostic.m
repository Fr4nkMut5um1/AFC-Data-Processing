function results = run_pod_lowrank_structure_diagnostic(varargin)
%RUN_POD_LOWRANK_STRUCTURE_DIAGNOSTIC 低阶 POD 重构场上的 LSM/VLSM 识别对比。
%
% 这是**诊断工具，不是主管线**。与 run_structure_pod_denoise.m 的区别：
%
%   run_structure_pod_denoise  (路径 A，去噪)
%     截断秩由噪声判据决定（Gavish-Donoho，通常几百阶），目的是只剔除测量
%     噪声子空间，保留全部真实湍流尺度。识别结果可与高斯预处理直接对比。
%
%   本脚本                      (路径 B，尺度分离)
%     截断秩人为设定为很低的值（如 10 阶或 80% 能量），重构场按构造只含大
%     尺度运动。识别到的「结构」很大程度上是 rank 的函数，不是独立的物理
%     测量——**长度尺度必须报告为 rank 条件量**，不能与路径 A 的结果混用。
%
% 之所以仍然值得做：扫 rank 能看出结构尺度随保留能量的演化趋势，用于判断
% VLSM 的能量主要落在哪几阶。前人做法见 Chi et al. (2022) PRF 7:084603 与
% Perret & Kerhervé (2019) Exp Fluids 60:97。
%
% 两种 rank 指定方式
%   'mode', 'fixed_rank'      + 'ranks', [5 10 20 50]
%   'mode', 'energy_fraction' + 'energy_targets', [0.5 0.8 0.9]
%
% 用法
%   r = run_pod_lowrank_structure_diagnostic('ranks', [5 10 20 50]);
%   r = run_pod_lowrank_structure_diagnostic('mode', 'energy_fraction', ...
%           'energy_targets', [0.5 0.8 0.9], 'frame_stride', 200);

parser = inputParser;
parser.addParameter('case_name', 'tandem_baseline_r2', @(x) ischar(x) || isstring(x));
parser.addParameter('mode', 'fixed_rank', @(x) ...
    ismember(char(x), {'fixed_rank', 'energy_fraction'}));
parser.addParameter('ranks', [5 10 20 50], @(x) isnumeric(x) && isvector(x));
parser.addParameter('energy_targets', [0.5 0.8 0.9], @(x) isnumeric(x) && isvector(x));
parser.addParameter('frame_stride', 200, @(x) isscalar(x) && x >= 1 && x == fix(x));
parser.addParameter('max_frames', [], @(x) isempty(x) || ...
    (isscalar(x) && x >= 1 && x == fix(x)));
parser.addParameter('output_dir', '', @(x) ischar(x) || isstring(x));
parser.parse(varargin{:});
opt = parser.Results;
case_name = char(opt.case_name);
mode = char(opt.mode);

% ------------------------------------------------------------------ 路径
script_dir = fileparts(mfilename('fullpath'));
if isempty(script_dir) || contains(script_dir, fullfile('Temp', 'Editor_'))
    script_dir = pwd;
end
repo_root = fileparts(fileparts(fileparts(script_dir)));   % tools/research/r2_diagnostics -> repo
per_case_root = fullfile(repo_root, 'cases', 'per_case');
library_root = fullfile(repo_root, 'lib');
if ~isfolder(library_root)
    error('podLowrankDiagnostic:MissingLibrary', ...
        '找不到 +tblR2 库目录：%s', library_root);
end
addpath(library_root);
addpath(fullfile(repo_root, 'tools', 'research'));

case_root = fullfile(per_case_root, case_name);
cfg = load_case_config(case_root, case_name);
paths = tblR2.build_paths(cfg.output_dir);
stats = tblR2.load_result(paths.statistics, cfg, 'statistics');
mean_bl = tblR2.load_result(paths.mean_bl, cfg, 'mean_bl');

if isempty(opt.output_dir)
    out_dir = fullfile(repo_root, 'tmp', 'pod_lowrank_diagnostic');
else
    out_dir = char(opt.output_dir);
end
if ~isfolder(out_dir); mkdir(out_dir); end

% ------------------------------------------------------ 复用去噪 POD 基底
% 路径 A 已经算过全量特征谱与前 r_A 阶模态，这里直接复用，不重新分解。
% 低阶诊断需要的模态是 r_A 的子集（低阶诊断的 rank 必然远小于去噪 rank）。
basis_cache = fullfile(cfg.output_dir, 'mat', ...
    '09_structure_pod_denoise_basis.mat');
if ~isfile(basis_cache)
    error('podLowrankDiagnostic:MissingBasis', ...
        ['找不到 POD 基底缓存：%s\n' ...
        '请先调用 tools/research/run_structure_pod_denoise.m，case_name=%s，生成基底。'], ...
        basis_cache, case_name);
end
loaded = load(basis_cache, 'denoise');
denoise = loaded.denoise;
fprintf('[低阶诊断] 复用 POD 基底：可用秩 %d，总帧 %d。\n', ...
    denoise.rank, numel(denoise.frame_ids));

% ---------------------------------------------------------- 解析待扫秩值
cumulative = cumsum(denoise.eigenvalues) / sum(denoise.eigenvalues);
switch mode
    case 'fixed_rank'
        rank_list = unique(round(double(opt.ranks(:).')));
        rank_labels = arrayfun(@(r) sprintf('rank=%d', r), rank_list, ...
            'UniformOutput', false);
    case 'energy_fraction'
        targets = unique(double(opt.energy_targets(:).'));
        rank_list = zeros(1, numel(targets));
        rank_labels = cell(1, numel(targets));
        for i = 1:numel(targets)
            idx = find(cumulative >= targets(i), 1, 'first');
            if isempty(idx); idx = numel(cumulative); end
            rank_list(i) = idx;
            rank_labels{i} = sprintf('E=%.0f%%(rank=%d)', 100 * targets(i), idx);
        end
end
% 低阶诊断的秩必须落在已缓存的模态范围内，超出部分无法重构。
too_large = rank_list > denoise.rank;
if any(too_large)
    fprintf(['[低阶诊断] 以下秩超出缓存基底的 %d 阶，已剔除：%s\n' ...
        '  如需更高秩，请用更宽松的 rank_method 重跑路径 A。\n'], ...
        denoise.rank, mat2str(rank_list(too_large)));
    rank_labels = rank_labels(~too_large);
    rank_list = rank_list(~too_large);
end
if isempty(rank_list)
    error('podLowrankDiagnostic:NoValidRank', '没有可用的截断秩。');
end
fprintf('[低阶诊断] 待扫秩：%s\n', mat2str(rank_list));

% ---------------------------------------------------- 结构识别几何与选项
J = size(stats.X, 1);
I = size(stats.X, 2);
Y_wall_mm = mean_bl.wall_distance_mm;
delta_grid = interp1(mean_bl.boundary_layer.x, ...
    mean_bl.boundary_layer.delta99, stats.X, 'linear', NaN);
valid_mask = stats.accepted_mask & isfinite(delta_grid) & delta_grid > 0;
opts = structure_opts(cfg.structures);
trusted_domain = trusted_domain_spec(cfg.structures);
analysis_domain_mask = tblR2.trusted_domain_mask( ...
    valid_mask, Y_wall_mm, trusted_domain);
dx = median(abs(diff(stats.X(1, :))), 'omitnan');
dy = median(abs(diff(Y_wall_mm(:, 1))), 'omitnan');
merge_enabled = isfield(cfg.structures, 'merge_gap_cells') && ...
    cfg.structures.merge_gap_cells > 0;
if merge_enabled
    merge_opts = struct( ...
        'merge_gap_cells', cfg.structures.merge_gap_cells, ...
        'merge_require_y_overlap', cfg.structures.merge_require_y_overlap, ...
        'min_lsm_delta', opts.min_lsm_delta, ...
        'min_vlsm_delta', opts.min_vlsm_delta);
end

% ------------------------------------------------------------- 帧列表
frame_ids = denoise.frame_ids(1:opt.frame_stride:end).';
if ~isempty(opt.max_frames)
    frame_ids = frame_ids(1:min(numel(frame_ids), opt.max_frames));
end
n_frames = numel(frame_ids);
fprintf('[低阶诊断] 每个秩识别 %d 帧，共 %d 个秩。\n', n_frames, numel(rank_list));

% --------------------------------------------------------- 逐秩逐帧识别
n_rank = numel(rank_list);
per_rank = repmat(struct('rank', NaN, 'label', '', 'energy_fraction', NaN, ...
    'mean_structures', NaN, 'mean_lsm', NaN, 'mean_vlsm', NaN, ...
    'mean_length_over_delta', NaN, 'max_length_over_delta', NaN, ...
    'catalog', table()), n_rank, 1);

for ri = 1:n_rank
    r = rank_list(ri);
    frame_tables = cell(n_frames, 1);
    counts = nan(n_frames, 3);

    for k = 1:n_frames
        frame_id = frame_ids(k);
        [pod_U, pod_V] = tblR2.pod_denoise_reconstruct_frame( ...
            denoise, frame_id, 1:r);
        [mean_U, mean_V] = mean_field_for_frame(stats, frame_id, 1:J, 1:I);

        structure_mask = analysis_domain_mask & isfinite(pod_U) & ...
            isfinite(pod_V) & isfinite(mean_U) & isfinite(mean_V);
        total_U_f = pod_U - mean_U;
        total_U_f(~structure_mask) = NaN;

        identified = tblR2.identify_structures(total_U_f, stats.u_rms, ...
            stats.X, Y_wall_mm, delta_grid, structure_mask, opts);
        if merge_enabled
            [identified.structures, ~] = ...
                tblR2.vlsm.merge_streamwise_neighbors( ...
                identified.structures, identified.positive_labels, ...
                identified.negative_labels, stats.X, Y_wall_mm, ...
                delta_grid, dx, dy, total_U_f, merge_opts);
        end

        T = identified.structures;
        nT = height(T);
        T = addvars(T, repmat(frame_id, nT, 1), repmat(r, nT, 1), ...
            'Before', 1, 'NewVariableNames', {'FrameID', 'Rank'});
        frame_tables{k} = T;
        counts(k, :) = [nT, sum(T.IsLSM), sum(T.IsVLSM)];
    end

    catalog = vertcat(frame_tables{:});
    per_rank(ri).rank = r;
    per_rank(ri).label = rank_labels{ri};
    per_rank(ri).energy_fraction = cumulative(min(r, numel(cumulative)));
    per_rank(ri).mean_structures = mean(counts(:, 1), 'omitnan');
    per_rank(ri).mean_lsm = mean(counts(:, 2), 'omitnan');
    per_rank(ri).mean_vlsm = mean(counts(:, 3), 'omitnan');
    if height(catalog) > 0
        per_rank(ri).mean_length_over_delta = ...
            mean(catalog.LengthX_over_delta, 'omitnan');
        per_rank(ri).max_length_over_delta = ...
            max(catalog.LengthX_over_delta, [], 'omitnan');
    end
    per_rank(ri).catalog = catalog;

    fprintf(['  %-20s 累计能量 %5.1f%% | 每帧结构 %5.2f | LSM %5.2f | ' ...
        'VLSM %5.2f | 平均长度 %5.2f δ\n'], ...
        per_rank(ri).label, 100 * per_rank(ri).energy_fraction, ...
        per_rank(ri).mean_structures, per_rank(ri).mean_lsm, ...
        per_rank(ri).mean_vlsm, per_rank(ri).mean_length_over_delta);
end

% -------------------------------------------------------------- 汇总输出
results = struct();
results.per_rank = per_rank;
results.rank_list = rank_list(:);
results.rank_labels = rank_labels(:);
results.mode = mode;
results.frame_ids = frame_ids(:);
results.cumulative_energy = cumulative;
results.case_name = case_name;
results.structure_opts = opts;
results.caveat = ['低阶重构场上的识别结果依赖截断秩，长度尺度是 rank ' ...
    '条件量，不能当作独立的物理测量，也不可与路径 A（去噪）的结果混用。'];

result_path = fullfile(out_dir, sprintf('pod_lowrank_%s_%s.mat', ...
    case_name, mode));
save(result_path, 'results', '-v7.3');

fprintf('\n=== 低阶 POD 结构诊断完成 ===\n');
fprintf('  扫描秩数量 : %d\n', n_rank);
fprintf('  每秩帧数   : %d\n', n_frames);
fprintf('  结果已保存 : %s\n', result_path);
fprintf('  注意       : %s\n', results.caveat);
end

% =========================================================================
function cfg = load_case_config(case_root, case_name)
config_file = fullfile(case_root, 'output', 'mat', '00_case_configuration.mat');
if ~isfile(config_file)
    error('podLowrankDiagnostic:MissingConfig', ...
        '找不到工况配置：%s（请先运行 %s_case.m）', config_file, case_name);
end
loaded = load(config_file);
if isfield(loaded, 'data') && isstruct(loaded.data) && isfield(loaded.data, 'cfg')
    cfg = loaded.data.cfg;
elseif isfield(loaded, 'cfg')
    cfg = loaded.cfg;
elseif isfield(loaded, 'data')
    cfg = loaded.data;
else
    error('podLowrankDiagnostic:InvalidConfig', ...
        '配置文件结构无法识别：%s', config_file);
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
function opts = structure_opts(settings)
%STRUCTURE_OPTS 与 structure_analysis_cache 的同名局部函数逐字段一致。
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
    'seed_alpha', seed_alpha, ...
    'connectivity', settings.connectivity, ...
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
