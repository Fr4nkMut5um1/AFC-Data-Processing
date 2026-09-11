function preview_section3()
%PREVIEW_SECTION3 Render the saved r2 Section 3 preview without changing cwd.
repo_root = fileparts(fileparts(mfilename('fullpath')));
case_root = fullfile(repo_root, 'cases', 'per_case', 'tandem_f40a3_phi0_r2');
mat_dir = fullfile(case_root, 'output', 'mat');
preview_dir = fullfile(case_root, 'output', 'preview', 'section3');
if ~isfolder(preview_dir); mkdir(preview_dir); end
addpath(fullfile(repo_root, 'lib'));

fprintf('Loading data...\n');
load(fullfile(mat_dir, '00_case_configuration.mat'), 'cfg');
results = struct();
load(fullfile(mat_dir, '02_statistics.mat'), 'data'); results.statistics = data;
load(fullfile(mat_dir, '02_mean_boundary_layer_friction.mat'), 'data'); results.mean_bl = data;
load(fullfile(mat_dir, '03_phase_triple_statistics.mat'), 'data'); results.phase = data;

cfg.preview.enabled = true;
cfg.phase_preview.profile_x_range_mm = [80 320];
cfg.phase_preview.contour_x_range_mm = [80 320];
cfg.phase_preview.marker_stride = 1;

% Match the case entry point's independent contour data source.
phase_contour = results.phase;
if strcmpi(cfg.phase_preview.contour_source, 'postproc') && ...
        ~strcmpi(cfg.statistics_source, 'postproc')
    fprintf('Computing postproc phase fields for the contour preview...\n');
    phase_contour = tblR2.phase_stats_cache( ...
        fullfile(mat_dir, '01_sequence_cache_postproc.mat'), cfg, results.statistics);
end

fprintf('=== 开始生成 Section 3 预览图 (v2) ===\n\n');

Uinf = cfg.Uinf;
delta99 = results.mean_bl.delta99_reference_mm;
x_vec  = results.statistics.X(1, :);
if isfield(results.mean_bl, 'wall_distance_mm') && ~isempty(results.mean_bl.wall_distance_mm)
    y_vec = results.mean_bl.wall_distance_mm(:, 1);
else
    y_vec = results.statistics.Y(:, 1);
end
y_norm = y_vec / delta99;

x_range_profile = cfg.phase_preview.profile_x_range_mm;
col_mask = (x_vec >= x_range_profile(1)) & (x_vec <= x_range_profile(2));
n_cols = sum(col_mask);

total_uu = mean(results.statistics.uu_rey(:, col_mask), 2, 'omitnan');
total_vv = mean(results.statistics.vv_rey(:, col_mask), 2, 'omitnan');
total_uv = mean(results.statistics.uv_rey(:, col_mask), 2, 'omitnan');

coh_uu_field = squeeze(mean(results.phase.u_coherent.^2, 1, 'omitnan'));
coh_vv_field = squeeze(mean(results.phase.v_coherent.^2, 1, 'omitnan'));
coh_uv_field = squeeze(-mean(results.phase.coherent_uv, 1, 'omitnan'));
coh_uu = mean(coh_uu_field(:, col_mask), 2, 'omitnan');
coh_vv = mean(coh_vv_field(:, col_mask), 2, 'omitnan');
coh_uv = mean(coh_uv_field(:, col_mask), 2, 'omitnan');

rand_uu = mean(results.phase.random_global.uu_rey(:, col_mask), 2, 'omitnan');
rand_vv = mean(results.phase.random_global.vv_rey(:, col_mask), 2, 'omitnan');
rand_uv = mean(results.phase.random_global.uv_rey(:, col_mask), 2, 'omitnan');

smooth_pts = 5;
sm_curve = @(v) movmean(v, min(smooth_pts, numel(v)), 'omitnan');

ms = max(1, round(cfg.phase_preview.marker_stride));
mi = 1:ms:numel(y_norm);
if numel(mi) < 2, mi = 1:max(1,round(numel(y_norm)/2)):numel(y_norm); end

%% 图1: 流向 Reynolds 应力
f1 = figure('Position', [100 100 480 440], 'Visible', 'on');
plot(sm_curve(total_uu / Uinf^2), y_norm, 'k-o', 'MarkerSize', 3, ...
    'MarkerIndices', mi, 'LineWidth', 1.4, 'DisplayName', 'Total'); hold on;
plot(sm_curve(coh_uu / Uinf^2), y_norm, 'r-s', 'MarkerSize', 3, ...
    'MarkerIndices', mi, 'LineWidth', 1.4, 'DisplayName', 'Coherent');
plot(sm_curve(rand_uu / Uinf^2), y_norm, 'b-^', 'MarkerSize', 3, ...
    'MarkerIndices', mi, 'LineWidth', 1.4, 'DisplayName', 'Random');
hold off;
xlabel('\langle u^{\prime 2} \rangle / U_\infty^2', 'FontSize', 12);
ylabel('y / \delta_{99}', 'FontSize', 12);
title(sprintf('Streamwise Reynolds stress (x=%d–%d mm)', ...
    x_range_profile(1), x_range_profile(2)), 'FontSize', 11);
legend('Location', 'northeast', 'FontSize', 9);
grid on; set(gca, 'YLim', [0 max(y_norm(isfinite(total_uu)))], 'FontSize', 11);
exportgraphics(f1, fullfile(preview_dir, 'test_v2_fig1_uu.png'), 'Resolution', 150);

%% 图2: 法向 Reynolds 应力
f2 = figure('Position', [180 100 480 440], 'Visible', 'on');
plot(sm_curve(total_vv / Uinf^2), y_norm, 'k-o', 'MarkerSize', 3, ...
    'MarkerIndices', mi, 'LineWidth', 1.4, 'DisplayName', 'Total'); hold on;
plot(sm_curve(coh_vv / Uinf^2), y_norm, 'r-s', 'MarkerSize', 3, ...
    'MarkerIndices', mi, 'LineWidth', 1.4, 'DisplayName', 'Coherent');
plot(sm_curve(rand_vv / Uinf^2), y_norm, 'b-^', 'MarkerSize', 3, ...
    'MarkerIndices', mi, 'LineWidth', 1.4, 'DisplayName', 'Random');
hold off;
xlabel('\langle v^{\prime 2} \rangle / U_\infty^2', 'FontSize', 12);
ylabel('y / \delta_{99}', 'FontSize', 12);
title(sprintf('Wall-normal Reynolds stress (x=%d–%d mm)', ...
    x_range_profile(1), x_range_profile(2)), 'FontSize', 11);
legend('Location', 'northeast', 'FontSize', 9);
grid on; set(gca, 'YLim', [0 max(y_norm(isfinite(total_vv)))], 'FontSize', 11);
exportgraphics(f2, fullfile(preview_dir, 'test_v2_fig2_vv.png'), 'Resolution', 150);

%% 图3: Reynolds 切应力
f3 = figure('Position', [260 100 480 440], 'Visible', 'on');
plot(sm_curve(total_uv / Uinf^2), y_norm, 'k-o', 'MarkerSize', 3, ...
    'MarkerIndices', mi, 'LineWidth', 1.4, 'DisplayName', 'Total'); hold on;
plot(sm_curve(coh_uv / Uinf^2), y_norm, 'r-s', 'MarkerSize', 3, ...
    'MarkerIndices', mi, 'LineWidth', 1.4, 'DisplayName', 'Coherent');
plot(sm_curve(rand_uv / Uinf^2), y_norm, 'b-^', 'MarkerSize', 3, ...
    'MarkerIndices', mi, 'LineWidth', 1.4, 'DisplayName', 'Random');
hold off;
xlabel('-\langle u^{\prime}v^{\prime} \rangle / U_\infty^2', 'FontSize', 12);
ylabel('y / \delta_{99}', 'FontSize', 12);
title(sprintf('Reynolds shear stress (x=%d–%d mm)', ...
    x_range_profile(1), x_range_profile(2)), 'FontSize', 11);
legend('Location', 'northeast', 'FontSize', 9);
grid on; set(gca, 'YLim', [0 max(y_norm(isfinite(total_uv)))], 'FontSize', 11);
exportgraphics(f3, fullfile(preview_dir, 'test_v2_fig3_uv.png'), 'Resolution', 150);

%% 图4 & 图5: 相位平均脉动云图
cx_range = cfg.phase_preview.contour_x_range_mm;
cx_mask = (x_vec >= cx_range(1)) & (x_vec <= cx_range(2));
cx_vec = x_vec(cx_mask);
Umean = results.statistics.Uavex;
Vmean = results.statistics.Vavex;
phase_bins_select = 1:2:23;
n_phase_show = numel(phase_bins_select);
bin_centers_deg = (phase_bins_select - 1) * (360 / cfg.phase.n_bins);
U_fluct_all = [];
V_fluct_all = [];
for k = 1:n_phase_show
    uf = squeeze(results.phase.U_phase(phase_bins_select(k), :, :)) - Umean;
    vf = squeeze(results.phase.V_phase(phase_bins_select(k), :, :)) - Vmean;
    U_fluct_all = [U_fluct_all; uf(:, cx_mask)];
    V_fluct_all = [V_fluct_all; vf(:, cx_mask)];
end
U_clim = max(abs(quantile(U_fluct_all(:), [0.02 0.98])));
V_clim = max(abs(quantile(V_fluct_all(:), [0.02 0.98])));
cmap_div = tblR2.viz.resolve_case_colormap('ocean', 256);
% 使用与两个 r2 入口一致的紧凑布局，确保测试图就是实际交付图的同一渲染路径。
[f4, f5] = tblR2.plot_phase_averaged_maps(x_vec, y_vec, phase_contour, ...
    Umean, Vmean, cx_mask, phase_bins_select, bin_centers_deg, cmap_div, ...
    U_clim, V_clim, 'on');
exportgraphics(f4, fullfile(preview_dir, 'test_v2_fig4_U_phase.png'), 'Resolution', 150);
exportgraphics(f5, fullfile(preview_dir, 'test_v2_fig5_V_phase.png'), 'Resolution', 150);

fprintf('\n=== 测试完成，5 张图已保存为 test_v2_*.png ===\n');
end
