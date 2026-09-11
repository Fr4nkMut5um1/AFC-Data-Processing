function components = connected_components_2d(mask, connectivity)
%CONNECTED_COMPONENTS_2D Return four- or eight-neighbour 2-D components.
% Uses bwconncomp when it is available, with a toolbox-free flood-fill
% fallback so the VLSM workflow does not require Image Processing Toolbox.

if nargin < 2 || isempty(connectivity)
    connectivity = 4;
end

if ~islogical(mask) || ~ismatrix(mask)
    error('tblR2:vlsm:connected_components_2d:InvalidMask', ...
        'mask 必须是二维逻辑数组。');
end
if ~ismember(connectivity, [4 8])
    error('tblR2:vlsm:connected_components_2d:InvalidConnectivity', ...
        'connectivity 必须是 4 或 8。');
end

if ~any(mask, 'all')
    components = cell(0, 1);
    return;
end

if exist('bwconncomp', 'file') == 2
    try
        cc = bwconncomp(mask, connectivity);
        components = cc.PixelIdxList(:);
        return;
    catch
        % A missing/unlicensed toolbox falls through to the local algorithm.
    end
end

[n_rows, n_cols] = size(mask);
visited = false(n_rows, n_cols);
seeds = find(mask);
queue = zeros(numel(seeds), 1, 'uint32');
components = cell(0, 1);

for seed_index = 1:numel(seeds)
    seed = seeds(seed_index);
    if visited(seed)
        continue;
    end

    head = 1;
    tail = 1;
    queue(1) = uint32(seed);
    visited(seed) = true;

    while head <= tail
        current = double(queue(head));
        head = head + 1;
        [row, col] = ind2sub([n_rows, n_cols], current);

        if row > 1
            neighbour = current - 1;
            if mask(neighbour) && ~visited(neighbour)
                tail = tail + 1;
                queue(tail) = uint32(neighbour);
                visited(neighbour) = true;
            end
        end
        if row < n_rows
            neighbour = current + 1;
            if mask(neighbour) && ~visited(neighbour)
                tail = tail + 1;
                queue(tail) = uint32(neighbour);
                visited(neighbour) = true;
            end
        end
        if col > 1
            neighbour = current - n_rows;
            if mask(neighbour) && ~visited(neighbour)
                tail = tail + 1;
                queue(tail) = uint32(neighbour);
                visited(neighbour) = true;
            end
        end
        if col < n_cols
            neighbour = current + n_rows;
            if mask(neighbour) && ~visited(neighbour)
                tail = tail + 1;
                queue(tail) = uint32(neighbour);
                visited(neighbour) = true;
            end
        end
        if connectivity == 8
            diagonal_rows = [row - 1, row - 1, row + 1, row + 1];
            diagonal_cols = [col - 1, col + 1, col - 1, col + 1];
            for diagonal_index = 1:4
                neighbour_row = diagonal_rows(diagonal_index);
                neighbour_col = diagonal_cols(diagonal_index);
                if neighbour_row < 1 || neighbour_row > n_rows || ...
                        neighbour_col < 1 || neighbour_col > n_cols
                    continue;
                end
                neighbour = sub2ind([n_rows n_cols], ...
                    neighbour_row, neighbour_col);
                if mask(neighbour) && ~visited(neighbour)
                    tail = tail + 1;
                    queue(tail) = uint32(neighbour);
                    visited(neighbour) = true;
                end
            end
        end
    end

    components{end+1, 1} = double(queue(1:tail)); %#ok<AGROW>
end
end
