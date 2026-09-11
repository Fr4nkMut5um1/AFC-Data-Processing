function [fU, fV] = plot_phase_averaged_maps(x_vec, y_vec, phase_data, Umean, Vmean, cx_mask, phase_bins_select, bin_centers_deg, cmap_div, U_clim, V_clim, visible)
%PLOT_PHASE_AVERAGED_MAPS Render compact phase-averaged fluctuation maps.
%   This helper only controls figure layout. The supplied phase_data and
%   color limits are used unchanged, so Section 3 numerical processing is
%   unaffected.

if nargin < 12 || isempty(visible)
    visible = 'on';
end

cx_vec = x_vec(cx_mask);
n_phase = numel(phase_bins_select);
if n_phase ~= 12
    error('tblR2:plot_phase_averaged_maps:PhaseCount', ...
        'The compact layout expects 12 displayed phase bins.');
end

% Pixel geometry is chosen from the physical x/y aspect ratio. This keeps
% the six rows close together without introducing the large blank bands that
% a tall tiledlayout creates for a slender streamwise field.
fig_w = 1100;
left_px = 88;
right_px = 88;
colorbar_px = 34;
column_gap_px = 28;
row_gap_px = 14;
title_px = 42;
top_px = 14;
bottom_px = 46;
axis_w = (fig_w - left_px - right_px - colorbar_px - column_gap_px) / 2;
data_aspect = max(eps, (max(cx_vec) - min(cx_vec)) / max(eps, (max(y_vec) - min(y_vec))));
axis_h = axis_w / data_aspect;
grid_h = 6 * axis_h + 5 * row_gap_px;
fig_h = ceil(title_px + top_px + grid_h + bottom_px);
grid_bottom = bottom_px;

        fU = local_make_figure(sprintf('Section3: phase-averaged U fluctuation (%d phases)', n_phase), ...
            fig_w, fig_h, visible, 'Phase-averaged streamwise velocity fluctuation, $\tilde{u}$ [m/s]');
        fV = local_make_figure(sprintf('Section3: phase-averaged V fluctuation (%d phases)', n_phase), ...
            fig_w, fig_h, visible, 'Phase-averaged wall-normal velocity fluctuation, $\tilde{v}$ [m/s]');

local_draw_grid(fU, x_vec, y_vec, phase_data.U_phase, Umean, cx_mask, ...
    phase_bins_select, bin_centers_deg, cmap_div, U_clim, 'U');
local_draw_grid(fV, x_vec, y_vec, phase_data.V_phase, Vmean, cx_mask, ...
    phase_bins_select, bin_centers_deg, cmap_div, V_clim, 'V');

    function f = local_make_figure(name, width, height, vis, overall_title)
        f = figure('Name', name, 'Position', [50 20 width height], 'Visible', vis, ...
            'Color', 'w');
        annotation(f, 'textbox', [0.06, 1 - (title_px - 4) / height, 0.86, (title_px - 4) / height], ...
            'String', overall_title, 'Interpreter', 'latex', 'FontName', 'Arial', ...
            'FontSize', 12, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', 'EdgeColor', 'none', 'Margin', 0);
    end

    function local_draw_grid(f, x_full, y_full, phase_field, mean_field, mask, bins, angles, cmap, clim_value, component)
        axes_handles = gobjects(numel(bins), 1);
        positions = cell(numel(bins), 1);
        for kk = 1:numel(bins)
            tile = [kk, kk + 6];
            if kk <= 6
                row = kk;
                col = 1;
            else
                row = kk - 6;
                col = 2;
            end
            pos = [left_px + (col - 1) * (axis_w + column_gap_px), ...
                grid_bottom + (6 - row) * (axis_h + row_gap_px), axis_w, axis_h];
            ax = axes('Parent', f, 'Units', 'pixels', 'Position', pos, ...
                'FontName', 'Arial', 'FontSize', 8, 'LineWidth', 0.6, ...
                'TickDir', 'out', 'Box', 'on', 'Layer', 'top');
            positions{kk} = pos;
            axes_handles(kk) = ax;
            field = squeeze(phase_field(bins(kk), :, :)) - mean_field;
            field = field(:, mask);
            contourf(ax, cx_vec, y_full, field, 40, 'LineStyle', 'none');
            set(ax, 'YDir', 'normal');
            colormap(ax, cmap);
            caxis(ax, [-clim_value, clim_value]);
            daspect(ax, [1 1 1]);
            title(ax, sprintf('\\phi = %d°', angles(kk)), 'Interpreter', 'tex', ...
                'FontName', 'Arial', 'FontSize', 9, 'FontWeight', 'normal', ...
                'Units', 'normalized', 'Position', [0.5 1.02 0]);
            if row == 6
                xlabel(ax, 'x [mm]', 'FontName', 'Arial', 'FontSize', 9);
            else
                set(ax, 'XTickLabel', []);
            end
            if col == 1
                ylabel(ax, 'y [mm]', 'FontName', 'Arial', 'FontSize', 9);
            else
                set(ax, 'YTickLabel', []);
            end
        end
        cb = colorbar(axes_handles(end), 'eastoutside');
        cb.Units = 'pixels';
        cb.FontName = 'Arial';
        cb.FontSize = 8;
        cb.LineWidth = 0.6;
        cb.Position = [fig_w - right_px + 8, grid_bottom + 8, 18, grid_h - 16];
        % colorbar() may resize its parent; restore the planned geometry.
        for kk = 1:numel(axes_handles)
            axes_handles(kk).Position = positions{kk};
        end
        annotation(f, 'textbox', [0.015, 0.012, 0.96, 0.02], ...
            'String', sprintf('Section 3 | %s component | phase bins: 0° to 330°', component), ...
            'Interpreter', 'none', 'FontName', 'Arial', 'FontSize', 8, ...
            'HorizontalAlignment', 'right', 'EdgeColor', 'none', 'Margin', 0);
    end
end
