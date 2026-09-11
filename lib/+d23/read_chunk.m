function chunk = read_chunk(cache_file, frame_ordinals)
%READ_CHUNK Read raw PostProc frames as double with a synchronized mask.
frame_ordinals = double(frame_ordinals(:));
if isempty(frame_ordinals) || any(frame_ordinals < 1) || ...
        any(frame_ordinals ~= fix(frame_ordinals))
    error('d23:read_chunk:InvalidFrames', 'Frame ordinals must be positive integers.');
end
cache = matfile(cache_file);
info = whos(cache, 'U');
if any(frame_ordinals > info.size(1))
    error('d23:read_chunk:OutOfRange', 'A requested frame is outside the cache.');
end
ny = info.size(2);
nx = info.size(3);
if numel(frame_ordinals) == 1 || all(diff(frame_ordinals) == 1)
    U = double(cache.U(frame_ordinals, :, :));
    V = double(cache.V(frame_ordinals, :, :));
    valid = logical(cache.sampleValid(frame_ordinals, :, :));
else
    U = nan(numel(frame_ordinals), ny, nx);
    V = nan(size(U));
    valid = false(size(U));
    for i = 1:numel(frame_ordinals)
        U(i, :, :) = double(cache.U(frame_ordinals(i), :, :));
        V(i, :, :) = double(cache.V(frame_ordinals(i), :, :));
        valid(i, :, :) = logical(cache.sampleValid(frame_ordinals(i), :, :));
    end
end
valid = valid & isfinite(U) & isfinite(V);
U(~valid) = NaN;
V(~valid) = NaN;
chunk = struct('U', U, 'V', V, 'valid', valid, ...
    'frame_ordinals', frame_ordinals);
end
