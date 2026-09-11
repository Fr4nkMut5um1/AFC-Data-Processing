function info = ensure_external_toolboxes(cfg, requested)
%ENSURE_EXTERNAL_TOOLBOXES Resolve only the local third-party code being used.
% Main scripts set cfg.script_file. Array/maintenance callers must also state
% the owning case script explicitly; no repository or historical path search.
if nargin < 2
    requested = {};
    for name = {'dmd', 'spod'}
        if isfield(cfg, 'stages') && isfield(cfg.stages, name{1}) && ...
                strcmp(cfg.stages.(name{1}), 'compute')
            requested{end+1} = name{1}; %#ok<AGROW>
        end
    end
end
info = struct('piDMD', '', 'spod', '');
if isempty(requested); return; end
if ~isfield(cfg, 'script_file') || isempty(cfg.script_file)
    error('tblR2:ensure_external_toolboxes:MissingCasePath', ...
        '请显式提供 cfg.script_file，第三方代码只从该 case 的 third_party 读取。');
end
case_root = char(java.io.File(fileparts(cfg.script_file)).getCanonicalPath());
third_party = fullfile(case_root, 'third_party');
for k = 1:numel(requested)
    switch requested{k}
        case 'dmd'
            name = 'piDMD';
            folder = fullfile(third_party, 'piDMD');
            if ~isfile(fullfile(folder, 'LICENSE'))
                error('tblR2:ensure_external_toolboxes:MissingPiDMD', ...
                    '缺少本 case 的 piDMD 及原 LICENSE：%s', folder);
            end
        case 'spod'
            name = 'spod';
            if ~isfield(cfg, 'spod') || ~isfield(cfg.spod, 'toolbox_dir') || ...
                    isempty(cfg.spod.toolbox_dir)
                error('tblR2:ensure_external_toolboxes:MissingSPOD', ...
                    ['原 ZIP 未包含 SPOD。请在本 case third_party 内放入合法副本，' ...
                    '并明确设置 cfg.spod.toolbox_dir（含 spod.m 的目录）。']);
            end
            folder = char(java.io.File(cfg.spod.toolbox_dir).getCanonicalPath());
            local_prefix = [third_party filesep];
            if ispc
                is_local = startsWith(lower(folder), lower(local_prefix));
            else
                is_local = startsWith(folder, local_prefix);
            end
            if ~is_local
                error('tblR2:ensure_external_toolboxes:ExternalSPOD', ...
                    'SPOD 必须位于本 case third_party 内：%s', folder);
            end
        otherwise
            error('tblR2:ensure_external_toolboxes:UnknownDependency', ...
                '未知第三方依赖：%s', requested{k});
    end
    expected = fullfile(folder, [name '.m']);
    if ~isfile(expected)
        error('tblR2:ensure_external_toolboxes:MissingLocalFile', ...
            '缺少本 case 第三方文件：%s。不会采用外部已安装的同名函数。', expected);
    end
    % Reject competing copies before changing path; keep user toolboxes intact.
    hits = which(name, '-all');
    if ischar(hits); hits = cellstr(hits); end
    for j = 1:numel(hits)
        actual = char(java.io.File(hits{j}).getCanonicalPath());
        same = strcmp(actual, expected);
        if ispc; same = strcmpi(actual, expected); end
        if ~same
            error('tblR2:ensure_external_toolboxes:ForeignDependency', ...
                ['%s 解析到外部副本：%s。请显式 rmpath 该副本目录后重跑本节；' ...
                '本 case 预期：%s'], name, actual, expected);
        end
    end
    addpath(folder, '-begin');
    actual = char(java.io.File(which(name)).getCanonicalPath());
    same = strcmp(actual, expected);
    if ispc; same = strcmpi(actual, expected); end
    if ~same
        error('tblR2:ensure_external_toolboxes:ForeignDependency', ...
            '%s 未解析到本 case 文件：%s（实际 %s）。', name, expected, actual);
    end
    info.(name) = actual;
end
end
