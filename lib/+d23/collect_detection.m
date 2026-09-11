function collected = collect_detection(detection, run_dir)
%COLLECT_DETECTION Consolidate compact summaries while leaving full catalog partitioned.
n_batches = height(detection.catalog_index);
summary_parts = cell(n_batches, 1);
performance_parts = cell(n_batches, 1);
ss_parts = cell(n_batches, 1);
for i = 1:n_batches
    filename = char(detection.catalog_index.MatFile(i));
    loaded = load(filename, 'catalog', 'frame_summary', 'frame_performance');
    summary_parts{i} = loaded.frame_summary;
    performance_parts{i} = loaded.frame_performance;
    ss_parts{i} = loaded.catalog(loaded.catalog.IsSS3, :);
end
frame_summary = vertcat(summary_parts{:});
frame_performance = vertcat(performance_parts{:});
if all(cellfun(@isempty, ss_parts))
    ss_catalog = d23.empty_catalog();
else
    ss_catalog = vertcat(ss_parts{:});
end
ss_catalog = sortrows(ss_catalog, ...
    {'FrameOrdinal','Connectivity','Sign','ComponentID'}, ...
    {'ascend','descend','descend','ascend'});
censored_ss_catalog = ss_catalog(ss_catalog.IsCensored, :);
complete_ss_catalog = ss_catalog(~ss_catalog.IsCensored, :);
d23.atomic_save(fullfile(run_dir, 'mat', 'detection_summary.mat'), struct( ...
    'frame_summary', frame_summary, 'frame_performance', frame_performance, ...
    'ss_catalog', ss_catalog, 'censored_ss_catalog', censored_ss_catalog, ...
    'complete_ss_catalog', complete_ss_catalog, ...
    'catalog_index', detection.catalog_index));
d23.atomic_writetable(fullfile(run_dir, 'csv', 'frame_summary.csv'), frame_summary);
d23.atomic_writetable(fullfile(run_dir, 'csv', 'frame_performance.csv'), frame_performance);
d23.atomic_writetable(fullfile(run_dir, 'csv', 'ss_catalog.csv'), ss_catalog);
d23.atomic_writetable(fullfile(run_dir, 'csv', 'censored_ss_catalog.csv'), ...
    censored_ss_catalog);
collected = struct('frame_summary', frame_summary, ...
    'frame_performance', frame_performance, 'ss_catalog', ss_catalog, ...
    'censored_ss_catalog', censored_ss_catalog, ...
    'complete_ss_catalog', complete_ss_catalog, ...
    'catalog_index', detection.catalog_index);
end
