function plot_structure_preview(cache_file, cfg, stats, mean_bl, sel)
%PLOT_STRUCTURE_PREVIEW 把 3 张"代表帧"当场画出来给用户预览。
%   ⚠ 只显示、不保存：不写任何 MAT、PNG/FIG 文件，因此不会影响已算好的结果。
%   三个面板（1×3）：
%     ① 含 VLSM 的帧 —— 底图是 u'/u_rms 归一化脉动云图，只框出 VLSM；
%     ② 只有 LSM 的帧 —— 只框出 LSM；
%     ③ 没有大结构的帧 —— 不加框，图上注明"无 LSM/VLSM"。
%   输入 sel 由 tblR2.select_structure_preview_frames 得到（含三个 frame_id 和结构行）。

J = size(stats.X, 1);
I = size(stats.X, 2);
y_wall = mean_bl.wall_distance_mm;                       % 每点离壁面的距离（mm）
x_mm = stats.X(1, :);                                    % 流向坐标（mm）
y_mm = y_wall(:, 1);                                     % 法向坐标 = 离壁距离（mm）

% 与正式结构识别保持一致的分析域：有效数据 → 去掉流向边缘/顶部（可信域）。
delta_grid = interp1(mean_bl.boundary_layer.x, ...
    mean_bl.boundary_layer.delta99, stats.X, 'linear', NaN);
valid_mask = stats.accepted_mask & isfinite(delta_grid) & delta_grid > 0;
domain_mask = tblR2.trusted_domain_mask(valid_mask, y_wall, ...
    cfg.structures.trusted_domain);

% —— 开一个预览图窗（只显示，随便关掉，不落盘）——
f = figure('Name', 'Section 4 代表帧预览（VLSM / 仅 LSM / 无大结构）', ...
    'NumberTitle', 'off', 'Color', 'w', 'Position', [60 60 2100 720], ...
    'DefaultAxesFontName', 'Arial', 'DefaultAxesFontSize', 10, ...
    'DefaultTextFontName', 'Arial', 'DefaultTextFontSize', 10);
layout = tiledlayout(f, 1, 3, 'TileSpacing', 'compact', 'Padding', 'loose');
layout.Title.String = 'Section 4 代表帧预览：只显示预览，不写入任何结果文件';
layout.Title.FontWeight = 'bold';

keys = {'vlsm', 'lsm', 'none'};
for k = 1:3
    key = keys{k};
    ax = nexttile(layout);
    e = sel.(key);
    if isempty(e.frame_id)
        % 该类型没有可用的帧：放个说明文字占位。
        text(ax, 0.5, 0.5, [panel_head(key) sprintf('\n未找到符合条件的帧')], ...
            'Units', 'normalized', 'HorizontalAlignment', 'center', ...
            'FontSize', 10);
        axis(ax, 'off');
        continue;
    end
    % 从后处理缓存读这一帧的原始速度，减去该帧对应的平均场 → 脉动 u'。
    chunk = tblR2.read_cache_chunk(cache_file, [e.frame_id], 1:J, 1:I, ...
        'raw', stats, []);
    U_raw = squeeze(chunk.U(1, :, :));
    sample_valid = squeeze(chunk.sampleValid(1, :, :));
    [mean_U, ~] = mean_field_for_frame(stats, e.frame_id);
    ok = domain_mask & sample_valid & isfinite(U_raw) & isfinite(mean_U);
    u_total = U_raw - mean_U;
    u_total(~ok) = NaN;
    normalized = double(u_total) ./ double(stats.u_rms);   % u'/u_rms：和正式结构图同一个量

    % 画归一化脉动云图（对称色标）。
    draw_preview_cloud(ax, x_mm, y_mm, normalized, cfg);

    % 按约定只框"这一类型"的结构。
    if strcmp(key, 'none')
        text(ax, 0.02, 0.98, '本帧无 LSM / VLSM（没有大尺度结构）', ...
            'Units', 'normalized', 'VerticalAlignment', 'top', 'FontSize', 9);
    else
        hold(ax, 'on');
        for ir = 1:height(e.structures)
            rectangle(ax, 'Position', [e.structures.XMin_mm(ir), ...
                e.structures.YMin_mm(ir), e.structures.XMax_mm(ir) - ...
                e.structures.XMin_mm(ir), e.structures.YMax_mm(ir) - ...
                e.structures.YMin_mm(ir)], ...
                'EdgeColor', 'k', 'LineWidth', 2);
        end
        hold(ax, 'off');
    end
    title(ax, panel_title_str(key, e), 'Interpreter', 'none');
end
drawnow;
fprintf('[代表帧预览] 预览图已显示（1×3 面板：VLSM / 仅 LSM / 无大结构），只显示未保存。\n');
end

% ==================== 下面都是本函数的"小帮手" ====================

function [mean_U, mean_V] = mean_field_for_frame(stats, frame_id)
% 取这一帧对应的平均场：有"按重复分段"的平均就用分段平均，否则用全区平均。
if isfield(stats, 'repeat_means') && ~isempty(stats.repeat_means) && ...
        isfield(stats, 'repeat_boundaries') && ~isempty(stats.repeat_boundaries)
    rep = 1 + nnz(frame_id > stats.repeat_boundaries(:)');
    mean_U = squeeze(stats.repeat_means(1, rep, :, :));
    mean_V = squeeze(stats.repeat_means(2, rep, :, :));
else
    mean_U = squeeze(stats.Uavex);
    mean_V = squeeze(stats.Vavex);
end
end

function draw_preview_cloud(ax, x_mm, y_mm, values, cfg)
% 画归一化脉动云图：红-白-蓝平衡色图（=ocean/balance），色标以 0 为中心、
% 上下限绝对值相等；并按物理尺寸固定轴比例（x 轴 1 mm 长度 = y 轴 1 mm 长度）。
values(~isfinite(values)) = NaN;
finite_values = values(isfinite(values));
if numel(finite_values) < 4
    text(ax, 0.5, 0.5, '本帧数据不足，无法绘制。', ...
        'Units', 'normalized', 'HorizontalAlignment', 'center');
    axis(ax, 'off');
    return;
end
contourf(ax, x_mm, y_mm, values, 60, 'LineStyle', 'none');
axis(ax, 'tight');
set(ax, 'YDir', 'normal');
% 对称色标：以 0 为中心，上下限绝对值相等（稳健分位数，与正式图一致）。
probability = [0.005 0.995];
gp = tblR2.figures_global(cfg, 'robust_color_quantiles');
if ~isempty(gp) && isnumeric(gp) && numel(gp) == 2
    probability = double(reshape(gp, 1, 2));
end
clim(ax, tblR2.viz.robust_limits(finite_values, 'balanced', probability));
% 红-白-蓝对称发散色图（ocean/balance/coolwarm 为同一张图）。
colormap(ax, tblR2.viz.resolve_case_colormap('balance', 256));
    cb = colorbar(ax, 'eastoutside');
    cb.FontSize = 9;
    cb.Box = 'on';
xlabel(ax, 'x (mm)');
ylabel(ax, '离壁距离 (mm)');
    tblR2.viz.apply_fov_aspect(ax, cfg);   % 物理 1:1：x 轴 1 mm = y 轴 1 mm
    ax.FontName = 'Arial';
    ax.FontSize = 10;
    ax.LineWidth = 0.8;
    ax.TickDir = 'out';
    ax.Box = 'on';
end

function s = panel_head(key)
% 每个面板的短标题。
switch key
    case 'vlsm'; s = '代表帧 1：含 VLSM（只框 VLSM）';
    case 'lsm';  s = '代表帧 2：仅有 LSM（只框 LSM）';
    otherwise;   s = '代表帧 3：无 LSM/VLSM（无大结构）';
end
end

function s = panel_title_str(key, e)
% 面板标题：类型 + 帧号 + 结构个数 + 最长结构长度。
if isempty(e.frame_id)
    s = panel_head(key);
    return;
end
if strcmp(key, 'vlsm')
    s = sprintf('%s｜第 %d 帧｜VLSM %d 个｜最长 Lx/δ=%.2f', ...
        panel_head(key), e.frame_id, e.count, e.max_length_over_delta);
elseif strcmp(key, 'lsm')
    s = sprintf('%s｜第 %d 帧｜LSM %d 个｜最长 Lx/δ=%.2f', ...
        panel_head(key), e.frame_id, e.count, e.max_length_over_delta);
else
    s = sprintf('%s｜第 %d 帧｜该帧结构共 %d 个（均未达 LSM 尺度）', ...
        panel_head(key), e.frame_id, e.count);
end
end
