function data = load_result(filename, cfg, stage, inputs, metadata_only)
%LOAD_RESULT Validate saved identities before loading scientific arrays.
if nargin < 4; inputs = struct(); end
if nargin < 5; metadata_only = false; end
if ~isfile(filename); error('tblR2:load_result:MissingFile', ...
        '结果文件不存在：%s', filename); end
if isfield(cfg, 'script_file')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.contract_difference'});
end
loaded = load(filename, 'meta');
variables = whos('-file', filename);
if ~isfield(loaded,'meta') || ~any(strcmp({variables.name}, 'data'))
    error('tblR2:load_result:InvalidFile', '结果文件缺少 data 或 meta 字段。');
end
meta = loaded.meta;
required_meta = {'case_id','stage','n_frames','grid_size','fs'};
if ~all(isfield(meta, required_meta))
    error('tblR2:load_result:ContractMismatch', ...
        '结果元数据缺少 case_id、stage、n_frames、grid_size 或 fs 字段。');
end
expected = struct('case_id',cfg.case_id,'stage',stage,'n_frames',cfg.n_frames, ...
    'grid_size',double(cfg.grid_size),'fs',cfg.fs);
saved = struct('case_id',meta.case_id,'stage',meta.stage,'n_frames',meta.n_frames, ...
    'grid_size',double(meta.grid_size),'fs',meta.fs);
difference = tblR2.contract_difference(saved, expected, 'meta');
if ~isempty(difference)
    error('tblR2:load_result:ContractMismatch', '%s: %s', filename, difference);
end
if ismember(stage, {'statistics','mean_bl','phase','structures'})
    if ~all(isfield(meta, {'schema_version','result_id','contract','parents'})) || meta.schema_version ~= 2
        error('tblR2:load_result:MissingProducerIdentity', ...
            '%s lacks the producer/parent identity. Use the corresponding section compute or a separately verified migration; old MAT is not relabelled.', filename);
    end
    difference = tblR2.contract_difference(meta.contract, ...
        tblR2.result_parameters(cfg, stage), 'producer');
    if ~isempty(difference)
        error('tblR2:load_result:ContractMismatch', '%s: %s. Run %s compute or read a matching result.', filename, difference, stage);
    end
    required_parents = {'cache'};
    if strcmp(stage, 'mean_bl'); required_parents = {'statistics'};
    elseif strcmp(stage, 'phase'); required_parents = {'cache','statistics'};
    elseif strcmp(stage, 'structures'); required_parents = {'cache','mean_bl'}; end
    if ~all(isfield(meta.parents, required_parents))
        error('tblR2:load_result:MissingProducerIdentity', '%s lacks required parent identities.', filename);
    end
    if ismember(stage, {'mean_bl','phase'})
        parent = meta.parents.statistics;
        if ~all(isfield(parent, {'result_id','contract','parents'})) || ...
                ~isfield(parent.parents, 'cache')
            error('tblR2:load_result:MissingProducerIdentity', '%s lacks original statistics identity.', filename);
        end
        difference = tblR2.contract_difference(parent.contract, ...
            tblR2.result_parameters(cfg, 'statistics'), 'parent.statistics');
        if ~isempty(difference)
            error('tblR2:load_result:ContractMismatch', '%s: %s', filename, difference);
        end
    end
    if strcmp(stage, 'structures')
        parent = meta.parents.mean_bl;
        if ~all(isfield(parent, {'result_id','contract','parents'})) || ...
                ~isfield(parent.parents, 'statistics')
            error('tblR2:load_result:MissingProducerIdentity', '%s lacks mean_bl/statistics identity.', filename);
        end
        difference = tblR2.contract_difference(parent.contract, ...
            tblR2.result_parameters(cfg, 'mean_bl'), 'parent.mean_bl');
        if ~isempty(difference); error('tblR2:load_result:ContractMismatch', '%s: %s', filename, difference); end
    end
    if ~isempty(fieldnames(inputs))
        difference = tblR2.contract_difference(meta.parents, ...
            tblR2.result_inputs(cfg, stage, inputs), 'parents');
        if ~isempty(difference)
            error('tblR2:load_result:ParentMismatch', ...
                '%s: %s. Run %s compute or read matching parents/results.', filename, difference, stage);
        end
    end
end
if metadata_only; data = meta; return; end
loaded = load(filename, 'data');
data = loaded.data;
end
