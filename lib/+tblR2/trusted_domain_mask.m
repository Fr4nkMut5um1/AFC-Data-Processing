function trusted = trusted_domain_mask(valid_mask, Y_wall_mm, options)
%TRUSTED_DOMAIN_MASK Keep only the declared outer trusted analysis domain.
%   The Section-4 nominal domain removes only:
%     (1) a fixed number of columns at the upstream/downstream FOV edges;
%     (2) the rows with the largest wall-normal coordinate in each column.
%   It deliberately does not erode around internal NaN/mask gaps.  Any
%   finite max_wall_normal_delta limit is an independent optional physical
%   restriction applied later by identify_structures.

if nargin < 3 || isempty(options)
    options = struct();
end
if ~islogical(valid_mask) || ~ismatrix(valid_mask) || ...
        ~isequal(size(valid_mask), size(Y_wall_mm))
    error('tblR2:trusted_domain_mask:SizeMismatch', ...
        'valid_mask 和 Y_wall_mm 必须是尺寸相同的二维数组。');
end

edge_columns = resolve_count(options, 'streamwise_edge_columns');
top_rows = resolve_count(options, 'wall_normal_top_rows');
trusted = valid_mask;
[n_rows, n_cols] = size(trusted);

if edge_columns > 0
    n_edge = min(edge_columns, floor(n_cols / 2));
    trusted(:, 1:n_edge) = false;
    trusted(:, n_cols - n_edge + 1:n_cols) = false;
end

if top_rows > 0
    for col = 1:n_cols
        candidate = find(isfinite(Y_wall_mm(:, col)));
        if isempty(candidate)
            continue;
        end
        [~, order] = sort(Y_wall_mm(candidate, col), 'descend');
        remove = candidate(order(1:min(top_rows, numel(order))));
        trusted(remove, col) = false;
    end
end
end

function value = resolve_count(options, name)
if ~isfield(options, name) || isempty(options.(name))
    value = 0;
    return;
end
value = options.(name);
if ~(isnumeric(value) && isscalar(value) && isfinite(value) && ...
        value >= 0 && value == fix(value))
    error('tblR2:trusted_domain_mask:InvalidCount', ...
        '%s 必须是非负整数标量。', name);
end
value = double(value);
end
