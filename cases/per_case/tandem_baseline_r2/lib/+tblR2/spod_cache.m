function result = spod_cache(cache_file, cfg, stats, phase_stats, mean_bl, branch)
%SPOD_CACHE Welch-block SPOD delegated to the installed Towne/Schmidt toolbox.

if ~ismember(branch, {'total', 'random'})
    error('tblR2:r2:spod_cache:InvalidBranch', ...
        'branch 必须是 total 或 random。');
end
if strcmp(branch, 'random') && isempty(phase_stats)
    error('tblR2:r2:spod_cache:MissingPhaseStatistics', ...
        'controlled random 分支需要 phase 统计。');
end
sequence = tblR2.modal_snapshot_matrix(cache_file, cfg, stats, ...
    phase_stats, mean_bl, branch, cfg.spod);
result = tblR2.spod_toolbox_adapter(sequence, cfg);
result.branch = branch;
end
