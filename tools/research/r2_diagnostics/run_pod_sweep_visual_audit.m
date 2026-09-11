function run_pod_sweep_visual_audit(varargin)
%RUN_POD_SWEEP_VISUAL_AUDIT 对能量扫描的每个条件每帧出瞬时流向脉动云图。
%
% 用途：人工审核。每帧一张图，LSM 蓝框、VLSM 红框。
% 文件夹按条件分：gaussian/ E20/ E30/ ... E80/
%
% 依赖：已跑过 run_pod_energy_sweep，基底缓存存在。

parser = inputParser;
parser.addParameter('case_name', 'tandem_baseline_r2', @(x) ischar(x) || isstring(x));
parser.addParameter('energy_targets', 0.2:0.1:0.8, @(x) isnumeric(x) && isvector(x));
parser.addParameter('frame_stride', 500, @(x) isscalar(x) && x >= 1);
parser.addParameter('structure_overrides', ...
    struct('alpha', 0.40, 'seed_alpha', 0.70, 'connectivity', 8), @isstruct);
parser.addParameter('output_dir', '', @(x) ischar(x) || isstring(x));
parser.addParameter('clim_sigma', 3, @(x) isscalar(x) && x > 0);
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
    out_root = fullfile(repo_root, 'tmp', 'pod_energy_sweep', 'figures');
else
    out_root = char(opt.output_dir);
end

% ------------------------------------------------------ 加载 POD 基底
basis_cache = fullfile(repo_root, 'tmp', 'pod_energy_sweep', ...
    'pod_energy_sweep_basis.mat');
if ~isfile(basis_cache)
    error('visualAudit:MissingBasis', ...
        '找不到基底缓存 %s。请先运行 run_pod_energy_sweep。', basis_cache);
end
loaded = load(basis_cache, 'denoise');
denoise = loaded.denoise;

cumulative = cumsum(denoise.eigenvalues) / sum(denoise.eigenvalues);
rank_for_target = zeros(size(targets));
for i = 1:numel(targets)
    idx = find(cumulative >= targets(i), 1, 'first');
    if isempty(idx); idx = numel(cumulative); end
    rank_for_target(i) = min(idx, denoise.rank);
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
n_frames = numel(frame_ids);

% 坐标网格（mm）
X_mm = stats.X;
% 颜色范围：±clim_sigma 倍 u_rms 的空间中位数
clim_val = opt.clim_sigma * median(stats.u_rms(valid_mask), 'omitnan');

% ------------------------------------------------------ 条件列表
conditions = cell(1 + numel(targets), 1);
conditions{1} = struct('name', 'gaussian', 'folder', 'gaussian', ...
    'preprocessing', 'gaussian', 'rank', NaN, 'mode_indices', []);
for i = 1:numel(targets)
    conditions{i + 1} = struct('name', sprintf('E=%.0f%%', 100 * targets(i)), ...
        'folder', sprintf('E%02.0f', 100 * targets(i)), ...
        'preprocessing', 'pod_denoise', ...
        'rank', rank_for_target(i), ...
        'mode_indices', 1:rank_for_target(i));
end

fprintf('[出图] %d 个条件 × %d 帧 = %d 张图。\n', ...
    numel(conditions), n_frames, numel(conditions) * n_frames);

% --------------------------------------------------------- 逐条件逐帧出图
for ci = 1:numel(conditions)
    cond = conditions{ci};
    fig_dir = fullfile(out_root, cond.folder);
    if ~isfolder(fig_dir); mkdir(fig_dir); end

    for k = 1:n_frames
        frame_id = frame_ids(k);

        if strcmp(cond.preprocessing, 'pod_denoise')
            [proc_U, ~] = tblR2.pod_denoise_reconstruct_frame( ...
                denoise, frame_id, cond.mode_indices);
            source_valid = analysis_domain_mask;
        else
            chunk = tblR2.read_cache_chunk(paths.sequence_cache_postproc, frame_id, ...
                1:J, 1:I, 'raw', [], []);
            raw_U = squeeze(chunk.U);
            raw_V = squeeze(chunk.V);
            raw_valid = valid_mask & squeeze(chunk.sampleValid);
            processed = tblR2.preprocess_structure_velocity(raw_U, raw_V, ...
                raw_valid, analysis_domain_mask, preprocess_spec);
            proc_U = processed.U;
            source_valid = processed.output_valid_mask;
        end

        [mean_U, ~] = mean_field_for_frame(stats, frame_id, 1:J, 1:I);
        structure_mask = source_valid & isfinite(proc_U) & isfinite(mean_U);
        total_U_f = proc_U - mean_U;
        total_U_f(~structure_mask) = NaN;

        % 识别
        identified = tblR2.identify_structures(total_U_f, stats.u_rms, ...
            stats.X, Y_wall_mm, delta_grid, structure_mask, opts);
        T = identified.structures;

        % 画图
        fig = figure('Visible', 'off', 'Units', 'centimeters', ...
            'Position', [1 1 24 6], 'Color', 'w');
        ax = axes(fig); %#ok<LAXES>
        pcolor(ax, X_mm, Y_wall_mm, total_U_f);
        shading(ax, 'interp');
        colormap(ax, bluewhitered(256));
        caxis(ax, [-clim_val clim_val]);
        hold(ax, 'on');
        axis(ax, 'equal', 'tight');
        set(ax, 'YDir', 'normal', 'FontSize', 7, 'TickDir', 'in');
        xlabel(ax, 'x (mm)');
        ylabel(ax, 'y (mm)');
        cb = colorbar(ax);
        ylabel(cb, "u' (m/s)");

        % 画框
        draw_boxes(ax, T, 'LSM');
        draw_boxes(ax, T, 'VLSM');

        title(ax, sprintf('%s  frame=%d  (#struct=%d  LSM=%d  VLSM=%d)', ...
            cond.name, frame_id, height(T), sum(T.IsLSM), sum(T.IsVLSM)), ...
            'FontSize', 8, 'FontWeight', 'normal');

        fname = fullfile(fig_dir, sprintf('frame_%05d.png', frame_id));
        exportgraphics(fig, fname, 'Resolution', 200);
        close(fig);
    end
    fprintf('  %s: %d 张已保存到 %s\n', cond.name, n_frames, fig_dir);
end

fprintf('\n=== 人工审核图已全部导出 ===\n  位置：%s\n', out_root);
end

% =========================================================================
function draw_boxes(ax, T, class)
%DRAW_BOXES 在已识别结构的包围盒上画矩形。
% LSM=蓝色虚线, VLSM=红色实线加粗。
if strcmp(class, 'LSM')
    mask = T.IsLSM & ~T.IsVLSM;
    color = [0.2 0.4 1.0];
    style = '--';
    lw = 1.2;
elseif strcmp(class, 'VLSM')
    mask = T.IsVLSM;
    color = [1.0 0.1 0.1];
    style = '-';
    lw = 1.8;
else
    return;
end
idx = find(mask);
for i = 1:numel(idx)
    row = T(idx(i), :);
    x0 = row.XMin_mm;
    y0 = row.YMin_mm;
    w = row.XMax_mm - row.XMin_mm;
    h = row.YMax_mm - row.YMin_mm;
    if w > 0 && h > 0
        rectangle(ax, 'Position', [x0 y0 w h], ...
            'EdgeColor', color, 'LineStyle', style, 'LineWidth', lw);
    end
end
end

% =========================================================================
function cmap = bluewhitered(n)
%BLUEWHITERED 蓝-白-红对称 colormap。
if nargin < 1; n = 256; end
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
function cfg = load_case_config(case_root, case_name)
config_file = fullfile(case_root, 'output', 'mat', '00_case_configuration.mat');
if ~isfile(config_file)
    error('visualAudit:MissingConfig', ...
        '找不到工况配置：%s（请先运行 %s_case.m）', config_file, case_name);
end
loaded = load(config_file);
if isfield(loaded, 'data') && isstruct(loaded.data) && isfield(loaded.data, 'cfg')
    cfg = loaded.data.cfg;
elseif isfield(loaded, 'cfg')
    cfg = loaded.cfg;
else
    error('visualAudit:InvalidConfig', '配置文件结构无法识别：%s', config_file);
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
        error('visualAudit:UnknownOverride', ...
            'cfg.structures 中不存在字段 %s。', names{i});
    end
    settings.(names{i}) = overrides.(names{i});
end
end

% =========================================================================
function opts = structure_opts(settings)
opts = struct('alpha', settings.alpha, 'min_pixels', settings.min_pixels, ...
    'seed_alpha', pick(settings, 'seed_alpha', settings.alpha), ...
    'connectivity', settings.connectivity, ...
    'max_internal_hole_pixels', pick(settings, 'max_internal_hole_pixels', 0), ...
    'envelope_closing_radius_cells', pick(settings, 'envelope_closing_radius_cells', 0), ...
    'max_aspect_ratio', pick(settings, 'max_aspect_ratio', inf), ...
    'reject_trusted_boundary_touching', pick(settings, 'reject_trusted_boundary_touching', false), ...
    'min_lsm_delta', settings.min_lsm_delta, ...
    'min_vlsm_delta', settings.min_vlsm_delta, ...
    'max_wall_normal_delta', settings.max_wall_normal_delta, ...
    'min_abs_fluctuation', pick(settings, 'min_abs_fluctuation', 0), ...
    'min_abs_seed_fluctuation', pick(settings, 'min_abs_seed_fluctuation', 0), ...
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
