function buffered = buffer_valid_mask(valid_mask, buffer_cells)
%BUFFER_VALID_MASK Erode a trusted 2-D domain by a rectangular cell buffer.
% A point remains valid only when every point in its surrounding
% (2*row_buffer+1)-by-(2*column_buffer+1) stencil is valid. Zero padding
% deliberately removes the outer field-of-view boundary as well as the
% configured neighbourhood of internal masks/contamination gaps.

if ~islogical(valid_mask) || ~ismatrix(valid_mask)
    error('tblR2:buffer_valid_mask:InvalidMask', ...
        'valid_mask 必须是二维逻辑数组。');
end
if isscalar(buffer_cells)
    buffer_cells = [buffer_cells buffer_cells];
end
if ~(isnumeric(buffer_cells) && numel(buffer_cells) == 2 && ...
        all(isfinite(buffer_cells)) && all(buffer_cells >= 0) && ...
        all(buffer_cells == fix(buffer_cells)))
    error('tblR2:buffer_valid_mask:InvalidBuffer', ...
        'buffer_cells 必须是非负整数标量或 [行 列] 向量。');
end
buffer_cells = double(reshape(buffer_cells, 1, 2));
if all(buffer_cells == 0)
    buffered = valid_mask;
    return;
end
kernel = ones(2 * buffer_cells(1) + 1, 2 * buffer_cells(2) + 1);
required = numel(kernel);
buffered = conv2(double(valid_mask), kernel, 'same') == required;
end
