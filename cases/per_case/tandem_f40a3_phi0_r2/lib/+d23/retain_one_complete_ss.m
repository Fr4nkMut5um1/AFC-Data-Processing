function catalog = retain_one_complete_ss(catalog, cfg)
%RETAIN_ONE_COMPLETE_SS Backward-compatible wrapper for the generalized selector.
catalog = d23.retain_nonoverlapping_complete_ss(catalog, cfg);
end
