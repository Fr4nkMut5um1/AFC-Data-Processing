% Research utility with historical cache/parameter assumptions; see tools/README.md.
% Not a daily entry or formal Section 4 acceptance test. Runtime not revalidated.
%% validate_single_frame_11627 — 单帧验证双机制改进（alpha=0.67, seed=1.5, merge_gap=40）
% 对第 11627 帧运行完整管线，输出结构检出统计与诊断图。

base_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(base_dir, 'lib'));
addpath(base_dir);

mat_dir = fullfile(base_dir, 'cases/per_case/tandem_baseline_r2/output/mat');
frame_id = 11627;

%% 加载依赖数据
fprintf('加载 statistics...\n');
S = load(fullfile(mat_dir, '02_statistics.mat'), 'data');
stats = S.data;

fprintf('加载 mean_bl...\n');
B = load(fullfile(mat_dir, '02_mean_boundary_layer_friction.mat'), 'data');
mean_bl = B.data;

fprintf('加载 postproc 缓存元信息...\n');
cache_file = fullfile(mat_dir, '01_sequence_cache_postproc.mat');

%% 设置配置（与 case 文件一致的新参数）
J = size(stats.X, 1);
I = size(stats.X, 2);
Y_wall_mm = mean_bl.wall_distance_mm;
delta_grid = interp1(mean_bl.boundary_layer.x, ...
    mean_bl.boundary_layer.delta99, stats.X, 'linear', NaN);
valid_mask = stats.accepted_mask & isfinite(delta_grid) & delta_grid > 0;

% 新参数
cfg_s = struct();
cfg_s.alpha = 1.0;
cfg_s.seed_alpha = 1.2;
cfg_s.min_pixels = 3;
cfg_s.connectivity = 4;
cfg_s.min_lsm_delta = 1.0;
cfg_s.min_vlsm_delta = 3.0;
cfg_s.max_wall_normal_delta = Inf;
cfg_s.max_internal_hole_pixels = 64;
cfg_s.envelope_closing_radius_cells = 2;
cfg_s.max_aspect_ratio = Inf;
cfg_s.reject_trusted_boundary_touching = true;
cfg_s.sign_mode = 'both';
cfg_s.merge_gap_cells = 40;
cfg_s.merge_require_y_overlap = true;
cfg_s.min_abs_fluctuation = 1.0;
cfg_s.min_abs_seed_fluctuation = 1.0;

% 预处理
cfg_s.preprocessing = struct();
cfg_s.preprocessing.enabled = true;
cfg_s.preprocessing.name = 'Gaussian_sigma1p5_9x9';
cfg_s.preprocessing.edge_buffer_cells = [0 0];
cfg_s.preprocessing.outlier = struct('enabled', false, ...
    'radius_cells', 1, 'threshold', 2.0, ...
    'residual_epsilon', 0.10, 'min_neighbors', 5);
cfg_s.preprocessing.gaussian = struct('enabled', true, ...
    'sigma_cells', 1.5, 'radius_cells', 4, 'min_support_fraction', 0.50);

% 可信域
cfg_s.trusted_domain = struct();
cfg_s.trusted_domain.streamwise_edge_columns = 16;
cfg_s.trusted_domain.wall_normal_top_rows = 2;

%% 构造 opts（与 structure_analysis_cache 中的 structure_opts 逻辑一致）
opts = struct();
opts.alpha = cfg_s.alpha;
opts.seed_alpha = cfg_s.seed_alpha;
opts.min_pixels = cfg_s.min_pixels;
opts.connectivity = cfg_s.connectivity;
opts.min_lsm_delta = cfg_s.min_lsm_delta;
opts.min_vlsm_delta = cfg_s.min_vlsm_delta;
opts.max_wall_normal_delta = cfg_s.max_wall_normal_delta;
opts.max_internal_hole_pixels = cfg_s.max_internal_hole_pixels;
opts.envelope_closing_radius_cells = cfg_s.envelope_closing_radius_cells;
opts.max_aspect_ratio = cfg_s.max_aspect_ratio;
opts.reject_trusted_boundary_touching = cfg_s.reject_trusted_boundary_touching;
opts.sign_mode = cfg_s.sign_mode;
opts.min_abs_fluctuation = cfg_s.min_abs_fluctuation;
opts.min_abs_seed_fluctuation = cfg_s.min_abs_seed_fluctuation;

%% 预处理规格（复制 structure_preprocessing 逻辑）
preprocess_spec = struct();
preprocess_spec.name = 'Gaussian_sigma1p5_9x9';
preprocess_spec.enabled = true;
preprocess_spec.edge_buffer_cells = [0 0];
preprocess_spec.outlier = struct('enabled', false, ...
    'radius_cells', 1, 'threshold', 2, ...
    'residual_epsilon', 0.1, 'min_neighbors', 5);
preprocess_spec.gaussian = struct( ...
    'enabled', true, ...
    'sigma_cells', 1.5, ...
    'radius_cells', 4, ...
    'sigma_x_cells', 1.5, ...
    'sigma_y_cells', 1.5, ...
    'radius_x_cells', 4, ...
    'radius_y_cells', 4, ...
    'kernel_type', 'gaussian', ...
    'kernel_normalization', 'sum1', ...
    'boundary_mode', 'legacy_zero', ...
    'mask_aware', false, ...
    'min_support_fraction', 0.5, ...
    'apply_to', {{'u', 'v'}}, ...
    'apply_stage', 'instantaneous_before_mean_subtraction');

%% 可信域掩膜
trusted_domain = struct( ...
    'streamwise_edge_columns', cfg_s.trusted_domain.streamwise_edge_columns, ...
    'wall_normal_top_rows', cfg_s.trusted_domain.wall_normal_top_rows);
analysis_domain_mask = tblR2.trusted_domain_mask(valid_mask, Y_wall_mm, trusted_domain);

%% 读取第 11627 帧
fprintf('读取第 %d 帧...\n', frame_id);
raw_batch = tblR2.read_cache_chunk(cache_file, frame_id, 1:J, 1:I, 'raw', stats, []);
raw_U = squeeze(raw_batch.U(1, :, :));
raw_V = squeeze(raw_batch.V(1, :, :));
raw_valid = valid_mask & squeeze(raw_batch.sampleValid(1, :, :));

%% 预处理 + 减均值
raw_preprocessed = tblR2.preprocess_structure_velocity( ...
    raw_U, raw_V, raw_valid, analysis_domain_mask, preprocess_spec);

% 使用与生产代码一致的均值场逻辑
if isfield(stats, 'repeat_means') && ~isempty(stats.repeat_means) && ...
        isfield(stats, 'repeat_boundaries') && ~isempty(stats.repeat_boundaries)
    rep = 1 + nnz(frame_id > stats.repeat_boundaries(:)');
    mean_U = squeeze(stats.repeat_means(1, rep, :, :));
    mean_V = squeeze(stats.repeat_means(2, rep, :, :));
    fprintf('使用 repeat %d 的均值场\n', rep);
else
    mean_U = stats.Uavex;
    mean_V = stats.Vavex;
    fprintf('使用全局均值场\n');
end
structure_mask = raw_preprocessed.output_valid_mask & ...
    isfinite(mean_U) & isfinite(mean_V);
total_U_f = raw_preprocessed.U - mean_U;
total_U_f(~structure_mask) = NaN;

%% 结构识别
fprintf('运行 identify_structures...\n');
id_result = tblR2.identify_structures( ...
    total_U_f, stats.u_rms, stats.X, Y_wall_mm, delta_grid, ...
    structure_mask, opts);

fprintf('\n===== 合并前 =====\n');
tbl_before = id_result.structures;
fprintf('总结构数: %d\n', height(tbl_before));
fprintf('LSM 数: %d\n', sum(tbl_before.IsLSM));
fprintf('VLSM 数: %d\n', sum(tbl_before.IsVLSM));
if height(tbl_before) > 0
    fprintf('最大 Lx/δ: %.2f\n', max(tbl_before.LengthX_over_delta));
end

%% 流向合并
dx = median(abs(diff(stats.X(1, :))), 'omitnan');
dy = median(abs(diff(Y_wall_mm(:, 1))), 'omitnan');
merge_opts = struct( ...
    'merge_gap_cells', cfg_s.merge_gap_cells, ...
    'merge_require_y_overlap', cfg_s.merge_require_y_overlap, ...
    'min_lsm_delta', cfg_s.min_lsm_delta, ...
    'min_vlsm_delta', cfg_s.min_vlsm_delta);
[tbl_after, mlog] = tblR2.vlsm.merge_streamwise_neighbors( ...
    id_result.structures, id_result.positive_labels, id_result.negative_labels, ...
    stats.X, Y_wall_mm, delta_grid, dx, dy, total_U_f, merge_opts);

fprintf('\n===== 合并后 =====\n');
fprintf('总结构数: %d (合并了 %d 对)\n', height(tbl_after), mlog.n_merges);
fprintf('LSM 数: %d\n', sum(tbl_after.IsLSM));
fprintf('VLSM 数: %d\n', sum(tbl_after.IsVLSM));
if height(tbl_after) > 0
    fprintf('最大 Lx/δ: %.2f\n', max(tbl_after.LengthX_over_delta));
    vlsm_rows = tbl_after(tbl_after.IsVLSM, :);
    if height(vlsm_rows) > 0
        fprintf('\n--- VLSM 详情 ---\n');
        for iv = 1:height(vlsm_rows)
            fprintf('  #%d: Sign=%+d, x=[%.1f, %.1f]mm, Lx=%.1fmm, Lx/δ=%.2f, y=[%.1f, %.1f]mm\n', ...
                iv, vlsm_rows.Sign(iv), ...
                vlsm_rows.XMin_mm(iv), vlsm_rows.XMax_mm(iv), ...
                vlsm_rows.LengthX_mm(iv), vlsm_rows.LengthX_over_delta(iv), ...
                vlsm_rows.YMin_mm(iv), vlsm_rows.YMax_mm(iv));
        end
    end
end

%% 诊断图：脉动场 + 结构 bounding box
fprintf('\n绘制诊断图...\n');
fig = figure('Position', [50 50 1400 500], 'Color', 'w');

X = stats.X;
Y = Y_wall_mm;
pcolor(X, Y, total_U_f); shading flat;
if exist('bluewhitered', 'file') == 2
    colormap(bluewhitered(256));
else
    colormap(jet(256));
end
caxis([-3 3]);
colorbar;
hold on;

% 画合并后的结构 bounding box
for is = 1:height(tbl_after)
    r = tbl_after(is, :);
    if r.IsVLSM
        lw = 2.5; ls = '-';
    elseif r.IsLSM
        lw = 1.5; ls = '--';
    else
        continue;
    end
    if r.Sign > 0
        clr = [0.8 0 0];
    else
        clr = [0 0 0.8];
    end
    x1 = r.XMin_mm; x2 = r.XMax_mm;
    y1 = r.YMin_mm; y2 = r.YMax_mm;
    plot([x1 x2 x2 x1 x1], [y1 y1 y2 y2 y1], ...
        'Color', clr, 'LineWidth', lw, 'LineStyle', ls);
end

xlabel('x (mm)'); ylabel('离壁距离 (mm)');
title(sprintf('帧 %d | 结构=%d, LSM=%d, VLSM=%d | \\alpha=%.2f, seed=%.2f, merge\\_gap=%d', ...
    frame_id, height(tbl_after), sum(tbl_after.IsLSM), sum(tbl_after.IsVLSM), ...
    cfg_s.alpha, cfg_s.seed_alpha, cfg_s.merge_gap_cells));
set(gca, 'FontSize', 10);

fig_dir = fullfile(base_dir, 'cases/per_case/tandem_baseline_r2/output/research');
if ~isfolder(fig_dir); mkdir(fig_dir); end
fig_path = fullfile(fig_dir, 'validate_frame_11627_dual_mechanism.png');
try
    exportgraphics(fig, fig_path, 'Resolution', 200);
catch
    print(fig, fig_path, '-dpng', '-r200');
end
fprintf('诊断图已保存: %s\n', fig_path);
fprintf('\n验证完成。\n');
