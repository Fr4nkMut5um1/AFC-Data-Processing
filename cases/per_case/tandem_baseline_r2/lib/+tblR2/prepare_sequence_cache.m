function info = prepare_sequence_cache(cfg, paths, source_role)
%PREPARE_SEQUENCE_CACHE Convert DAT frames to an on-disk single-precision cache.
%
% Contract (schema_version=4):
%   * The completed cache file contains U, V, sampleValid with size
%     [2*n_frames J I] (single for U/V, logical for sampleValid) formed by
%     concatenating the two selected numbered repeats (repeat 1 frames
%     1:n_frames, repeat 2 frames n_frames+1:2*n_frames), X and Y
%     (J x I double, mm), h_mm (scalar double), frame_ids (2*n_frames x 1
%     column vector 1:2*n_frames), source_grid_size (1 x 2 double),
%     j_wall_removed (scalar double) and cache_meta (scalar struct).
%   * cache_meta.schema_version is 4 and carries case_id, data_root,
%     grid_size, cached_size, n_frames (per-repeat), total_frames,
%     frame_offset (repeat 1), source_first_file, source_last_file, fs,
%     precision, created_utc, repeat_ids (1x2 cellstr), repeat_roots
%     (1x2 cellstr), repeat_offsets (1x2 double), repeat_boundaries
%     (n_frames x (n_repeats-1) double), repeat_means (2 x n_repeats x J x I,
%     per-repeat temporal mean of U and V, for fluctuation concatenation).
%   * cfg.stages.cache semantics live in the case script: Section 1 prepares
%     both raw and postproc caches; reuse validates and returns a matching
%     cache before touching the DAT source, so an unavailable original data
%     disk does not prevent independent cache reuse. A missing cache is built
%     at the explicitly supplied local path; no legacy cache path is searched.
%     Compute forces a rebuild from the explicitly declared DAT sources.
%   * A new cache is written to a temporary file next to the final path and
%     atomically moved into place, so an interrupted build never leaves a
%     half-written mat/01_sequence_cache.mat and never deletes the previous
%     good cache before the replacement is ready.
%   * source_role selects the DAT root and cache path: 'raw' uses
%     cfg.sources.raw / paths.sequence_cache, 'postproc' uses
%     cfg.sources.postproc / paths.sequence_cache_postproc.
%   * cfg.sources.(source_role) may be a plain folder (legacy single-repeat
%     contract, n_frames total) or a struct with roots/offsets/ids for two
%     repeats (n_frames per repeat, 2*n_frames total).

if nargin < 3 || isempty(source_role)
    source_role = 'raw';
end
source_role = char(source_role);
if ~ismember(source_role, {'raw', 'postproc'})
    error('tblR2:prepare_sequence_cache:InvalidSourceRole', ...
        'source_role 必须是 raw 或 postproc。');
end
% rebuild_cache 已由主脚本从 stages.cache 派生一次；维护调用者显式提供它。
if ~isfield(cfg, 'wall_side')
    cfg.wall_side = 'bottom';
end
cfg.wall_side = char(cfg.wall_side);

% --- repeat-aware source resolution ----------------------------------------
% cfg.sources.(source_role) may be a single folder (legacy) or a struct with
% fields roots (1x2 cellstr), offsets (1x2 double), ids (1x2 cellstr) for the
% two selected repeats. n_frames is the per-repeat frame count; the cache
% stores 2*n_frames concatenated frames.
repeat_roots = {cfg.sources.(source_role)};
repeat_offsets = cfg.frame_offset;
repeat_ids = {''};
if isstruct(cfg.sources.(source_role)) && ...
        isfield(cfg.sources.(source_role), 'roots')
    rep_spec = cfg.sources.(source_role);
    repeat_roots = rep_spec.roots(:).';
    repeat_offsets = rep_spec.offsets(:).';
    repeat_ids = rep_spec.ids(:).';
    if numel(repeat_roots) ~= 2 || numel(repeat_offsets) ~= 2
        error('tblR2:prepare_sequence_cache:BadRepeatSpec', ...
            'cfg.sources.%s.repeats 必须包含恰好两个根目录和偏移量。', ...
            source_role);
    end
end
n_repeats = numel(repeat_roots);
total_frames = n_repeats * cfg.n_frames;

source_root = repeat_roots{1};
cache_filename = paths.sequence_cache;
manifest_filename = paths.source_manifest;
if strcmp(source_role, 'postproc')
    cache_filename = paths.sequence_cache_postproc;
    manifest_filename = paths.source_manifest_postproc;
end

% 复用必须先于源目录检查：只要缓存合同匹配，就不再访问原始数据盘。
raw_j_wall_removed = [];
if ~logical(cfg.rebuild_cache)
    reusable_file = '';
    if isfile(cache_filename)
        reusable_file = cache_filename;
    end
    if ~isempty(reusable_file)
        info = tblR2.validate_sequence_cache(reusable_file, cfg, source_role);
        stale_postproc_crop = false;
        if strcmp(source_role, 'postproc') && isfile(paths.sequence_cache)
            % raw 缓存存在时继续核对壁面裁剪；raw 缓存缺失时仍允许
            % postproc 缓存独立复用，主脚本后续的双源网格校验会给出明确提示。
            raw_meta = load(paths.sequence_cache, 'j_wall_removed');
            raw_j_wall_removed = double(raw_meta.j_wall_removed);
            stale_postproc_crop = info.j_wall_removed ~= raw_j_wall_removed;
        end
        if stale_postproc_crop
            fprintf(['[缓存] postproc 的 j_wall_removed=%d 与 raw 的 %d 不同，' ...
                '正在重建对齐缓存。\n'], info.j_wall_removed, ...
                raw_j_wall_removed);
        else
            info.reused = true;
            info.legacy_location = false; % Kept as metadata for old readers; no fallback.
            print_reuse_notice(info, source_role, reusable_file);
            return;
        end
    end
end

% 只有缓存缺失、缓存合同不匹配或 compute 强制重建时，才访问 DAT 源。
if strcmp(source_role, 'postproc')
    if ~isfile(paths.sequence_cache)
        error('tblR2:input:MissingRawCacheForPostproc', ...
            '构建 PostProc 缓存前必须先有 raw 序列缓存：%s', ...
            paths.sequence_cache);
    end
    raw_meta = load(paths.sequence_cache, 'j_wall_removed');
    raw_j_wall_removed = double(raw_meta.j_wall_removed);
end

for r = 1:n_repeats
    if ~isfolder(repeat_roots{r})
        error('tblR2:input:MissingDataRoot', ...
            ['数据目录不存在：%s\n应包含连续的 B0001.dat ... B%04d.dat 文件。' ...
             '请检查数据盘是否已挂载，并更新 cfg.sources.%s。'], ...
            repeat_roots{r}, cfg.n_frames, source_role);
    end
    dat_files = dir(fullfile(repeat_roots{r}, 'B*.dat'));
    required_files = repeat_offsets(r) + cfg.n_frames;
    if numel(dat_files) < required_files
        error('tblR2:input:FrameWindowOutOfRange', ...
            ['声明的帧窗口 B%04d.dat..B%04d.dat 需要 %d 个源文件，' ...
             '但在 %s 中只找到 %d 个。请检查 cfg.frame_offset 和 cfg.n_frames。'], ...
            repeat_offsets(r) + 1, ...
            repeat_offsets(r) + cfg.n_frames, required_files, ...
            repeat_roots{r}, numel(dat_files));
    end
end

% 只有实际需要读取 DAT 时才生成 manifest；纯缓存复用保持只读。
manifest = tblR2.singlecase.dat_manifest( ...
    repeat_roots{1}, cfg.n_frames, repeat_offsets(1));
for r = 2:n_repeats
    manifest_r = tblR2.singlecase.dat_manifest( ...
        repeat_roots{r}, cfg.n_frames, repeat_offsets(r));
    manifest = [manifest, manifest_r]; %#ok<AGROW>
end
manifest_table = struct2table(manifest);
writetable(manifest_table, manifest_filename, 'Encoding', 'UTF-8');

temporary_file = [tempname(paths.mat), '.mat'];
try
    first_end = min(cfg.chunk_frames, cfg.n_frames);
    first = tblR2.io.load_tecplot_dat( ...
        repeat_roots{1}, [1 first_end], cfg.grid_size, ...
        repeat_offsets(1), cfg.wall_side, raw_j_wall_removed, true);
    J = size(first.U, 2);
    I = size(first.U, 3);
    if I ~= cfg.grid_size(1)
        error('tblR2:input:UnexpectedCroppedGrid', ...
            '读取后的流向网格大小为 %d，预期为 %d。', ...
            I, cfg.grid_size(1));
    end

    cache = matfile(temporary_file, 'Writable', true);
    cache.U(total_frames, J, I) = single(NaN);
    cache.V(total_frames, J, I) = single(NaN);
    cache.sampleValid(total_frames, J, I) = false;
    cache.X = double(first.X);
    cache.Y = double(first.Y);
    cache.h_mm = double(first.h);
    cache.frame_ids = (1:total_frames)';
    cache.source_grid_size = double(cfg.grid_size);
    cache.j_wall_removed = double(first.j_wall_removed);

    % Per-repeat: load in chunks, validate grid/wall crop consistency both
    % within and across repeats, write into the concatenated cache, and
    % accumulate the per-repeat mean (used by fluctuation concatenation).
    repeat_means = zeros(2, n_repeats, J, I);
    for r = 1:n_repeats
        block_offset = (r - 1) * cfg.n_frames;
        first_end = min(cfg.chunk_frames, cfg.n_frames);
        first = tblR2.io.load_tecplot_dat( ...
            repeat_roots{r}, [1 first_end], cfg.grid_size, ...
            repeat_offsets(r), cfg.wall_side, raw_j_wall_removed, true);
        cache.U(block_offset + 1:block_offset + first_end, :, :) = ...
            single(first.U);
        cache.V(block_offset + 1:block_offset + first_end, :, :) = ...
            single(first.V);
        cache.sampleValid(block_offset + 1:block_offset + first_end, ...
            :, :) = logical(first.sampleValid);
        repeat_mean_u = zeros(J, I);
        repeat_mean_v = zeros(J, I);
        repeat_mean_cnt = zeros(J, I);
        repeat_mean_u = repeat_mean_u + squeeze(sum(double(first.U), 1));
        repeat_mean_v = repeat_mean_v + squeeze(sum(double(first.V), 1));
        repeat_mean_cnt = repeat_mean_cnt + first_end;
        for frame_start = first_end + 1:cfg.chunk_frames:cfg.n_frames
            frame_end = min(cfg.n_frames, frame_start + cfg.chunk_frames - 1);
            field = tblR2.io.load_tecplot_dat( ...
                repeat_roots{r}, [frame_start frame_end], cfg.grid_size, ...
                repeat_offsets(r), cfg.wall_side, raw_j_wall_removed, true);
            if ~isequal(size(field.X), [J I]) || ...
                    max(abs(field.X(:) - first.X(:)), [], 'omitnan') > 1e-9 || ...
                    max(abs(field.Y(:) - first.Y(:)), [], 'omitnan') > 1e-9
                error('tblR2:input:GridChanged', ...
                    ['repeat %d 的帧 %d-%d 坐标或裁剪网格尺寸发生变化。' ...
                     '请检查这些 DAT 文件和壁面掩膜，不要把不同导出结果拼到同一工况。'], ...
                    r, frame_start, frame_end);
            end
            if field.j_wall_removed ~= first.j_wall_removed
                error('tblR2:input:WallCropChanged', ...
                    ['repeat %d 的帧 %d-%d 壁面行检测从 %d 变为 %d。' ...
                     '请检查源文件中的 isValid 和壁面掩膜。'], ...
                    r, frame_start, frame_end, first.j_wall_removed, ...
                    field.j_wall_removed);
            end
            cache.U(block_offset + frame_start:block_offset + frame_end, ...
                :, :) = single(field.U);
            cache.V(block_offset + frame_start:block_offset + frame_end, ...
                :, :) = single(field.V);
            cache.sampleValid(block_offset + frame_start:block_offset + ...
                frame_end, :, :) = logical(field.sampleValid);
            repeat_mean_u = repeat_mean_u + squeeze(sum(double(field.U), 1));
            repeat_mean_v = repeat_mean_v + squeeze(sum(double(field.V), 1));
            repeat_mean_cnt = repeat_mean_cnt + (frame_end - frame_start + 1);
        end
        repeat_means(1, r, :, :) = repeat_mean_u ./ max(repeat_mean_cnt, 1);
        repeat_means(2, r, :, :) = repeat_mean_v ./ max(repeat_mean_cnt, 1);
    end

    cache_meta = struct();
    cache_meta.schema_version = 4;
    cache_meta.case_id = cfg.case_id;
    cache_meta.data_root = repeat_roots{1};
    cache_meta.repeat_ids = repeat_ids;
    cache_meta.repeat_roots = repeat_roots;
    cache_meta.repeat_offsets = repeat_offsets;
    if n_repeats > 1
        cache_meta.repeat_boundaries = cfg.n_frames * (1:n_repeats - 1);
    else
        cache_meta.repeat_boundaries = [];
    end
    cache_meta.repeat_means = repeat_means;
    cache_meta.source_role = source_role;
    cache_meta.source_root = source_root;
    cache_meta.wall_side = cfg.wall_side;
    cache_meta.grid_size = cfg.grid_size;
    cache_meta.cached_size = [total_frames J I];
    cache_meta.n_frames = cfg.n_frames; % per-repeat frame count
    cache_meta.total_frames = total_frames;
    cache_meta.frame_offset = repeat_offsets(1);
    cache_meta.source_first_file = sprintf( ...
        'B%04d.dat', repeat_offsets(1) + 1);
    cache_meta.source_last_file = sprintf( ...
        'B%04d.dat', repeat_offsets(1) + cfg.n_frames);
    cache_meta.fs = cfg.fs;
    cache_meta.precision = 'single';
    cache_meta.y_mapping = struct( ...
        'version', 1, ...
        'method', 'first_retained_row_0_plus_h', ...
        'equation', 'y(j) = j * h_y; wall at y = 0, first retained row y = 0 + h_y', ...
        'h_y_mm', double(first.h_y_mm));
    cache_meta.created_utc = char(datetime('now', 'TimeZone', 'UTC', ...
        'Format', 'yyyy-MM-dd''T''HH:mm:ssXXX'));
    cache.cache_meta = cache_meta;
    clear cache

    % Replace the final path with one move: movefile(...,'f') overwrites the
    % destination, so a failed move cannot leave the previous good cache deleted.
    [ok, message] = movefile(temporary_file, cache_filename, 'f');
    if ~ok
        error('tblR2:input:CacheMoveFailed', ...
            '无法将已完成的序列缓存移动到目标位置：%s', message);
    end
catch ME
    if isfile(temporary_file)
        delete(temporary_file);
    end
    rethrow(ME);
end

info = tblR2.validate_sequence_cache(cache_filename, cfg, source_role);
info.reused = false;
info.legacy_location = false;
end

function print_reuse_notice(info, source_role, filename)
%PRINT_REUSE_NOTICE 在命令行显示缓存复用及其创建时的数据源位置。
meta = info.cache_meta;
created_utc = '未记录';
if isfield(meta, 'created_utc') && ~isempty(meta.created_utc)
    created_utc = char(meta.created_utc);
end
source_root = '未记录';
if isfield(meta, 'source_root') && ~isempty(meta.source_root)
    source_root = char(meta.source_root);
elseif isfield(meta, 'data_root') && ~isempty(meta.data_root)
    source_root = char(meta.data_root);
end

fprintf('[缓存复用] %s：%s\n', source_role, filename);
fprintf('  缓存创建时间：%s\n', created_utc);
fprintf('  创建时源数据盘位置：%s\n', source_root);
if isfield(meta, 'repeat_roots') && ~isempty(meta.repeat_roots)
    repeat_roots = meta.repeat_roots;
    if ischar(repeat_roots)
        repeat_roots = {char(repeat_roots)};
    elseif isstring(repeat_roots)
        repeat_roots = cellstr(repeat_roots);
    end
    for k = 1:numel(repeat_roots)
        fprintf('  创建时第 %d 个重复序列：%s\n', k, ...
            char(repeat_roots{k}));
    end
end
end
