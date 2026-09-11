function stats = wall_attached_statistics(catalog, options)
%WALL_ATTACHED_STATISTICS attached/detached 分组统计 + population density。
%
% Population density n_s(l_y)：按 HeightY_mm 分 bin，统计每个尺度 bin 内
% attached 结构的计数密度。Hwang & Sung (2018) 报告 n_s ~ l_y^(-1)（inverse
% power law）是 attached-eddy hierarchy 的证据；这里只算密度分布，不做幂律拟合
% ——拟合需要更宽的尺度范围和更严格的误差处理，留给用户在 catalog 上自行做。
%
% 输入
%   catalog : run_catalog 累积的结构表（需含 classify_wall_attached 加的列）
%   options : 结构体，.n_bins 默认 12（对数分 bin 用）
%
% 输出 stats 结构体
%   .n_total, .n_attached, .n_detached
%   .attached_fraction        计数占比
%   .attached_area_fraction   面积占比（Area_mm2 加权，对应论文"体积占比"的 2D 类比）
%   .population_density       table，列 BinEdgeLow/BinEdgeHigh/BinCenter/Count/Density

if ~ismember('IsWallAttached', catalog.Properties.VariableNames)
    error('tblR2:vlsmpod:wall_attached_statistics:MissingColumn', ...
        'catalog 缺少 IsWallAttached 列，请先对每帧调用 classify_wall_attached。');
end
if nargin < 2 || isempty(options); options = struct(); end
n_bins = 12;
if isfield(options, 'n_bins') && ~isempty(options.n_bins)
    n_bins = options.n_bins;
end

stats = struct();
stats.n_total = height(catalog);
stats.n_attached = sum(catalog.IsWallAttached);
stats.n_detached = stats.n_total - stats.n_attached;
if stats.n_total > 0
    stats.attached_fraction = stats.n_attached / stats.n_total;
else
    stats.attached_fraction = NaN;
end

total_area = sum(catalog.Area_mm2);
attached_area = sum(catalog.Area_mm2(catalog.IsWallAttached));
if total_area > 0
    stats.attached_area_fraction = attached_area / total_area;
else
    stats.attached_area_fraction = NaN;
end

stats.population_density = population_density(catalog, n_bins);
end

% =========================================================================
function T = population_density(catalog, n_bins)
attached = catalog(catalog.IsWallAttached, :);
if isempty(attached) || height(attached) < 2
    T = table('Size', [0, 5], 'VariableTypes', ...
        {'double', 'double', 'double', 'double', 'double'}, ...
        'VariableNames', {'BinEdgeLow', 'BinEdgeHigh', 'BinCenter', 'Count', 'Density'});
    return;
end

ly = attached.HeightY_mm;
ly = ly(isfinite(ly) & ly > 0);
if isempty(ly)
    T = table('Size', [0, 5], 'VariableTypes', ...
        {'double', 'double', 'double', 'double', 'double'}, ...
        'VariableNames', {'BinEdgeLow', 'BinEdgeHigh', 'BinCenter', 'Count', 'Density'});
    return;
end

edges = logspace(log10(min(ly)), log10(max(ly)), n_bins + 1);
edges(end) = edges(end) * (1 + 1e-9);
counts = histcounts(ly, edges);
bin_width = diff(edges);
density = counts ./ bin_width;

T = table(edges(1:end-1).', edges(2:end).', sqrt(edges(1:end-1) .* edges(2:end)).', ...
    counts.', density.', 'VariableNames', ...
    {'BinEdgeLow', 'BinEdgeHigh', 'BinCenter', 'Count', 'Density'});
end
