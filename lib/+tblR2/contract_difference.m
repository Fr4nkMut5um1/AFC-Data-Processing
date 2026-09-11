function message = contract_difference(saved, current, name)
%CONTRACT_DIFFERENCE First exact metadata difference, including array/cell index.
if nargin < 3; name = 'contract'; end
message = '';
if isequaln(saved, current); return; end
if ~strcmp(class(saved), class(current)) || ~isequal(size(saved), size(current))
    message = sprintf('%s: saved %s %s; current %s %s', name, ...
        class(saved), mat2str(size(saved)), class(current), mat2str(size(current)));
elseif isstruct(saved)
    names = union(fieldnames(saved), fieldnames(current), 'stable');
    for j = 1:numel(saved)
        for k = 1:numel(names)
            field = names{k}; path = [name '.' field];
            if numel(saved) > 1; path = sprintf('%s(%d).%s', name, j, field); end
            if ~isfield(saved, field) || ~isfield(current, field)
                message = [path ': missing field']; return;
            end
            message = tblR2.contract_difference(saved(j).(field), current(j).(field), path);
            if ~isempty(message); return; end
        end
    end
elseif iscell(saved)
    for k = 1:numel(saved)
        message = tblR2.contract_difference(saved{k}, current{k}, sprintf('%s{%d}', name, k));
        if ~isempty(message); return; end
    end
elseif isnumeric(saved) || islogical(saved)
    k = find(~(saved == current | (isnan(saved) & isnan(current))), 1);
    message = sprintf('%s(%d): saved %s; current %s', name, k, ...
        mat2str(saved(k)), mat2str(current(k)));
elseif ischar(saved) || isstring(saved)
    message = sprintf('%s: saved "%s"; current "%s"', name, ...
        char(join(string(saved), ',')), char(join(string(current), ',')));
else
    message = [name ': value changed'];
end
end
