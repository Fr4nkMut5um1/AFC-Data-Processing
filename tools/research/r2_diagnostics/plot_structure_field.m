function info = plot_structure_field(ax, ctx, u_fluct, T, opts)
%PLOT_STRUCTURE_FIELD 瞬时流向脉动场 contourf + LSM/VLSM 包围盒，唯一一处。
%
% 绘图用 contourf，不用 pcolor/scatter：项目约定（commit 1d63a31）。contourf 在
% 掩膜外的 NaN 区域留空、保持场的拓扑；散点渲染会把实测速度场画成一堆圆点。
%
% 框线约定（与既有 24 帧对照图一致，不要改，否则新旧图不可并读）：
%   蓝色虚线  = IsLSM 且非 VLSM
%   红色实线加粗 = IsVLSM（后画，保证与 LSM 重叠时可见）
% VLSM 判据 Lx/d99 >= 3 严于 LSM 判据 >= 1，所以 VLSM 恒为 LSM 子集，一个结构只
% 会画一种框。标题里的 "LSM n / VLSM m" 用的是 sum(IsLSM)/sum(IsVLSM)，因此
% 画出的蓝框数 = n - m。返回值里给出实际画出的框数，供调用方核对。
%
% 输入
%   ax       : 目标坐标轴
%   ctx      : tblR2.vlsmpod.prepare_context 的输出（要 X_mm、Y_wall_mm）
%   u_fluct  : [J x I] 流向脉动场，掩膜外 NaN
%   T        : structures 表，需要 IsLSM/IsVLSM/XMin_mm/XMax_mm/YMin_mm/YMax_mm
%   opts     : 结构体
%              .levels      contourf 等值线级别（必需）
%              .clim_val    色标半幅，caxis 取 [-clim_val clim_val]（必需）
%              .show_xlabel 是否画 x 轴标签，默认 true
%
% 输出 info 结构体
%   .n_lsm / .n_vlsm            表里的计数
%   .n_lsm_boxes / .n_vlsm_boxes 实际画出的框数
%   .n_degenerate_boxes         因宽或高为 0 被跳过的框数（应恒为 0，非 0 说明
%                               几何列有问题，不要静默忽略）

if ~isfield(opts, 'levels') || isempty(opts.levels)
    error('r2diag:plot_structure_field:MissingLevels', 'opts.levels 必需。');
end
if ~isfield(opts, 'clim_val') || isempty(opts.clim_val)
    error('r2diag:plot_structure_field:MissingClim', 'opts.clim_val 必需。');
end
show_xlabel = true;
if isfield(opts, 'show_xlabel') && ~isempty(opts.show_xlabel)
    show_xlabel = logical(opts.show_xlabel);
end

contourf(ax, ctx.X_mm, ctx.Y_wall_mm, u_fluct, opts.levels, 'LineStyle', 'none');
colormap(ax, blue_white_red(256));
caxis(ax, [-opts.clim_val opts.clim_val]);
hold(ax, 'on');

info = struct('n_lsm', 0, 'n_vlsm', 0, 'n_lsm_boxes', 0, ...
    'n_vlsm_boxes', 0, 'n_degenerate_boxes', 0);
if ~isempty(T) && height(T) > 0
    info.n_lsm = sum(T.IsLSM);
    info.n_vlsm = sum(T.IsVLSM);
    [info.n_lsm_boxes, d1] = draw_class(ax, T, T.IsLSM & ~T.IsVLSM, ...
        [0.10 0.35 0.95], '--', 1.0);
    [info.n_vlsm_boxes, d2] = draw_class(ax, T, T.IsVLSM, ...
        [0.90 0.05 0.05], '-', 1.8);
    info.n_degenerate_boxes = d1 + d2;
end

axis(ax, 'tight');
set(ax, 'YDir', 'normal', 'FontSize', 7, 'TickDir', 'out', 'Layer', 'top');
if show_xlabel
    xlabel(ax, 'x (mm)', 'FontSize', 8);
end
ylabel(ax, 'y_{wall} (mm)', 'FontSize', 8);
cb = colorbar(ax);
ylabel(cb, "u' (m/s)", 'FontSize', 8);
set(cb, 'FontSize', 7);
end

% =========================================================================
function [n_drawn, n_degenerate] = draw_class(ax, T, mask, color, style, lw)
idx = find(mask);
n_drawn = 0;
n_degenerate = 0;
for i = 1:numel(idx)
    w = T.XMax_mm(idx(i)) - T.XMin_mm(idx(i));
    h = T.YMax_mm(idx(i)) - T.YMin_mm(idx(i));
    if w <= 0 || h <= 0
        n_degenerate = n_degenerate + 1;
        continue;
    end
    rectangle(ax, 'Position', ...
        [T.XMin_mm(idx(i)) T.YMin_mm(idx(i)) w h], ...
        'EdgeColor', color, 'LineStyle', style, 'LineWidth', lw);
    n_drawn = n_drawn + 1;
end
end

% =========================================================================
function cmap = blue_white_red(n)
half = floor(n / 2);
blue = [linspace(0, 1, half)', linspace(0, 1, half)', ones(half, 1)];
red = [ones(half, 1), linspace(1, 0, half)', linspace(1, 0, half)'];
if mod(n, 2) == 1
    cmap = [blue; 1 1 1; red];
else
    cmap = [blue; red];
end
end
