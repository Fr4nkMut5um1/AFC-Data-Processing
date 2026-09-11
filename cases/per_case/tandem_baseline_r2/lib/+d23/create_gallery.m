function files = create_gallery(selection, ss_catalog, ctx, stats, ...
    detection_stats, cfg, run_dir, pod_file)
%CREATE_GALLERY Render selected frames and five fixed six-panel contact sheets.
if nargin < 8
    pod_file = '';
end
files = strings(0,1);
if ~cfg.execution.make_gallery
    return;
end
dpi = cfg.output.figure_dpi;
for i = find(selection.Selected).'
    row = selection(i, :);
    fields = d23.fluctuation_chunk(ctx, stats, cfg, ...
        double(row.FrameOrdinal), pod_file);
    up = squeeze(fields.up(1, :, :));
    normalized = up ./ detection_stats.u_rms_y;
    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [50 50 1500 500]);
    ax = axes(fig);
    imagesc(ax, ctx.x_mm, ctx.wall_y_mm, normalized);
    set(ax, 'YDir', 'normal');
    axis(ax, 'image');
    caxis(ax, cfg.output.field_clim);
    colormap(fig, d23.balance_colormap(cfg.output.field_colormap_levels));
    cb = colorbar(ax);
    cb.Label.String = 'u''/u_{rms}(y)';
    cb.Label.Interpreter = 'tex';
    xlabel(ax, 'x (mm)'); ylabel(ax, 'wall distance (mm)'); hold(ax, 'on');
    d23.draw_spatial_exclusion(ax, ctx);
    same_frame = ss_catalog.FrameOrdinal == row.FrameOrdinal & ...
        ss_catalog.IsSS3;
    frame_ss = ss_catalog(same_frame, :);
    frame_ss = sortrows(frame_ss, 'Connectivity', 'descend');
    for j = 1:height(frame_ss)
        if frame_ss.Connectivity(j) == 8
            style = '-'; color = [0 0 0]; width = 1.5;
        else
            style = '--'; color = [0 0.65 0.2]; width = 1.8;
        end
        if frame_ss.IsCensored(j)
            style = ':'; color = [0.35 0.35 0.35];
        end
        if frame_ss.Connectivity(j) == 8 && ...
                frame_ss.ComponentID(j) == row.ComponentID && ...
                frame_ss.Sign(j) == row.ActualSign
            color = [1 1 0]; width = 2.5;
        end
        rectangle(ax, 'Position', [frame_ss.XMin_mm(j), frame_ss.YMin_mm(j), ...
            frame_ss.XMax_mm(j)-frame_ss.XMin_mm(j), ...
            frame_ss.YMax_mm(j)-frame_ss.YMin_mm(j)], ...
            'EdgeColor', color, 'LineStyle', style, 'LineWidth', width);
    end
    h8 = plot(ax, NaN, NaN, 'k-', 'LineWidth', 1.5);
    h4 = plot(ax, NaN, NaN, '--', 'Color', [0 0.65 0.2], 'LineWidth', 1.8);
    hsel = plot(ax, NaN, NaN, '-', 'Color', [1 1 0], 'LineWidth', 2.5);
    legend(ax, [h8 h4 hsel], {'8-neighbor SS','4-neighbor SS', ...
        'selected 8-neighbor SS'}, 'Location', 'southoutside', ...
        'Orientation', 'horizontal');
    title(ax, sprintf(['%s | slot %02d | frame %d | sign %+d | tier %d | ' ...
        'Lx/delta=%.2f | %s'], detection_stats.field_source, row.SlotID, ...
        row.FrameID, row.ActualSign, ...
        row.ActualTier, row.Lx_over_delta, char(row.SelectionReason)), ...
        'Interpreter', 'none');
    stem_name = sprintf('slot_%02d_frame_%05d', row.SlotID, row.FrameID);
    png_file = fullfile(run_dir, 'png', 'gallery', [stem_name '.png']);
    fig_file = fullfile(run_dir, 'fig', [stem_name '.fig']);
    savefig(fig, fig_file);
    exportgraphics(fig, png_file, 'Resolution', dpi);
    close(fig);
    files(end+1,1) = string(png_file);
end

for b = 1:5
    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [30 30 1500 520]);
    tiledlayout(fig, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    rows = find(selection.TimeBin == b);
    for j = 1:numel(rows)
        nexttile;
        row = selection(rows(j), :);
        if row.Selected
            pattern = sprintf('slot_%02d_frame_%05d.png', row.SlotID, row.FrameID);
            image_file = fullfile(run_dir, 'png', 'gallery', pattern);
            image(imread(image_file)); axis image off;
        else
            axis off;
        text(0.5, 0.5, sprintf('req %+d/T%d\nno unused complete SS object', ...
                row.RequestedSign, row.RequestedTier), ...
                'HorizontalAlignment', 'center');
        end
    end
    png_file = fullfile(run_dir, 'png', 'contact_sheets', ...
        sprintf('contact_sheet_timebin_%d.png', b));
    fig_file = fullfile(run_dir, 'fig', ...
        sprintf('contact_sheet_timebin_%d.fig', b));
    savefig(fig, fig_file);
    exportgraphics(fig, png_file, 'Resolution', dpi);
    close(fig);
    files(end+1,1) = string(png_file);
end
end
