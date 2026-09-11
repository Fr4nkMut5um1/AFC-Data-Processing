function ctx = prepare_source(cfg)
%PREPARE_SOURCE Validate cache/r2 provenance and read the common grid.
if ~isfile(cfg.data.cache_file)
    error('d23:prepare_source:MissingCache', ...
        'Missing PostProc cache: %s', cfg.data.cache_file);
end
cache = matfile(cfg.data.cache_file);
u_info = whos(cache, 'U');
v_info = whos(cache, 'V');
valid_info = whos(cache, 'sampleValid');
if isempty(u_info) || isempty(v_info) || isempty(valid_info) || ...
        ~isequal(u_info.size, cfg.data.expected_cache_size) || ...
        ~isequal(v_info.size, cfg.data.expected_cache_size) || ...
        ~isequal(valid_info.size, cfg.data.expected_cache_size)
    error('d23:prepare_source:CacheShape', ...
        'PostProc U/V/sampleValid must all be exactly %s.', ...
        mat2str(cfg.data.expected_cache_size));
end
if ~strcmp(u_info.class, 'single') || ~strcmp(v_info.class, 'single') || ...
        ~strcmp(valid_info.class, 'logical')
    error('d23:prepare_source:CacheClass', ...
        'Expected single U/V and logical sampleValid in the PostProc cache.');
end
X = double(cache.X);
Y = double(cache.Y);
expected_grid = cfg.data.expected_cache_size(2:3);
if ~isequal(size(X), expected_grid) || ~isequal(size(Y), expected_grid)
    error('d23:prepare_source:GridShape', 'X/Y do not match the cached grid.');
end
cache_meta = cache.cache_meta;
required_meta = {'case_id', 'source_role', 'cached_size', 'total_frames', ...
    'grid_size', 'created_utc'};
if ~all(isfield(cache_meta, required_meta)) || ...
        ~strcmp(cache_meta.case_id, cfg.case_id) || ...
        ~strcmp(cache_meta.source_role, 'postproc') || ...
        cache_meta.total_frames ~= cfg.data.expected_cache_size(1) || ...
        ~isequal(double(cache_meta.cached_size), cfg.data.expected_cache_size)
    error('d23:prepare_source:CacheIdentity', ...
        'PostProc cache metadata does not match the locked case/size contract.');
end
source_grid_info = whos(cache, 'source_grid_size');
if ~isempty(source_grid_info)
    source_grid_size = double(cache.source_grid_size);
else
    source_grid_size = double(cache_meta.grid_size);
end
frame_ids = double(cache.frame_ids(:, 1));
if ~isequal(frame_ids, (1:cfg.data.expected_cache_size(1)).')
    error('d23:prepare_source:FrameIdentity', ...
        'Cache frame_ids must be exactly the ordered 1:12000 contract.');
end
x_mm = median(X, 1, 'omitnan');
y_grid_mm = median(Y, 2, 'omitnan');
dx_values = diff(x_mm);
dy_values = diff(y_grid_mm);
spacing_info = whos(cache, 'h_mm');
if ~isempty(spacing_info)
    dx_mm = double(cache.h_mm);
else
    dx_mm = median(dx_values, 'omitnan');
end
dy_mm = median(dy_values, 'omitnan');
grid_tol_x = 0.01 * abs(dx_mm);
grid_tol_y = 0.01 * abs(dy_mm);
rectilinear_x_deviation = max(abs(X - repmat(x_mm, size(X, 1), 1)), [], 'all');
rectilinear_y_deviation = max(abs(Y - repmat(y_grid_mm, 1, size(Y, 2))), [], 'all');
if ~all(isfinite(x_mm)) || ~all(isfinite(y_grid_mm)) || ...
        dx_mm <= 0 || dy_mm <= 0 || ...
        max(abs(dx_values - dx_mm)) > grid_tol_x || ...
        max(abs(dy_values - dy_mm)) > grid_tol_y || ...
        rectilinear_x_deviation > grid_tol_x || ...
        rectilinear_y_deviation > grid_tol_y
    error('d23:prepare_source:NonuniformGrid', ...
        'The implementation requires the measured rectilinear uniform grid.');
end
utau = d23.load_utau(cfg.data.utau_result_file, cfg.case_id, ...
    cfg.data.expected_cache_size(1), expected_grid);
if isfield(utau.meta, 'grid_size') && ...
        ~isequal(double(utau.meta.grid_size), source_grid_size)
    error('d23:prepare_source:SourceGridMismatch', ...
        'The r2 source grid does not match the PostProc cache source grid.');
end
cache_info = dir(cfg.data.cache_file);
[spatial_exclusion_mask, spatial_exclusion] = ...
    d23.resolve_spatial_exclusion(X, utau.wall_distance_mm, ...
    cfg.preprocessing.spatial_exclusion);
ctx = struct();
ctx.cache_file = cfg.data.cache_file;
ctx.cache_meta = cache_meta;
ctx.cache_size = cfg.data.expected_cache_size;
ctx.source_grid_size = source_grid_size;
ctx.frame_ids = frame_ids;
ctx.X_mm = X;
ctx.Y_mm = Y;
ctx.x_mm = x_mm;
ctx.y_grid_mm = y_grid_mm;
ctx.dx_mm = dx_mm;
ctx.dy_mm = dy_mm;
ctx.rectilinear_x_deviation_mm = rectilinear_x_deviation;
ctx.rectilinear_y_deviation_mm = rectilinear_y_deviation;
ctx.wall_distance_mm = utau.wall_distance_mm;
ctx.spatial_exclusion_mask = spatial_exclusion_mask;
ctx.spatial_exclusion = spatial_exclusion;
ctx.u_tau_m_s = utau.u_tau_m_s;
ctx.utau_source = rmfield(utau, 'wall_distance_mm');
ctx.cache_source = struct('path', cfg.data.cache_file, ...
    'bytes', cache_info.bytes, 'datenum', cache_info.datenum, ...
    'created_utc', cache_meta.created_utc);
ctx.source_fingerprint = d23.sha256_text(jsonencode(struct( ...
    'cache_path', cfg.data.cache_file, 'cache_bytes', cache_info.bytes, ...
    'cache_datenum', cache_info.datenum, ...
    'cache_created_utc', cache_meta.created_utc, ...
    'utau_path', utau.path, 'utau_bytes', utau.bytes, ...
    'utau_datenum', utau.datenum)));
end
