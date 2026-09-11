function stats = superstructure_statistics(catalog)
%SUPERSTRUCTURE_STATISTICS VLSM 子结构分解的汇总统计。
%
% 检验 concatenation hypothesis 的关键量：子结构长度是否聚集在 LSM 尺度
% （1-3 delta99），而不是随 VLSM 总长线性增长。若子结构长度与总长成正比，说明
% 分解只是把长度按固定比例切分，没有揭示物理拼接单元。
%
% 输入
%   catalog : 含 decompose_superstructure 加的列的结构表
%
% 输出 stats 结构体
%   .n_vlsm_analyzed           成功分解的 VLSM 数
%   .n_sub_mean / _median      每个 VLSM 的子结构数
%   .n_sub_histogram           table，NSub / Count
%   .sub_length_median_over_delta  全体子结构段长中位数（delta99 单位）
%   .total_vs_sub_correlation  VLSM 总长与子结构段长中位数的相关系数。
%                              接近 0 支持「子结构尺度不随总长变化」（自相似拼接）；
%                              接近 1 说明只是按比例切分。

required = {'NSubStructures', 'SubLengthMedian_over_delta', 'IsVLSM', ...
    'LengthX_over_delta'};
missing = required(~ismember(required, catalog.Properties.VariableNames));
if ~isempty(missing)
    error('tblR2:vlsmpod:superstructure_statistics:MissingColumn', ...
        'catalog 缺少列：%s。', strjoin(missing, ', '));
end

analyzed = catalog(catalog.IsVLSM & isfinite(catalog.NSubStructures), :);

stats = struct();
stats.n_vlsm_analyzed = height(analyzed);
if isempty(analyzed)
    stats.n_sub_mean = NaN;
    stats.n_sub_median = NaN;
    stats.n_sub_histogram = table(zeros(0, 1), zeros(0, 1), ...
        'VariableNames', {'NSub', 'Count'});
    stats.sub_length_median_over_delta = NaN;
    stats.total_vs_sub_correlation = NaN;
    return;
end

stats.n_sub_mean = mean(analyzed.NSubStructures, 'omitnan');
stats.n_sub_median = median(analyzed.NSubStructures, 'omitnan');

edges = unique(analyzed.NSubStructures);
counts = zeros(numel(edges), 1);
for k = 1:numel(edges)
    counts(k) = sum(analyzed.NSubStructures == edges(k));
end
stats.n_sub_histogram = table(edges, counts, 'VariableNames', {'NSub', 'Count'});

stats.sub_length_median_over_delta = ...
    median(analyzed.SubLengthMedian_over_delta, 'omitnan');

% 相关性只在两列都有效且样本足够时算——2 个点的相关系数恒为 ±1，没有意义。
both = isfinite(analyzed.LengthX_over_delta) & ...
    isfinite(analyzed.SubLengthMedian_over_delta);
if nnz(both) >= 3
    c = corrcoef(analyzed.LengthX_over_delta(both), ...
        analyzed.SubLengthMedian_over_delta(both));
    stats.total_vs_sub_correlation = c(1, 2);
else
    stats.total_vs_sub_correlation = NaN;
end

stats.caveats = build_caveats(analyzed);
end

% =========================================================================
function c = build_caveats(analyzed)
%BUILD_CAVEATS 把口径限制做成字段，避免 n_sub_mean 被单独引用时误读。
c = struct();

% amplitude_factor 未标定：实测 0.5->1.29 段、0.05->3.24 段，结论随参数走。
af = unique(analyzed.SubAmplitudeFactor(isfinite(analyzed.SubAmplitudeFactor)));
c.amplitude_factor_used = af(:).';
c.amplitude_factor_calibrated = false;
c.amplitude_factor_note = ['amplitude_factor 未标定：24 帧/17 VLSM 实测 ' ...
    '0.5->1.29 段, 0.3->2.06, 0.2->2.53, 0.1->3.00, 0.05->3.24。' ...
    '引用子结构数时必须同时给出该参数。'];

% 尺度口径：D&M 的 superstructure 是 Lx>6*delta99，本数据尚未达到。
maxLx = max(analyzed.LengthX_over_delta, [], 'omitnan');
c.max_length_over_delta = maxLx;
c.reaches_superstructure_scale = maxLx > 6;
if ~c.reaches_superstructure_scale
    c.scale_note = sprintf(['本帧集最长 VLSM 仅 %.2f*delta99，未达 ' ...
        'Deshpande&Marusic 的 superstructure 判据 (>6*delta99)，' ...
        '不能直接对照其 concatenation 结论。'], maxLx);
else
    c.scale_note = '';
end

c.sample_size = height(analyzed);
c.sample_adequate = height(analyzed) >= 100;
end
