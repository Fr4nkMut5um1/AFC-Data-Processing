function output = plot_core_products(job, results, cfg, paths, mode)
%PLOT_CORE_PRODUCTS Core figure rendering for the compact r2 case.
% 所有图形均为 MATLAB 原生 graphics（plot/contourf/semilogx/imagesc 等），
% 无自研渲染后端。大样式（面板结构、标题/标签/图例/注记规范）对应 r1 参考
% 实现（+tbl/+periodic/plot_products.m）；具体数值参数由主脚本决定：
%   - 参数族按 Section 分组：cfg.figures.section<N>.window_size /
%     colormaps / color_limits / contour_levels（N=1..9，见主脚本 Section 0），
%     本文件通过 tblR2.figures_family / figures_global 查找，兼容旧式平坦命名；
%   - 全局导出参数：cfg.figures.section9.{formats, export_dpi,
%     robust_color_quantiles, fov_aspect_ratio, jobs, contour_levels};
%   - 深度样式：cfg.figures.job_style.<job> = struct（平铺、按图/面板序号，
%     字段：layout_titles / panel_titles / xlabels / ylabels / rlabels /
%     series / legends / annotations / cloud_backgrounds / preview_titles），
%     字段缺省 = r1 现值（见下方 default_style）；写错字段名/类型/枚举值
%     一律报错停止（不静默回退），用法见主脚本 Section 0 注释目录。
% 单入口：tblR2.plot_core_products(job, results, cfg, paths, mode)，一次
% 渲染一个 job；preview 返回可见图窗句柄，export 返回文件路径清单。

if nargin < 5 || isempty(mode); mode = 'export'; end
if strcmp(char(job), 'transport') && isfield(results, 'transport') && ...
        ~isempty(results.transport) && isfield(results.transport, 'schema_version') && ...
        results.transport.schema_version >= 2
    transport_paths = paths;
    if isfield(results.transport, 'output_dir')
        transport_paths = tblR2.build_paths(results.transport.output_dir);
    end
    output = tblR2.transport_figures(results.transport, cfg, transport_paths, mode);
    return;
end
mode = lower(char(mode));
if ~ismember(mode, {'export', 'preview'})
    error('tblR2:plot_core_products:InvalidMode', ...
        'mode 必须是 export 或 preview。');
end

files = cell(0, 1);
figures = gobjects(0, 1);
switch char(job)
    case 'mean_turbulence'; render_mean_turbulence();
    case 'mean_profiles'; render_mean_profiles();
    case 'loglaw'; render_loglaw();
    case 'loglaw_diagnostic'; render_loglaw_diagnostic();
    case 'modern_clauser'; render_modern_clauser();
    case 'friction'; render_friction();
    case 'cache_raw'; render_cache_raw();
    case 'instantaneous_fields'; render_instantaneous_fields();
    case 'instantaneous_vortex'; render_instantaneous_vortex();
    case 'structures'; render_structures();
    case 'transport'; render_transport();
    case 'temporal_spectra'; render_temporal_spectra();
    case 'spatial_spectra'; render_spatial_spectra();
    case 'pod'; render_pod();
    case 'dmd'; render_dmd();
    case 'spod'; render_spod();
    case 'correlations'; render_correlations();
    case 'harmonics'; render_harmonics();
    case 'phase_triple'; render_phase_triple();
    otherwise
        error('tblR2:plot_core_products:UnknownJob', ...
            '未知的图形任务：%s。', char(job));
end
output = struct('files', {files}, 'figures', figures, ...
    'job', char(job), 'role', source_role_for_job(char(job)));

% =========================================================================
% Section 2 图形（六个 job，格式参数对齐 r1）
% =========================================================================

% -------------------- mean_turbulence：三组二联无量纲云图 --------------------
    function render_mean_turbulence()
        if ~isfield(results, 'statistics') || isempty(results.statistics)
            return;
        end
        S = results.statistics;
        Uinf = resolve_uinf();
        Uinf2 = Uinf * Uinf;
        data = { {S.Uavex ./ Uinf, 'mean_u'}, ...
            {S.Vavex ./ Uinf, 'mean_v'}, ...
            {S.u_rms ./ Uinf, 'u_rms'}, ...
            {S.v_rms ./ Uinf, 'v_rms'}, ...
            {S.uv_rey ./ Uinf2, 'negative_uv'}, ...
            {S.TKE, 'tke'}};
        style = resolve_style(job);
        ut = tokens(struct('Uinf', sprintf('%.1f', Uinf)));
        for ig = 1:numel(style.figures)
            fig_spec = style.figures{ig};
            f = new_fig('mean_turbulence', [1450 760]);
            layout = tiledlayout(f, 2, 1, ...
                'TileSpacing', 'compact', 'Padding', 'loose');
            for ip = 1:2
                row = data{(ig - 1) * 2 + ip};
                field_tile(nexttile(layout), row{1}, ...
                    fig_spec.panels{ip}, row{2});
            end
            title(layout, expand_title(fig_spec.layout_title, ut), ...
                'Interpreter', 'none');
            save_fig(f, fig_spec.stem);
        end
    end

% -------------------- mean_profiles：范围平均四联剖面 --------------------
    function render_mean_profiles()
        if ~isfield(results, 'statistics') || isempty(results.statistics)
            return;
        end
        if ~isfield(cfg, 'profile') || isempty(cfg.profile); return; end
        S = results.statistics;
        Uinf = resolve_uinf();
        profile_bl = [];
        if isfield(results, 'mean_bl'); profile_bl = results.mean_bl; end
        [y_mm, U, u_rms, v_rms, uv_rey, x_range, n_columns] = ...
            tblR2.range_average_profiles(S, profile_bl, cfg);
        series_data = {U, u_rms ./ Uinf, v_rms ./ Uinf, ...
            -uv_rey ./ (Uinf .* Uinf)};
        style = resolve_style(job);
        fig_spec = style.figures{1};
        f = new_fig('mean_profiles', [1500 700]);
        layout = tiledlayout(f, 2, 2, ...
            'TileSpacing', 'compact', 'Padding', 'loose');
        for ip = 1:4
            ax = nexttile(layout);
            hold(ax, 'on');
            draw_curve(ax, series_data{ip}, y_mm, ...
                fig_spec.panels{ip}.series(1));
            grid(ax, 'on');
            set(ax, 'YDir', 'normal');
            xlabel(ax, fig_spec.panels{ip}.xlabel, 'Interpreter', 'tex');
            ylabel(ax, fig_spec.panels{ip}.ylabel);
            title(ax, fig_spec.panels{ip}.title, 'Interpreter', 'tex');
        end
        title(layout, expand_title(fig_spec.layout_title, tokens(struct( ...
            'x1', sprintf('%.1f', x_range(1)), ...
            'x2', sprintf('%.1f', x_range(2)), ...
            'ncol', sprintf('%d', n_columns)))), 'Interpreter', 'none');
        save_fig(f, fig_spec.stem);
    end

% -------------------- loglaw：Cf chart + 壁面单位拟合 --------------------
    function render_loglaw()
        if ~isfield(results, 'mean_bl') || isempty(results.mean_bl) || ...
                ~isfield(results.mean_bl, 'loglaw') || ...
                isempty(results.mean_bl.loglaw)
            return;
        end
        LF = results.mean_bl.loglaw;
        chart = tblR2.bl.load_cf_chart();
        style = resolve_style(job);
        fig_spec = style.figures{1};
        if strcmp(mode, 'preview')
            for ip = 1:2
                f = new_fig('loglaw', [1250 560]);
                ax = axes(f);
                if ip == 1
                    draw_cf_chart_axes(ax, LF, chart, fig_spec.panels{1});
                else
                    draw_loglaw_axes(ax, LF, fig_spec.panels{2});
                end
                title(ax, expand_title(style.preview_titles{ip}, ...
                    tokens(struct('Uinf', sprintf('%.1f', LF.Uinf_used)))), ...
                    'Interpreter', 'none');
                if ip == 1
                    save_fig(f, '06a_cf_chart');
                else
                    save_fig(f, '06b_loglaw_fit');
                end
            end
        else
            f = new_fig('loglaw', [1250 560]);
            layout = tiledlayout(f, 1, 2, ...
                'TileSpacing', 'compact', 'Padding', 'loose');
            draw_cf_chart_axes(nexttile(layout), LF, chart, ...
                fig_spec.panels{1});
            draw_loglaw_axes(nexttile(layout), LF, fig_spec.panels{2});
            title(layout, expand_title(fig_spec.layout_title, ...
                tokens(struct('Uinf', sprintf('%.1f', LF.Uinf_used)))), ...
                'Interpreter', 'none');
            save_fig(f, fig_spec.stem);
        end
    end

    function draw_cf_chart_axes(ax, LF, chart, panel_spec)
        hold(ax, 'on');
        h_first = gobjects(1);
        for k = 1:chart.n_curves
            h_ref = semilogx(ax, chart.x_cols{k}, chart.y_cols{k}, '-', ...
                'Color', [0.5 0.5 0.5], 'LineWidth', 0.5);
            if k == 1
                h_first = h_ref;
            else
                h_ref.HandleVisibility = 'off';
            end
        end
        n_points = numel(LF.u_valid);
        y_shifted_m = (((1:n_points)' - 1 + LF.n_skip) * LF.h_mm + ...
            LF.dy_opt) * 1e-3;
        x_meas = y_shifted_m * LF.Uinf_used / LF.nu;
        y_meas = LF.u_valid / LF.Uinf_used;
        s_meas = panel_spec.series(1);
        sl_meas = line_spec(s_meas);
        h_measured = semilogx(ax, x_meas, y_meas, sl_meas{:}, ...
            'DisplayName', 'measured profile');
        legend_handles = [h_first h_measured];
        legend_entries = {'Cf chart family', 'measured profile'};
        if isfinite(LF.Cf_opt)
            xq = logspace(log10(max(1, min(x_meas))), ...
                log10(max(x_meas)), 300);
            sl_opt = line_spec(panel_spec.series(2));
            try
                yq = tblR2.bl.interp_cf_curve(LF.Cf_opt, xq, chart);
                h_opt = semilogx(ax, xq, yq, sl_opt{:}, 'DisplayName', '');
            catch
                [~, idx] = min(abs(chart.Cf_values - LF.Cf_opt));
                h_opt = semilogx(ax, chart.x_cols{idx}, ...
                    chart.y_cols{idx}, sl_opt{:}, 'DisplayName', '');
            end
            legend_handles(end + 1) = h_opt;
            if strcmp(LF.mode, 'manual_utau')
                legend_entries{end + 1} = sprintf( ...
                    'manual u_\tau, derived C_f=%.4g', LF.Cf);
            else
                legend_entries{end + 1} = sprintf( ...
                    'optimum Cfnum=%.2f', LF.Cfnum_opt);
            end
        end
        xlim(ax, [100 1e6]);
        ylim(ax, [0 1.05]);
        xlabel(ax, panel_spec.xlabel, 'Interpreter', 'tex');
        ylabel(ax, panel_spec.ylabel, 'Interpreter', 'tex');
        grid(ax, 'on');
        set(ax, 'XScale', 'log');
        legend(ax, legend_handles, legend_entries, ...
            'Location', 'southeast', 'Box', 'on');
        add_annotation(ax, panel_spec.annotation, tokens(struct( ...
            'cf', sprintf('%.4e', LF.Cf))));
    end

    function draw_loglaw_axes(ax, LF, panel_spec)
        rmse_range = LF.rmse_yplus_range;
        s = panel_spec.series;
        sl1 = line_spec(s(1));
        sl2 = line_spec(s(2));
        sl3 = line_spec(s(3));
        sl4 = line_spec(s(4));
        semilogx(ax, LF.y_plus, LF.u_plus, sl1{:}, ...
            'DisplayName', s(1).display_name);
        hold(ax, 'on');
        yy = logspace(0, log10(2500), 300);
        uu = (1 / LF.kappa) * log(yy) + LF.B;
        rmse_window = yy >= rmse_range(1) & yy <= rmse_range(2);
        extension_window = yy > 10 & ~rmse_window;
        semilogx(ax, yy(yy <= 10), yy(yy <= 10), sl2{:}, ...
            'DisplayName', s(2).display_name);
        semilogx(ax, yy(rmse_window), uu(rmse_window), ...
            sl3{:}, 'DisplayName', s(3).display_name);
        uu_extension = uu;
        uu_extension(~extension_window) = NaN;
        semilogx(ax, yy, uu_extension, sl4{:}, ...
            'DisplayName', s(4).display_name);
        xlim(ax, [5 2500]);
        ylim(ax, [1 28]);
        xlabel(ax, panel_spec.xlabel, 'Interpreter', 'tex');
        ylabel(ax, panel_spec.ylabel, 'Interpreter', 'tex');
        grid(ax, 'on');
        set(ax, 'XScale', 'log');
        legend(ax, 'Location', 'southeast', 'Box', 'on');
        add_annotation(ax, panel_spec.annotation, tokens(struct( ...
            'utau', sprintf('%.4f', LF.u_tau), ...
            'kappa', sprintf('%.3f', LF.kappa), ...
            'b', sprintf('%.2f', LF.B), ...
            'rmse', sprintf('%.3f', LF.RMSE), ...
            'r1', sprintf('%.0f', rmse_range(1)), ...
            'r2', sprintf('%.0f', rmse_range(2)), ...
            'nskip', sprintf('%d', LF.n_skip))));
    end

% -------------------- loglaw_diagnostic：Xi 参考诊断 --------------------
    function render_loglaw_diagnostic()
        if ~isfield(results, 'mean_bl') || isempty(results.mean_bl) || ...
                ~isfield(results.mean_bl, 'loglaw') || ...
                isempty(results.mean_bl.loglaw)
            return;
        end
        D = tblR2.bl.loglaw_diagnostic_function(results.mean_bl.loglaw);
        style = resolve_style(job);
        fig_spec = style.figures{1};
        panel_spec = fig_spec.panels{1};
        f = new_fig('loglaw_diagnostic', [1250 560]);
        ax = axes(f);
        hold(ax, 'on');
        draw_series(ax, D.y_plus, D.Xi_5, panel_spec, 1);
        draw_series(ax, D.y_plus, D.Xi_7, panel_spec, 2);
        draw_series(ax, D.target, [], panel_spec, 3);
        finite_x = D.y_plus(isfinite(D.y_plus));
        if ~isempty(finite_x)
            xlim(ax, [max(1, min(finite_x)) max(finite_x)]);
        end
        finite_xi = [D.Xi_5(isfinite(D.Xi_5)); D.Xi_7(isfinite(D.Xi_7))];
        y_low = 0;
        y_high = max(3, 1.5 * D.target);
        if ~isempty(finite_xi)
            y_low = min(y_low, min(finite_xi));
            y_high = max(y_high, 1.1 * max(finite_xi));
        end
        ylim(ax, [y_low y_high]);
        set(ax, 'XScale', 'log');
        grid(ax, 'on');
        xlabel(ax, panel_spec.xlabel, 'Interpreter', 'tex');
        ylabel(ax, panel_spec.ylabel, 'Interpreter', 'tex');
        title(ax, expand_title(fig_spec.layout_title, ...
            tokens(struct('name', case_name()))), 'Interpreter', 'none');
        legend(ax, 'Location', panel_spec.legend.location, ...
            'Box', onoff(panel_spec.legend.box));
        add_annotation(ax, panel_spec.annotation, tokens(struct( ...
            'target', sprintf('%.3f', D.target))));
        save_fig(f, fig_spec.stem);
    end

% -------------------- modern_clauser：选项 B 复合剖面 --------------------
    function render_modern_clauser()
        if ~isfield(results, 'mean_bl') || isempty(results.mean_bl) || ...
                ~isfield(results.mean_bl, 'modern_clauser') || ...
                isempty(results.mean_bl.modern_clauser)
            return;
        end
        B = results.mean_bl.modern_clauser;
        if ~isfield(B, 'enabled') || ~B.enabled; return; end
        style = resolve_style(job);
        fig_spec = style.figures{1};
        f = new_fig('modern_clauser', [1250 560]);
        layout = tiledlayout(f, 1, 2, ...
            'TileSpacing', 'compact', 'Padding', 'compact');
        ax = nexttile(layout);
        hold(ax, 'on');
        draw_series(ax, B.u_mps, B.y_mm, fig_spec.panels{1}, 1);
        if isfield(B, 'excluded_nearwall') && ...
                ~isempty(B.excluded_nearwall.u_mps)
            draw_series(ax, B.excluded_nearwall.u_mps, ...
                B.excluded_nearwall.y_mm, fig_spec.panels{1}, 2);
        end
        draw_series(ax, B.u_model_mps, B.y_mm, fig_spec.panels{1}, 3);
        grid(ax, 'on'); set(ax, 'YDir', 'normal');
        xlabel(ax, fig_spec.panels{1}.xlabel);
        ylabel(ax, fig_spec.panels{1}.ylabel);
        legend(ax, 'Location', 'southeast', 'Box', 'on');
        title(ax, fig_spec.panels{1}.title, 'Interpreter', 'none');

        ax = nexttile(layout);
        hold(ax, 'on');
        draw_series(ax, B.y_plus, B.u_plus_exp, fig_spec.panels{2}, 1);
        if isfield(B, 'excluded_nearwall') && ...
                ~isempty(B.excluded_nearwall.u_plus_exp)
            draw_series(ax, B.excluded_nearwall.y_plus, ...
                B.excluded_nearwall.u_plus_exp, fig_spec.panels{2}, 2);
        end
        draw_series(ax, B.y_plus, B.u_plus_model, ...
            fig_spec.panels{2}, 3);
        grid(ax, 'on');
        set(ax, 'XScale', 'log');
        xlabel(ax, fig_spec.panels{2}.xlabel, 'Interpreter', 'tex');
        ylabel(ax, fig_spec.panels{2}.ylabel, 'Interpreter', 'tex');
        legend(ax, 'Location', 'southeast', 'Box', 'on');
        title(ax, fig_spec.panels{2}.title, 'Interpreter', 'none');
        title(layout, expand_title(fig_spec.layout_title, ...
            tokens(struct('name', case_name()))), 'Interpreter', 'none');
        extra_lines = {};
        if isfield(B, 'warning') && ~isempty(B.warning)
            extra_lines = {sprintf('diagnostic: %s', B.warning)};
        end
        tok = struct('utau', sprintf('%.4f', B.u_tau), ...
            'cf', sprintf('%.4e', B.Cf), ...
            'pi', sprintf('%.3f', B.Pi), ...
            'delta', sprintf('%.2f', B.delta_mm), ...
            'e1', sprintf('%.4g', B.objective.value), ...
            'kappa', sprintf('%.3f', B.kappa), ...
            'b', sprintf('%.2f', B.B), ...
            'dyh', sprintf('%.2f', B.dy_h), ...
            'nskip', sprintf('%d', B.n_skip));
        add_annotation(ax, fig_spec.panels{2}.annotation, tok, extra_lines);
        save_fig(f, fig_spec.stem);
    end

% -------------------- friction：边界层厚度与摩阻 --------------------
    function render_friction()
        if ~isfield(results, 'mean_bl') || isempty(results.mean_bl)
            return;
        end
        M = results.mean_bl;
        style = resolve_style(job);
        fig_spec = style.figures{1};
        f = new_fig('friction', [1250 560]);
        layout = tiledlayout(f, 1, 2, ...
            'TileSpacing', 'compact', 'Padding', 'compact');
        ax = nexttile(layout);
        hold(ax, 'on');
        series = fig_spec.panels{1}.series;
        draw_curve(ax, M.boundary_layer.x, M.boundary_layer.delta99, ...
            series(1));
        draw_curve(ax, M.boundary_layer.x, M.boundary_layer.delta_star, ...
            series(2));
        draw_curve(ax, M.boundary_layer.x, M.boundary_layer.theta, ...
            series(3));
        grid(ax, 'on');
        xlabel(ax, fig_spec.panels{1}.xlabel);
        ylabel(ax, fig_spec.panels{1}.ylabel);
        legend(ax, 'Location', 'best');
        ax = nexttile(layout);
        hold(ax, 'on');
        series = fig_spec.panels{2}.series;
        draw_curve(ax, M.drag.primary.local.x, M.drag.primary.local.Cf, ...
            series(1));
        has_option_b = isfield(M, 'modern_clauser') && ...
            isfield(M.modern_clauser, 'enabled') && ...
            M.modern_clauser.enabled && isfinite(M.modern_clauser.Cf);
        draw_hline(ax, M.loglaw.Cf, series(2));
        if has_option_b
            draw_hline(ax, M.modern_clauser.Cf, series(3));
        end
        grid(ax, 'on');
        xlabel(ax, fig_spec.panels{2}.xlabel);
        ylabel(ax, fig_spec.panels{2}.ylabel);
        legend(ax, 'Location', 'best');
        title(layout, expand_title(fig_spec.layout_title, ...
            tokens(struct('name', case_name()))), 'Interpreter', 'none');
        save_fig(f, fig_spec.stem);
    end

% =========================================================================
% Section 1/4-8 图形（cache_raw、瞬时、结构、输运、谱、模态、相关、谐波）
% =========================================================================

% -------------------- cache_raw：原始缓存帧三面板 --------------------
    function render_cache_raw()
        if ~isfield(paths, 'sequence_cache') || ~isfile(paths.sequence_cache)
            return;
        end
        frame_id = 1;
        if isfield(cfg, 'preview') && isfield(cfg.preview, 'cache_frame_id')
            frame_id = cfg.preview.cache_frame_id;
        end
        C = matfile(paths.sequence_cache);
        X = double(C.X);
        Y = double(C.Y);
        chunk = tblR2.read_cache_chunk(paths.sequence_cache, frame_id, ...
            1:size(X, 1), 1:size(X, 2), 'raw', [], []);
        style = resolve_style(job);
        fig_spec = style.figures{1};
        f = new_fig('cache_raw', [820 410]);
        layout = tiledlayout(f, 3, 1, ...
            'TileSpacing', 'compact', 'Padding', 'compact');
        Y_disp = cache_display_y(Y);
        field_tile(nexttile(layout), squeeze(chunk.U(1, :, :)), ...
            fig_spec.panels{1}, 'cache_u_raw', X(1, :), Y_disp(:, 1));
        field_tile(nexttile(layout), squeeze(chunk.V(1, :, :)), ...
            fig_spec.panels{2}, 'cache_v_raw', X(1, :), Y_disp(:, 1));
        field_tile(nexttile(layout), ...
            double(squeeze(chunk.sampleValid(1, :, :))), ...
            fig_spec.panels{3}, 'cache_valid_mask', X(1, :), Y_disp(:, 1));
        title(layout, expand_title(fig_spec.layout_title, ...
            tokens(struct('frame', sprintf('%d', frame_id)))), ...
            'Interpreter', 'none');
        save_fig(f, sprintf('01_cache_raw_frame_%04d', frame_id));
    end

% -------------------- instantaneous_fields：瞬时 u/u′ 二联 --------------------
    function render_instantaneous_fields()
        if ~has('structures') || ...
                isempty(results.structures.instantaneous); return; end
        style = resolve_style(job);
        items = results.structures.instantaneous;
        for ii = 1:numel(items)
            item = items(ii);
            fig_spec = style.figures{1};
            f = new_fig('instantaneous_fields', [900 900]);
            layout = tiledlayout(f, 2, 1, ...
                'TileSpacing', 'compact', 'Padding', 'compact');
            ax = field_tile(nexttile(layout), item.U_raw, ...
                fig_spec.panels{1}, 'u_raw', [], []);
            overlay_large_scales(ax, item.structures_total);
            ax = field_tile(nexttile(layout), item.u_prime, ...
                fig_spec.panels{2}, 'u_prime', [], []);
            overlay_large_scales(ax, item.structures_total);
            title(layout, expand_title(fig_spec.layout_title, ...
                tokens(struct('frame', sprintf('%d', item.frame_id)))), ...
                'Interpreter', 'none');
            save_fig(f, sprintf('03_instantaneous_u_uprime_frame_%04d', ...
                item.frame_id));
        end
    end

% -------------------- instantaneous_vortex：平面判据 2×2 --------------------
    function render_instantaneous_vortex()
        if ~has('structures') || ...
                isempty(results.structures.instantaneous); return; end
        items = results.structures.instantaneous;
        style = resolve_style(job);
        for ii = 1:numel(items)
            item = items(ii);
            if ~isfield(item, 'planar_criteria'); continue; end
            C = item.planar_criteria;
            fig_spec = style.figures{1};
            f = new_fig('instantaneous_planar', [1300 400]);
            layout = tiledlayout(f, 2, 2, ...
                'TileSpacing', 'compact', 'Padding', 'compact');
            field_tile(nexttile(layout), C.omega_z, fig_spec.panels{1}, ...
                'omega_z', [], []);
            field_tile(nexttile(layout), C.Q_planar, fig_spec.panels{2}, ...
                'q_planar', [], []);
            field_tile(nexttile(layout), C.lambda2_planar, ...
                fig_spec.panels{3}, 'lambda2_planar', [], []);
            field_tile(nexttile(layout), C.lambda_ci, ...
                fig_spec.panels{4}, 'lambda_ci', [], []);
            title(layout, expand_title(fig_spec.layout_title, ...
                tokens(struct('frame', sprintf('%d', item.frame_id)))), ...
                'Interpreter', 'none');
            save_fig(f, sprintf('10_instantaneous_vortex_frame_%04d', ...
                item.frame_id));
        end
    end

% -------------------- structures：结构识别 2×2 --------------------
    function render_structures()
        if ~has('structures') || ...
                isempty(results.structures.instantaneous); return; end
        items = results.structures.instantaneous;
        style = resolve_style(job);
        S = results.statistics;
        y_mm = results.mean_bl.wall_distance_mm;
        for ii = 1:numel(items)
            item = items(ii);
            fig_spec = style.figures{1};
            f = new_fig('structures', [1800 560]);
            layout = tiledlayout(f, 2, 2, ...
                'TileSpacing', 'compact', 'Padding', 'compact');
            raw_normalized = double(item.u_total) ./ S.u_rms;
            if isfield(item, 'preprocessing_total') && ...
                    isfield(item.preprocessing_total, 'input_valid_mask')
                raw_normalized(~item.preprocessing_total.input_valid_mask) = NaN;
            end
            ax = field_tile(nexttile(layout), raw_normalized, ...
                fig_spec.panels{1}, 'structure_normalized', [], []);
            overlay_large_scales(ax, item.structures_total);
            ax = field_tile(nexttile(layout), ...
                item.structures_total.normalized_field, ...
                fig_spec.panels{2}, 'structure_normalized', [], []);
            overlay_large_scales(ax, item.structures_total);
            st = item.structures_total;
            if isfield(st, 'positive_mask') && isfield(st, 'negative_mask')
                event_sign = double(st.positive_mask) - double(st.negative_mask);
                event_sign(~st.analysis_mask) = NaN;
                ax = nexttile(layout);
                draw_events(ax, S.X(1, :), y_mm(:, 1), event_sign, ...
                    fig_spec.panels{3});
            end
            if isfield(item, 'preprocessing_total') && ...
                    isfield(item.preprocessing_total, 'output_valid_mask')
                quality_code = nan(size(raw_normalized));
                quality_code(item.preprocessing_total.output_valid_mask) = 1;
                ax = nexttile(layout);
                draw_quality(ax, S.X(1, :), y_mm(:, 1), quality_code, ...
                    fig_spec.panels{4});
            end
            n_lsm = 0;
            if isfield(st, 'structures') && ...
                    ismember('IsLSM', st.structures.Properties.VariableNames)
                n_lsm = nnz(st.structures.IsLSM);
            end
            title(layout, expand_title(fig_spec.layout_title, ...
                tokens(struct('frame', sprintf('%d', item.frame_id), ...
                'nlsm', sprintf('%d', n_lsm)))), 'Interpreter', 'none');
            save_fig(f, sprintf('09_structures_frame_%04d', item.frame_id));
        end
    end

% -------------------- transport：输运 2×2 --------------------
    function render_transport()
        if ~has('transport') || ~isfield(results.transport, 'total'); return; end
        T = results.transport.total;
        S = results.statistics;
        y_mm = results.mean_bl.wall_distance_mm;
        style = resolve_style(job);
        fig_spec = style.figures{1};
        f = new_fig('transport', [1450 420]);
        layout = tiledlayout(f, 2, 2, ...
            'TileSpacing', 'compact', 'Padding', 'compact');
        field_tile(nexttile(layout), T.negative_uv, fig_spec.panels{1}, ...
            'transport_negative_uv', S.X(1, :), y_mm(:, 1));
        field_tile(nexttile(layout), T.production_primary_fd, ...
            fig_spec.panels{2}, 'production_fd', S.X(1, :), y_mm(:, 1));
        if isfield(T, 'production_sensitivity_rbf')
            field_tile(nexttile(layout), T.production_sensitivity_rbf, ...
                fig_spec.panels{3}, 'production_rbf', S.X(1, :), y_mm(:, 1));
        else
            nexttile(layout);
        end
        info_ax = nexttile(layout);
        axis(info_ax, 'off');
        text(info_ax, 0.02, 0.55, ...
            {expand_title(fig_spec.panels{4}.title, ...
            tokens(struct('name', case_name()))), ...
            'planar transport terms [PostProc; raw mean normalization]', ...
            transport_display_note()}, 'FontSize', 12, ...
            'FontWeight', 'bold', 'Interpreter', 'none', ...
            'VerticalAlignment', 'middle');
        title(layout, expand_title(fig_spec.layout_title, ...
            tokens(struct('name', case_name()))), 'Interpreter', 'none');
        save_fig(f, fig_spec.stem);
    end

    function note = transport_display_note()
        production_limits = resolve_limits([], 'production_fd');
        if isempty(production_limits)
            note = 'production colors use automatic display limits';
        else
            note = sprintf(['production robust CLim [%.3g, %.3g] m^2/s^3; ' ...
                'raw extrema in MAT'], production_limits(1), ...
                production_limits(2));
        end
    end

% -------------------- temporal_spectra：时域谱两张单图 --------------------
    function render_temporal_spectra()
        if ~has('temporal'); return; end
        style = resolve_style(job);
        names = fieldnames(results.temporal);
        for k = 1:numel(names)
            V = results.temporal.(names{k});
            if isempty(V); continue; end
            fig_spec = style.figures{1};
            f = new_fig('temporal_psd', [1250 570]);
            layout = tiledlayout(f, 1, 1, ...
                'TileSpacing', 'compact', 'Padding', 'compact');
            ax = nexttile(layout);
            phi_map = V.phi_uu_mean_across_x;
            phi_map(~isfinite(phi_map)) = NaN;
            draw_cloud(ax, V.frequency_hz, V.y_plus, phi_map, ...
                fig_spec.panels{1}, 'temporal_psd');
            set(ax, 'XScale', 'log', 'YScale', 'log', 'YDir', 'normal');
            cb = colorbar(ax);
            cb.Label.String = '\Phi_{uu}(f) [(m/s)^2/Hz]';
            title(ax, {expand_title(fig_spec.panels{1}.title, ...
                tokens(struct('branch', names{k}))), ...
                expand_title(fig_spec.layout_title, ...
                tokens(struct('branch', names{k})))}, ...
                'Interpreter', 'none');
            save_fig(f, ['05_basic_PSD_' names{k}]);

            fig_spec = style.figures{2};
            f = new_fig('temporal_premultiplied', [900 650]);
            ax = axes(f);
            premult_map = V.premultiplied_phi_over_lambda;
            premult_map(~isfinite(premult_map)) = NaN;
            draw_cloud(ax, V.lambda_x_plus, V.y_plus, premult_map, ...
                fig_spec.panels{1}, 'temporal_premultiplied');
            set(ax, 'XScale', 'log', 'YScale', 'log', 'YDir', 'normal');
            cb = colorbar(ax);
            cb.Label.String = '\lambda_x\Phi_{uu}(\lambda_x)/u_\tau^2';
            title(ax, expand_title(fig_spec.layout_title, ...
                tokens(struct('branch', names{k}))), 'Interpreter', 'none');
            save_fig(f, ['05_temporal_premultiplied_' names{k}]);
        end
    end

% -------------------- spatial_spectra：空间谱图+曲线 --------------------
    function render_spatial_spectra()
        if ~has('spatial'); return; end
        style = resolve_style(job);
        names = fieldnames(results.spatial);
        for k = 1:numel(names)
            V = results.spatial.(names{k});
            if isempty(V) || isempty(V.windows); continue; end
            W = V.windows(1);
            fig_spec = style.figures{1};
            f = new_fig('spatial', [1250 570]);
            layout = tiledlayout(f, 1, 2, ...
                'TileSpacing', 'compact', 'Padding', 'compact');
            if isfield(W, 'premultiplied_frequency_phi')
                premult_map = W.premultiplied_frequency_phi;
            else
                premult_map = W.premultiplied_k_phi;
            end
            spatial_plot_rows = 1:numel(W.y_plus);
            if isfield(W, 'used_rows') && ~isempty(W.used_rows)
                spatial_plot_rows = W.used_rows;
            end
            premult_map = premult_map(spatial_plot_rows, :);
            spatial_y_plus = W.y_plus(spatial_plot_rows);
            premult_map(~isfinite(premult_map)) = NaN;
            ax = nexttile(layout);
            draw_cloud(ax, W.lambda_x_over_delta99_ref, spatial_y_plus, ...
                premult_map, fig_spec.panels{1}, 'spatial_premultiplied');
            set(ax, 'XScale', 'log', 'YScale', 'log', 'YDir', 'normal');
            cb = colorbar(ax);
            cb.Label.String = 'f_x\Phi_{uu}(f_x)';
            ax = nexttile(layout);
            hold(ax, 'on');
            sl_curve = line_spec(fig_spec.panels{2}.series(1));
            semilogx(ax, W.lambda_x_over_delta99_ref, W.selected_curves, ...
                sl_curve{:});
            xlabel(ax, fig_spec.panels{2}.xlabel);
            ylabel(ax, fig_spec.panels{2}.ylabel);
            grid(ax, 'on');
            n_curves = size(W.selected_curves, 1);
            names_out = cell(1, n_curves);
            for iy = 1:n_curves
                names_out{iy} = expand_series_name( ...
                    fig_spec.panels{2}.series(1), ...
                    tokens(struct('yplus', sprintf('%.0f', ...
                    W.selected_y_plus_actual(iy)))));
            end
            legend(ax, names_out, 'Location', 'best');
            title(layout, expand_title(fig_spec.layout_title, ...
                tokens(struct('branch', names{k}))), 'Interpreter', 'none');
            save_fig(f, ['05_spatial_premultiplied_' names{k}]);
        end
    end

% -------------------- pod：能量+模态 2×2 --------------------
    function render_pod()
        if ~has('pod'); return; end
        style = resolve_style(job);
        names = fieldnames(results.pod);
        for k = 1:numel(names)
            value = results.pod.(names{k});
            if ~isstruct(value) || ~isfield(value, 'modes') || ...
                    ~isfield(value, 'energy_ratio'); continue; end
            fig_spec = style.figures{1};
            f = new_fig('pod', [1500 460]);
            layout = tiledlayout(f, 2, 2, ...
                'TileSpacing', 'compact', 'Padding', 'compact');
            ax = nexttile(layout, [2 1]);
            yyaxis(ax, 'left');
            bar(ax, 1:numel(value.energy_ratio), ...
                100 .* value.energy_ratio);
            xlabel(ax, fig_spec.panels{1}.xlabel);
            ylabel(ax, fig_spec.panels{1}.ylabel);
            yyaxis(ax, 'right');
            hold(ax, 'on');
            draw_series(ax, 1:numel(value.cumulative_energy_ratio), ...
                100 .* value.cumulative_energy_ratio, ...
                fig_spec.panels{1}, 2);
            ylabel(ax, fig_spec.panels{1}.rlabel);
            grid(ax, 'on');
            mode_U = squeeze(real(value.modes.U(1, :, :)));
            mode_V = squeeze(real(value.modes.V(1, :, :)));
            ax = nexttile(layout);
            field_tile(ax, mode_U, fig_spec.panels{2}, 'pod_mode', ...
                value.modes.X_mm(1, :), value.modes.Y_mm(:, 1));
            ax = nexttile(layout);
            field_tile(ax, mode_V, fig_spec.panels{3}, 'pod_mode', ...
                value.modes.X_mm(1, :), value.modes.Y_mm(:, 1));
            title(layout, expand_title(fig_spec.layout_title, ...
                tokens(struct('branch', names{k}))), 'Interpreter', 'none');
            save_fig(f, ['06_POD_' names{k}]);
        end
    end

% -------------------- dmd：特征平面+模态 2×2 --------------------
    function render_dmd()
        if ~has('dmd'); return; end
        style = resolve_style(job);
        names = fieldnames(results.dmd);
        for k = 1:numel(names)
            value = results.dmd.(names{k});
            if ~isstruct(value) || ~isfield(value, 'modes'); continue; end
            amplitude = abs(value.amplitudes(:));
            [~, selected_mode] = max(amplitude);
            significant = amplitude >= 0.05 .* max(amplitude);
            if nnz(significant) < min(3, numel(amplitude))
                [~, order] = sort(amplitude, 'descend');
                significant(order(1:min(3, numel(order)))) = true;
            end
            fig_spec = style.figures{1};
            f = new_fig('dmd', [1500 480]);
            layout = tiledlayout(f, 2, 2, ...
                'TileSpacing', 'compact', 'Padding', 'compact');
            ax = nexttile(layout, [2 1]);
            hold(ax, 'on');
            draw_scatter(ax, real(value.eigenvalues(~significant)), ...
                imag(value.eigenvalues(~significant)), ...
                fig_spec.panels{1}.series(1));
            draw_scatter(ax, real(value.eigenvalues(significant)), ...
                imag(value.eigenvalues(significant)), ...
                fig_spec.panels{1}.series(2), amplitude(significant));
            theta = linspace(0, 2 * pi, 300);
            plot(ax, cos(theta), sin(theta), 'k--', ...
                'HandleVisibility', 'off');
            axis(ax, 'equal');
            grid(ax, 'on');
            xlabel(ax, fig_spec.panels{1}.xlabel);
            ylabel(ax, fig_spec.panels{1}.ylabel);
            title(ax, fig_spec.panels{1}.title, 'Interpreter', 'none');
            ax = nexttile(layout);
            hold(ax, 'on');
            draw_scatter(ax, value.frequency_hz(~significant), ...
                value.growth_rate_per_s(~significant), ...
                fig_spec.panels{2}.series(1));
            draw_scatter(ax, value.frequency_hz(significant), ...
                value.growth_rate_per_s(significant), ...
                fig_spec.panels{2}.series(2), amplitude(significant));
            xlabel(ax, fig_spec.panels{2}.xlabel);
            ylabel(ax, fig_spec.panels{2}.ylabel);
            grid(ax, 'on');
            title(ax, fig_spec.panels{2}.title, 'Interpreter', 'none');
            mode_U = squeeze(real(value.modes.U(selected_mode, :, :)));
            ax = nexttile(layout);
            field_tile(ax, mode_U, fig_spec.panels{3}, 'dmd_mode', ...
                value.modes.X_mm(1, :), value.modes.Y_mm(:, 1));
            title(ax, expand_title(fig_spec.panels{3}.title, ...
                tokens(struct('mode', sprintf('%d', selected_mode), ...
                'freq', sprintf('%.2f', value.frequency_hz(selected_mode)), ...
                'growth', sprintf('%.2g', ...
                value.growth_rate_per_s(selected_mode))))), ...
                'Interpreter', 'none');
            title(layout, expand_title(fig_spec.layout_title, ...
                tokens(struct('branch', names{k}))), 'Interpreter', 'none');
            save_fig(f, ['07_DMD_' names{k}]);
        end
    end

% -------------------- spod：谱+模态 2×2 --------------------
    function render_spod()
        if ~has('spod'); return; end
        style = resolve_style(job);
        names = fieldnames(results.spod);
        for k = 1:numel(names)
            value = results.spod.(names{k});
            if ~isstruct(value) || ~isfield(value, 'eigenvalues') || ...
                    ~isfield(value, 'selected_modes'); continue; end
            fig_spec = style.figures{1};
            f = new_fig('spod', [1500 460]);
            layout = tiledlayout(f, 2, 2, ...
                'TileSpacing', 'compact', 'Padding', 'compact');
            ax = nexttile(layout, [2 1]);
            non_dc = value.frequency_hz > 0;
            semilogy(ax, value.frequency_hz(non_dc), ...
                value.eigenvalues(:, non_dc)', 'LineWidth', 1.1);
            xlabel(ax, fig_spec.panels{1}.xlabel);
            ylabel(ax, fig_spec.panels{1}.ylabel);
            grid(ax, 'on');
            title(ax, fig_spec.panels{1}.title, 'Interpreter', 'none');
            selected = value.selected_modes(1);
            selected_U = squeeze(real(selected.U(1, :, :)));
            selected_V = squeeze(real(selected.V(1, :, :)));
            freq_text = sprintf('%.3g', value.selected_frequency_hz(1));
            ax = nexttile(layout);
            field_tile(ax, selected_U, fig_spec.panels{2}, 'spod_mode', ...
                selected.X_mm(1, :), selected.Y_mm(:, 1));
            title(ax, expand_title(fig_spec.panels{2}.title, ...
                tokens(struct('freq', freq_text))), 'Interpreter', 'none');
            ax = nexttile(layout);
            field_tile(ax, selected_V, fig_spec.panels{3}, 'spod_mode', ...
                selected.X_mm(1, :), selected.Y_mm(:, 1));
            title(ax, expand_title(fig_spec.panels{3}.title, ...
                tokens(struct('freq', freq_text))), 'Interpreter', 'none');
            title(layout, expand_title(fig_spec.layout_title, ...
                tokens(struct('branch', names{k}, ...
                'nblocks', sprintf('%d', value.n_blocks)))), ...
                'Interpreter', 'none');
            save_fig(f, ['08_SPOD_' names{k}]);
        end
    end

% -------------------- correlations：面板跟随开关 --------------------
    function render_correlations()
        if ~has('correlations'); return; end
        style = resolve_style(job);
        names = fieldnames(results.correlations);
        for k = 1:numel(names)
            V = results.correlations.(names{k});
            if isempty(V); continue; end
            fig_spec = style.figures{1};
            panels = fig_spec.panels;
            enabled = [true, switch_enabled(V.two_point), ...
                switch_enabled(V.space_time), ...
                switch_enabled(V.streamwise_spatial)];
            n_active = nnz(enabled);
            if n_active < 1; continue; end
            n_rows = ceil(n_active / 2);
            f = new_fig('correlations', [1650 950]);
            layout = tiledlayout(f, n_rows, 2, ...
                'TileSpacing', 'compact', 'Padding', 'compact');
            if enabled(1)
                ax = nexttile(layout);
                hold(ax, 'on');
                panel_spec = panels{1};
                for ir = 1:numel(V.temporal)
                    draw_curve(ax, V.temporal(ir).lag_seconds, ...
                        V.temporal(ir).Ruu, panel_spec.series(1), ...
                        tokens(struct('ir', sprintf('%d', ir))));
                end
                yline(ax, 0, 'k:', 'HandleVisibility', 'off');
                grid(ax, 'on');
                legend(ax, 'Location', 'best');
                xlabel(ax, panel_spec.xlabel);
                ylabel(ax, panel_spec.ylabel);
                title(ax, panel_spec.title, 'Interpreter', 'none');
            end
            if enabled(2)
                ax = nexttile(layout);
                field_tile(ax, V.two_point(1).Ruu, panels{2}, ...
                    'two_point_ruu', [], []);
            end
            if enabled(3)
                ax = nexttile(layout);
                st_ruu = V.space_time(1).Ruu;
                st_ruu(~isfinite(st_ruu)) = NaN;
                field_tile(ax, st_ruu, panels{3}, 'space_time_ruu', [], []);
                Uc_ridge = V.space_time(1).convection_velocity_ridge_mps;
                if isfinite(Uc_ridge)
                    title(ax, sprintf('space-time Ruu, Uc=%.3g m/s', ...
                        Uc_ridge));
                end
            end
            if enabled(4)
                ax = nexttile(layout);
                hold(ax, 'on');
                panel_spec = panels{4};
                for iy = 1:numel(V.streamwise_spatial)
                    draw_curve(ax, ...
                        V.streamwise_spatial(iy).delta_x_mm, ...
                        V.streamwise_spatial(iy).Ruu, ...
                        panel_spec.series(1), tokens(struct( ...
                        'yplus', sprintf('%.0f', ...
                        V.streamwise_spatial(iy).y_plus_actual))));
                end
                yline(ax, 0, 'k:', 'HandleVisibility', 'off');
                xlabel(ax, panel_spec.xlabel);
                ylabel(ax, panel_spec.ylabel);
                grid(ax, 'on');
                legend(ax, 'Location', 'best');
                title(ax, panel_spec.title, 'Interpreter', 'none');
            end
            title(layout, expand_title(fig_spec.layout_title, ...
                tokens(struct('branch', names{k}))), 'Interpreter', 'none');
            save_fig(f, ['13_correlations_' names{k}]);
        end
    end

% -------------------- harmonics：沿程发展 1×3 --------------------
    function render_harmonics()
        if ~has('harmonics'); return; end
        H = results.harmonics;
        style = resolve_style(job);
        if isfield(H, 'harmonic_number') && ~isempty(H.harmonic_number)
            fig_spec = style.figures{1};
            f = new_fig('harmonics_amplitude', [1350 520]);
            layout = tiledlayout(f, 1, numel(H.harmonic_number), ...
                'TileSpacing', 'compact', 'Padding', 'compact');
            for ih = 1:numel(H.harmonic_number)
                ax = nexttile(layout);
                field_tile(ax, squeeze(H.u_amplitude_mps(ih, :, :)), ...
                    fig_spec.panels{1}, 'harmonic_u_amplitude', [], []);
                title(ax, expand_title(fig_spec.panels{1}.title, ...
                    tokens(struct('hf0', sprintf('%d', ...
                    H.harmonic_number(ih))))), 'Interpreter', 'none');
            end
            title(layout, expand_title(fig_spec.layout_title, ...
                tokens(struct('name', case_name()))), 'Interpreter', 'none');
            save_fig(f, '13_harmonic_amplitude_maps');
        end
        if ~isfield(H, 'nonphase') || isempty(H.nonphase); return; end
        N = H.nonphase;
        fig_spec = style.figures{2};
        f = new_fig('harmonics_nonphase', [1450 560]);
        layout = tiledlayout(f, 1, 3, ...
            'TileSpacing', 'compact', 'Padding', 'compact');
        x_valid = true(size(N.x_mm));
        if isfield(N, 'streamwise_valid_mask')
            x_valid = N.streamwise_valid_mask;
        end
        edge_columns = 0;
        if isfield(cfg, 'streamwise_development') && ...
                isfield(cfg.streamwise_development, 'edge_buffer_columns')
            edge_columns = max(0, round(double( ...
                cfg.streamwise_development.edge_buffer_columns)));
        end
        if edge_columns > 0 && numel(x_valid) > 2 * edge_columns
            x_valid(1:edge_columns) = false;
            x_valid(end - edge_columns + 1:end) = false;
        end
        ax = nexttile(layout);
        hold(ax, 'on');
        u_peak = N.u_rms.peak;
        u_peak(~x_valid) = NaN;
        draw_curve(ax, N.x_mm, u_peak, fig_spec.panels{1}.series(1));
        apply_streamwise_display_limits(ax, u_peak, 'positive');
        grid(ax, 'on');
        xlabel(ax, fig_spec.panels{1}.xlabel);
        ylabel(ax, fig_spec.panels{1}.ylabel);
        ax = nexttile(layout);
        hold(ax, 'on');
        uv_peak = N.negative_uv.peak;
        uv_peak(~x_valid) = NaN;
        draw_curve(ax, N.x_mm, uv_peak, fig_spec.panels{2}.series(1));
        uv_trend = movmedian(uv_peak, 7, 'omitnan', ...
            'Endpoints', 'shrink');
        draw_curve(ax, N.x_mm, uv_trend, fig_spec.panels{2}.series(2));
        apply_streamwise_display_limits(ax, uv_trend, 'positive');
        grid(ax, 'on');
        xlabel(ax, fig_spec.panels{2}.xlabel);
        ylabel(ax, fig_spec.panels{2}.ylabel);
        legend(ax, 'Location', 'best');
        ax = nexttile(layout);
        hold(ax, 'on');
        if isfield(N, 'transport') && ...
                isfield(N.transport, 'total_production')
            production_peak = N.transport.total_production.peak;
            production_peak(~x_valid) = NaN;
            draw_curve(ax, N.x_mm, production_peak, ...
                fig_spec.panels{3}.series(1));
            production_trend = movmedian(production_peak, 7, ...
                'omitnan', 'Endpoints', 'shrink');
            draw_curve(ax, N.x_mm, production_trend, ...
                fig_spec.panels{3}.series(2));
            apply_streamwise_display_limits(ax, production_trend, ...
                'range');
            legend(ax, 'Location', 'best');
        else
            text(ax, 0.5, 0.5, 'Transport stage unavailable', ...
                'Units', 'normalized', 'HorizontalAlignment', 'center');
        end
        xlabel(ax, fig_spec.panels{3}.xlabel);
        ylabel(ax, fig_spec.panels{3}.ylabel);
        grid(ax, 'on');
        title(layout, expand_title(fig_spec.layout_title, ...
            tokens(struct('name', case_name()))), 'Interpreter', 'none');
        save_fig(f, '13_nonphase_streamwise_development');
    end

% -------------------- phase_triple：兼容占位（baseline 为空） --------------------
    function render_phase_triple()
        if ~has('phase') || ~isfield(results.phase, 'coherent_TKE'); return; end
        style = resolve_style(job);
        fig_spec = style.figures{1};
        f = new_fig('phase_triple', [1500 760]);
        ax = axes(f);
        field_tile(ax, squeeze(mean(results.phase.coherent_TKE, 1, ...
            'omitnan')), fig_spec.panels{1}, 'phase_coherent_u', [], []);
        title(ax, expand_title(fig_spec.layout_title, ...
            tokens(struct('name', case_name()))), 'Interpreter', 'none');
        save_fig(f, '04_phase_coherent_tke');
    end

% =========================================================================
% 样式默认表（r1 现值）与校验合并
% =========================================================================

    function style = default_style(job_name)
        switch char(job_name)
            case 'mean_turbulence'
                style.figures = { ...
                    fig_def('{name}: dimensionless mean velocity (Uinf = {Uinf} m/s) [PIV raw]', ...
                    '02a_mean_velocity_norm', ...
                    cloud_panel('U mean / Uinf'), cloud_panel('V mean / Uinf')), ...
                    fig_def('{name}: dimensionless turbulence intensities (Uinf = {Uinf} m/s) [PIV raw]', ...
                    '02b_turbulence_rms_norm', ...
                    cloud_panel('u''_rms / Uinf'), cloud_panel('v''_rms / Uinf')), ...
                    fig_def('{name}: dimensionless Reynolds shear stress and TKE (Uinf = {Uinf} m/s) [PIV raw]', ...
                    '02c_shear_stress_tke_norm', ...
                    cloud_panel('-<u''v''> / Uinf^2'), cloud_panel('TKE / Uinf^2'))};
            case 'mean_profiles'
                style.figures = {fig_def( ...
                    '{name}: range-averaged wall-normal profiles, x = {x1}--{x2} mm ({ncol} columns) [PIV raw]', ...
                    '02d_range_average_profiles', ...
                    std_curve_panel('U [m/s]', 'U [m/s]', 'y [mm]'), ...
                    std_curve_panel('u''_rms / U_{\infty}', ...
                    'u''_rms / U_{\infty}', 'y [mm]'), ...
                    std_curve_panel('v''_rms / U_{\infty}', ...
                    'v''_rms / U_{\infty}', 'y [mm]'), ...
                    std_curve_panel('<u''v''> / U_{\infty}^2', ...
                    '<u''v''> / U_{\infty}^2', 'y [mm]'))};
            case 'loglaw'
                style.preview_titles = { ...
                    '{name}: Cf chart and mean velocity profile [PIV raw]', ...
                    '{name}: mean velocity profile in wall units [PIV raw]'};
                style.figures = {fig_def( ...
                    '{name}: log-law fit of the mean velocity profile [PIV raw]', ...
                    '06_loglaw', ...
                    curve_panel('', 'y U_{\infty}/\nu', 'u/U_{\infty}', ...
                    [series_def('measured profile', 'r', '-', '', [], 1.2, [], []); ...
                    series_def('', 'k', '-', '', [], 1.2, [], [])], ...
                    legend_def('southeast'), annotation_def({'C_f={cf}'})), ...
                    curve_panel('', 'y^+', 'u^+', ...
                    [series_def('measured', 'r', 'none', 'o', 5, 0.8, [], []); ...
                    series_def('viscous sublayer u^+=y^+', 'k', '--', '', [], 1.0, [], []); ...
                    series_def('log-law RMSE window', 'g', '-', '', [], 1.2, [], []); ...
                    series_def('log-law extension', 'g', ':', '', [], 1.2, [], [])], ...
                    legend_def('southeast'), annotation_def({'u_\tau={utau} m/s', ...
                    '\kappa={kappa}, B={b}, RMSE={rmse}', ...
                    'fit window: {r1} \leq y^+ \leq {r2}', ...
                    'excluded near-wall points: {nskip}'})))};
            case 'loglaw_diagnostic'
                style.figures = {fig_def( ...
                    '{name}: Xi reference diagnostic (not a log-law acceptance test) [PIV raw]', ...
                    '06c_xi_reference', ...
                    curve_panel('', 'y^+', ...
                    '\Xi = y^+ dU^+/dy^+ = dU^+/d ln(y^+)', ...
                    [series_def('5-point local slope', 'k', '-', 'o', 4, 1.0, [], []); ...
                    series_def('7-point local slope', 'b', '-', 's', 4, 1.0, [], []); ...
                    series_def('1/\kappa', 'r', '--', '', [], 1.2, [], 'hline')], ...
                    legend_def('best'), annotation_def({'Reference only: Xi does not accept or reject log-law applicability.', ...
                    'target Xi = 1/kappa = {target}', ...
                    'Use with profile residuals and experimental context.'})))};
            case 'modern_clauser'
                style.figures = {fig_def( ...
                    '{name}: option B modern Clauser composite fit (Rodriguez-Lopez et al., 2015) [PIV raw]', ...
                    '06d_modern_clauser_composite', ...
                    curve_panel('Selected mean-profile fit', 'U [m/s]', 'y [mm]', ...
                    [series_def('measured', 'k', 'none', 'o', 5, 0.5, [], []); ...
                    series_def('excluded: wall reflection', [0.55 0.55 0.55], ...
                    'none', 'x', 7, 1.2, [], []); ...
                    series_def('composite model', 'r', '-', '', [], 1.4, [], [])], ...
                    legend_def('southeast'), annotation_def({})), ...
                    curve_panel('Wall-unit composite profile', 'y^+', 'U^+', ...
                    [series_def('measured', 'k', 'none', 'o', 5, 0.5, [], []); ...
                    series_def('excluded: wall reflection', [0.55 0.55 0.55], ...
                    'none', 'x', 7, 1.2, [], []); ...
                    series_def('Musker + bump + wake', 'r', '-', '', [], 1.4, [], [])], ...
                    legend_def('southeast'), annotation_def({'u_tau={utau} m/s, C_f={cf}', ...
                    'Pi={pi}, delta={delta} mm, E_1={e1}', ...
                    'fixed: kappa={kappa}, B={b}, dy/h={dyh}', ...
                    'excluded near-wall points: {nskip}'})))};
            case 'friction'
                style.figures = {fig_def( ...
                    'Boundary layer and distinct friction estimates (option A/B independent) [PIV raw]', ...
                    '11_friction_and_BL', ...
                    curve_panel('', 'x [mm]', 'thickness [mm]', ...
                    [series_def('delta99', 'auto', '-', '', [], 1.2, [], []); ...
                    series_def('delta*', 'auto', '-', '', [], 1.2, [], []); ...
                    series_def('theta', 'auto', '-', '', [], 1.2, [], [])], ...
                    legend_def('best'), annotation_def({})), ...
                    curve_panel('', 'x [mm]', 'Cf', ...
                    [series_def('local MIE', 'auto', '-', '', [], 1.2, [], []); ...
                    series_def('Clauser option A', 'auto', '--', '', [], 1.2, [], 'hline'); ...
                    series_def('composite option B', 'auto', '-.', '', [], 1.2, [], 'hline')], ...
                    legend_def('best'), annotation_def({})))};
            case 'cache_raw'
                style.figures = {fig_def( ...
                    '{name}：缓存原始帧 {frame} [PIV raw]', ...
                    '01_cache_raw_frame', ...
                    cloud_panel('瞬时 U [m/s]'), ...
                    cloud_panel('瞬时 V [m/s]'), ...
                    cloud_panel('有效矢量掩膜'))};
            case 'instantaneous_fields'
                style.figures = {fig_def( ...
                    '{name}：原始瞬时 u 与 u''，源帧 {frame} [PostProc]', ...
                    '03_instantaneous_fields', ...
                    cloud_panel('原始瞬时 u [m/s]'), ...
                    cloud_panel('瞬时 u'' = u - Uavg [m/s]'))};
            case 'instantaneous_vortex'
                style.figures = {fig_def( ...
                    '{name}: planar criteria, source frame {frame} [PostProc]', ...
                    '10_instantaneous_vortex', ...
                    cloud_panel('planar omega_z [1/s]'), ...
                    cloud_panel('planar Q [1/s^2]'), ...
                    cloud_panel('planar lambda_2 [1/s^2]'), ...
                    cloud_panel('planar lambda_ci [1/s]'))};
            case 'structures'
                style.figures = {fig_def( ...
                    '{name}: Section 4 preprocessing, frame {frame} [PostProc], {nlsm} LSM/VLSM contours', ...
                    '09_structures', ...
                    cloud_panel('raw u''/u_rms'), ...
                    cloud_panel('ordinary Gaussian -> mean-subtracted u''/u_rms'), ...
                    std_curve_panel('thresholded signed events (component IDs omitted)', ...
                    'x [mm]', 'y [mm]'), ...
                    std_curve_panel('preprocessing mask: trusted domain / ordinary Gaussian', ...
                    'x [mm]', 'y [mm]'))};
            case 'transport'
                style.figures = {fig_def( ...
                    'Planar transport terms [PostProc; raw mean normalization]', ...
                    '04_transport', ...
                    cloud_panel('-<u''v''>'), ...
                    cloud_panel('total production, FD'), ...
                    cloud_panel('total production, RBF-FD'), ...
                    std_curve_panel('{name}', '', ''))};
            case 'temporal_spectra'
                style.figures = { ...
                    fig_def('{branch} basic PSD branch [PostProc; raw mean normalization]', ...
                    '05_basic_PSD', ...
                    cloud_panel('raw frequency PSD after x-wise PSD averaging', ...
                    'f [Hz]', 'y^+')), ...
                    fig_def('{branch} temporal branch: PSD-at-x then x-average [PostProc; raw mean normalization]', ...
                    '05_temporal_premultiplied', ...
                    cloud_panel('', 'lambda_x^+', 'y^+'))};
            case 'spatial_spectra'
                style.figures = {fig_def( ...
                    '{branch} spatial branch [PostProc; raw mean normalization]', ...
                    '05_spatial_premultiplied', ...
                    cloud_panel('direct spatial FFT map, f_x in cycles/m', ...
                    'Streamwise wavelength, \lambda_x/\delta_{99} [-]', 'y^+'), ...
                    curve_panel('', 'Streamwise wavelength, \lambda_x/\delta_{99} [-]', ...
                    'f_x \Phi_{uu}(f_x)', ...
                    series_def('y^+={yplus}', 'auto', '-', '', [], 1.2, [], []), ...
                    legend_def('best'), annotation_def({})))};
            case 'pod'
                style.figures = {fig_def( ...
                    'POD {branch}: per-mode/cumulative energy and joint mode 1 [PostProc; raw mean normalization]', ...
                    '06_POD', ...
                    energy_panel(), ...
                    cloud_panel('mode 1, Re(\phi_u)'), ...
                    cloud_panel('mode 1, Re(\phi_v)'))};
            case 'dmd'
                style.figures = {fig_def( ...
                    'DMD {branch} [PostProc; raw mean normalization]', ...
                    '07_DMD', ...
                    scatter_panel('eigenvalue plane; color = |amplitude|', ...
                    'Re(lambda)', 'Im(lambda)', ...
                    [scatter_def('', [0.75 0.75 0.75], 24, true); ...
                    scatter_def('', 'auto', 45, true)]), ...
                    scatter_panel('amplitude-relevant modes emphasized', ...
                    'frequency [Hz]', 'growth rate [1/s]', ...
                    [scatter_def('', [0.75 0.75 0.75], 22, true); ...
                    scatter_def('', 'auto', 52, true)]), ...
                    cloud_panel('largest-|a| mode {mode}: Re(phi_u), f={freq} Hz, growth={growth} 1/s'))};
            case 'spod'
                style.figures = {fig_def( ...
                    'SPOD {branch}, {nblocks} Welch blocks; DC omitted from display only [PostProc; raw mean normalization]', ...
                    '08_SPOD', ...
                    std_curve_panel('non-DC SPOD eigenspectrum', ...
                    'frequency [Hz]', 'SPOD eigenvalue', ...
                    series_def('', 'auto', '-', '', [], 1.1, [], [])), ...
                    cloud_panel('mode 1 Re(phi_u), f={freq} Hz'), ...
                    cloud_panel('mode 1 Re(phi_v), f={freq} Hz'))};
            case 'correlations'
                style.figures = {fig_def( ...
                    'Correlations {branch} [PostProc; raw mean normalization]', ...
                    '13_correlations', ...
                    curve_panel('temporal reference correlations', 'lag [s]', 'Ruu', ...
                    series_def('ref {ir}', 'auto', '-', '', [], 1.1, [], []), ...
                    legend_def('best'), annotation_def({})), ...
                    cloud_panel('two-point Ruu (pairwise Pearson)'), ...
                    cloud_panel('space-time Ruu'), ...
                    curve_panel('same-height streamwise correlation', ...
                    '\Delta x [mm]', 'R_{uu}', ...
                    series_def('y^+={yplus}', 'auto', '-', '', [], 1.1, [], []), ...
                    legend_def('best'), annotation_def({})))};
            case 'harmonics'
                style.figures = { ...
                    fig_def('Phase-coherent streamwise harmonic amplitude [PIV raw]', ...
                    '13_harmonic_amplitude_maps', ...
                    cloud_panel('|utilde| at {hf0}f0')), ...
                    fig_def('Non-phase streamwise development handoff [PostProc; raw mean normalization]', ...
                    '13_nonphase_streamwise_development', ...
                    std_curve_panel('', 'x [mm]', 'peak_y u RMS [m/s]', ...
                    series_def('', 'auto', '-', '', [], 1.2, [], [])), ...
                    std_curve_panel('', 'x [mm]', 'peak_y -<uv> [m^2/s^2]', ...
                    [series_def('raw column peak', [0.72 0.72 0.72], '-', '', [], 0.55, [], []); ...
                    series_def('7-column median trend', 'auto', '-', '', [], 1.25, [], [])]), ...
                    std_curve_panel('', 'x [mm]', 'peak_y production [m^2/s^3]', ...
                    [series_def('raw column peak', [0.72 0.72 0.72], '-', '', [], 0.55, [], []); ...
                    series_def('7-column median trend', 'auto', '-', '', [], 1.25, [], [])]))};
            case 'phase_triple'
                style.figures = {fig_def( ...
                    '{name}: phase-coherent TKE map [PostProc]', ...
                    '04_phase_coherent_tke', ...
                    cloud_panel('phase-coherent TKE'))};
            otherwise
                error('tblR2:plot_core_products:UnknownStyleJob', ...
                    '没有 %s 的样式默认表。', char(job_name));
        end
    end

    function f = fig_def(layout_title, stem, varargin)
        f = struct('layout_title', layout_title, 'stem', stem, ...
            'panels', {varargin});
    end

    function p = std_curve_panel(title, xlabel, ylabel, series)
        if nargin < 4; series = series_def(); end
        p = curve_panel(title, xlabel, ylabel, series, ...
            legend_off_def(), annotation_def({}));
    end

    function l = legend_def(location)
        l = struct('show', true, 'location', location, 'box', true, ...
            'items', {{}});
    end

    function p = energy_panel()
        p = struct('title', '', 'xlabel', 'mode', ...
            'ylabel', 'per-mode energy [%]', ...
            'rlabel', 'cumulative retained energy [%]', ...
            'series', [series_def('', 'auto', 'none', '', [], [], [], ...
            'bar'); series_def('', 'k', '-', 'o', 3, 1.1, [], [])], ...
            'legend', legend_off_def(), 'annotation', annotation_def({}), ...
            'cloud', struct('background', [0.82 0.82 0.82]));
    end

    function p = scatter_panel(title, xlabel, ylabel, series)
        p = struct('title', title, 'xlabel', xlabel, 'ylabel', ylabel, ...
            'series', series, 'legend', legend_off_def(), ...
            'annotation', annotation_def({}), ...
            'cloud', struct('background', [0.82 0.82 0.82]));
    end

    function p = cloud_panel(title, xlabel, ylabel)
        if nargin < 2; xlabel = 'x [mm]'; end
        if nargin < 3; ylabel = 'y [mm]'; end
        p = struct('title', title, 'xlabel', xlabel, 'ylabel', ylabel, ...
            'series', series_def(), 'legend', legend_off_def(), ...
            'annotation', annotation_def({}), ...
            'cloud', struct('background', [0.82 0.82 0.82]));
    end

    function p = curve_panel(title, xlabel, ylabel, series, legend, annotation)
        p = struct('title', title, 'xlabel', xlabel, 'ylabel', ylabel, ...
            'series', series, 'legend', legend, ...
            'annotation', annotation, ...
            'cloud', struct('background', [0.82 0.82 0.82]));
    end

    function l = legend_off_def()
        l = struct('show', false, 'location', 'best', 'box', true, ...
            'items', {{}});
    end

    function a = annotation_def(lines)
        a = struct('lines', {lines}, 'position', [0.03 0.97], ...
            'interpreter', 'tex', 'show', true);
    end

    function s = series_def(display_name, color, line_style, marker, ...
            marker_size, line_width, items, kind)
        if nargin < 1; display_name = ''; end
        if nargin < 2; color = 'auto'; end
        if nargin < 3; line_style = '-'; end
        if nargin < 4; marker = ''; end
        if nargin < 5; marker_size = 6; end
        if nargin < 6; line_width = 1.0; end
        if nargin < 8; kind = 'line'; end
        if isempty(display_name); display_name = ''; end
        if isempty(color) || (ischar(color) && strcmp(color, 'auto'))
            color = 'auto';
        end
        if isempty(line_style); line_style = '-'; end
        if isempty(marker); marker = ''; end
        if isempty(marker_size); marker_size = 6; end
        if isempty(line_width); line_width = 1.0; end
        if isempty(kind); kind = 'line'; end
        s = struct('kind', kind, 'display_name', display_name, ...
            'color', color, 'line_style', line_style, 'marker', marker, ...
            'marker_size', marker_size, 'line_width', line_width, ...
            'fill', false);
    end

    function s = scatter_def(display_name, color, marker_size, fill)
        s = series_def(display_name, color, 'none', '.', marker_size, ...
            1.0, [], 'scatter');
        s.fill = logical(fill);
    end

% -------------------- 样式合并与校验（写错一律报错） --------------------
    function style = resolve_style(job_name)
        default = default_style(job_name);
        user_flat = [];
        if isfield(cfg, 'figures') && isfield(cfg.figures, 'job_style') && ...
                isstruct(cfg.figures.job_style) && ...
                isfield(cfg.figures.job_style, job_name) && ...
                ~isempty(cfg.figures.job_style.(job_name))
            user_flat = cfg.figures.job_style.(job_name);
        end
        if isempty(user_flat)
            style = default;
        else
            validate_flat_style(job_name, default, user_flat);
            user = flat_to_nested(default, user_flat);
            style = merge_style(default, user, ['job_style.' job_name]);
        end
        validate_style(job_name, style);
    end

    function user = flat_to_nested(default, flat)
        % 将平铺的用户样式（按面板/图序号的 cell）转换成内部嵌套样式。
        F = numel(default.figures);
        user = struct('figures', {cell(1, F)});
        for i = 1:F; user.figures{i} = struct(); end
        if isfield(flat, 'layout_titles') && ~isempty(flat.layout_titles)
            n = min(numel(flat.layout_titles), F);
            for i = 1:n
                if ischar(flat.layout_titles{i}) && ...
                        ~isempty(flat.layout_titles{i})
                    user.figures{i}.layout_title = flat.layout_titles{i};
                end
            end
        end
        if isfield(flat, 'preview_titles') && ~isempty(flat.preview_titles)
            user.preview_titles = flat.preview_titles;
        end
        panels_map = panel_map(default);
        P = size(panels_map, 1);
        fields_def = { ...
            'panel_titles', 'title', 'panel'; ...
            'xlabels', 'xlabel', 'panel'; ...
            'ylabels', 'ylabel', 'panel'; ...
            'rlabels', 'rlabel', 'panel'; ...
            'cloud_backgrounds', 'background', 'cloud'; ...
            'series', 'series', 'panel'; ...
            'legends', 'legend', 'panel'; ...
            'annotations', 'annotation', 'panel'};
        for k = 1:size(fields_def, 1)
            name = fields_def{k, 1};
            if ~isfield(flat, name) || isempty(flat.(name)); continue; end
            n = min(numel(flat.(name)), P);
            for p = 1:n
                value = flat.(name){p};
                if isempty(value); continue; end
                fig = panels_map(p, 1);
                ip = panels_map(p, 2);
                if ~isfield(user.figures{fig}, 'panels')
                    user.figures{fig}.panels = cell(1, ...
                        numel(default.figures{fig}.panels));
                    for kk = 1:numel(user.figures{fig}.panels)
                        user.figures{fig}.panels{kk} = struct();
                    end
                end
                switch fields_def{k, 3}
                    case 'panel'
                        user.figures{fig}.panels{ip}.(fields_def{k, 2}) = value;
                    case 'cloud'
                        user.figures{fig}.panels{ip}.cloud = ...
                            struct(fields_def{k, 2}, value);
                    otherwise
                        user.figures{fig}.panels{ip}.(fields_def{k, 2}) = ...
                            value(:);
                end
            end
        end
    end

    function map = panel_map(default)
        cells = cell(0, 2);
        for i = 1:numel(default.figures)
            for ip = 1:numel(default.figures{i}.panels)
                cells(end + 1, :) = {i, ip}; %#ok<AGROW>
            end
        end
        map = cell2mat(cells);
    end

    function validate_flat_style(job_name, default, flat)
        allowed = {'layout_titles', 'preview_titles', 'panel_titles', ...
            'xlabels', 'ylabels', 'rlabels', 'cloud_backgrounds', ...
            'series', 'legends', 'annotations'};
        check_fields(flat, allowed, ['job_style.' job_name]);
        if isfield(flat, 'layout_titles')
            check_titles_cell(flat.layout_titles, ...
                ['job_style.' job_name '.layout_titles']);
        end
        if isfield(flat, 'preview_titles')
            check_cellstr(flat.preview_titles, ...
                ['job_style.' job_name '.preview_titles']);
        end
        for name = {'panel_titles', 'xlabels', 'ylabels', 'rlabels'}
            if isfield(flat, name{1})
                check_titles_cell(flat.(name{1}), ...
                    ['job_style.' job_name '.' name{1}]);
            end
        end
        if isfield(flat, 'cloud_backgrounds')
            fp = ['job_style.' job_name '.cloud_backgrounds'];
            if ~iscell(flat.cloud_backgrounds)
                error('tblR2:plot_core_products:InvalidStyleField', ...
                    '%s 必须是 cell（按面板顺序）。', fp);
            end
            for p = 1:numel(flat.cloud_backgrounds)
                value = flat.cloud_backgrounds{p};
                if isempty(value); continue; end
                if ~(isnumeric(value) && numel(value) == 3 && ...
                        all(isfinite(value)) && ...
                        all(value >= 0 & value <= 1))
                    error('tblR2:plot_core_products:InvalidStyleField', ...
                        '%s{%d} 必须是 [0,1] 内 1x3 颜色。', fp, p);
                end
            end
        end
        if isfield(flat, 'series')
            fp = ['job_style.' job_name '.series'];
            if ~iscell(flat.series)
                error('tblR2:plot_core_products:InvalidStyleField', ...
                    '%s 必须是 cell（按面板顺序）。', fp);
            end
            for p = 1:numel(flat.series)
                if isempty(flat.series{p}); continue; end
                validate_series_partial(flat.series{p}, ...
                    sprintf('%s{%d}', fp, p));
            end
        end
        if isfield(flat, 'legends')
            fp = ['job_style.' job_name '.legends'];
            if ~iscell(flat.legends)
                error('tblR2:plot_core_products:InvalidStyleField', ...
                    '%s 必须是 cell（按面板顺序）。', fp);
            end
            for p = 1:numel(flat.legends)
                if isempty(flat.legends{p}); continue; end
                validate_legend_partial(flat.legends{p}, ...
                    sprintf('%s{%d}', fp, p));
            end
        end
        if isfield(flat, 'annotations')
            fp = ['job_style.' job_name '.annotations'];
            if ~iscell(flat.annotations)
                error('tblR2:plot_core_products:InvalidStyleField', ...
                    '%s 必须是 cell（按面板顺序）。', fp);
            end
            for p = 1:numel(flat.annotations)
                if isempty(flat.annotations{p}); continue; end
                validate_annotation_partial(flat.annotations{p}, ...
                    sprintf('%s{%d}', fp, p));
            end
        end
    end

    function check_titles_cell(value, path)
        if ~iscell(value)
            error('tblR2:plot_core_products:InvalidStyleField', ...
                '%s 必须是 cell（按顺序）。', path);
        end
        for i = 1:numel(value)
            if isempty(value{i}); continue; end
            if ~(ischar(value{i}) && (isvector(value{i}) || ...
                    isempty(value{i})))
                error('tblR2:plot_core_products:InvalidStyleField', ...
                    '%s{%d} 必须是字符串（或 [] 不改）。', path, i);
            end
        end
    end

    function validate_series_partial(value, path)
        if ~isstruct(value) || ~isvector(value)
            error('tblR2:plot_core_products:InvalidStyleField', ...
                '%s 必须是 struct（单条曲线/或曲线数组）。', path);
        end
        for i = 1:numel(value)
            sp = [path '(' num2str(i) ')'];
            check_fields(value(i), {'kind', 'display_name', 'color', ...
                'line_style', 'marker', 'marker_size', 'line_width', ...
                'fill'}, sp);
            if isfield(value(i), 'kind') && ...
                    ~ismember(value(i).kind, {'line', 'hline', 'vline', ...
                    'bar', 'scatter'})
                error('tblR2:plot_core_products:InvalidStyleField', ...
                    '%s.kind 取值非法：%s。', sp, value(i).kind);
            end
            if isfield(value(i), 'display_name') && ...
                    ~(ischar(value(i).display_name) && ...
                    (isvector(value(i).display_name) || ...
                    isempty(value(i).display_name)))
                error('tblR2:plot_core_products:InvalidStyleField', ...
                    '%s.display_name 必须是字符串。', sp);
            end
            if isfield(value(i), 'color')
                color_ok = (ischar(value(i).color) && ...
                    (strcmp(value(i).color, 'auto') || ...
                    (numel(value(i).color) == 1 && ...
                    ismember(value(i).color, 'rgbcmykw')))) || ...
                    (isnumeric(value(i).color) && ...
                    numel(value(i).color) == 3);
                if ~color_ok
                    error('tblR2:plot_core_products:InvalidStyleField', ...
                        '%s.color 取值非法：%s。', sp, ...
                        mat2str(value(i).color));
                end
            end
            if isfield(value(i), 'line_style') && ...
                    ~ismember(value(i).line_style, {'-', '--', ':', ...
                    '-.', 'none'})
                error('tblR2:plot_core_products:InvalidStyleField', ...
                    '%s.line_style 取值非法：%s。', sp, ...
                    value(i).line_style);
            end
            if isfield(value(i), 'marker') && ...
                    ~ismember(value(i).marker, {'', 'none', 'o', 's', ...
                    'd', 'p', 'h', 'x', '+', '*', '.', '^', 'v', '<', '>'})
                error('tblR2:plot_core_products:InvalidStyleField', ...
                    '%s.marker 取值非法：%s。', sp, value(i).marker);
            end
            if isfield(value(i), 'marker_size') && ...
                    ~(isnumeric(value(i).marker_size) && ...
                    isscalar(value(i).marker_size) && ...
                    isfinite(value(i).marker_size) && ...
                    value(i).marker_size > 0)
                error('tblR2:plot_core_products:InvalidStyleField', ...
                    '%s.marker_size 必须是正数标量。', sp);
            end
            if isfield(value(i), 'line_width') && ...
                    ~(isnumeric(value(i).line_width) && ...
                    isscalar(value(i).line_width) && ...
                    isfinite(value(i).line_width) && ...
                    value(i).line_width > 0)
                error('tblR2:plot_core_products:InvalidStyleField', ...
                    '%s.line_width 必须是正数标量。', sp);
            end
            if isfield(value(i), 'fill') && ...
                    ~(islogical(value(i).fill) || ...
                    isnumeric(value(i).fill)) && ...
                    ~isscalar(value(i).fill)
                error('tblR2:plot_core_products:InvalidStyleField', ...
                    '%s.fill 必须是逻辑标量。', sp);
            end
        end
    end

    function validate_legend_partial(value, path)
        if ~isstruct(value) || ~isscalar(value)
            error('tblR2:plot_core_products:InvalidStyleField', ...
                '%s 必须是标量 struct。', path);
        end
        check_fields(value, {'show', 'location', 'box', 'items'}, path);
        if isfield(value, 'location') && ...
                ~ismember(value.location, {'north', 'south', 'east', ...
                'west', 'northeast', 'northwest', 'southeast', ...
                'southwest', 'northoutside', 'southoutside', ...
                'eastoutside', 'westoutside', 'northeastoutside', ...
                'northwestoutside', 'southeastoutside', ...
                'southwestoutside', 'best', 'bestoutside', 'none'})
            error('tblR2:plot_core_products:InvalidStyleField', ...
                '%s.location 取值非法：%s。', path, value.location);
        end
        for name = {'show', 'box'}
            if isfield(value, name{1}) && ...
                    ~(islogical(value.(name{1})) || ...
                    isnumeric(value.(name{1}))) && ...
                    ~isscalar(value.(name{1}))
                error('tblR2:plot_core_products:InvalidStyleField', ...
                    '%s.%s 必须是逻辑标量。', path, name{1});
            end
        end
        if isfield(value, 'items')
            check_cellstr(value.items, [path '.items']);
        end
    end

    function validate_annotation_partial(value, path)
        if ~isstruct(value) || ~isscalar(value)
            error('tblR2:plot_core_products:InvalidStyleField', ...
                '%s 必须是标量 struct。', path);
        end
        check_fields(value, {'lines', 'position', 'interpreter', 'show'}, ...
            path);
        if isfield(value, 'lines')
            check_cellstr(value.lines, [path '.lines']);
        end
        if isfield(value, 'position') && ...
                ~(isnumeric(value.position) && ...
                numel(value.position) == 2 && ...
                all(isfinite(value.position)))
            error('tblR2:plot_core_products:InvalidStyleField', ...
                '%s.position 必须是 [x y] 双元素数值。', path);
        end
        if isfield(value, 'interpreter') && ...
                ~ismember(value.interpreter, {'tex', 'latex', 'none'})
            error('tblR2:plot_core_products:InvalidStyleField', ...
                '%s.interpreter 取值非法：%s', path, value.interpreter);
        end
        if isfield(value, 'show') && ...
                ~(islogical(value.show) || isnumeric(value.show)) && ...
                ~isscalar(value.show)
            error('tblR2:plot_core_products:InvalidStyleField', ...
                '%s.show 必须是逻辑标量。', path);
        end
    end

    function merged = merge_style(default, user, path)
        if isempty(user)
            merged = default;
            return;
        end
        if isstruct(default) && isstruct(user)
            if ~isscalar(default) || ~isscalar(user)
                if numel(user) > numel(default)
                    error('tblR2:plot_core_products:InvalidStyleField', ...
                        '%s 的元素数（%d）超过默认样式（%d）。', ...
                        path, numel(user), numel(default));
                end
                merged = default;
                for i = 1:numel(user)
                    merged(i) = merge_style(default(i), user(i), ...
                        sprintf('%s(%d)', path, i));
                end
                return;
            end
            names = fieldnames(default);
            merged = default;
            for i = 1:numel(names)
                name = names{i};
                if isfield(user, name)
                    merged.(name) = merge_style(default.(name), ...
                        user.(name), [path '.' name]);
                end
            end
            extra = setdiff(fieldnames(user), names);
            if ~isempty(extra)
                error('tblR2:plot_core_products:UnknownStyleField', ...
                    '%s 含未知字段：%s（允许字段见主脚本注释目录）。', ...
                    path, strjoin(extra, ', '));
            end
        elseif iscell(default) && iscell(user)
            merged = default;
            n = min(numel(default), numel(user));
            for i = 1:n
                merged{i} = merge_style(default{i}, user{i}, ...
                    sprintf('%s{%d}', path, i));
            end
        else
            merged = user;
        end
    end

    function validate_style(job_name, style)
        check_fields(style, {'figures', 'preview_titles'}, ...
            ['job_style.' job_name]);
        if isfield(style, 'preview_titles')
            check_cellstr(style.preview_titles, ...
                ['job_style.' job_name '.preview_titles']);
        end
        for ifig = 1:numel(style.figures)
            fp = ['job_style.' job_name '.figures{' num2str(ifig) '}'];
            fig_spec = style.figures{ifig};
            check_fields(fig_spec, {'layout_title', 'stem', 'panels'}, fp);
            check_char(fig_spec.layout_title, [fp '.layout_title']);
            check_char(fig_spec.stem, [fp '.stem']);
            for ip = 1:numel(fig_spec.panels)
                pp = [fp '.panels{' num2str(ip) '}'];
                panel_spec = fig_spec.panels{ip};
                check_fields(panel_spec, {'title', 'xlabel', 'ylabel', ...
                    'series', 'legend', 'annotation', 'cloud', 'rlabel'}, pp);
                if iscell(panel_spec.title)
                    check_cellstr(panel_spec.title, [pp '.title']);
                else
                    check_char(panel_spec.title, [pp '.title']);
                end
                check_char(panel_spec.xlabel, [pp '.xlabel']);
                check_char(panel_spec.ylabel, [pp '.ylabel']);
                if isfield(panel_spec, 'rlabel')
                    check_char(panel_spec.rlabel, [pp '.rlabel']);
                end
                validate_series(panel_spec.series, [pp '.series']);
                validate_legend(panel_spec.legend, [pp '.legend']);
                validate_annotation(panel_spec.annotation, ...
                    [pp '.annotation']);
                validate_cloud(panel_spec.cloud, [pp '.cloud']);
            end
        end
    end

    function validate_series(series, path)
        if ~isstruct(series) || ~isvector(series)
            error('tblR2:plot_core_products:InvalidStyleField', ...
                '%s 必须是 struct 向量。', path);
        end
        for i = 1:numel(series)
            sp = [path '(' num2str(i) ')'];
            check_fields(series(i), {'kind', 'display_name', 'color', ...
                'line_style', 'marker', 'marker_size', 'line_width', ...
                'fill'}, sp);
            if ~ismember(series(i).kind, {'line', 'hline', 'vline', ...
                    'bar', 'scatter'})
                error('tblR2:plot_core_products:InvalidStyleField', ...
                    '%s.kind 取值非法：%s（允许 line/hline/vline/bar/scatter）。', ...
                    sp, series(i).kind);
            end
            check_char(series(i).display_name, [sp '.display_name']);
            if ~(ischar(series(i).color) || ...
                    (isnumeric(series(i).color) && ...
                    numel(series(i).color) == 3))
                error('tblR2:plot_core_products:InvalidStyleField', ...
                    '%s.color 必须是颜色字符、1x3 数值或 ''auto''。', sp);
            end
            if ischar(series(i).color) && ...
                    ~strcmp(series(i).color, 'auto') && ...
                    ~(numel(series(i).color) == 1 && ...
                    ismember(series(i).color, 'rgbcmykw'))
                error('tblR2:plot_core_products:InvalidStyleField', ...
                    '%s.color 取值非法：%s（允许 auto/rgbcmykw/1x3 数值）。', ...
                    sp, series(i).color);
            end
            if ~ismember(series(i).line_style, {'-', '--', ':', ...
                    '-.', 'none'})
                error('tblR2:plot_core_products:InvalidStyleField', ...
                    '%s.line_style 取值非法：%s（允许 -/--/:/-./none）。', ...
                    sp, series(i).line_style);
            end
            markers = {'', 'none', 'o', 's', 'd', 'p', 'h', 'x', ...
                '+', '*', '.', '^', 'v', '<', '>'};
            if ~ismember(series(i).marker, markers)
                error('tblR2:plot_core_products:InvalidStyleField', ...
                    '%s.marker 取值非法：%s。', sp, series(i).marker);
            end
            if ~(isnumeric(series(i).marker_size) && ...
                    isscalar(series(i).marker_size) && ...
                    isfinite(series(i).marker_size) && ...
                    series(i).marker_size > 0)
                error('tblR2:plot_core_products:InvalidStyleField', ...
                    '%s.marker_size 必须是正数标量。', sp);
            end
            if ~(isnumeric(series(i).line_width) && ...
                    isscalar(series(i).line_width) && ...
                    isfinite(series(i).line_width) && ...
                    series(i).line_width > 0)
                error('tblR2:plot_core_products:InvalidStyleField', ...
                    '%s.line_width 必须是正数标量。', sp);
            end
            if ~(islogical(series(i).fill) || isnumeric(series(i).fill)) || ...
                    ~isscalar(series(i).fill)
                error('tblR2:plot_core_products:InvalidStyleField', ...
                    '%s.fill 必须是逻辑标量。', sp);
            end
        end
    end

    function validate_legend(legend, path)
        check_fields(legend, {'show', 'location', 'box', 'items'}, path);
        if ~(islogical(legend.show) || isnumeric(legend.show)) || ...
                ~isscalar(legend.show)
            error('tblR2:plot_core_products:InvalidStyleField', ...
                '%s.show 必须是逻辑标量。', path);
        end
        if ~(islogical(legend.box) || isnumeric(legend.box)) || ...
                ~isscalar(legend.box)
            error('tblR2:plot_core_products:InvalidStyleField', ...
                '%s.box 必须是逻辑标量。', path);
        end
        locations = {'north', 'south', 'east', 'west', 'northeast', ...
            'northwest', 'southeast', 'southwest', 'northoutside', ...
            'southoutside', 'eastoutside', 'westoutside', ...
            'northeastoutside', 'northwestoutside', ...
            'southeastoutside', 'southwestoutside', 'best', ...
            'bestoutside', 'none'};
        if ~ismember(legend.location, locations)
            error('tblR2:plot_core_products:InvalidStyleField', ...
                '%s.location 取值非法：%s。', path, legend.location);
        end
        check_cellstr(legend.items, [path '.items']);
    end

    function validate_annotation(annotation, path)
        check_fields(annotation, {'lines', 'position', 'interpreter', ...
            'show'}, path);
        check_cellstr(annotation.lines, [path '.lines']);
        if ~(isnumeric(annotation.position) && ...
                numel(annotation.position) == 2 && ...
                all(isfinite(annotation.position)))
            error('tblR2:plot_core_products:InvalidStyleField', ...
                '%s.position 必须是 [x y] 双元素数值。', path);
        end
        if ~ismember(annotation.interpreter, {'tex', 'latex', 'none'})
            error('tblR2:plot_core_products:InvalidStyleField', ...
                '%s.interpreter 取值非法：%s', path, ...
                annotation.interpreter);
        end
        if ~(islogical(annotation.show) || isnumeric(annotation.show)) || ...
                ~isscalar(annotation.show)
            error('tblR2:plot_core_products:InvalidStyleField', ...
                '%s.show 必须是逻辑标量。', path);
        end
    end

    function validate_cloud(cloud, path)
        check_fields(cloud, {'background'}, path);
        if ~(isnumeric(cloud.background) && ...
                numel(cloud.background) == 3 && ...
                all(isfinite(cloud.background)) && ...
                all(cloud.background >= 0 & cloud.background <= 1))
            error('tblR2:plot_core_products:InvalidStyleField', ...
                '%s.background 必须是 [0,1] 内的 1x3 颜色。', path);
        end
    end

    function check_fields(value, allowed, path)
        if ~isstruct(value) || ~isscalar(value)
            error('tblR2:plot_core_products:InvalidStyleField', ...
                '%s 必须是标量 struct。', path);
        end
        extra = setdiff(fieldnames(value), allowed);
        if ~isempty(extra)
            error('tblR2:plot_core_products:UnknownStyleField', ...
                '%s 含未知字段：%s。', path, strjoin(extra, ', '));
        end
    end

    function check_char(value, path)
        if ~(ischar(value) && (isvector(value) || isempty(value)))
            error('tblR2:plot_core_products:InvalidStyleField', ...
                '%s 必须是字符向量。', path);
        end
    end

    function check_cellstr(value, path)
        if ~iscell(value) || ...
                ~all(cellfun(@(v) ischar(v) && (isvector(v) || isempty(v)), ...
                value))
            error('tblR2:plot_core_products:InvalidStyleField', ...
                '%s 必须是字符向量 cell 数组。', path);
        end
    end

% =========================================================================
% 绘制助手（全部 MATLAB 原生图形调用）
% =========================================================================

    function draw_series(ax, x, y, panel_spec, index)
        if index > numel(panel_spec.series); return; end
        s = panel_spec.series(index);
        if strcmp(s.kind, 'hline'); draw_hline(ax, x, s); return; end
        if strcmp(s.kind, 'vline'); draw_vline(ax, x, s); return; end
        if strcmp(s.kind, 'scatter'); draw_scatter(ax, x, y, s); return; end
        draw_curve(ax, x, y, s);
    end

    function draw_curve(ax, x, y, s, tok)
        if nargin < 5; tok = tokens(struct()); end
        sl = line_spec(s);
        if isempty(s.display_name)
            h = line(ax, x, y, sl{:});
        else
            h = line(ax, x, y, sl{:}, 'DisplayName', ...
                expand_title(s.display_name, tok));
        end
        if strcmp(s.kind, 'scatter') && ~isempty(h)
            set(h, 'MarkerFaceColor', resolve_color(s.color, []));
        end
    end

    function draw_scatter(ax, x, y, s, values)
        if nargin < 5; values = []; end
        color = resolve_color(s.color, values);
        if isempty(color)
            scatter(ax, x, y, s.marker_size, 'filled');
        else
            scatter(ax, x, y, s.marker_size, color, 'filled');
        end
    end

    function draw_vline(ax, value, s)
        spec = line_spec(s);
        if ~isempty(s.display_name)
            spec = [spec, 'DisplayName', expand_title(s.display_name, ...
                tokens(struct()))];
        end
        xline(ax, value, spec{:});
    end

    function draw_hline(ax, value, s)
        spec = line_spec(s);
        if ~isempty(s.display_name)
            spec = [spec, 'DisplayName', expand_title(s.display_name, ...
                tokens(struct()))];
        end
        yline(ax, value, spec{:});
    end

    function spec = line_spec(s)
        spec = {};
        if ~(ischar(s.color) && strcmp(s.color, 'auto'))
            spec = [spec, 'Color', resolve_color(s.color, [])];
        end
        if ~strcmp(s.line_style, 'none')
            spec = [spec, 'LineStyle', s.line_style];
        end
        if ~isempty(s.marker) && ~strcmp(s.marker, 'none')
            spec = [spec, 'Marker', s.marker, ...
                'MarkerSize', s.marker_size];
        end
        spec = [spec, 'LineWidth', s.line_width];
    end

    function color = resolve_color(value, data)
        if ischar(value) && strcmp(value, 'auto')
            color = data;
        else
            color = value;
        end
    end

    function ax = field_tile(ax, values, panel_spec, key, x, y)
        if nargin < 5 || isempty(x)
            x = results.statistics.X(1, :);
        end
        if nargin < 6 || isempty(y)
            y = results.statistics.Y(:, 1);
            if isfield(results, 'mean_bl') && ...
                    ~isempty(results.mean_bl) && ...
                    isfield(results.mean_bl, 'wall_distance_mm')
                y = results.mean_bl.wall_distance_mm(:, 1);
            end
        end
        draw_cloud(ax, x, y, values, panel_spec, key);
    end

    function draw_cloud(ax, x, y, values, panel_spec, key)
        values(~isfinite(values)) = NaN;
        limits = resolve_limits(values, key);
        n_levels = resolve_contour_levels(key);
        if ~isempty(limits)
            n_levels = linspace(limits(1), limits(2), n_levels);
        end
        contourf(ax, x, y, values, n_levels, 'LineStyle', 'none');
        ax.Color = panel_spec.cloud.background;
        apply_colormap(ax, resolve_colormap(key));
        set(ax, 'YDir', 'normal');
        axis(ax, 'tight');
        xlabel(ax, panel_spec.xlabel);
        ylabel(ax, panel_spec.ylabel);
        title(ax, expand_title(panel_spec.title, tokens(struct())), ...
            'Interpreter', 'none');
        if ~isempty(limits)
            clim(ax, limits);
        end
        cb = colorbar(ax, 'eastoutside');
        cb.FontSize = 9;
        cb.Box = 'on';
        tblR2.viz.apply_fov_aspect(ax, cfg);
        style_axes(ax);
    end

    function draw_events(ax, x, y, values, panel_spec)
        contourf(ax, x, y, values, [-1.5 -0.5 0.5 1.5], ...
            'LineStyle', 'none');
        axis(ax, 'tight');
        clim(ax, [-1.5 1.5]);
        colormap(ax, [0.15 0.35 0.80; 0.92 0.92 0.92; 0.80 0.20 0.15]);
        cb = colorbar(ax, 'eastoutside');
        cb.Ticks = [-1 0 1];
        cb.TickLabels = {'negative event', 'background', ...
            'positive event'};
        xlabel(ax, panel_spec.xlabel);
        ylabel(ax, panel_spec.ylabel);
        title(ax, panel_spec.title, 'Interpreter', 'none');
        tblR2.viz.apply_fov_aspect(ax, cfg);
        style_axes(ax);
    end

    function draw_quality(ax, x, y, values, panel_spec)
        finite_values = values(isfinite(values));
        if isempty(finite_values)
            levels = [0.5 1.5];
        elseif max(finite_values) - min(finite_values) < eps
            % 常量场（如全部可信）需要人为张开等值线，避免 contourf 警告。
            level = double(min(finite_values));
            levels = [level - 0.5 level + 0.5];
        else
            levels = [min(finite_values) max(finite_values)];
        end
        contourf(ax, x, y, values, levels, 'LineStyle', 'none');
        axis(ax, 'tight');
        clim(ax, levels);
        colormap(ax, [0.25 0.65 0.35]);
        cb = colorbar(ax, 'eastoutside');
        cb.FontSize = 9;
        cb.Box = 'on';
        cb.Ticks = 1;
        cb.TickLabels = {'trusted Gaussian field'};
        xlabel(ax, panel_spec.xlabel);
        ylabel(ax, panel_spec.ylabel);
        title(ax, panel_spec.title, 'Interpreter', 'none');
        tblR2.viz.apply_fov_aspect(ax, cfg);
        style_axes(ax);
    end

    function overlay_large_scales(ax, structure_result)
        if ~isstruct(structure_result) || ...
                ~isfield(structure_result, 'structures') || ...
                ~isfield(structure_result, 'positive_labels') || ...
                ~isfield(structure_result, 'negative_labels')
            return;
        end
        structures = structure_result.structures;
        if ~istable(structures) || height(structures) == 0 || ...
                ~ismember('LengthX_over_delta', ...
                structures.Properties.VariableNames)
            return;
        end
        if ismember('IsLSM', structures.Properties.VariableNames)
            selected = structures(isfinite(structures.LengthX_over_delta) & ...
                structures.LengthX_over_delta >= 1, :);
        else
            selected = structures;
        end
        if isempty(selected); return; end
        x = results.statistics.X(1, :);
        y = results.mean_bl.wall_distance_mm(:, 1);
        hold(ax, 'on');
        for iv = 1:height(selected)
            if selected.Sign(iv) >= 0
                labels = structure_result.positive_labels;
                same_sign = structures.Sign >= 0;
            else
                labels = structure_result.negative_labels;
                same_sign = structures.Sign < 0;
            end
            global_index = find(structures.StructureID == ...
                selected.StructureID(iv), 1);
            local_label = nnz(same_sign(1:global_index));
            if isempty(local_label) || local_label < 1; continue; end
            mask = labels == local_label;
            if ~any(mask(:)); continue; end
            contour(ax, x, y, double(mask), [0.5 0.5], 'Color', 'k', ...
                'LineStyle', '--', 'LineWidth', 1.5, ...
                'HandleVisibility', 'off');
        end
    end

    function apply_streamwise_display_limits(ax, values, limit_mode)
        finite_values = values(isfinite(values));
        if numel(finite_values) < 2; return; end
        probability = [0.005 0.995];
        global_probability = tblR2.figures_global(cfg, ...
            'robust_color_quantiles');
        if ~isempty(global_probability) && isnumeric(global_probability) && ...
                numel(global_probability) == 2
            probability = global_probability;
        end
        limits = tblR2.viz.robust_limits(finite_values, limit_mode, ...
            probability);
        span = limits(2) - limits(1);
        if isfinite(span) && span > 0
            ylim(ax, limits + [-0.05 0.08] .* span);
        end
    end

    function add_annotation(ax, annotation, tok, extra_lines)
        if ~annotation.show || isempty(annotation.lines); return; end
        if nargin < 4; extra_lines = {}; end
        lines = expand_cell(annotation.lines, tok);
        lines = [lines(:); extra_lines(:)];
        text(ax, annotation.position(1), annotation.position(2), lines, ...
            'Units', 'normalized', 'VerticalAlignment', 'top', ...
            'Interpreter', annotation.interpreter);
    end

    function f = new_fig(key, fallback)
        visibility = 'off';
        if strcmp(mode, 'preview'); visibility = 'on'; end
        f = figure('Visible', visibility, 'Color', 'w', ...
            'Name', char(job), 'NumberTitle', 'off', ...
            'Position', [50 50 resolve_window_size(key, fallback)], ...
            'DefaultAxesFontName', 'Arial', 'DefaultAxesFontSize', 10, ...
            'DefaultTextFontName', 'Arial', 'DefaultTextFontSize', 10, ...
            'DefaultLegendFontName', 'Arial', 'DefaultLegendFontSize', 9);
    end

    function style_axes(ax)
        ax.FontName = 'Arial';
        ax.FontSize = 10;
        ax.LineWidth = 0.8;
        ax.TickDir = 'out';
        ax.Box = 'on';
        ax.Layer = 'top';
    end

    function save_fig(f, stem)
        if strcmp(mode, 'preview')
            drawnow;
            figures(end + 1, 1) = f; %#ok<AGROW>
            return;
        end
        formats = {'png'};
        global_formats = tblR2.figures_global(cfg, 'formats');
        if ~isempty(global_formats)
            formats = cellstr(global_formats);
        end
        export_dpi = 200;
        global_dpi = tblR2.figures_global(cfg, 'export_dpi');
        if ~isempty(global_dpi) && isnumeric(global_dpi) && ...
                isscalar(global_dpi)
            export_dpi = global_dpi;
        end
        for jf = 1:numel(formats)
            ext = lower(strtrim(formats{jf}));
            if ~isfield(paths, ext)
                error('tblR2:plot_core_products:UnsupportedFigureFormat', ...
                    '没有为格式 %s 配置输出目录。', ext);
            end
            base = fullfile(paths.(ext), stem);
            tblR2.viz.export_publication_figure(f, base, {ext}, export_dpi);
            files{end + 1, 1} = [base '.' ext]; %#ok<AGROW>
        end
        close(f);
    end

    function position = resolve_window_size(key, fallback)
        position = fallback;
        configured = tblR2.figures_family(cfg, 'window_size', key);
        if isempty(configured)
            configured = tblR2.figures_family(cfg, 'window_size', 'default');
        end
        if ~isempty(configured)
            position = configured;
        end
        if ~(isnumeric(position) && numel(position) == 2 && ...
                all(isfinite(position)) && all(position > 0))
            position = fallback;
        end
        position = double(reshape(position, 1, 2));
    end

    function limits = resolve_limits(values, key)
        limits = [];
        icl = tblR2.figures_family(cfg, 'instantaneous', 'color_limits');
        if ~isempty(icl) && isstruct(icl) && ...
                ~isempty(key) && isfield(icl, key) && ~isempty(icl.(key))
            limits = icl.(key);
        end
        if isempty(limits)
            limits = tblR2.figures_family(cfg, 'color_limits', key);
        end
        if ~isempty(limits); return; end
        probability = [0.005 0.995];
        global_probability = tblR2.figures_global(cfg, ...
            'robust_color_quantiles');
        if ~isempty(global_probability) && isnumeric(global_probability) && ...
                numel(global_probability) == 2
            probability = global_probability;
        end
        if any(strcmp(key, {'mean_v', 'negative_uv', ...
                'transport_negative_uv', 'production_fd', ...
                'production_rbf', 'omega_z', 'q_planar', ...
                'lambda2_planar', 'pod_mode', 'dmd_mode', 'spod_mode', ...
                'two_point_ruu', 'space_time_ruu', 'structure_normalized', ...
                'u_prime', 'v_prime', 'uv_prime', 'negative_uv_prime', ...
                'u_random', 'v_random', 'uv_random'}))
            limits = tblR2.viz.robust_limits(values, 'balanced', ...
                probability);
        elseif any(strcmp(key, {'u_rms', 'v_rms', 'tke', 'lambda_ci', ...
                'temporal_psd', 'temporal_premultiplied', ...
                'spatial_premultiplied', 'harmonic_u_amplitude'}))
            limits = tblR2.viz.robust_limits(values, 'positive', ...
                probability);
        end
    end

    function n_levels = resolve_contour_levels(key)
        n_levels = 30;
        configured = tblR2.figures_family(cfg, 'contour_levels', 'default');
        if isempty(configured)
            configured = tblR2.figures_global(cfg, 'contour_levels');
        end
        if isnumeric(configured) && isscalar(configured) && ...
                isfinite(configured) && configured >= 2
            n_levels = configured;
        end
        per_key = tblR2.figures_family(cfg, 'contour_levels', key);
        if ~isempty(per_key) && isnumeric(per_key) && isscalar(per_key) && ...
                isfinite(per_key) && per_key >= 2
            n_levels = per_key;
        end
        if ~(isfinite(n_levels) && n_levels >= 2 && ...
                n_levels == fix(n_levels))
            n_levels = 30;
        end
    end

    function name = resolve_colormap(key)
        name = 'turbo';
        key_config = tblR2.figures_family(cfg, 'colormaps', key);
        if ischar(key_config) && ~isempty(key_config)
            % 该字段有专门配置（如 u_prime='ocean'）：以配置为准。
            name = key_config;
        elseif any(strcmp(key, {'u_prime', 'v_prime', 'uv_prime', ...
                'negative_uv_prime', 'u_random', 'v_random', ...
                'uv_random', 'structure_normalized'}))
            % 未单独配置的"脉动/正负对称"流场，一律默认红-白-蓝平衡色图
            % （resolve_case_colormap 中 ocean/balance/coolwarm 同一张图）。
            name = 'balance';
        else
            % 其余字段用 section9 的默认色图。
            fallback = tblR2.figures_family(cfg, 'colormaps', 'default');
            if ischar(fallback) && ~isempty(fallback)
                name = fallback;
            end
        end
    end

    function apply_colormap(ax, cmap_name)
        if strcmp(cmap_name, 'turbo')
            colormap(ax, turbo(256));
        else
            colormap(ax, tblR2.viz.resolve_case_colormap(cmap_name, 256));
        end
    end

    function Uinf = resolve_uinf()
        Uinf = 25;
        if isfield(cfg, 'Uinf') && ~isempty(cfg.Uinf) && ...
                isnumeric(cfg.Uinf) && isscalar(cfg.Uinf) && ...
                isfinite(cfg.Uinf) && cfg.Uinf > 0
            Uinf = double(cfg.Uinf);
        end
    end

    function name = case_name()
        name = 'Case';
        if isfield(cfg, 'name') && ~isempty(cfg.name)
            name = char(cfg.name);
        end
    end

    function tf = has(section)
        tf = isfield(results, section) && ~isempty(results.(section));
    end

    function tf = switch_enabled(value)
        tf = true;
        if isempty(value)
            tf = false;
        elseif isstruct(value) && isfield(value, 'enabled')
            tf = logical(value(1).enabled);
        end
    end

    function tok = tokens(extra)
        if nargin < 1 || isempty(extra); extra = struct(); end
        tok = extra;
        tok.name = case_name();
        tok.Uinf = sprintf('%.1f', resolve_uinf());
    end

    function out = expand_title(template, tok)
        if ~ischar(template)
            out = template;
            return;
        end
        out = expand_tokens(template, tok);
    end

    function out = expand_cell(cell_lines, tok)
        out = cell(size(cell_lines));
        for i = 1:numel(cell_lines)
            out{i} = expand_tokens(cell_lines{i}, tok);
        end
    end

    function out = expand_series_name(series, tok)
        out = expand_tokens(series.display_name, tok);
    end

    function out = expand_tokens(template, tok)
        out = template;
        if ~ischar(template) || ~isstruct(tok); return; end
        names = fieldnames(tok);
        for i = 1:numel(names)
            key = names{i};
            value = tok.(key);
            if ischar(value)
                text = value;
            elseif isnumeric(value) && isscalar(value)
                text = sprintf('%g', value);
            else
                text = '';
            end
            out = strrep(out, ['{' key '}'], text);
        end
    end

    function y_disp = cache_display_y(Y)
        if ~ismatrix(Y) || isempty(Y)
            error('tblR2:plot_core_products:InvalidCacheY', ...
                '缓存 Y 必须是非空矩阵。');
        end
        n_rows = size(Y, 1);
        y_col = Y(:, 1);
        d = diff(y_col);
        if isempty(d)
            h_y = 1;
        else
            h_y = median(abs(d), 'omitnan');
            if ~isfinite(h_y) || h_y <= 0; h_y = 1; end
        end
        y_disp = (1:n_rows)' .* h_y;
    end

    function value = onoff(flag)
        if flag; value = 'on'; else; value = 'off'; end
    end

    function role = source_role_for_job(job_name)
        raw_jobs = {'mean_turbulence', 'mean_profiles', 'loglaw', ...
            'loglaw_diagnostic', 'modern_clauser', 'friction', ...
            'cache_raw', 'phase_triple'};
        if any(strcmp(job_name, raw_jobs))
            role = 'raw';
        else
            role = 'postproc';
        end
    end
end
