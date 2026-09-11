function result = connectivity_length_distribution(ss_catalog)
%CONNECTIVITY_LENGTH_DISTRIBUTION Common-bin 8/4 complete-SS length comparison.
complete = ss_catalog.IsSS3 & ~ss_catalog.IsCensored;
values8 = ss_catalog.Lx_over_delta(complete & ss_catalog.Connectivity == 8);
values4 = ss_catalog.Lx_over_delta(complete & ss_catalog.Connectivity == 4);
all_values = [values8; values4];
if isempty(all_values)
    edges = 3:0.25:3.25;
else
    upper = max(3.25, ceil(max(all_values) * 4) / 4);
    edges = 3:0.25:(upper + 0.25);
end
parts = cell(2, 1);
statistics = repmat(struct('connectivity', 0, 'n', 0, 'median', NaN, ...
    'p90', NaN, 'p95', NaN, 'maximum', NaN), 2, 1);
for i = 1:2
    if i == 1
        connectivity = 8;
        values = values8;
    else
        connectivity = 4;
        values = values4;
    end
    counts = histcounts(values, edges);
    probability = counts / max(numel(values), 1);
    parts{i} = table(repmat(uint8(connectivity), numel(counts), 1), ...
        edges(1:end-1).', edges(2:end).', ...
        ((edges(1:end-1) + edges(2:end)) / 2).', ...
        uint32(counts(:)), probability(:), ...
        'VariableNames', {'Connectivity','BinLeft','BinRight','BinCenter', ...
        'Count','Probability'});
    statistics(i).connectivity = connectivity;
    statistics(i).n = numel(values);
    if ~isempty(values)
        statistics(i).median = median(values);
        statistics(i).p90 = prctile(values, 90);
        statistics(i).p95 = prctile(values, 95);
        statistics(i).maximum = max(values);
    end
end
result = struct('table', vertcat(parts{:}), 'edges', edges, ...
    'values8', values8, 'values4', values4, ...
    'statistics', statistics, ...
    'definition', 'Complete SS satisfying strict Lx/delta > 3; common 0.25-delta bins.');
end
