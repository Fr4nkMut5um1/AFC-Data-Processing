function ctx = prepare_context(cfg, stats, mean_bl, resolved)
%PREPARE_CONTEXT 组装结构识别所需的几何上下文，唯一一处。
%
% 原先这 12 行几何组装（Y_wall_mm / delta_grid / valid_mask / analysis_domain_mask
% / dx / dy）在 4 个入口脚本里各有一份逐字副本。它们必须完全一致，否则 POD 与
% Gaussian 分支就不是在同一个空间域上比较。
%
% 输入
%   cfg      : case 配置（需要 nu；u_tau 从 mean_bl 取）
%   stats    : statistics 结果（需要 X、u_rms、accepted_mask、n_frames、
%              repeat_means/repeat_boundaries 或 Uavex/Vavex）
%   mean_bl  : mean_bl 结果（需要 wall_distance_mm、boundary_layer、normalization）
%   resolved : tblR2.vlsmpod.resolve_settings 的输出
%
% 输出 ctx 结构体
%   .J, .I                  网格尺寸
%   .X_mm                   流向坐标（= stats.X）
%   .Y_wall_mm              壁面法向距离（= mean_bl.wall_distance_mm）
%   .delta_grid             逐点 delta99（按 x 插值到全网格）
%   .u_rms                  局部归一化尺度（= stats.u_rms）
%   .valid_mask             accepted_mask 且 delta99 有效
%   .analysis_domain_mask   再裁掉 trusted_domain 声明的边界
%   .dx_mm, .dy_mm          网格间距
%   .u_tau, .nu             壁面单位换算量（wall-attached 分类用）
%   .dt_s                   采样间隔（时间追踪用）
%   .Uavex                  平均流向速度（时间追踪的对流速度来源）
%   .stats, .mean_bl, .cfg  原样保留，供下游取其他字段

required_stats = {'X', 'u_rms', 'accepted_mask'};
missing = required_stats(~isfield(stats, required_stats));
if ~isempty(missing)
    error('tblR2:vlsmpod:prepare_context:MissingStats', ...
        'stats 缺少字段：%s。', strjoin(missing, ', '));
end
if ~isfield(mean_bl, 'wall_distance_mm') || ~isfield(mean_bl, 'boundary_layer')
    error('tblR2:vlsmpod:prepare_context:MissingMeanBl', ...
        'mean_bl 缺少 wall_distance_mm 或 boundary_layer。');
end

ctx = struct();
ctx.J = size(stats.X, 1);
ctx.I = size(stats.X, 2);
ctx.X_mm = stats.X;
ctx.Y_wall_mm = mean_bl.wall_distance_mm;
ctx.u_rms = stats.u_rms;

% delta99 按流向位置插值到全网格。超出标定 x 范围的列给 NaN，随后被 valid_mask 剔除。
ctx.delta_grid = interp1(mean_bl.boundary_layer.x, ...
    mean_bl.boundary_layer.delta99, stats.X, 'linear', NaN);
ctx.valid_mask = stats.accepted_mask & isfinite(ctx.delta_grid) & ctx.delta_grid > 0;
ctx.analysis_domain_mask = tblR2.trusted_domain_mask( ...
    ctx.valid_mask, ctx.Y_wall_mm, resolved.trusted_domain);

ctx.dx_mm = median(abs(diff(stats.X(1, :))), 'omitnan');
ctx.dy_mm = median(abs(diff(ctx.Y_wall_mm(:, 1))), 'omitnan');

% 壁面单位：wall-attached 分类需要。u_tau 取 mean_bl 已选定的归一化值，
% 与 mean_bl.y_plus 同源，不重新拟合。
ctx.u_tau = NaN;
if isfield(mean_bl, 'normalization') && isfield(mean_bl.normalization, 'u_tau')
    ctx.u_tau = mean_bl.normalization.u_tau;
end
ctx.nu = NaN;
if isfield(cfg, 'nu') && ~isempty(cfg.nu)
    ctx.nu = cfg.nu;
end

% 采样间隔：时间追踪的对流位移需要。
ctx.dt_s = NaN;
if isfield(cfg, 'fs') && ~isempty(cfg.fs) && cfg.fs > 0
    ctx.dt_s = 1 / cfg.fs;
end

% 对流速度来源。逐结构按其重心高度取行平均，不用全局值——实测剪切下
% y/delta99=0.05 与 1.0 之间的帧间位移差 19 格。
ctx.Uavex = [];
if isfield(stats, 'Uavex'); ctx.Uavex = stats.Uavex; end

ctx.n_frames = NaN;
if isfield(stats, 'n_frames') && ~isempty(stats.n_frames)
    ctx.n_frames = stats.n_frames;
end

ctx.cfg = cfg;
ctx.stats = stats;
ctx.mean_bl = mean_bl;
ctx.resolved = resolved;
end
