function identity = sequence_cache_identity(filename, cfg, source)
%SEQUENCE_CACHE_IDENTITY Read-only cache evidence; no velocity/frame-content hash.
% Validates all repeat roots/ids/offsets/boundaries, fs, actual dimensions/classes,
% and coordinate/crop contract before recording the metadata and grid identities.
tblR2.validate_sequence_cache(filename, cfg, source);
small = load(filename, 'cache_meta','X','Y','h_mm','frame_ids', ...
    'source_grid_size','j_wall_removed');
item = dir(filename);
identity = struct('path', char(java.io.File(filename).getCanonicalPath()), ...
    'bytes', item.bytes, 'datenum', item.datenum, 'metadata', small, ...
    'identity_scope', 'validated metadata/grid/frame IDs plus file size/time; not per-frame content hash');
end
