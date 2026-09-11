function require_case_library(case_root, names)
%REQUIRE_CASE_LIBRARY Check the package functions this section actually uses.
% Does not change path, clear functions, or remove any user toolbox.
case_root = char(java.io.File(case_root).getCanonicalPath());
library_root = fullfile(case_root, 'lib');
for k = 1:numel(names)
    name = names{k};
    parts = strsplit(name, '.');
    folders = cellfun(@(p) ['+' p], parts(1:end-1), 'UniformOutput', false);
    expected = fullfile(library_root, folders{:}, [parts{end} '.m']);
    if ~isfile(expected)
        error('tblR2:require_case_library:MissingLocalDependency', ...
            '本节缺少本 case 函数：%s。请恢复该 case 的 lib。', expected);
    end
    hits = which(name, '-all');
    if ischar(hits); hits = cellstr(hits); end
    if isempty(hits)
        error('tblR2:require_case_library:UnresolvedDependency', ...
            '未找到 %s。请先 Run Section 0；预期：%s。', name, expected);
    end
    for j = 1:numel(hits)
        actual = char(java.io.File(hits{j}).getCanonicalPath());
        same = strcmp(actual, expected);
        if ispc; same = strcmpi(actual, expected); end
        if ~same
            error('tblR2:require_case_library:ForeignDependency', ...
                ['%s 存在其他 case/目录的同名副本：%s。请显式 rmpath 旧 lib ' ...
                '后重跑 Section 0；本 case 预期：%s。'], name, actual, expected);
        end
    end
end
end
