function results = run_pod_energy_sweep(varargin)
%RUN_POD_ENERGY_SWEEP 扫描 POD 去噪的累计能量目标，对照高斯基准。
%
% 为什么单独写这个脚本：run_structure_pod_denoise 每换一次 energy_target
% 都会重新做一次 12000×12000 的特征分解（约 8-12 分钟），扫 7 个点要一个
% 半小时。但特征谱与模态矩阵只依赖数据本身，**与你想取多少阶无关**——
% 所以这里只分解一次（取到最大能量目标对应的秩），之后各能量目标都只是
% 在同一组模态上取不同长度的前缀。
%
% 背景（2026-08-24 实测）：本工况的特征值谱几乎平坦，前 10 阶仅占 6.6%
% 能量，95% 能量需要 8425 阶。因此**能量目标越高 → 秩越大 → 保留越多小
% 尺度 → 结构越碎**，与直觉相反。80% 能量（rank=4737）比高斯碎 5.5 倍。
% 本扫描的目的就是找出结构尺度能与高斯基准相当或更好的能量区间。
%
% 用法
%   r = run_pod_energy_sweep();                       % 默认 0.2:0.1:0.8
%   r = run_pod_energy_sweep('energy_targets', [0.2 0.4 0.6]);
%   r = run_pod_energy_sweep('frame_stride', 200);    % 更多帧、更稳的统计

parser = inputParser;
parser.addParameter('case_name', 'tandem_baseline_r2', @(x) ischar(x) || isstring(x));
parser.addParameter('energy_targets', 0.2:0.1:0.8, @(x) isnumeric(x) && isvector(x));
parser.addParameter('frame_stride', 500, @(x) isscalar(x) && x >= 1 && x == fix(x));
parser.addParameter('max_frames', [], @(x) isempty(x) || ...
    (isscalar(x) && x >= 1 && x == fix(x)));
% 默认用 r1 的聚类连通法参数：2026-08-24 实测只有这一组能识别出 VLSM。
parser.addParameter('structure_overrides', ...
    struct('alpha', 0.40, 'seed_alpha', 0.70, 'connectivity', 8), @isstruct);
parser.addParameter('output_dir', '', @(x) ischar(x) || isstring(x));
parser.addParameter('include_gaussian', true, @(x) islogical(x) || isnumeric(x));
parser.parse(varargin{:});
opt = parser.Results;
case_name = char(opt.case_name);
targets = sort(unique(double(opt.energy_targets(:).')));

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
cfg = load_case_config(case_root, case_name);
paths = tblR2.build_paths(cfg.output_dir);
stats = tblR2.load_result(paths.statistics, cfg, 'statistics');
mean_bl = tblR2.load_result(paths.mean_bl, cfg, 'mean_bl');

if isempty(opt.output_dir)
    out_dir = fullfile(repo_root, 'tmp', 'pod_energy_sweep');
else
    out_dir = char(opt.output_dir);
end
if ~isfolder(out_dir); mkdir(out_dir); end

% ------------------------------------------ 单次分解，取到最大能量目标
% 一次分解到 max(targets) 对应的秩，之后所有更低的目标都是它的前缀。
basis_cache = fullfile(out_dir, 'pod_energy_sweep_basis.mat');
denoise = tblR2.pod_denoise_prepare(paths.sequence_cache_postproc, cfg, stats, ...
    struct('rank_method', 'energy_fraction', ...
    'energy_target', max(targets), ...
    'cache_path', basis_cache));

cumulative = cumsum(denoise.eigenvalues) / sum(denoise.eigenvalues);
rank_for_target = zeros(size(targets));
for i = 1:numel(targets)
    idx = find(cumulative >= targets(i), 1, 'first');
    if isempty(idx); idx = numel(cumulative); end
    rank_for_target(i) = min(idx, denoise.rank);
end
fprintf('[能量扫描] 基底秩 %d；各目标对应秩：\n', denoise.rank);
for i = 1:numel(targets)
    fprintf('    E=%.0f%% -> rank=%d\n', 100 * targets(i), rank_for_target(i));
end

% ---------------------------------------------------- 结构识别几何与选项
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
preprocess_spec = structure_preprocessing(structure_settings);

frame_ids = denoise.frame_ids(1:opt.frame_stride:end).';
if ~isempty(opt.max_frames)
    frame_ids = frame_ids(1:min(numel(frame_ids), opt.max_frames));
end
n_frames = numel(frame_ids);
fprintf('[能量扫描] 每个条件识别 %d 帧，识别参数 alpha=%.2f seed=%.2f conn=%d。\n', ...
    n_frames, opts.alpha, opts.seed_alpha, opts.connectivity);

% ------------------------------------------------------------- 逐条件扫描
n_cond = numel(targets) + double(logical(opt.include_gaussian));
rows = repmat(empty_row(), n_cond, 1);
row_index = 0;

if logical(opt.include_gaussian)
    row_index = row_index + 1;
    rows(row_index) = evaluate_condition('gaussian', NaN, NaN, ...
        frame_ids, denoise, [], paths.sequence_cache_postproc, stats, ...
        valid_mask, analysis_domain_mask, preprocess_spec, ...
        Y_wall_mm, delta_grid, opts, J, I);
    print_row(rows(row_index));
end

for i = 1:numel(targets)
    row_index = row_index + 1;
    rows(row_index) = evaluate_condition('pod_denoise', targets(i), ...
        rank_for_target(i), frame_ids, denoise, 1:rank_for_target(i), ...
        paths.sequence_cache_postproc, stats, valid_mask, analysis_domain_mask, ...
        preprocess_spec, Y_wall_mm, delta_grid, opts, J, I);
    print_row(rows(row_index));
end

% -------------------------------------------------------------- 汇总输出
results = struct();
results.rows = rows;
results.table = struct2table(rows);
results.targets = targets(:);
results.rank_for_target = rank_for_target(:);
results.basis_rank = denoise.rank;
results.cumulative_energy = cumulative;
results.frame_ids = frame_ids(:);
results.structure_opts = opts;
results.case_name = case_name;

result_path = fullfile(out_dir, 'pod_energy_sweep_result.mat');
save(result_path, 'results', '-v7.3');

fprintf('\n=== 能量目标扫描汇总（%d 帧，alpha=%.2f seed=%.2f conn=%d）===\n', ...
    n_frames, opts.alpha, opts.seed_alpha, opts.connectivity);
fprintf('%-14s %7s %9s %8s %8s %9s %9s %9s\n', ...
    '条件', 'rank', '每帧结构', 'LSM', 'VLSM', 'Lx中位', 'Lx_p90', 'Lx最大');
for i = 1:numel(rows)
    fprintf('%-14s %7s %9.1f %8.2f %8.2f %9.3f %9.3f %9.3f\n', ...
        rows(i).condition, rank_text(rows(i).rank), ...
        rows(i).mean_structures, rows(i).mean_lsm, rows(i).mean_vlsm, ...
        rows(i).length_median, rows(i).length_p90, rows(i).length_max);
end
fprintf('结果已保存：%s\n', result_path);
end

% =========================================================================
function row = evaluate_condition(preprocessing, energy_target, rank_used, ...
    frame_ids, denoise, mode_indices, cache_file, stats, valid_mask, ...
    analysis_domain_mask, preprocess_spec, Y_wall_mm, delta_grid, opts, J, I)
%EVALUATE_CONDITION 在一个预处理条件下跑完所有帧并汇总。

n_frames = numel(frame_ids);
counts = nan(n_frames, 3);
lengths = cell(n_frames, 1);
pixels = cell(n_frames, 1);

for k = 1:n_frames
    frame_id = frame_ids(k);
    if strcmp(preprocessing, 'pod_denoise')
        [proc_U, proc_V] = tblR2.pod_denoise_reconstruct_frame( ...
            denoise, frame_id, mode_indices);
        source_valid = analysis_domain_mask;
    else
        chunk = tblR2.read_cache_chunk(cache_file, frame_id, 1:J, 1:I, ...
            'raw', [], []);
        raw_U = squeeze(chunk.U);
        raw_V = squeeze(chunk.V);
        raw_valid = valid_mask & squeeze(chunk.sampleValid);
        processed = tblR2.preprocess_structure_velocity(raw_U, raw_V, ...
            raw_valid, analysis_domain_mask, preprocess_spec);
        proc_U = processed.U;
        proc_V = processed.V;
        source_valid = processed.output_valid_mask;
    end

    [mean_U, mean_V] = mean_field_for_frame(stats, frame_id, 1:J, 1:I);
    structure_mask = source_valid & isfinite(proc_U) & isfinite(proc_V) & ...
        isfinite(mean_U) & isfinite(mean_V);
    total_U_f = proc_U - mean_U;
    total_U_f(~structure_mask) = NaN;

    identified = tblR2.identify_structures(total_U_f, stats.u_rms, ...
        stats.X, Y_wall_mm, delta_grid, structure_mask, opts);
    T = identified.structures;
    counts(k, :) = [height(T), sum(T.IsLSM), sum(T.IsVLSM)];
    lengths{k} = T.LengthX_over_delta;
    pixels{k} = double(T.PixelCount);
end

all_lengths = vertcat(lengths{:});
all_pixels = vertcat(pixels{:});

row = empty_row();
if strcmp(preprocessing, 'gaussian')
    row.condition = 'gaussian';
else
    row.condition = sprintf('E=%.0f%%', 100 * energy_target);
end
row.preprocessing = preprocessing;
row.energy_target = energy_target;
row.rank = rank_used;
row.mean_structures = mean(counts(:, 1), 'omitnan');
row.mean_lsm = mean(counts(:, 2), 'omitnan');
row.mean_vlsm = mean(counts(:, 3), 'omitnan');
row.total_structures = sum(counts(:, 1), 'omitnan');
if ~isempty(all_lengths)
    row.length_median = median(all_lengths, 'omitnan');
    row.length_p90 = prctile(all_lengths, 90);
    row.length_max = max(all_lengths, [], 'omitnan');
    row.pixel_median = median(all_pixels, 'omitnan');
end
end

% =========================================================================
function row = empty_row()
row = struct('condition', '', 'preprocessing', '', 'energy_target', NaN, ...
    'rank', NaN, 'mean_structures', NaN, 'mean_lsm', NaN, ...
    'mean_vlsm', NaN, 'total_structures', NaN, 'length_median', NaN, ...
    'length_p90', NaN, 'length_max', NaN, 'pixel_median', NaN);
end

% =========================================================================
function print_row(row)
fprintf(['  %-12s rank=%-6s 每帧结构 %6.1f | LSM %5.2f | VLSM %5.2f | ' ...
    'Lx中位 %.3f\n'], row.condition, rank_text(row.rank), ...
    row.mean_structures, row.mean_lsm, row.mean_vlsm, row.length_median);
end

% =========================================================================
function txt = rank_text(value)
if isnan(value)
    txt = '-';
else
    txt = sprintf('%d', value);
end
end

% =========================================================================
function cfg = load_case_config(case_root, case_name)
config_file = fullfile(case_root, 'output', 'mat', '00_case_configuration.mat');
if ~isfile(config_file)
    error('podEnergySweep:MissingConfig', ...
        '找不到工况配置：%s（请先运行 %s_case.m）', config_file, case_name);
end
loaded = load(config_file);
if isfield(loaded, 'data') && isstruct(loaded.data) && isfield(loaded.data, 'cfg')
    cfg = loaded.data.cfg;
elseif isfield(loaded, 'cfg')
    cfg = loaded.cfg;
else
    error('podEnergySweep:InvalidConfig', '配置文件结构无法识别：%s', config_file);
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
        error('podEnergySweep:UnknownOverride', ...
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
function spec = structure_preprocessing(settings)
source = struct('enabled', true, 'name', 'Gaussian_sigma1p5_9x9');
if isfield(settings, 'preprocessing') && ~isempty(settings.preprocessing)
    source = settings.preprocessing;
end
spec = source;
if ~isfield(spec, 'gaussian') || isempty(spec.gaussian)
    spec.gaussian = struct('enabled', false);
end
if ~isfield(spec.gaussian, 'enabled')
    spec.gaussian.enabled = false;
end
if ~isfield(spec, 'outlier') || isempty(spec.outlier)
    spec.outlier = struct('enabled', false);
end
end

% =========================================================================
function value = pick(settings, name, fallback)
value = fallback;
if isfield(settings, name) && ~isempty(settings.(name))
    value = settings.(name);
end
end
