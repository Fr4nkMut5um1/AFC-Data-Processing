function generate_annotation_samples(varargin)
%GENERATE_ANNOTATION_SAMPLES 生成用于人工标注的 POD 重构流场图像序列。
%
% 用途：为参数寻优建立 Ground Truth。从指定能量档的 POD 重构场中随机选择
%       36 帧，生成标准化的脉动云图（u'/u_rms），供人工标注 VLSM 边界框。
%
% 调用方式：
%   generate_annotation_samples('energy_target', 0.60, ...
%                               'output_dir', 'tmp/annotation_samples/e60', ...
%                               'n_frames', 36, ...
%                               'random_seed', 20260829)
%
% 输入参数（Name-Value pairs）
%   energy_target   : POD 能量目标（如 0.60）
%   output_dir      : 输出目录（存放图像和元数据）
%   n_frames        : 采样帧数（默认 36）
%   random_seed     : 随机种子（默认 20260829）
%   case_name       : case 名称（默认 'tandem_baseline_r2'）
%
% 输出
%   output_dir/frames/frame_XXXX.png    : 36 张标准化脉动云图
%   output_dir/metadata.json            : 帧号、能量、rank 等元数据
%   output_dir/annotation_template.json : 空标注模板（待填充）
%
% 工作流程：
%   1. 加载 case 配置、统计、POD 基
%   2. 按种子随机选择 36 帧
%   3. 逐帧 POD 重构 → 去均值 → 归一化（u'/u_rms）
%   4. 生成脉动云图 PNG（红白蓝对称色标）
%   5. 输出元数据和空标注模板

p = inputParser;
addParameter(p, 'energy_target', 0.60, @(x) isnumeric(x) && x > 0 && x < 1);
addParameter(p, 'output_dir', 'tmp/annotation_samples/e60', @ischar);
addParameter(p, 'n_frames', 36, @(x) isnumeric(x) && x > 0);
addParameter(p, 'random_seed', 20260829, @isnumeric);
addParameter(p, 'case_name', 'tandem_baseline_r2', @ischar);
parse(p, varargin{:});
opts = p.Results;

fprintf('[生成标注样本] 能量=%g%%, 采样帧数=%d\n', opts.energy_target*100, opts.n_frames);

%% 1. 加载 case 数据
repo = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
case_dir = fullfile(repo, 'cases', 'per_case', opts.case_name);
addpath(fullfile(repo, 'lib'));

% 配置文件在 output/mat/ 子目录下
mat_dir = fullfile(case_dir, 'output', 'mat');
cfg_file = fullfile(mat_dir, '00_case_configuration.mat');
stats_file = fullfile(mat_dir, '02_statistics.mat');
cache_file = fullfile(mat_dir, '01_sequence_cache.mat');
mean_bl_file = fullfile(mat_dir, '02_mean_boundary_layer_friction.mat');

if ~isfile(cfg_file) || ~isfile(stats_file) || ~isfile(mean_bl_file)
    error('Case 数据文件缺失：%s', opts.case_name);
end

% 阶段结果以 data/meta 包装存盘，必须经 tblR2.load_result 读取——它同时校验
% case_id/stage/帧数/网格/fs 的身份合同。直接 load(...,'stats') 取不到东西。
cfg = load(cfg_file, 'cfg'); cfg = cfg.cfg;
stats = tblR2.load_result(stats_file, cfg, 'statistics');
mean_bl = tblR2.load_result(mean_bl_file, cfg, 'mean_bl');

%% 2. 加载 POD 基
basis_file = fullfile(repo, 'tmp/pod_energy_sweep/pod_energy_sweep_basis.mat');
if ~isfile(basis_file)
    error('POD 基文件不存在：%s', basis_file);
end
denoise = load(basis_file, 'denoise'); denoise = denoise.denoise;

% 根据 energy_target 确定 rank
cumulative = cumsum(denoise.eigenvalues) / sum(denoise.eigenvalues);
rank_r = find(cumulative >= opts.energy_target, 1, 'first');
if isempty(rank_r)
    rank_r = denoise.rank;
end
fprintf('[POD] 能量 %g%% 对应 rank=%d, 累计能量=%.4f\n', ...
    opts.energy_target*100, rank_r, cumulative(rank_r));

mode_indices = 1:rank_r;

%% 3. 随机选择 36 帧
rng(opts.random_seed);
all_frames = denoise.frame_ids(:)';
n_available = numel(all_frames);
if opts.n_frames > n_available
    warning('可用帧数(%d)少于请求帧数(%d)，采样全部', n_available, opts.n_frames);
    selected_frames = all_frames;
else
    selected_frames = randsample(all_frames, opts.n_frames);
end
selected_frames = sort(selected_frames);
fprintf('[采样] 从 %d 帧中随机选择 %d 帧（种子=%d）\n', ...
    n_available, numel(selected_frames), opts.random_seed);

%% 4. 创建输出目录
if ~isfolder(opts.output_dir)
    mkdir(opts.output_dir);
end
frames_dir = fullfile(opts.output_dir, 'frames');
if ~isfolder(frames_dir)
    mkdir(frames_dir);
end

%% 5. 生成脉动云图
J = size(stats.X, 1);
I = size(stats.X, 2);
x_mm = stats.X(1, :);
y_mm = mean_bl.wall_distance_mm(:, 1);

% 准备可信域掩膜
delta_grid = interp1(mean_bl.boundary_layer.x, ...
    mean_bl.boundary_layer.delta99, stats.X, 'linear', NaN);
valid_mask = stats.accepted_mask & isfinite(delta_grid) & delta_grid > 0;
domain_mask = tblR2.trusted_domain_mask(valid_mask, mean_bl.wall_distance_mm, ...
    cfg.structures.trusted_domain);

metadata = struct();
metadata.case_name = opts.case_name;
metadata.energy_target = opts.energy_target;
metadata.pod_rank = rank_r;
metadata.cumulative_energy = cumulative(rank_r);
metadata.random_seed = opts.random_seed;
metadata.n_frames = numel(selected_frames);
metadata.frame_ids = selected_frames;
metadata.generated_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');

fprintf('[生成图像] 开始生成 %d 张脉动云图...\n', numel(selected_frames));
for k = 1:numel(selected_frames)
    fid = selected_frames(k);

    % POD 重构
    [U_pod, V_pod] = tblR2.pod_denoise_reconstruct_frame(denoise, fid, mode_indices);

    % 去均值：按 repeat 分段均值
    if isfield(stats, 'repeat_means') && ~isempty(stats.repeat_means)
        rep = 1 + nnz(fid > stats.repeat_boundaries(:)');
        mean_U = squeeze(stats.repeat_means(1, rep, :, :));
    else
        mean_U = squeeze(stats.Uavex);
    end

    % 脉动归一化
    u_prime = U_pod - mean_U;
    u_norm = u_prime ./ stats.u_rms;
    u_norm(~domain_mask) = NaN;

    % 生成云图
    fig = figure('Visible', 'off', 'Position', [100 100 1200 400]);
    ax = axes(fig);
    contourf(ax, x_mm, y_mm, u_norm, 60, 'LineStyle', 'none');
    axis(ax, 'tight');
    set(ax, 'YDir', 'normal');

    % 对称色标
    finite_vals = u_norm(isfinite(u_norm));
    clim_val = quantile(abs(finite_vals), 0.995);
    clim(ax, [-clim_val, clim_val]);
    colormap(ax, tblR2.viz.resolve_case_colormap('balance', 256));
    colorbar(ax);

    xlabel(ax, 'x (mm)');
    ylabel(ax, '离壁距离 (mm)');
    title(ax, sprintf('Frame %d | E=%g%% rank=%d | u''/u_{rms}', ...
        fid, opts.energy_target*100, rank_r), 'Interpreter', 'tex');
    tblR2.viz.apply_fov_aspect(ax, cfg);

    % 保存
    png_file = fullfile(frames_dir, sprintf('frame_%04d.png', fid));
    saveas(fig, png_file);
    close(fig);

    if mod(k, 6) == 0
        fprintf('  已完成 %d/%d\n', k, numel(selected_frames));
    end
end

%% 6. 生成空标注模板
annotations = struct();
annotations.metadata = metadata;
annotations.frames = struct();

for k = 1:numel(selected_frames)
    fid = selected_frames(k);
    key = sprintf('frame_%04d', fid);
    annotations.frames.(key) = struct(...
        'frame_id', fid, ...
        'image_file', sprintf('frames/frame_%04d.png', fid), ...
        'vlsm_boxes', [], ...  % 待标注：[{x_min, x_max, y_min, y_max, length_mm, center_x, center_y}]
        'annotation_status', 'pending', ...  % pending / completed / verified
        'annotator_notes', '' ...
    );
end

% 写入文件
metadata_file = fullfile(opts.output_dir, 'metadata.json');
template_file = fullfile(opts.output_dir, 'annotation_template.json');

write_json(metadata_file, metadata);
write_json(template_file, annotations);

fprintf('[完成] 生成 %d 张图像\n', numel(selected_frames));
fprintf('  输出目录: %s\n', opts.output_dir);
fprintf('  元数据: %s\n', metadata_file);
fprintf('  标注模板: %s\n', template_file);
fprintf('\n下一步：人工标注 VLSM 边界框，填充 annotation_template.json\n');
end

function write_json(filepath, data)
% 简单 JSON 写入（MATLAB R2016b+ 支持 jsonencode）
fid = fopen(filepath, 'w', 'n', 'UTF-8');
fprintf(fid, '%s', jsonencode(data));
fclose(fid);
end
