function repo_root = locate_repository_root(script_file, allow_pwd_fallback)
%LOCATE_REPOSITORY_ROOT Find the repository that owns third_party tools.

if nargin < 2
    allow_pwd_fallback = true;
end
if isempty(script_file) || ...
        ~(isfile(script_file) || exist(script_file, 'file') == 2)
    error('tblR2:locate_repository_root:MissingScript', ...
        '周期 case 脚本路径无效：%s', char(script_file));
end
starts = {fileparts(script_file)};
if allow_pwd_fallback
    starts{end + 1} = pwd; %#ok<AGROW>
end
checked = {};
for i = 1:numel(starts)
    current = starts{i};
    while ~isempty(current)
        marker = fullfile(current, 'third_party');
        checked{end + 1} = marker; %#ok<AGROW>
        if isfolder(marker) || exist(marker, 'dir') == 7
            repo_root = current;
            return;
        end
        parent = fileparts(current);
        if strcmp(parent, current)
            break;
        end
        current = parent;
    end
end
checked = unique(checked, 'stable');
error('tblR2:locate_repository_root:MissingRepositoryRoot', ...
    ['无法找到包含 third_party 的项目根目录。脚本：%s；当前文件夹：%s；' ...
    '已检查：%s'], script_file, pwd, strjoin(checked, ' | '));
end
