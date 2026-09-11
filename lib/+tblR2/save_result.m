function save_result(filename, data, cfg, stage, inputs)
%SAVE_RESULT Save results; S2/S3 require explicit producer and parent identities.
if nargin < 5; inputs = struct(); end
parent = fileparts(filename);
if ~isfolder(parent); mkdir(parent); end
meta = struct('schema_version',1,'case_id',cfg.case_id,'stage',stage, ...
    'data_root',cfg.data_root,'n_frames',cfg.n_frames,'total_frames',cfg.total_frames, ...
    'grid_size',cfg.grid_size,'fs',cfg.fs,'created_utc',char(datetime('now', ...
    'TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ssXXX')));
if ismember(stage, {'statistics','mean_bl','phase','structures'})
    meta.schema_version = 2;
    meta.result_id = char(java.util.UUID.randomUUID());
    meta.contract = tblR2.result_parameters(cfg, stage);
    meta.parents = tblR2.result_inputs(cfg, stage, inputs);
end
save(filename, 'data', 'meta', '-v7.3');
end
