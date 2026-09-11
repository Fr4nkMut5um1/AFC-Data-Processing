function [y_mm, U, u_rms, v_rms, uv_rey, x_range, n_columns] = ...
    range_average_profiles(stats, mean_bl, cfg)
%RANGE_AVERAGE_PROFILES Extract Section 2 wall-normal range-average profiles.
%   The same streamwise columns are averaged for U, u'_rms, v'_rms, and
%   uv_rey. The returned uv_rey follows the statistics contract (-<u'v'>).
%   When available, mean_bl.drag_statistics is used so the profile
%   honors the Section 2 contamination mask used by the Clauser fit.

if nargin < 3 || ~isstruct(cfg) || ~isfield(cfg, 'profile')
    error('tblR2:range_average_profiles:InvalidConfig', ...
        '必须提供 cfg.profile。');
end
if isstruct(mean_bl) && isfield(mean_bl, 'drag_statistics') && ...
        ~isempty(mean_bl.drag_statistics)
    S = mean_bl.drag_statistics;
    if isfield(mean_bl, 'wall_distance_mm') && ...
            isequal(size(mean_bl.wall_distance_mm), size(S.X))
        Y = double(mean_bl.wall_distance_mm);
    else
        Y = double(S.Y);
    end
else
    S = stats;
    Y = double(S.Y);
end
required = {'X', 'Uavex', 'u_rms', 'v_rms', 'uv_rey'};
if ~all(isfield(S, required))
    missing = required(~isfield(S, required));
    error('tblR2:range_average_profiles:MissingStatistics', ...
        '缺少剖面统计字段：%s。', strjoin(missing, ', '));
end
grid_size = size(S.X);
for i = 2:numel(required)
    if ~isequal(size(S.(required{i})), grid_size)
        error('tblR2:range_average_profiles:SizeMismatch', ...
            'S.%s 必须与 S.X 尺寸一致。', required{i});
    end
end

x_vec = double(S.X(1, :));
mode = lower(char(cfg.profile.mode));
params = double(cfg.profile.params(:)');
switch mode
    case 'range_avg'
        if numel(params) ~= 2 || params(1) > params(2)
            error('tblR2:range_average_profiles:InvalidRange', ...
                'range_avg 要求 cfg.profile.params=[x_min x_max] 且上下限有序。');
        end
        columns = find(x_vec >= params(1) & x_vec <= params(2));
    case 'multi_avg'
        if isempty(params)
            error('tblR2:range_average_profiles:InvalidStations', ...
                'multi_avg 至少需要一个流向站位。');
        end
        columns = zeros(1, numel(params));
        for i = 1:numel(params)
            [~, columns(i)] = min(abs(x_vec - params(i)));
        end
        columns = unique(columns, 'stable');
    case 'fixed'
        if numel(params) ~= 1
            error('tblR2:range_average_profiles:InvalidStation', ...
                'fixed 需要且只能指定一个流向站位。');
        end
        [~, column] = min(abs(x_vec - params));
        columns = column;
    otherwise
        error('tblR2:range_average_profiles:UnsupportedMode', ...
            '不支持的 cfg.profile.mode：%s。', mode);
end
if isempty(columns)
    error('tblR2:range_average_profiles:EmptyRange', ...
        '请求的剖面选择范围内没有统计网格列。');
end

y_mm = mean(Y(:, columns), 2, 'omitnan');
U = mean(double(S.Uavex(:, columns)), 2, 'omitnan');
u_rms = mean(double(S.u_rms(:, columns)), 2, 'omitnan');
v_rms = mean(double(S.v_rms(:, columns)), 2, 'omitnan');
uv_rey = mean(double(S.uv_rey(:, columns)), 2, 'omitnan');
x_range = [min(x_vec(columns)) max(x_vec(columns))];
n_columns = numel(columns);
end
