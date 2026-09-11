%% Historical Phase C experiment: Gaussian + streamwise-neighbor merging.
% Research only: these historical parameters are not the formal Section 4.
% Requires historical-compatible caches; runtime has not been revalidated.
% 在推荐参数 (alpha=1.0, seed=1.2, min_abs=1.0, merge_gap=40) 下运行 480 帧，
% 统计 VLSM/LSM 检出量，并为每帧保存结构叠加诊断图。

base_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(base_dir, 'lib'));
addpath(fullfile(base_dir, 'tools/research/r2_diagnostics'));
addpath(base_dir);

mat_dir = fullfile(base_dir, 'cases/per_case/tandem_baseline_r2/output/mat');
fig_dir = fullfile(base_dir, 'cases/per_case/tandem_baseline_r2/output/research/phaseC_frames');
if ~isfolder(fig_dir), mkdir(fig_dir); end

%% 帧抽样（与逾渗扫描一致）
rng(20260824);
n_repeat = 2; n_per_repeat = 240;
frame_ids = [];
for r = 1:n_repeat
    lo = (r - 1) * 6000 + 1; hi = r * 6000;
    frame_ids = [frame_ids, sort(randperm(hi - lo + 1, n_per_repeat) + (lo - 1))]; %#ok<AGROW>
end
fprintf('Phase C: %d 帧抽样完成\n', numel(frame_ids));

%% 加载数据
fprintf('加载帧数据...\n');
ctx = load_sweep_frames(mat_dir, frame_ids);

%% 参数配置
preprocess_spec = make_gaussian_spec(ctx.baseline_preprocess, 1.5, 4);
td = struct('streamwise_edge_columns', 16, 'wall_normal_top_rows', 2);
analysis_domain_mask = tblR2.trusted_domain_mask( ...
    ctx.raw_valid(:,:,1) | true(size(ctx.X)), ctx.Y_wall_mm, td);

opts = struct('alpha', 1.0, 'seed_alpha', 1.2, 'min_pixels', 3, ...
    'connectivity', 4, 'min_lsm_delta', 1.0, 'min_vlsm_delta', 3.0, ...
    'max_wall_normal_delta', Inf, 'max_internal_hole_pixels', 64, ...
    'envelope_closing_radius_cells', 2, 'max_aspect_ratio', Inf, ...
    'reject_trusted_boundary_touching', true, 'sign_mode', 'both', ...
    'min_abs_fluctuation', 1.0, 'min_abs_seed_fluctuation', 1.0);

merge_opts = struct('merge_gap_cells', 40, 'merge_require_y_overlap', true, ...
    'min_lsm_delta', 1.0, 'min_vlsm_delta', 3.0);

dx = median(abs(diff(ctx.X(1,:))), 'omitnan');
dy = median(abs(diff(ctx.Y_wall_mm(:,1))), 'omitnan');

%% 逐帧处理
n_frames = ctx.n_frames;
stats_per_frame = struct( ...
    'frame_id', num2cell(frame_ids(:)), ...
    'n_structures', num2cell(zeros(n_frames,1)), ...
    'n_lsm', num2cell(zeros(n_frames,1)), ...
    'n_vlsm', num2cell(zeros(n_frames,1)), ...
    'n_merges', num2cell(zeros(n_frames,1)), ...
    'max_lx_delta', num2cell(zeros(n_frames,1)));

cmap = cmocean('balance', 256);
fig = figure('Position', [50 50 1400 500], 'Color', 'w', 'Visible', 'off');

fprintf('开始逐帧处理 + 生成诊断图...\n');
tic;
for k = 1:n_frames
    raw_U = ctx.raw_U(:,:,k);
    raw_V = ctx.raw_V(:,:,k);
    raw_valid = ctx.raw_valid(:,:,k);

    prep = tblR2.preprocess_structure_velocity( ...
        raw_U, raw_V, raw_valid, analysis_domain_mask, preprocess_spec);
    struct_mask = prep.output_valid_mask & isfinite(ctx.mean_U(:,:,k));
    u_fluct = prep.U - ctx.mean_U(:,:,k);
    u_fluct(~struct_mask) = NaN;

    id = tblR2.identify_structures(u_fluct, ctx.u_rms, ctx.X, ...
        ctx.Y_wall_mm, ctx.delta_grid, struct_mask, opts);

    [tbl, mlog] = tblR2.vlsm.merge_streamwise_neighbors( ...
        id.structures, id.positive_labels, id.negative_labels, ...
        ctx.X, ctx.Y_wall_mm, ctx.delta_grid, dx, dy, u_fluct, merge_opts);

    stats_per_frame(k).n_structures = height(tbl);
    stats_per_frame(k).n_lsm = sum(tbl.IsLSM);
    stats_per_frame(k).n_vlsm = sum(tbl.IsVLSM);
    stats_per_frame(k).n_merges = mlog.n_merges;
    if height(tbl) > 0
        stats_per_frame(k).max_lx_delta = max(tbl.LengthX_over_delta);
    end

    % 绘制诊断图
    clf(fig);
    pcolor(ctx.X, ctx.Y_wall_mm, u_fluct); shading flat;
    colormap(cmap); caxis([-3 3]); colorbar;
    hold on;
    for is = 1:height(tbl)
        r = tbl(is, :);
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
    title(sprintf('帧 %d | 结构=%d, LSM=%d, VLSM=%d', ...
        frame_ids(k), height(tbl), sum(tbl.IsLSM), sum(tbl.IsVLSM)));
    set(gca, 'FontSize', 9);

    fname = fullfile(fig_dir, sprintf('frame_%05d.png', frame_ids(k)));
    exportgraphics(fig, fname, 'Resolution', 150);

    if mod(k, 50) == 0 || k == n_frames
        elapsed = toc;
        fprintf('[Phase C] %d/%d 帧完成 (%.1f s, %.2f s/帧)\n', ...
            k, n_frames, elapsed, elapsed/k);
    end
end
close(fig);

%% 汇总统计
all_vlsm = [stats_per_frame.n_vlsm];
all_lsm = [stats_per_frame.n_lsm];
all_struct = [stats_per_frame.n_structures];
all_merges = [stats_per_frame.n_merges];
all_maxlx = [stats_per_frame.max_lx_delta];

fprintf('\n============ Phase C 结果汇总 ============\n');
fprintf('参数: alpha=1.0, seed=1.2, min_abs=1.0, merge_gap=40, conn=4\n');
fprintf('帧数: %d\n', n_frames);
fprintf('VLSM/帧: mean=%.2f, median=%.1f, max=%d\n', mean(all_vlsm), median(all_vlsm), max(all_vlsm));
fprintf('LSM/帧: mean=%.2f, median=%.1f, max=%d\n', mean(all_lsm), median(all_lsm), max(all_lsm));
fprintf('结构/帧: mean=%.1f, median=%.1f\n', mean(all_struct), median(all_struct));
fprintf('合并/帧: mean=%.2f\n', mean(all_merges));
fprintf('最大 Lx/δ: %.2f\n', max(all_maxlx));
fprintf('VLSM>0 的帧比例: %.1f%%\n', 100*mean(all_vlsm > 0));
fprintf('==========================================\n');

%% 保存统计结果
phaseC_result = struct();
phaseC_result.params = opts;
phaseC_result.merge_opts = merge_opts;
phaseC_result.frame_ids = frame_ids;
phaseC_result.stats_per_frame = stats_per_frame;
phaseC_result.summary = struct('vlsm_per_frame_mean', mean(all_vlsm), ...
    'lsm_per_frame_mean', mean(all_lsm), ...
    'structures_per_frame_mean', mean(all_struct), ...
    'merges_per_frame_mean', mean(all_merges), ...
    'max_lx_delta', max(all_maxlx), ...
    'vlsm_frame_fraction', mean(all_vlsm > 0));
save(fullfile(mat_dir, '09d_phaseC_dual_mechanism.mat'), 'phaseC_result', '-v7.3');
fprintf('统计结果已保存: 09d_phaseC_dual_mechanism.mat\n');
fprintf('诊断图已保存到: %s\n', fig_dir);
