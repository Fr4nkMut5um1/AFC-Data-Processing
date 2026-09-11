function chunk = fluctuation_chunk(ctx, stats, cfg, frame_ordinals, pod_file)
%FLUCTUATION_CHUNK Produce u',v' in locked POD-then-Gaussian order.
if nargin < 5
    pod_file = '';
end
ny = ctx.cache_size(2);
nx = ctx.cache_size(3);
if cfg.preprocessing.pod.enabled
    if isempty(pod_file) || ~isfile(pod_file)
        error('d23:fluctuation_chunk:MissingPodCache', ...
            'Enabled POD requires a completed reconstruction cache.');
    end
    source = matfile(pod_file);
    up = double(source.Uprime(frame_ordinals, :, :));
    vp = double(source.Vprime(frame_ordinals, :, :));
    raw = d23.read_chunk(ctx.cache_file, frame_ordinals);
    valid = raw.valid & reshape(d23.spatial_active_mask(ctx), 1, ny, nx);
    up(~valid) = NaN;
    vp(~valid) = NaN;
else
    raw = d23.read_chunk(ctx.cache_file, frame_ordinals);
    valid = raw.valid & reshape(d23.spatial_active_mask(ctx), 1, ny, nx);
    up = raw.U - reshape(stats.Ubar, 1, ny, nx);
    vp = raw.V - reshape(stats.Vbar, 1, ny, nx);
    up(~valid) = NaN;
    vp(~valid) = NaN;
end
[up, vp, gaussian_meta] = d23.apply_gaussian(up, vp, valid, ...
    cfg.preprocessing.gaussian);
chunk = struct('up', up, 'vp', vp, 'valid', valid, ...
    'frame_ordinals', double(frame_ordinals(:)), ...
    'gaussian_metadata', gaussian_meta);
end
