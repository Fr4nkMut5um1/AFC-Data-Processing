function out = merge_config(base, override)
%MERGE_CONFIG Recursively merge scalar configuration structures.
if ~isstruct(base) || ~isstruct(override) || ~isscalar(base) || ~isscalar(override)
    error('d23:merge_config:InvalidInput', ...
        'Both base and override must be scalar structures.');
end
out = base;
names = fieldnames(override);
for i = 1:numel(names)
    name = names{i};
    value = override.(name);
    if isfield(out, name) && isstruct(out.(name)) && isscalar(out.(name)) && ...
            isstruct(value) && isscalar(value)
        out.(name) = d23.merge_config(out.(name), value);
    else
        out.(name) = value;
    end
end
end
