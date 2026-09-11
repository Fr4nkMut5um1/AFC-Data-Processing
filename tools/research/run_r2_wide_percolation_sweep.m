% Research utility with historical cache/parameter assumptions; see tools/README.md.
% Not a daily entry or formal Section 4 acceptance test. Runtime not revalidated.
%% run_r2_wide_percolation_sweep — 宽范围逾渗扫描 + seed_alpha 联合标定
% 2026-08-24: sigma 缺陷修复后，用正式生产配置（sigma=1.5/9x9, connectivity=4）
% 重新定位逾渗转变区，并通过 bootstrap 稳定区判据确定推荐工作点。
%
% Phase A: 宽扫描 alpha∈[0.5, 2.5], seed_alpha=alpha（无滞回），定位转变区
% Phase B: 在转变区后平台段，扫描 seed_alpha 联合标定
%
% 输出:
%   cases/per_case/tandem_baseline_r2/output/mat/09d_percolation_sweep_wide.mat

base_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(base_dir, 'lib'));
addpath(fullfile(base_dir, 'tools/research/r2_diagnostics'));
addpath(base_dir);

mat_dir = fullfile(base_dir, 'cases/per_case/tandem_baseline_r2/output/mat');
fig_dir = fullfile(base_dir, 'cases/per_case/tandem_baseline_r2/output/research');
if ~isfolder(fig_dir), mkdir(fig_dir); end

% ---- 帧抽样（与原扫描一致：480帧，2 repeats x 240） ----
rng(20260824);
n_repeat = 2;
n_per_repeat = 240;
frame_ids = [];
for r = 1:n_repeat
    lo = (r - 1) * 6000 + 1;
    hi = r * 6000;
    frame_ids = [frame_ids, sort(randperm(hi - lo + 1, n_per_repeat) + (lo - 1))]; %#ok<AGROW>
end
fprintf('抽样帧数：%d\n', numel(frame_ids));

ctx = load_sweep_frames(mat_dir, frame_ids);

% ======== Phase A: 宽扫描定位转变区 ========
fprintf('\n======== Phase A: 宽范围逾渗扫描 (alpha∈[0.5, 2.5]) ========\n');

% 使用修复后的正式生产配置（sigma=1.5/9x9）
preprocess_spec = make_gaussian_spec(ctx.baseline_preprocess, 1.5, 4);

alpha_values = 0.50:0.05:2.50;
n_alpha = numel(alpha_values);

% 逐 alpha 值运行，每次 seed_alpha = alpha（无滞回效应，纯逾渗特性）
% connectivity 固定 4（已在 Stage 3 确定）
fprintf('alpha 范围: [%.2f, %.2f], 步长 0.05, 共 %d 点\n', ...
    alpha_values(1), alpha_values(end), n_alpha);
fprintf('connectivity: 4 (固定)\n');
fprintf('seed_alpha: = alpha (无滞回，纯逾渗特性)\n');

per_frame_wide = cell(n_alpha, 1);
for j = 1:n_alpha
    per_frame_wide{j} = struct( ...
        'alpha', alpha_values(j), ...
        'max_component_ratio', nan(ctx.n_frames, 1), ...
        'n_components', nan(ctx.n_frames, 1), ...
        'occupancy', nan(ctx.n_frames, 1), ...
        'mean_component_size', nan(ctx.n_frames, 1), ...
        'susceptibility', nan(ctx.n_frames, 1), ...
        'small_component_fraction', nan(ctx.n_frames, 1));
end

tic;
for k = 1:ctx.n_frames
    raw_U = ctx.raw_U(:, :, k);
    raw_V = ctx.raw_V(:, :, k);
    raw_valid = ctx.raw_valid(:, :, k);

    prep = tblR2.preprocess_structure_velocity( ...
        raw_U, raw_V, raw_valid, ctx.analysis_domain_mask, preprocess_spec);
    u_prep = prep.U;
    struct_mask = prep.output_valid_mask & isfinite(ctx.mean_U(:, :, k));
    u_fluct = u_prep - ctx.mean_U(:, :, k);
    u_fluct(~struct_mask) = NaN;

    for j = 1:n_alpha
        a = alpha_values(j);
        local_opts = struct( ...
            'alpha', a, ...
            'seed_alpha', a, ...    % seed = alpha, no hysteresis
            'connectivity', 4, ...
            'min_pixels', 1, ...
            'min_lsm_delta', inf, ...
            'min_vlsm_delta', inf, ...
            'max_wall_normal_delta', inf, ...
            'max_aspect_ratio', inf, ...
            'reject_trusted_boundary_touching', false, ...
            'max_internal_hole_pixels', 0, ...
            'envelope_closing_radius_cells', 0, ...
            'sign_mode', 'both');
        id = tblR2.identify_structures( ...
            u_fluct, ctx.u_rms, ctx.X, ctx.Y_wall_mm, ctx.delta_grid, ...
            struct_mask, local_opts);
        m = percolation_metrics( ...
            id.positive_mask, id.negative_mask, ...
            struct_mask, 4, height(id.structures));

        f = per_frame_wide{j};
        f.max_component_ratio(k)      = m.max_component_ratio;
        f.n_components(k)             = m.n_components;
        f.occupancy(k)                = m.occupancy;
        f.mean_component_size(k)      = m.mean_component_size;
        f.susceptibility(k)           = m.susceptibility;
        f.small_component_fraction(k) = m.small_component_fraction;
        per_frame_wide{j} = f;
    end

    if mod(k, 50) == 0 || k == ctx.n_frames
        fprintf('[宽扫描] 进度 %d / %d 帧\n', k, ctx.n_frames);
    end
end
elapsed_A = toc;
fprintf('Phase A 完成: %.1f s\n', elapsed_A);

% ---- Bootstrap 稳定区判据 ----
fprintf('\n---- Bootstrap 稳定区分析 ----\n');
curve_wide = zeros(ctx.n_frames, n_alpha);
for j = 1:n_alpha
    curve_wide(:, j) = per_frame_wide{j}.max_component_ratio;
end

bs_wide = bootstrap_stability(curve_wide, struct( ...
    'n_boot', 500, 'ci_level', 0.95, ...
    'max_rel_change', 0.10, 'min_run', 3, ...
    'rng_seed', 20260824));

% 识别转变区（最大簇占比的谷值位置）
median_mcr = bs_wide.median;
[~, valley_idx] = min(median_mcr);
transition_alpha = alpha_values(valley_idx);
fprintf('转变区位置（最大簇占比谷值）: alpha = %.2f\n', transition_alpha);

if bs_wide.stable_found
    stable_alphas = alpha_values(bs_wide.stable_idx);
    recommended_alpha = median(stable_alphas);
    fprintf('Bootstrap 稳定区: alpha ∈ [%.2f, %.2f]\n', ...
        stable_alphas(1), stable_alphas(end));
    fprintf('推荐工作点（稳定区中点）: alpha = %.2f\n', recommended_alpha);
else
    recommended_alpha = NaN;
    fprintf('WARNING: 未找到 bootstrap 稳定区。%s\n', bs_wide.note);
end

% ======== Phase B: seed_alpha 联合标定 ========
fprintf('\n======== Phase B: seed_alpha 联合标定 ========\n');

if ~isnan(recommended_alpha)
    % 在推荐 alpha 附近 ±0.2 范围内，测试不同 seed_alpha 的效果
    alpha_local = max(0.5, recommended_alpha - 0.20) : 0.05 : ...
                  min(2.5, recommended_alpha + 0.20);
    seed_alpha_candidates = recommended_alpha : 0.10 : min(2.5, recommended_alpha + 0.50);

    fprintf('alpha 局部范围: [%.2f, %.2f]\n', alpha_local(1), alpha_local(end));
    fprintf('seed_alpha 候选: %s\n', mat2str(seed_alpha_candidates, 2));

    n_local = numel(alpha_local);
    n_seeds = numel(seed_alpha_candidates);
    seed_results = struct('seed_alpha', {}, 'per_frame', {}, 'stability', {});

    tic;
    for is = 1:n_seeds
        sa = seed_alpha_candidates(is);
        pf = cell(n_local, 1);
        for j = 1:n_local
            pf{j} = struct('max_component_ratio', nan(ctx.n_frames, 1));
        end

        for k = 1:ctx.n_frames
            raw_U = ctx.raw_U(:, :, k);
            raw_V = ctx.raw_V(:, :, k);
            raw_valid = ctx.raw_valid(:, :, k);

            prep = tblR2.preprocess_structure_velocity( ...
                raw_U, raw_V, raw_valid, ctx.analysis_domain_mask, preprocess_spec);
            u_prep = prep.U;
            struct_mask = prep.output_valid_mask & isfinite(ctx.mean_U(:, :, k));
            u_fluct = u_prep - ctx.mean_U(:, :, k);
            u_fluct(~struct_mask) = NaN;

            for j = 1:n_local
                a = alpha_local(j);
                if sa < a, continue; end
                local_opts = struct( ...
                    'alpha', a, 'seed_alpha', sa, ...
                    'connectivity', 4, ...
                    'min_pixels', 1, 'min_lsm_delta', inf, ...
                    'min_vlsm_delta', inf, 'max_wall_normal_delta', inf, ...
                    'max_aspect_ratio', inf, ...
                    'reject_trusted_boundary_touching', false, ...
                    'max_internal_hole_pixels', 0, ...
                    'envelope_closing_radius_cells', 0, ...
                    'sign_mode', 'both');
                id = tblR2.identify_structures( ...
                    u_fluct, ctx.u_rms, ctx.X, ctx.Y_wall_mm, ctx.delta_grid, ...
                    struct_mask, local_opts);
                m = percolation_metrics( ...
                    id.positive_mask, id.negative_mask, ...
                    struct_mask, 4, height(id.structures));
                pf{j}.max_component_ratio(k) = m.max_component_ratio;
            end
        end

        % Bootstrap for this seed_alpha
        curve_seed = zeros(ctx.n_frames, n_local);
        for j = 1:n_local
            curve_seed(:, j) = pf{j}.max_component_ratio;
        end
        bs_seed = bootstrap_stability(curve_seed, struct( ...
            'n_boot', 500, 'ci_level', 0.95, ...
            'max_rel_change', 0.10, 'min_run', 3, ...
            'rng_seed', 20260824));

        seed_results(end + 1) = struct('seed_alpha', sa, ...
            'per_frame', {pf}, 'stability', bs_seed); %#ok<AGROW>

        if bs_seed.stable_found
            sa_stable = alpha_local(bs_seed.stable_idx);
            fprintf('  seed_alpha=%.2f: 稳定区 [%.2f, %.2f], 宽度 %.2f\n', ...
                sa, sa_stable(1), sa_stable(end), sa_stable(end)-sa_stable(1));
        else
            fprintf('  seed_alpha=%.2f: 未找到稳定区\n', sa);
        end
    end
    elapsed_B = toc;
    fprintf('Phase B 完成: %.1f s\n', elapsed_B);

    % 选择最宽稳定区对应的 seed_alpha
    best_width = 0;
    best_seed = recommended_alpha;  % 回退值：seed = alpha
    for is = 1:numel(seed_results)
        if seed_results(is).stability.stable_found
            w = numel(seed_results(is).stability.stable_idx);
            if w > best_width
                best_width = w;
                best_seed = seed_results(is).seed_alpha;
            end
        end
    end
    fprintf('\n推荐 seed_alpha（最宽稳定区）: %.2f\n', best_seed);
else
    seed_results = struct([]);
    best_seed = 0.70;
    fprintf('跳过 Phase B（Phase A 未找到稳定区）\n');
end

% ---- 保存结果 ----
wide_sweep = struct();
wide_sweep.alpha_values = alpha_values;
wide_sweep.per_frame = per_frame_wide;
wide_sweep.bootstrap = bs_wide;
wide_sweep.transition_alpha = transition_alpha;
wide_sweep.recommended_alpha = recommended_alpha;
wide_sweep.recommended_seed_alpha = best_seed;
wide_sweep.seed_results = seed_results;
wide_sweep.connectivity = 4;
wide_sweep.sigma_cells = 1.5;
wide_sweep.n_frames = ctx.n_frames;
wide_sweep.frame_ids = ctx.frame_ids;
wide_sweep.elapsed_phase_A = elapsed_A;

save(fullfile(mat_dir, '09d_percolation_sweep_wide.mat'), 'wide_sweep', '-v7.3');
fprintf('\n结果已保存: 09d_percolation_sweep_wide.mat\n');

% ---- 诊断图 ----
fprintf('\n---- 生成诊断图 ----\n');
fig = figure('Position', [80 80 1200 900], 'Color', 'w', 'Visible', 'off');

subplot(2,2,1); hold on;
plot(alpha_values, bs_wide.median, '-o', 'LineWidth', 1.5, 'MarkerSize', 3);
fill([alpha_values fliplr(alpha_values)], ...
    [bs_wide.ci_lo fliplr(bs_wide.ci_hi)], [0 0.45 0.74], ...
    'FaceAlpha', 0.15, 'EdgeColor', 'none');
if bs_wide.stable_found
    xline(stable_alphas(1), '--r'); xline(stable_alphas(end), '--r');
end
xline(transition_alpha, ':k', 'LineWidth', 1.5);
xlabel('\alpha'); ylabel('A_{max}/\SigmaA');
title('(a) 最大簇占比'); grid on;

subplot(2,2,2); hold on;
med_nc = zeros(1, n_alpha);
for j = 1:n_alpha, med_nc(j) = median(per_frame_wide{j}.n_components, 'omitnan'); end
plot(alpha_values, med_nc, '-o', 'LineWidth', 1.5, 'MarkerSize', 3);
xline(transition_alpha, ':k', 'LineWidth', 1.5);
xlabel('\alpha'); ylabel('N'); title('(b) 连通域数量'); grid on;

subplot(2,2,3); hold on;
med_occ = zeros(1, n_alpha);
for j = 1:n_alpha, med_occ(j) = median(per_frame_wide{j}.occupancy, 'omitnan'); end
plot(alpha_values, med_occ, '-o', 'LineWidth', 1.5, 'MarkerSize', 3);
xline(transition_alpha, ':k', 'LineWidth', 1.5);
xlabel('\alpha'); ylabel('占据率'); title('(c) 占据率'); grid on;

subplot(2,2,4); hold on;
med_sus = zeros(1, n_alpha);
for j = 1:n_alpha, med_sus(j) = median(per_frame_wide{j}.susceptibility, 'omitnan'); end
plot(alpha_values, med_sus, '-o', 'LineWidth', 1.5, 'MarkerSize', 3);
xline(transition_alpha, ':k', 'LineWidth', 1.5);
xlabel('\alpha'); ylabel('\chi'); title('(d) 逾渗敏感度'); grid on;

sgtitle(sprintf('宽扫描逾渗诊断  \\sigma=1.5  conn=4  帧=%d  转变区\\alpha=%.2f  推荐\\alpha=%.2f', ...
    ctx.n_frames, transition_alpha, recommended_alpha), 'FontSize', 11);

png_path = fullfile(fig_dir, '09d_percolation_wide_sweep.png');
try
    exportgraphics(fig, png_path, 'Resolution', 200);
catch
    print(fig, png_path, '-dpng', '-r200');
end
close(fig);
fprintf('诊断图已导出: %s\n', png_path);

% ---- 摘要 ----
fprintf('\n============ 宽扫描结果摘要 ============\n');
fprintf('转变区位置（谷值）: alpha = %.2f\n', transition_alpha);
fprintf('推荐 alpha: %.2f\n', recommended_alpha);
fprintf('推荐 seed_alpha: %.2f\n', best_seed);
fprintf('Bootstrap 稳定区: %s\n', ...
    ternary(bs_wide.stable_found, ...
    sprintf('[%.2f, %.2f]', stable_alphas(1), stable_alphas(end)), '未找到'));
fprintf('=========================================\n');

% ======== Phase C: 流向合并间距扫描 ========
fprintf('\n======== Phase C: merge_gap_cells 扫描 (alpha=0.67, seed=1.5) ========\n');

gap_candidates = [0, 10, 20, 30, 40, 50, 60];
n_gaps = numel(gap_candidates);
dx_mm = median(abs(diff(ctx.X(1, :))), 'omitnan');
dy_mm = median(abs(diff(ctx.Y_wall_mm(:, 1))), 'omitnan');

production_opts = struct( ...
    'alpha', 0.67, 'seed_alpha', 1.5, ...
    'connectivity', 4, 'min_pixels', 3, ...
    'min_lsm_delta', 1.0, 'min_vlsm_delta', 3.0, ...
    'max_wall_normal_delta', inf, 'max_aspect_ratio', inf, ...
    'reject_trusted_boundary_touching', true, ...
    'max_internal_hole_pixels', 64, ...
    'envelope_closing_radius_cells', 2, ...
    'sign_mode', 'both');

gap_results = struct( ...
    'gap_cells', num2cell(gap_candidates), ...
    'vlsm_per_frame', num2cell(nan(1, n_gaps)), ...
    'lsm_per_frame', num2cell(nan(1, n_gaps)), ...
    'structures_per_frame', num2cell(nan(1, n_gaps)), ...
    'max_lx_over_delta', num2cell(nan(1, n_gaps)), ...
    'n_merges_per_frame', num2cell(nan(1, n_gaps)));

tic;
for ig = 1:n_gaps
    gc = gap_candidates(ig);
    m_opts = struct('merge_gap_cells', gc, 'merge_require_y_overlap', true, ...
        'min_lsm_delta', 1.0, 'min_vlsm_delta', 3.0);
    vlsm_count = 0; lsm_count = 0; total_count = 0;
    max_lx = 0; total_merges = 0;

    for k = 1:ctx.n_frames
        raw_U = ctx.raw_U(:, :, k);
        raw_V = ctx.raw_V(:, :, k);
        raw_valid = ctx.raw_valid(:, :, k);

        prep = tblR2.preprocess_structure_velocity( ...
            raw_U, raw_V, raw_valid, ctx.analysis_domain_mask, preprocess_spec);
        struct_mask = prep.output_valid_mask & isfinite(ctx.mean_U(:, :, k));
        u_fluct = prep.U - ctx.mean_U(:, :, k);
        u_fluct(~struct_mask) = NaN;

        id = tblR2.identify_structures( ...
            u_fluct, ctx.u_rms, ctx.X, ctx.Y_wall_mm, ctx.delta_grid, ...
            struct_mask, production_opts);

        if gc > 0 && ~isempty(id.structures) && height(id.structures) > 0
            [id.structures, mlog] = tblR2.vlsm.merge_streamwise_neighbors( ...
                id.structures, id.positive_labels, id.negative_labels, ...
                ctx.X, ctx.Y_wall_mm, ctx.delta_grid, dx_mm, dy_mm, ...
                u_fluct, m_opts);
            total_merges = total_merges + mlog.n_merges;
        end

        if ~isempty(id.structures) && height(id.structures) > 0
            vlsm_count = vlsm_count + sum(id.structures.IsVLSM);
            lsm_count = lsm_count + sum(id.structures.IsLSM);
            total_count = total_count + height(id.structures);
            lx_vals = id.structures.LengthX_over_delta;
            max_lx = max(max_lx, max(lx_vals));
        end
    end

    gap_results(ig).vlsm_per_frame = vlsm_count / ctx.n_frames;
    gap_results(ig).lsm_per_frame = lsm_count / ctx.n_frames;
    gap_results(ig).structures_per_frame = total_count / ctx.n_frames;
    gap_results(ig).max_lx_over_delta = max_lx;
    gap_results(ig).n_merges_per_frame = total_merges / ctx.n_frames;

    fprintf('  gap=%2d cells: VLSM/帧=%.2f, LSM/帧=%.2f, 结构/帧=%.1f, maxLx/δ=%.2f, merges/帧=%.2f\n', ...
        gc, gap_results(ig).vlsm_per_frame, gap_results(ig).lsm_per_frame, ...
        gap_results(ig).structures_per_frame, max_lx, ...
        gap_results(ig).n_merges_per_frame);
end
elapsed_C = toc;
fprintf('Phase C 完成: %.1f s\n', elapsed_C);

wide_sweep.gap_results = gap_results;
wide_sweep.elapsed_phase_C = elapsed_C;
save(fullfile(mat_dir, '09d_percolation_sweep_wide.mat'), 'wide_sweep', '-v7.3');
fprintf('Phase C 结果已追加保存。\n');

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end
