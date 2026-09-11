function figs = plot_percolation_diagnostics(sweep1, out_dir)
%PLOT_PERCOLATION_DIAGNOSTICS Percolation curves with bootstrap CI and plateau.
%   sweep1  : the struct array saved by tools/research/run_r2_structure_diagnostics.m
%   out_dir : directory for PNG export; created if absent
%
%   One figure per smoothing variant, four panels:
%     (a) max cluster ratio vs alpha, with bootstrap CI and the plateau shaded
%     (b) component count vs alpha
%     (c) occupancy vs alpha
%     (d) susceptibility vs alpha (peak marks the percolation transition)
%   4- and 8-connectivity are overlaid so the connectivity comparison is direct.

if nargin < 2 || isempty(out_dir)
    out_dir = pwd;
end
if ~isfolder(out_dir)
    mkdir(out_dir);
end

figs = gobjects(numel(sweep1), 1);
colors = struct('c4', [0.00 0.45 0.74], 'c8', [0.85 0.33 0.10]);

for iv = 1:numel(sweep1)
    r = sweep1(iv).result;
    stab = sweep1(iv).stability;
    variant = sweep1(iv).variant;

    fig = figure('Name', sprintf('percolation_%s', variant), ...
        'Position', [80 80 1180 820], 'Color', 'w');
    figs(iv) = fig;

    panels = { ...
        'max_component_ratio', '最大簇占比 A_{max}/\SigmaA', 'a'; ...
        'n_components',        '连通域数量 N',                'b'; ...
        'occupancy',           '占据率',                      'c'; ...
        'susceptibility',      '簇尺寸二阶矩（逾渗敏感度）',  'd'};

    conns = unique(r.connectivity);
    for ip = 1:size(panels, 1)
        ax = subplot(2, 2, ip);
        hold(ax, 'on');
        field = panels{ip, 1};

        for ic = 1:numel(conns)
            conn = conns(ic);
            sel = find(r.connectivity == conn);
            [av, ord] = sort(r.alpha(sel));
            av = reshape(av, 1, []);   % force row: r.alpha is a column
                                        % post-fix, but this plot builds
                                        % row vectors (med/lo/hi) to match
            sel = sel(ord);

            med = zeros(1, numel(sel));
            lo  = zeros(1, numel(sel));
            hi  = zeros(1, numel(sel));
            for jj = 1:numel(sel)
                v = r.per_frame{sel(jj)}.(field);
                med(jj) = median(v, 'omitnan');
                lo(jj)  = quantile(v, 0.25);
                hi(jj)  = quantile(v, 0.75);
            end

            if conn == 4
                col = colors.c4;
            else
                col = colors.c8;
            end

            % Interquartile band across frames, then the median curve.
            fill(ax, [av fliplr(av)], [lo fliplr(hi)], col, ...
                'FaceAlpha', 0.12, 'EdgeColor', 'none', ...
                'HandleVisibility', 'off');
            plot(ax, av, med, '-o', 'Color', col, 'LineWidth', 1.6, ...
                'MarkerSize', 4.5, 'MarkerFaceColor', col, ...
                'DisplayName', sprintf('%d 邻域', conn));

            % On panel (a) add the bootstrap CI and shade the plateau.
            if strcmp(field, 'max_component_ratio')
                k = find([stab.connectivity] == conn, 1);
                if ~isempty(k)
                    bs = stab(k).stability;
                    errorbar(ax, stab(k).alphas, bs.median, ...
                        bs.median - bs.ci_lo, bs.ci_hi - bs.median, ...
                        'Color', col, 'LineStyle', 'none', ...
                        'LineWidth', 1.0, 'CapSize', 4, ...
                        'HandleVisibility', 'off');
                    if bs.stable_found
                        idx = bs.stable_idx;
                        xa = stab(k).alphas(idx);
                        yl = ylim(ax);
                        patch(ax, [min(xa) max(xa) max(xa) min(xa)], ...
                            [yl(1) yl(1) yl(2) yl(2)], col, ...
                            'FaceAlpha', 0.07, 'EdgeColor', col, ...
                            'LineStyle', '--', ...
                            'DisplayName', sprintf('%d 邻域稳定区', conn));
                    end
                end
            end
        end

        xlabel(ax, '\alpha');
        ylabel(ax, panels{ip, 2});
        title(ax, sprintf('(%s) %s', panels{ip, 3}, panels{ip, 2}));
        grid(ax, 'on');
        box(ax, 'on');
        if ip == 1
            legend(ax, 'Location', 'northeast', 'Box', 'off');
        end
    end

    sgtitle(sprintf('逾渗诊断  变体=%s  帧数=%d  阴影=帧间四分位距  误差棒=bootstrap 95%%CI', ...
        strrep(variant, '_', '\_'), r.n_frames), 'FontSize', 11);

    png = fullfile(out_dir, sprintf('09d_percolation_%s.png', variant));
    exportgraphics_compat(fig, png);
    fprintf('已导出 %s\n', png);
end
end

function exportgraphics_compat(fig, png)
% exportgraphics exists from R2020a; fall back to print on older releases.
try
    exportgraphics(fig, png, 'Resolution', 200);
catch
    print(fig, png, '-dpng', '-r200');
end
end
