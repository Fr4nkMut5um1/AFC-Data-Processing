function parents = result_inputs(cfg, stage, inputs)
%RESULT_INPUTS Explicit scientific parents of S2/S3 saved results.
parents = struct();
if ismember(stage, {'statistics','phase','structures'})
    if ~isfield(inputs, 'cache')
        error('tblR2:result:MissingInput', '%s requires inputs.cache; run the corresponding section compute/read.', stage);
    end
    source = cfg.statistics_source;
    if strcmp(stage, 'phase'); source = 'raw'; end
    if strcmp(stage, 'structures'); source = 'postproc'; end
    parents.cache = tblR2.sequence_cache_identity(inputs.cache, cfg, source);
end
if ismember(stage, {'mean_bl','phase'})
    if ~isfield(inputs, 'statistics')
        error('tblR2:result:MissingInput', '%s requires inputs.statistics.', stage);
    end
    % Metadata only: validates the producer contract without requiring old DAT
    % or another source cache online. The UUID identifies the saved parent result.
    meta = tblR2.load_result(inputs.statistics, cfg, 'statistics', struct(), true);
    parents.statistics = struct('result_id', meta.result_id, ...
        'contract', meta.contract, 'parents', meta.parents);
end
if strcmp(stage, 'structures')
    if ~isfield(inputs, 'mean_bl')
        error('tblR2:result:MissingInput', 'structures requires inputs.mean_bl.');
    end
    meta = tblR2.load_result(inputs.mean_bl, cfg, 'mean_bl', struct(), true);
    parents.mean_bl = struct('result_id', meta.result_id, ...
        'contract', meta.contract, 'parents', meta.parents);
end

end
