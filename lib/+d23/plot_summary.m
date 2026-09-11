function files = plot_summary(ctx, stats, detection_stats, collected, ...
    connectivity, spectra, cfg, run_dir)
%PLOT_SUMMARY Create method/geometry, counts, spectra, and energy summaries.
files = strings(0,1);
dpi = cfg.output.figure_dpi;

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [50 50 1450 440]);
tiledlayout(fig, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile;
plot(ctx.reference_profile.MeanU_m_s, ...
    ctx.reference_profile.WallDistance_mm / ctx.delta99_mm, 'k-', 'LineWidth', 1.5);
hold on;
xline(ctx.profile_target_m_s, '--r', '0.99U_e');
yline(1, ':k', '\delta_{99}');
xlabel('\overline{U} (m s^{-1})'); ylabel('y/\delta_{99}'); grid on;
title(sprintf('Reference profile | delta99 = %.3f mm', ctx.delta99_mm), ...
    'Interpreter', 'none');
nexttile;
plot(detection_stats.postproc_same_domain_u_rms_y / ctx.u_tau_m_s, ...
    ctx.wall_y_mm / ctx.delta99_mm, 'k--', 'LineWidth', 1.4);
hold on;
plot(detection_stats.u_rms_y / ctx.u_tau_m_s, ...
    ctx.wall_y_mm / ctx.delta99_mm, 'r-', 'LineWidth', 1.6);
yline(ctx.wall_y_mm(ctx.lower_spectrum_row) / ctx.delta99_mm, '--k', 'lower row');
yline(ctx.wall_y_mm(ctx.upper_spectrum_row) / ctx.delta99_mm, ':k', 'upper row');
xlabel('u_{rms}(y)/u_\tau'); ylabel('y/\delta_{99}'); grid on;
legend({'PostProc on active domain', detection_stats.field_source}, ...
    'Location', 'best', 'Interpreter', 'none');
title(sprintf('Re_tau = %.1f | u_tau = %.6f m s^{-1}', ...
    ctx.Re_tau, ctx.u_tau_m_s), 'Interpreter', 'none');
nexttile;
plot(detection_stats.rms_ratio_to_postproc_same_domain_y, ...
    ctx.wall_y_mm / ctx.delta99_mm, 'm-', 'LineWidth', 1.6);
xline(1, '--k'); grid on;
xlabel('active / PostProc same-domain u_{rms}'); ylabel('y/\delta_{99}');
title(sprintf('%s | POD rank %d | joint E=%.4f', ...
    detection_stats.field_source, detection_stats.pod_selected_rank, ...
    detection_stats.pod_joint_energy_retained_fraction), 'Interpreter', 'none');
stem = fullfile(run_dir, 'png', 'summary_statistics');
savefig(fig, fullfile(run_dir, 'fig', 'summary_statistics.fig'));
exportgraphics(fig, [stem '.png'], 'Resolution', dpi);
close(fig);
files(end+1,1) = string([stem '.png']);

thresholds = cfg.detection.length_thresholds;
ss = collected.ss_catalog;
complete_counts = zeros(2, numel(thresholds));
censored_counts = zeros(2, numel(thresholds));
for c = 1:2
    connectivity_value = cfg.detection.connectivities(c);
    selected_conn = ss.Connectivity == connectivity_value;
    flags = {ss.IsSS3, ss.IsSS3p8, ss.IsSS4p5};
    for k = 1:numel(thresholds)
        complete_counts(c,k) = nnz(selected_conn & flags{k} & ~ss.IsCensored);
        censored_counts(c,k) = nnz(selected_conn & flags{k} & ss.IsCensored);
    end
end
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [50 50 1100 440]);
tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile;
bar(thresholds, complete_counts.'); grid on;
xlabel('strict L_x/\delta threshold'); ylabel('complete SS count');
legend({'8-neighbor','4-neighbor'}, 'Location', 'best');
title('Complete superstructures');
nexttile;
bar(thresholds, censored_counts.'); grid on;
xlabel('strict L_x/\delta threshold'); ylabel('censored SS count');
legend({'8-neighbor','4-neighbor'}, 'Location', 'best');
title('Boundary-censored superstructures');
if ~any(censored_counts, 'all')
    ylim([0 1]);
end
stem = fullfile(run_dir, 'png', 'summary_connectivity_counts');
savefig(fig, fullfile(run_dir, 'fig', 'summary_connectivity_counts.fig'));
exportgraphics(fig, [stem '.png'], 'Resolution', dpi);
close(fig);
files(end+1,1) = string([stem '.png']);

lengths = d23.connectivity_length_distribution(ss);
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [50 50 1100 440]);
tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile;
rows8 = lengths.table.Connectivity == 8;
rows4 = lengths.table.Connectivity == 4;
stairs(lengths.edges, [lengths.table.Probability(rows8); 0], ...
    'LineWidth', 1.6); hold on;
stairs(lengths.edges, [lengths.table.Probability(rows4); 0], ...
    'LineWidth', 1.6);
grid on; xlabel('Lx/delta'); ylabel('probability per 0.25 bin');
legend({'8-neighbor','4-neighbor'}, 'Location', 'best');
title('Complete-SS length distribution');
nexttile;
plot_survival(lengths.values8, 'LineWidth', 1.6); hold on;
plot_survival(lengths.values4, 'LineWidth', 1.6);
grid on; set(gca, 'YScale', 'log');
xlabel('Lx/delta'); ylabel('P(length >= Lx/delta)');
legend({'8-neighbor','4-neighbor'}, 'Location', 'best');
title('Empirical length-tail comparison');
stem = fullfile(run_dir, 'png', 'summary_connectivity_length_distribution');
savefig(fig, fullfile(run_dir, 'fig', ...
    'summary_connectivity_length_distribution.fig'));
exportgraphics(fig, [stem '.png'], 'Resolution', dpi);
close(fig);
files(end+1,1) = string([stem '.png']);

comparison = connectivity.summary_table;
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [50 50 1400 440]);
tiledlayout(fig, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile;
bar(comparison.LengthThreshold, double([comparison.Only8, comparison.Both, ...
    comparison.Only4]), 'stacked'); grid on;
xlabel('strict L_x/\delta threshold'); ylabel('frame-sign units');
legend({'only 8','both','only 4'}, 'Location', 'best');
title('8/4 detection agreement');
nexttile;
plot(comparison.LengthThreshold, comparison.FrameSignJaccard, ...
    'ko-', 'LineWidth', 1.6, 'MarkerFaceColor', 'k');
ylim([0 1]); grid on;
xlabel('strict L_x/\delta threshold'); ylabel('frame-sign Jaccard');
title('Occurrence overlap');
nexttile;
plot(comparison.LengthThreshold, comparison.MedianBBoxIoU, ...
    'bo-', 'LineWidth', 1.6, 'MarkerFaceColor', 'b'); hold on;
plot(comparison.LengthThreshold, comparison.MeanBBoxIoU, ...
    'rs--', 'LineWidth', 1.4, 'MarkerFaceColor', 'r');
ylim([0 1]); grid on;
xlabel('strict L_x/\delta threshold'); ylabel('paired bounding-box IoU');
legend({'median','mean'}, 'Location', 'best');
title('Geometry agreement when both detect');
stem = fullfile(run_dir, 'png', 'summary_connectivity_agreement');
savefig(fig, fullfile(run_dir, 'fig', 'summary_connectivity_agreement.fig'));
exportgraphics(fig, [stem '.png'], 'Resolution', dpi);
close(fig);
files(end+1,1) = string([stem '.png']);

if ~isempty(spectra.spectra_table)
    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [50 50 1250 700]);
    tiledlayout(fig, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    for r = 1:2
        for k = 1:3
            nexttile;
            rows = spectra.spectra_table.LengthThreshold == thresholds(k) & ...
                spectra.spectra_table.RowLabel == spectra.row_labels(r);
            part = spectra.spectra_table(rows, :);
            semilogx(part.LambdaX_over_delta, part.SSPremultiplied, ...
                'r-', 'LineWidth', 1.4); hold on;
            semilogx(part.LambdaX_over_delta, part.NoSSPremultiplied, ...
                'k--', 'LineWidth', 1.4);
            xline(3, ':b'); grid on;
            xlabel('\lambda_x/\delta'); ylabel('f\Phi_{uu}');
            if r == 1
                row_title = 'lower criterion row';
            else
                row_title = 'upper criterion row';
            end
            title(sprintf('%s | Lx/delta > %.1f | Nmax = %d', ...
                row_title, thresholds(k), max(part.EnsembleCount)), ...
                'Interpreter', 'none');
            if r == 1 && k == 1
                legend({'SS','matched noSS'}, 'Location', 'best');
            end
        end
    end
    stem = fullfile(run_dir, 'png', 'summary_conditional_spectra');
    savefig(fig, fullfile(run_dir, 'fig', 'summary_conditional_spectra.fig'));
    exportgraphics(fig, [stem '.png'], 'Resolution', dpi);
    close(fig);
    files(end+1,1) = string([stem '.png']);

    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [50 50 900 450]);
    energy = spectra.energy_table;
    labels = strcat(energy.RowLabel, " >", string(energy.LengthThreshold));
    bar(energy.SS_to_NoSS_LargeScaleRatio);
    yline(1, '--k'); grid on;
    xticks(1:height(energy)); xticklabels(labels); xtickangle(35);
    set(gca, 'TickLabelInterpreter', 'none');
    ylabel('SS / matched-noSS energy, \lambda_x/\delta \geq 3');
    title('Descriptive large-scale conditional energy ratio');
    stem = fullfile(run_dir, 'png', 'summary_large_scale_energy');
    savefig(fig, fullfile(run_dir, 'fig', 'summary_large_scale_energy.fig'));
    exportgraphics(fig, [stem '.png'], 'Resolution', dpi);
    close(fig);
    files(end+1,1) = string([stem '.png']);
end
end

function plot_survival(values, varargin)
values = sort(double(values(:)), 'ascend');
if isempty(values)
    plot(NaN, NaN, varargin{:});
    return;
end
survival = (numel(values):-1:1).' / numel(values);
stairs(values, survival, varargin{:});
end
