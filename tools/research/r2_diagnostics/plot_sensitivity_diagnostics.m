function figs = plot_sensitivity_diagnostics(sweep2, out_dir)
%PLOT_SENSITIVITY_DIAGNOSTICS Response surfaces for the preprocessing sweep.
%   sweep2  : struct saved by tools/research/run_r2_structure_diagnostics.m
%   out_dir : directory for PNG export
%
%   Figure 1  main effects: each swept factor vs the fragmentation and
%             merging diagnostics, marginalized over the other factors.
%   Figure 2  sigma x closing response surface at the production seed_alpha
%             and hole budget, separately for 4- and 8-connectivity, which is
%             the interaction most likely to drive over/under-segmentation.

if nargin < 2 || isempty(out_dir)
    out_dir = pwd;
end
if ~isfolder(out_dir)
    mkdir(out_dir);
end

% Collapse each combination's per-frame vectors to a median.
n = numel(sweep2.per_frame);
metrics = {'n_structures', 'median_area', 'tail_area_share', ...
    'p95_aspect_ratio', 'rejected_boundary', 'vlsm_count', ...
    'small_component_fraction', 'occupancy'};
M = struct();
for im = 1:numel(metrics)
    M.(metrics{im}) = nan(n, 1);
end
for j = 1:n
    f = sweep2.per_frame{j};
    for im = 1:numel(metrics)
        M.(metrics{im})(j) = median(f.(metrics{im}), 'omitnan');
    end
end

factors = {'sigma_cells', '\sigma (网格点)'; ...
           'seed_alpha',  'seed \alpha'; ...
           'closing_radius', '闭运算半径'; ...
           'hole_pixels', '孔洞上限 (px)'};
show = {'n_structures', '结构数（升高=碎化）'; ...
        'median_area',  '面积中位数（降低=碎化）'; ...
        'tail_area_share', '大结构面积占比（变薄=碎化）'; ...
        'p95_aspect_ratio', '长宽比 P95（膨胀=噪声桥）'};

conns = unique(sweep2.connectivity);
colors = [0.00 0.45 0.74; 0.85 0.33 0.10];

%% Figure 1 — main effects
fig1 = figure('Name', 'sensitivity_main_effects', ...
    'Position', [60 60 1280 900], 'Color', 'w');
ip = 0;
for ifa = 1:size(factors, 1)
    for ish = 1:size(show, 1)
        ip = ip + 1;
        ax = subplot(size(factors, 1), size(show, 1), ip);
        hold(ax, 'on');
        fac = sweep2.(factors{ifa, 1});
        levels = unique(fac);
        for ic = 1:numel(conns)
            y = nan(1, numel(levels));
            for il = 1:numel(levels)
                sel = fac == levels(il) & sweep2.connectivity == conns(ic);
                y(il) = median(M.(show{ish, 1})(sel), 'omitnan');
            end
            plot(ax, levels, y, '-o', 'Color', colors(ic, :), ...
                'LineWidth', 1.5, 'MarkerFaceColor', colors(ic, :), ...
                'MarkerSize', 4, 'DisplayName', sprintf('%d 邻域', conns(ic)));
        end
        grid(ax, 'on'); box(ax, 'on');
        if ip <= size(show, 1)
            title(ax, show{ish, 2}, 'FontSize', 9);
        end
        if ish == 1
            ylabel(ax, factors{ifa, 2}, 'FontWeight', 'bold');
        end
        if ifa == size(factors, 1)
            xlabel(ax, factors{ifa, 2});
        end
        if ip == 1
            legend(ax, 'Location', 'best', 'Box', 'off', 'FontSize', 7);
        end
    end
end
sgtitle(sprintf(['预处理/形态学主效应   \\alpha 锁定=%.2f   帧数=%d   ' ...
    '每点为其余因子的中位数'], sweep2.production_alpha, sweep2.n_frames), ...
    'FontSize', 11);
png1 = fullfile(out_dir, '09d_sensitivity_main_effects.png');
export_compat(fig1, png1);
fprintf('已导出 %s\n', png1);

%% Figure 2 — sigma x closing surface at production seed/hole
seed_ref = 0.70;
hole_ref = 64;
if ~any(sweep2.seed_alpha == seed_ref)
    seed_ref = median(unique(sweep2.seed_alpha));
end
if ~any(sweep2.hole_pixels == hole_ref)
    hole_ref = median(unique(sweep2.hole_pixels));
end

sig_levels = unique(sweep2.sigma_cells);
clo_levels = unique(sweep2.closing_radius);
surf_metrics = {'n_structures', '结构数'; 'median_area', '面积中位数'; ...
    'tail_area_share', '大结构面积占比'; 'vlsm_count', 'VLSM 数'};

fig2 = figure('Name', 'sensitivity_sigma_closing', ...
    'Position', [60 60 1280 640], 'Color', 'w');
ip = 0;
for ic = 1:numel(conns)
    for ism = 1:size(surf_metrics, 1)
        ip = ip + 1;
        ax = subplot(numel(conns), size(surf_metrics, 1), ip);
        Z = nan(numel(sig_levels), numel(clo_levels));
        for a = 1:numel(sig_levels)
            for b = 1:numel(clo_levels)
                sel = sweep2.sigma_cells == sig_levels(a) & ...
                      sweep2.closing_radius == clo_levels(b) & ...
                      sweep2.seed_alpha == seed_ref & ...
                      sweep2.hole_pixels == hole_ref & ...
                      sweep2.connectivity == conns(ic);
                if any(sel)
                    Z(a, b) = median(M.(surf_metrics{ism, 1})(sel), 'omitnan');
                end
            end
        end
        imagesc(ax, clo_levels, sig_levels, Z);
        set(ax, 'YDir', 'normal');
        colorbar(ax);
        xlabel(ax, '闭运算半径');
        ylabel(ax, '\sigma');
        title(ax, sprintf('%d 邻域: %s', conns(ic), surf_metrics{ism, 2}), ...
            'FontSize', 9);
        xticks(ax, clo_levels);
        yticks(ax, sig_levels);
    end
end
sgtitle(sprintf('\\sigma \\times 闭运算响应面   seed \\alpha=%.2f   孔洞=%d px   \\alpha=%.2f', ...
    seed_ref, hole_ref, sweep2.production_alpha), 'FontSize', 11);
png2 = fullfile(out_dir, '09d_sensitivity_sigma_closing.png');
export_compat(fig2, png2);
fprintf('已导出 %s\n', png2);

figs = [fig1; fig2];
end

function export_compat(fig, png)
try
    exportgraphics(fig, png, 'Resolution', 200);
catch
    print(fig, png, '-dpng', '-r200');
end
end
