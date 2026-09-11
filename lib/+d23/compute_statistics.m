function stats = compute_statistics(ctx, cfg, run_dir)
%COMPUTE_STATISTICS Two-pass global 12,000-frame PostProc statistics.
final_file = fullfile(run_dir, 'mat', 'statistics.mat');
if ~isempty(cfg.statistics.reuse_file)
    loaded = load(cfg.statistics.reuse_file, 'stats', 'stats_meta');
    validate_reused(loaded, ctx);
    stats = loaded.stats;
    stats.reused_from = cfg.statistics.reuse_file;
    d23.atomic_save(final_file, struct('stats', stats, ...
        'stats_meta', loaded.stats_meta));
    return;
end
if isfile(final_file)
    loaded = load(final_file, 'stats', 'stats_meta');
    validate_reused(loaded, ctx);
    stats = loaded.stats;
    return;
end

nt = ctx.cache_size(1);
ny = ctx.cache_size(2);
nx = ctx.cache_size(3);
all_frames = double(cfg.statistics.frame_ordinals(:));
if ~isequal(all_frames, (1:nt).')
    error('d23:compute_statistics:FrameContract', ...
        'Statistics must use every ordered PostProc frame exactly once.');
end
checkpoint_file = fullfile(run_dir, 'checkpoints', 'statistics_checkpoint.mat');
if isfile(checkpoint_file)
    loaded = load(checkpoint_file, 'checkpoint');
    checkpoint = loaded.checkpoint;
    if ~strcmp(checkpoint.source_fingerprint, ctx.source_fingerprint)
        error('d23:compute_statistics:ResumeMismatch', ...
            'Statistics checkpoint source changed.');
    end
else
    checkpoint = struct('schema_version', 1, 'stage', 1, 'next_frame', 1, ...
        'sum_u', zeros(ny, nx), 'sum_v', zeros(ny, nx), ...
        'valid_count', zeros(ny, nx, 'uint32'), ...
        'source_fingerprint', ctx.source_fingerprint, ...
        'updated_utc', d23.utc_now());
end
chunk_size = cfg.statistics.chunk_size;
if checkpoint.stage == 1
    for first = checkpoint.next_frame:chunk_size:nt
        ids = first:min(first + chunk_size - 1, nt);
        chunk = d23.read_chunk(ctx.cache_file, ids);
        checkpoint.sum_u = checkpoint.sum_u + ...
            squeeze(sum(chunk.U, 1, 'omitnan'));
        checkpoint.sum_v = checkpoint.sum_v + ...
            squeeze(sum(chunk.V, 1, 'omitnan'));
        checkpoint.valid_count = checkpoint.valid_count + ...
            uint32(squeeze(sum(chunk.valid, 1)));
        checkpoint.next_frame = ids(end) + 1;
        checkpoint.updated_utc = d23.utc_now();
        d23.atomic_save(checkpoint_file, struct('checkpoint', checkpoint));
    end
    valid_count_double = double(checkpoint.valid_count);
    Ubar = checkpoint.sum_u ./ valid_count_double;
    Vbar = checkpoint.sum_v ./ valid_count_double;
    Ubar(valid_count_double == 0) = NaN;
    Vbar(valid_count_double == 0) = NaN;
    checkpoint = struct('schema_version', 1, 'stage', 2, 'next_frame', 1, ...
        'Ubar', Ubar, 'Vbar', Vbar, ...
        'valid_count', checkpoint.valid_count, ...
        'sum_up2_y', zeros(ny, 1), ...
        'valid_count_y', zeros(ny, 1, 'uint64'), ...
        'source_fingerprint', ctx.source_fingerprint, ...
        'updated_utc', d23.utc_now());
    d23.atomic_save(checkpoint_file, struct('checkpoint', checkpoint));
end
if checkpoint.stage ~= 2
    error('d23:compute_statistics:InvalidCheckpoint', ...
        'Unknown statistics checkpoint stage.');
end
for first = checkpoint.next_frame:chunk_size:nt
    ids = first:min(first + chunk_size - 1, nt);
    chunk = d23.read_chunk(ctx.cache_file, ids);
    up = chunk.U - reshape(checkpoint.Ubar, 1, ny, nx);
    up(~chunk.valid) = NaN;
    block_sum = squeeze(sum(sum(up .^ 2, 1, 'omitnan'), 3, 'omitnan'));
    block_count = squeeze(sum(sum(chunk.valid, 1), 3));
    checkpoint.sum_up2_y = checkpoint.sum_up2_y + block_sum(:);
    checkpoint.valid_count_y = checkpoint.valid_count_y + uint64(block_count(:));
    checkpoint.next_frame = ids(end) + 1;
    checkpoint.updated_utc = d23.utc_now();
    d23.atomic_save(checkpoint_file, struct('checkpoint', checkpoint));
end
count_y = double(checkpoint.valid_count_y);
u_rms_y = sqrt(checkpoint.sum_up2_y ./ count_y);
u_rms_y(count_y == 0) = NaN;
stats = struct('Ubar', checkpoint.Ubar, 'Vbar', checkpoint.Vbar, ...
    'valid_count_xy', checkpoint.valid_count, ...
    'valid_count_y', checkpoint.valid_count_y, ...
    'u_rms_y', u_rms_y, 'n_frames', nt, ...
    'mean_definition', 'global 12000-frame valid-sample mean', ...
    'rms_definition', 'pooled x,t RMS about global Ubar(x,y)', ...
    'created_utc', d23.utc_now(), 'reused_from', '');
stats_meta = struct('schema_version', 1, ...
    'source_fingerprint', ctx.source_fingerprint, ...
    'cache_size', ctx.cache_size, 'frame_ordinals', all_frames);
d23.atomic_save(final_file, struct('stats', stats, 'stats_meta', stats_meta));
if isfile(checkpoint_file)
    delete(checkpoint_file);
end
end

function validate_reused(loaded, ctx)
if ~isfield(loaded, 'stats') || ~isfield(loaded, 'stats_meta') || ...
        ~strcmp(loaded.stats_meta.source_fingerprint, ctx.source_fingerprint) || ...
        ~isequal(double(loaded.stats_meta.cache_size), double(ctx.cache_size)) || ...
        loaded.stats.n_frames ~= ctx.cache_size(1)
    error('d23:compute_statistics:ReuseMismatch', ...
        'Reused statistics do not match the current source/cache contract.');
end
end
