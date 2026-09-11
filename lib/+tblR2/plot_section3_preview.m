function preview = plot_section3_preview(results, cfg, phase_contour)
%PLOT_SECTION3_PREVIEW Actual Section-3 drawing moved without changing formula/style.
% The caller must explicitly prepare phase_contour; no cache/DAT/statistics calls here.
% CLim intentionally retains the original results.phase source even when contour data
% uses PostProc. This existing scientific/display question is not changed by the move.
preview = struct('figures', [], 'errors', struct('job', {}, 'identifier', {}, 'message', {}));
try
    % ---- 公共量准备 ----
    Uinf   = cfg.Uinf;                                  % 来流速度 (m/s)
    delta99 = results.mean_bl.delta99_reference_mm;      % 参考 δ99 (mm, 标量)
    x_vec  = results.statistics.X(1, :);                 % 流向坐标向量 (mm)
    if isfield(results.mean_bl, 'wall_distance_mm') && ...
            ~isempty(results.mean_bl.wall_distance_mm)
        y_vec = results.mean_bl.wall_distance_mm(:, 1);  % 壁面距离 (mm)
    else
        y_vec = results.statistics.Y(:, 1);              % 退化为原始 Y 坐标 (mm)
    end
    y_norm = y_vec / delta99;                            % y/δ99 无量纲法向坐标

    % ---- 范围平均列选取（可由用户配置）----
    x_range_profile = cfg.phase_preview.profile_x_range_mm;  % [x_min x_max] (mm)
    col_mask = (x_vec >= x_range_profile(1)) & (x_vec <= x_range_profile(2));
    n_cols   = sum(col_mask);

    % ---- 三重分解 Reynolds 应力计算 ----
    % 总脉动（来自 Section 2 时均统计）
    total_uu = mean(results.statistics.uu_rey(:, col_mask), 2, 'omitnan');  % [J,1]
    total_vv = mean(results.statistics.vv_rey(:, col_mask), 2, 'omitnan');
    total_uv = mean(results.statistics.uv_rey(:, col_mask), 2, 'omitnan');  % 已含 -<u'v'> 符号

    % 相干分量：<ũ²> = (1/n_bins) * Σ_φ (u_coherent(φ))²
    coh_uu_field = squeeze(mean(results.phase.u_coherent.^2, 1, 'omitnan'));   % [J, I]
    coh_vv_field = squeeze(mean(results.phase.v_coherent.^2, 1, 'omitnan'));
    coh_uv_field = squeeze(-mean(results.phase.coherent_uv, 1, 'omitnan'));    % -<ũṽ>
    coh_uu = mean(coh_uu_field(:, col_mask), 2, 'omitnan');  % [J,1]
    coh_vv = mean(coh_vv_field(:, col_mask), 2, 'omitnan');
    coh_uv = mean(coh_uv_field(:, col_mask), 2, 'omitnan');

    % 随机分量（相位坍缩后的全局统计）
    rand_uu = mean(results.phase.random_global.uu_rey(:, col_mask), 2, 'omitnan');
    rand_vv = mean(results.phase.random_global.vv_rey(:, col_mask), 2, 'omitnan');
    rand_uv = mean(results.phase.random_global.uv_rey(:, col_mask), 2, 'omitnan');

    % ---- 剖面曲线平滑（不改变源数据；只用于显示）----
    % 用 movmean 窗口平滑，保留趋势而滤除逐点噪声；剖面点较少时自动减小窗口。
    smooth_pts = cfg.phase_preview.smooth_points;
    sm_curve = @(v) movmean(v, min(smooth_pts, numel(v)), 'omitnan');

    % marker 显示步长：cfg.phase_preview.marker_stride=1 表示每点都显示，>1 隔 N 点显示。
    ms = max(1, round(cfg.phase_preview.marker_stride));
    mi = 1:ms:numel(y_norm);                            % 显示 marker 的索引
    if numel(mi) < 2, mi = 1:max(1,round(numel(y_norm)/2)):numel(y_norm); end % 兜底：至少 2 个

    % ---- 图1: 流向 Reynolds 正应力 <u'²>/Uinf² ----
    % 方案B：每条曲线用单个 plot，通过 MarkerIndices 稀疏显示标记（marker_stride=1 则全部显示）。
    f1 = figure('Name', 'Section3: streamwise Reynolds stress triple decomposition', ...
        'Position', [100 100 480 440], 'Visible', 'on');
    plot(sm_curve(total_uu / Uinf^2), y_norm, 'k-o', 'MarkerSize', 3, ...
        'MarkerIndices', mi, 'LineWidth', 1.4, 'DisplayName', 'Total'); hold on;
    plot(sm_curve(coh_uu / Uinf^2), y_norm, 'r-s', 'MarkerSize', 3, ...
        'MarkerIndices', mi, 'LineWidth', 1.4, 'DisplayName', 'Coherent');
    plot(sm_curve(rand_uu / Uinf^2), y_norm, 'b-^', 'MarkerSize', 3, ...
        'MarkerIndices', mi, 'LineWidth', 1.4, 'DisplayName', 'Random');
    hold off;
    xlabel('\langle u^{\prime 2} \rangle / U_\infty^2', 'FontSize', 12);
    ylabel('y / \delta_{99}', 'FontSize', 12);
    title(sprintf('Streamwise Reynolds stress (x=%d–%d mm, %d cols)', ...
        x_range_profile(1), x_range_profile(2), n_cols), 'FontSize', 11);
    legend('Location', 'northeast', 'FontSize', 9);
    grid on; set(gca, 'YLim', [0 max(y_norm(isfinite(total_uu)))]);
    set(gca, 'FontSize', 11);

    % ---- 图2: 法向 Reynolds 正应力 <v'²>/Uinf² ----
    f2 = figure('Name', 'Section3: wall-normal Reynolds stress triple decomposition', ...
        'Position', [180 100 480 440], 'Visible', 'on');
    plot(sm_curve(total_vv / Uinf^2), y_norm, 'k-o', 'MarkerSize', 3, ...
        'MarkerIndices', mi, 'LineWidth', 1.4, 'DisplayName', 'Total'); hold on;
    plot(sm_curve(coh_vv / Uinf^2), y_norm, 'r-s', 'MarkerSize', 3, ...
        'MarkerIndices', mi, 'LineWidth', 1.4, 'DisplayName', 'Coherent');
    plot(sm_curve(rand_vv / Uinf^2), y_norm, 'b-^', 'MarkerSize', 3, ...
        'MarkerIndices', mi, 'LineWidth', 1.4, 'DisplayName', 'Random');
    hold off;
    xlabel('\langle v^{\prime 2} \rangle / U_\infty^2', 'FontSize', 12);
    ylabel('y / \delta_{99}', 'FontSize', 12);
    title(sprintf('Wall-normal Reynolds stress (x=%d–%d mm, %d cols)', ...
        x_range_profile(1), x_range_profile(2), n_cols), 'FontSize', 11);
    legend('Location', 'northeast', 'FontSize', 9);
    grid on; set(gca, 'YLim', [0 max(y_norm(isfinite(total_vv)))]);
    set(gca, 'FontSize', 11);

    % ---- 图3: Reynolds 切应力 -<u'v'>/Uinf² ----
    f3 = figure('Name', 'Section3: Reynolds shear stress triple decomposition', ...
        'Position', [260 100 480 440], 'Visible', 'on');
    plot(sm_curve(total_uv / Uinf^2), y_norm, 'k-o', 'MarkerSize', 3, ...
        'MarkerIndices', mi, 'LineWidth', 1.4, 'DisplayName', 'Total'); hold on;
    plot(sm_curve(coh_uv / Uinf^2), y_norm, 'r-s', 'MarkerSize', 3, ...
        'MarkerIndices', mi, 'LineWidth', 1.4, 'DisplayName', 'Coherent');
    plot(sm_curve(rand_uv / Uinf^2), y_norm, 'b-^', 'MarkerSize', 3, ...
        'MarkerIndices', mi, 'LineWidth', 1.4, 'DisplayName', 'Random');
    hold off;
    xlabel('-\langle u^{\prime}v^{\prime} \rangle / U_\infty^2', 'FontSize', 12);
    ylabel('y / \delta_{99}', 'FontSize', 12);
    title(sprintf('Reynolds shear stress (x=%d–%d mm, %d cols)', ...
        x_range_profile(1), x_range_profile(2), n_cols), 'FontSize', 11);
    legend('Location', 'northeast', 'FontSize', 9);
    grid on; set(gca, 'YLim', [0 max(y_norm(isfinite(total_uv)))]);
    set(gca, 'FontSize', 11);

    % ---- 图4: 相位平均流向速度脉动云图（12相位，6行×2列）----
    % 绘制的流场由 cfg.phase_preview.contour_x_range_mm 限定（默认截掉激励器薄膜区）。
    cx_range = cfg.phase_preview.contour_x_range_mm;     % [x_min x_max] (mm)
    cx_mask  = (x_vec >= cx_range(1)) & (x_vec <= cx_range(2));
    cx_vec   = x_vec(cx_mask);                           % 截取后的流向坐标 (mm)
    % 相位平均处减去时均值，得到相位平均脉动（coherent 脉动云图）。
    Umean = results.statistics.Uavex;                    % [J, I] 时均流向速度
    Vmean = results.statistics.Vavex;                    % [J, I] 时均法向速度

    phase_bins_select = 1:2:23;                          % 24 bins → 取奇数 bin = 0°,30°,…,330°
    n_phase_show = numel(phase_bins_select);             % = 12
    bin_centers_deg = (phase_bins_select - 1) * (360 / cfg.phase.n_bins); % 各 bin 中心角度
    % 子图排列：左列从上到下 = 前6个相位，右列从上到下 = 后6个相位
    % tiledlayout(6,2) 默认 rowmajor: tile 1=(r1,c1), tile 2=(r1,c2), ...
    tile_order = [1, 3, 5, 7, 9, 11, 2, 4, 6, 8, 10, 12]; % 相位→tile 映射

    % 所有子图共用同一 colorbar 和 color limit（发散色标，零点居中）。
    % 先收集所有 12 个相位的脉动值，计算统一的对称 color limit。
    U_fluct_all = [];
    V_fluct_all = [];
    for k = 1:n_phase_show
        uf = squeeze(results.phase.U_phase(phase_bins_select(k), :, :)) - Umean;
        vf = squeeze(results.phase.V_phase(phase_bins_select(k), :, :)) - Vmean;
        uf = uf(:, cx_mask); vf = vf(:, cx_mask);
        U_fluct_all = [U_fluct_all; uf(:)];
        V_fluct_all = [V_fluct_all; vf(:)];
    end
    % 用稳健分位数求对称色限，避免个别离散点拉垮色标。
    U_clim = max(abs(quantile(U_fluct_all, [0.02 0.98])));   % 对称限 = ±max(|分位|)
    V_clim = max(abs(quantile(V_fluct_all, [0.02 0.98])));
    cmap_div = tblR2.viz.resolve_case_colormap('ocean', 256);  % 红-白-蓝发散色标

    % 采用固定像素几何的紧凑 6×2 布局，避免 tiledlayout 在等比例坐标下
    % 产生过大的行间空白，并将总标题放在独立的顶部区域。
    [f4, f5] = tblR2.plot_phase_averaged_maps(x_vec, y_vec, phase_contour, ...
        Umean, Vmean, cx_mask, phase_bins_select, bin_centers_deg, cmap_div, ...
        U_clim, V_clim, 'on');

    preview.figures = [f1 f2 f3 f4 f5];
catch problem
    preview.errors(end+1) = struct('job', 'section3_preview', ...
        'identifier', problem.identifier, 'message', problem.message);
    % Existing open figures remain open; an empty figures list on failure is not
    % a complete export/preview claim. The caller reports the error list.
end
end
