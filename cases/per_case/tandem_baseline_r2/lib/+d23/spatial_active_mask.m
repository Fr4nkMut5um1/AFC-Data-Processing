function mask = spatial_active_mask(ctx)
%SPATIAL_ACTIVE_MASK Return the persistent Section-4 analysis domain.
expected = double(ctx.cache_size(2:3));
if isfield(ctx, 'spatial_exclusion_mask') && ...
        ~isempty(ctx.spatial_exclusion_mask)
    excluded = logical(ctx.spatial_exclusion_mask);
    if ~isequal(size(excluded), expected)
        error('d23:spatial_active_mask:ShapeMismatch', ...
            'The spatial exclusion mask does not match the cached grid.');
    end
else
    excluded = false(expected);
end
mask = ~excluded;
end
