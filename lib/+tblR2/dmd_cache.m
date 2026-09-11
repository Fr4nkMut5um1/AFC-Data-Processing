function result = dmd_cache(cache_file, cfg, stats, phase_stats, mean_bl, branch)
%DMD_CACHE Backward-compatible r2 stage wrapper for the standalone DMD module.
%
% Existing case scripts retain this six-argument cache signature. All
% numerical work now lives in dmd_module, which can also consume an in-memory
% sequence or a joint snapshot matrix.
result = tblR2.dmd_module(cache_file, cfg, stats, phase_stats, mean_bl, branch);
end
