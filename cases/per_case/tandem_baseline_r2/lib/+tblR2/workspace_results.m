function results = workspace_results(action, results, cfg, names, mode, current_script_file)
%WORKSPACE_RESULTS Track this MATLAB workspace only; never compute/load/save a stage.
% accepted_cfg records the parameters when this workspace accepted a result.
% It is NOT the historical producer configuration of a legacy MAT file.
% File size/time detect ordinary replacement during this session, not content identity.
if nargin < 4; names = {}; end
if nargin < 5; mode = ''; end
owner = struct('case_id', cfg.case_id, 'script_file', cfg.script_file, ...
    'output_dir', cfg.output_dir);
% The entry section supplies its own executing filename. Equal case_id alone
% cannot distinguish two independently copied folders of the same case.
if nargin >= 6
    if isempty(current_script_file)
        try
            current_script_file = matlab.desktop.editor.getActiveFilename;
        catch
            current_script_file = '';
        end
    end
    configured_script = regexprep(char(cfg.script_file), '\.m$', '');
    executing_script = regexprep(char(current_script_file), '\.m$', '');
    if ispc; same_script = strcmpi(configured_script, executing_script);
    else; same_script = strcmp(configured_script, executing_script); end
    if isempty(executing_script) || ~same_script
        error('tblR2:workspace:WrongScript', ...
            '工作区配置来自 %s；当前执行文件为 %s。请先运行当前文件的 Section 0。', ...
            cfg.script_file, current_script_file);
    end
end
if strcmp(action, 'init')
    if ~isempty(results) && (~isstruct(results) || ~isfield(results, 'workspace') || ...
            ~isstruct(results.workspace) || ~isfield(results.workspace, 'owner'))
        error('tblR2:workspace:UnknownOwner', ...
            '工作区 results 缺少本 case 归属记录。请先自行保存需要的旧结果，再明确 clear results，重跑 Section 0。');
    end
    if isempty(results) || ~isequaln(results.workspace.owner, owner)
        if ~isempty(results)
            fprintf('[工作区] 切换 case/脚本/输出目录；仅初始化本 case 的 results。\n');
        end
        results = struct();
        fields = {'cache','postproc_cache','statistics','mean_bl','phase','structures', ...
            'transport','temporal','spatial','pod','dmd','lcs','spod','correlations', ...
            'harmonics','figures'};
        for k = 1:numel(fields); results.(fields{k}) = []; end
        results.workspace = struct('owner', owner, 'records', struct(), 'serial', 0, ...
            'started_utc', char(datetime('now', 'TimeZone', 'UTC', ...
            'Format', 'yyyy-MM-dd''T''HH:mm:ssXXX')));
    end
    return;
end
if ~isstruct(results) || ~isfield(results, 'workspace') || ...
        ~isequaln(results.workspace.owner, owner)
    error('tblR2:workspace:WrongOwner', ...
        'cfg/results 不属于当前 case、脚本或输出目录。请先运行本 case 的 Section 0。');
end
for k = 1:numel(names)
    name = names{k};
    switch action
        case 'forget'
            % Clear acceptance before an attempted calculation/read. A failed task
            % must not leave its old workspace record looking freshly accepted.
            if isfield(results.workspace.records, name)
                results.workspace.records = rmfield(results.workspace.records, name);
            end
        case 'record'
            if ~isfield(results, name) || isempty(results.(name))
                continue;
            end
            [accepted_cfg, files, parents] = input_record(cfg, name);
            parent_serial = struct();
            for j = 1:numel(parents)
                parent = parents{j};
                if isfield(results.workspace.records, parent)
                    parent_serial.(parent) = results.workspace.records.(parent).serial;
                end
            end
            results.workspace.serial = results.workspace.serial + 1;
            record = struct('accepted_cfg', accepted_cfg, 'files', {files}, ...
                'parent_serial', parent_serial, 'serial', results.workspace.serial, ...
                'mode', mode, 'verification', 'workspace_lifecycle_only');
            if strcmp(mode, 'reuse') && ~ismember(name, {'cache','postproc_cache','transport','statistics','mean_bl','phase','structures'})
                record.verification = 'legacy_minimum_disk_contract_only';
                warning('tblR2:workspace:LegacyContractLimited', ...
                    ['%s 已按 load_result 的旧最小合同读取；旧 MAT 缺少完整参数/父输入身份。' ...
                    '本工作区仅记录读取时的 cfg，不能证明历史生产配置；此阶段尚未新增完整复用合同。'], name);
            end
            results.workspace.records.(name) = record;
        case 'require'
            if ~isfield(results, name) || isempty(results.(name)) || ...
                    ~isfield(results.workspace.records, name)
                error('tblR2:workspace:MissingResult', ...
                    '需要已完成且有本次工作区记录的 results.%s。请运行 %s 的 compute 或显式 reuse。', ...
                    name, section_name(name));
            end
            record = results.workspace.records.(name);
            [current_cfg, current_files] = input_record(cfg, name);
            changed = first_difference(record.accepted_cfg, current_cfg, 'cfg');
            if ~isempty(changed)
                error('tblR2:workspace:StaleParameters', ...
                    ['results.%s 已过期：%s 改变。请到 %s compute；' ...
                    '若读取旧 MAT，须独立确认其参数身份（须通过该阶段磁盘合同检查）。'], ...
                    name, changed, section_name(name));
            end
            if ~isequaln(record.files, current_files)
                error('tblR2:workspace:ChangedFile', ...
                    ['results.%s 的缓存/结果文件存在性、大小或修改时间已改变。' ...
                    '请在 %s compute 或显式读取已核实文件。'], name, section_name(name));
            end
            parents = fieldnames(record.parent_serial);
            for j = 1:numel(parents)
                parent = parents{j};
                if ~isfield(results.workspace.records, parent) || ...
                        record.parent_serial.(parent) ~= results.workspace.records.(parent).serial
                    error('tblR2:workspace:ChangedParent', ...
                        'results.%s 已过期：父产物 %s 已重新处理。请重新运行 %s。', ...
                        name, parent, section_name(name));
                end
                tblR2.workspace_results('require', results, cfg, {parent});
            end
        otherwise
            error('tblR2:workspace:InvalidAction', '未知工作区动作：%s。', action);
    end
end
end

function [value, files, parents] = input_record(cfg, name)
% Explicit input groups, with display-only configuration outside numerical records.
source_fields = {'case_id','case_type','fs','grid_size','wall_side','n_frames', ...
    'total_frames','formal_required_frames','allow_debug_snapshot','frame_offset'};
statistics_fields = [source_fields, {'statistics_source','statistics_frame_mode', ...
    'min_valid_fraction','chunk_frames','Uinf'}];
mean_fields = [statistics_fields, {'profile','loglaw','modern_clauser', ...
    'normalization','friction','nu','rho','x_max'}];
parents = {}; roles = {}; files = {};
source = 'raw';
if isfield(cfg, 'statistics_source'); source = cfg.statistics_source; end
switch name
    case 'cache'
        fields = [source_fields, {'chunk_frames'}]; roles = {'raw'};
    case 'postproc_cache'
        fields = [source_fields, {'chunk_frames'}]; roles = {'postproc'};
    case 'statistics'
        fields = statistics_fields; roles = {source};
    case 'mean_bl'
        fields = mean_fields; roles = {source}; parents = {'statistics'};
    case 'phase'
        fields = [statistics_fields, {'phase'}]; roles = unique({'raw', source}, 'stable');
        parents = {'statistics'};
    case 'structures'
        fields = [source_fields, {'Uinf','nu','D_mm','chunk_frames','structures','section4','instantaneous'}];
        roles = {'postproc'};
        files = {file_state(fullfile(cfg.output_dir, 'mat', '02_mean_boundary_layer_friction.mat'))};
    case 'transport'
        fields = [source_fields, {'Uinf','nu','min_valid_fraction','chunk_frames', ...
            'transport','friction','statistics_frame_mode'}];
        if strcmp(cfg.case_type, 'controlled'); fields{end+1} = 'phase'; end
        roles = {cfg.transport.source};
    otherwise
        fields = [mean_fields, {'D_mm'}]; roles = unique({source, 'postproc'}, 'stable');
        parents = {'statistics','mean_bl'};
        if ismember(name, {'harmonics','figures'})
            parents = [parents, {'structures','transport','temporal','spatial','pod','dmd','lcs','spod','correlations'}];
            if strcmp(name, 'figures'); parents{end+1} = 'harmonics'; end
        end
        if strcmp(cfg.case_type, 'controlled') && ismember(name, {'harmonics','figures'})
            parents{end+1} = 'phase'; fields{end+1} = 'phase';
        end
        if strcmp(name, 'dmd'); fields{end+1} = 'phase'; end
        if strcmp(name, 'lcs')
            if strcmp(cfg.lcs.source_role, 'raw'); roles = {source, 'raw'}; end
            if strcmp(cfg.lcs.branch, 'random')
                parents{end+1} = 'phase'; fields{end+1} = 'phase';
            end
        end
        if strcmp(name, 'correlations'); fields{end+1} = 'temporal'; end
        if ismember(name, {'temporal','spatial','pod','dmd','lcs','spod','correlations'})
            fields{end+1} = name;
        elseif strcmp(name, 'harmonics')
            fields = [fields, {'streamwise_development','spatial'}];
        elseif strcmp(name, 'figures')
            fields = [fields, {'figures','preview','phase_preview','instantaneous','structures'}];
        end
end
value = struct();
for k = 1:numel(fields)
    if isfield(cfg, fields{k}); value.(fields{k}) = cfg.(fields{k}); end
end
for k = 1:numel(roles)
    role = roles{k};
    value.sources.(role) = cfg.sources.(role); % Both repeat IDs, roots and offsets.
    if strcmp(role, 'raw'); filename = '01_sequence_cache.mat';
    else; filename = '01_sequence_cache_postproc.mat'; end
    files{end+1} = file_state(fullfile(cfg.output_dir, 'mat', filename)); %#ok<AGROW>
end
% Product file replacement invalidates the in-memory object as well.
product_files = struct('statistics','02_statistics.mat', ...
    'mean_bl','02_mean_boundary_layer_friction.mat','phase','03_phase_triple_statistics.mat', ...
    'structures','09_structure_analysis.mat','temporal','05_temporal_spectra.mat', ...
    'spatial','05_spatial_spectra.mat','pod','06_pod_analysis.mat','dmd','07_dmd_analysis.mat', ...
    'lcs','08_lcs_ftle_analysis.mat','spod','08_spod_analysis.mat', ...
    'correlations','13_correlation_analysis.mat','harmonics','13_streamwise_harmonic_development.mat', ...
    'figures','12_figure_export_manifest.mat');
if isfield(product_files, name)
    files{end+1} = file_state(fullfile(cfg.output_dir, 'mat', product_files.(name)));
elseif strcmp(name, 'transport')
    files{end+1} = file_state(fullfile(cfg.output_dir, 'section5', cfg.transport.source, ...
        'mat', '04_transport_quadrant.mat'));
end
end

function value = file_state(filename)
info = dir(filename);
value = struct('filename', filename, 'exists', ~isempty(info), 'bytes', [], 'datenum', []);
if ~isempty(info); value.bytes = info(1).bytes; value.datenum = info(1).datenum; end
end

function label = section_name(name)
switch name
    case {'cache','postproc_cache'}; section = 1;
    case {'statistics','mean_bl'}; section = 2;
    case 'phase'; section = 3;
    case 'structures'; section = 4;
    case 'transport'; section = 5;
    case {'temporal','spatial'}; section = 6;
    case {'pod','dmd','lcs','spod'}; section = 7;
    case {'correlations','harmonics'}; section = 8;
    otherwise; section = 9;
end
label = sprintf('Section %d (%s)', section, name);
end

function name = first_difference(a, b, prefix)
name = '';
if isequaln(a, b); return; end
if isstruct(a) && isscalar(a) && isstruct(b) && isscalar(b)
    fields = union(fieldnames(a), fieldnames(b));
    for k = 1:numel(fields)
        field = fields{k};
        if ~isfield(a, field) || ~isfield(b, field)
            name = [prefix '.' field]; return;
        end
        name = first_difference(a.(field), b.(field), [prefix '.' field]);
        if ~isempty(name); return; end
    end
else
    name = prefix;
end
end
