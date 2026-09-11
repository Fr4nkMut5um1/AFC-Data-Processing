function ctx = load_sweep_frames(mat_dir, frame_ids)
%LOAD_SWEEP_FRAMES Read raw frames plus geometry once for a parameter sweep.
%   Returns a context struct holding raw U/V/valid per frame together with
%   the grid, u_rms, delta99 and per-repeat means, so a sweep can re-run
%   preprocessing and identification without touching the 4.5 GB cache again.
%
%   Geometry is assembled exactly as structure_analysis_cache.m does it, so
%   sweep results stay comparable with the production analysis.

s_struct  = load(fullfile(mat_dir, '09_structure_analysis.mat'));
s_stats   = load(fullfile(mat_dir, '02_statistics.mat'));
s_mean_bl = load(fullfile(mat_dir, '02_mean_boundary_layer_friction.mat'));
seq = matfile(fullfile(mat_dir, '01_sequence_cache_postproc.mat'));

data    = s_struct.data;
stats   = s_stats.data;
mean_bl = s_mean_bl.data;

Y_wall_mm  = mean_bl.wall_distance_mm;
delta_grid = interp1(mean_bl.boundary_layer.x, ...
    mean_bl.boundary_layer.delta99, stats.X, 'linear', NaN);
valid_mask = stats.accepted_mask & isfinite(delta_grid) & delta_grid > 0;

n_total = size(seq, 'U', 1);
frame_ids = frame_ids(:)';
if any(frame_ids < 1 | frame_ids > n_total)
    error('tblR2:load_sweep_frames:FrameOutOfRange', ...
        'frame_ids 必须在 1..%d 范围内。', n_total);
end

n_frames = numel(frame_ids);
grid_size = size(stats.X);
raw_U     = nan([grid_size n_frames]);
raw_V     = nan([grid_size n_frames]);
raw_valid = false([grid_size n_frames]);
mean_U    = nan([grid_size n_frames]);
mean_V    = nan([grid_size n_frames]);

for k = 1:n_frames
    fid = frame_ids(k);
    raw_U(:, :, k) = squeeze(seq.U(fid, :, :));
    raw_V(:, :, k) = squeeze(seq.V(fid, :, :));
    frame_valid    = squeeze(seq.sampleValid(fid, :, :));
    raw_valid(:, :, k) = valid_mask & logical(frame_valid);

    % Repeat-resolved mean: frames after a repeat boundary use that repeat.
    rep = 1 + nnz(fid > stats.repeat_boundaries(:)');
    mean_U(:, :, k) = squeeze(stats.repeat_means(1, rep, :, :));
    mean_V(:, :, k) = squeeze(stats.repeat_means(2, rep, :, :));
end

ctx = struct();
ctx.frame_ids            = frame_ids;
ctx.n_frames             = n_frames;
ctx.raw_U                = raw_U;
ctx.raw_V                = raw_V;
ctx.raw_valid            = raw_valid;
ctx.mean_U               = mean_U;
ctx.mean_V               = mean_V;
ctx.X                    = stats.X;
ctx.Y_wall_mm            = Y_wall_mm;
ctx.u_rms                = stats.u_rms;
ctx.delta_grid           = delta_grid;
ctx.analysis_domain_mask = data.preprocessing.analysis_domain_mask;
ctx.baseline_options     = data.options;
ctx.baseline_preprocess  = data.preprocessing.options;
ctx.n_total_frames       = n_total;
end
