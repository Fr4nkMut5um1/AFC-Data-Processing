% Research utility with historical cache/parameter assumptions; see tools/README.md.
% Not a daily entry or formal Section 4 acceptance test. Runtime not revalidated.
%% Single-frame timing benchmark for tblR2.identify_structures
% Measures wall-clock cost of one frame (Gaussian preprocessing + signed
% hysteresis connected-component labeling) under the current R2 baseline
% configuration, then projects the cost of the planned parameter sweeps.
%
% A +package folder must NOT itself be on the path; its PARENT must be.
% genpath() would add cases/.../+tblR2 directly, which MATLAB rejects.

base_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(base_dir, 'lib'));
mat_dir = fullfile(base_dir, 'cases/per_case/tandem_baseline_r2/output/mat');

%% Load small caches fully; read the 4.5 GB sequence cache one frame at a time
fprintf('Loading caches...\n');
s_struct  = load(fullfile(mat_dir, '09_structure_analysis.mat'));
s_stats   = load(fullfile(mat_dir, '02_statistics.mat'));
s_mean_bl = load(fullfile(mat_dir, '02_mean_boundary_layer_friction.mat'));
seq = matfile(fullfile(mat_dir, '01_sequence_cache_postproc.mat'));

data    = s_struct.data;
stats   = s_stats.data;
mean_bl = s_mean_bl.data;

n_frames = size(seq, 'U', 1);
fprintf('Sequence cache frames: %d\n', n_frames);
fprintf('Grid: %d x %d\n', size(stats.X, 1), size(stats.X, 2));

%% Geometry, exactly as structure_analysis_cache.m builds it
Y_wall_mm  = mean_bl.wall_distance_mm;
delta_grid = interp1(mean_bl.boundary_layer.x, ...
    mean_bl.boundary_layer.delta99, stats.X, 'linear', NaN);
valid_mask = stats.accepted_mask & isfinite(delta_grid) & delta_grid > 0;

opts                  = data.options;
preprocess_spec       = data.preprocessing.options;
analysis_domain_mask  = data.preprocessing.analysis_domain_mask;

fprintf('\nCurrent locked options:\n');
fprintf('  alpha                         = %.2f\n', opts.alpha);
fprintf('  seed_alpha                    = %.2f\n', opts.seed_alpha);
fprintf('  connectivity                  = %d\n',   opts.connectivity);
fprintf('  min_pixels                    = %d\n',   opts.min_pixels);
fprintf('  envelope_closing_radius_cells = %d\n',   opts.envelope_closing_radius_cells);
fprintf('  max_internal_hole_pixels      = %d\n',   opts.max_internal_hole_pixels);
fprintf('  gaussian sigma_cells          = %.2f\n', preprocess_spec.gaussian.sigma_cells);
fprintf('  gaussian radius_cells         = %d\n',   preprocess_spec.gaussian.radius_cells);

%% Benchmark over several frames spread across both repeats
frame_ids = [1, 1500, 3000, 6001, 7500, 9000];
n_trials  = numel(frame_ids);

t_read    = zeros(n_trials, 1);
t_preproc = zeros(n_trials, 1);
t_ident   = zeros(n_trials, 1);
n_struct  = zeros(n_trials, 1);

fprintf('\nRunning %d frames...\n', n_trials);
for k = 1:n_trials
    fid = frame_ids(k);

    tic;
    raw_U       = squeeze(seq.U(fid, :, :));
    raw_V       = squeeze(seq.V(fid, :, :));
    frame_valid = squeeze(seq.sampleValid(fid, :, :));
    t_read(k) = toc;

    raw_valid = valid_mask & logical(frame_valid);

    tic;
    prep = tblR2.preprocess_structure_velocity( ...
        raw_U, raw_V, raw_valid, analysis_domain_mask, preprocess_spec);
    t_preproc(k) = toc;

    % Repeat-resolved mean, matching structure_analysis_cache.m
    rep = 1 + nnz(fid > stats.repeat_boundaries(:)');
    mean_U = squeeze(stats.repeat_means(1, rep, :, :));
    mean_V = squeeze(stats.repeat_means(2, rep, :, :));

    structure_mask = prep.output_valid_mask & isfinite(mean_U) & isfinite(mean_V);
    total_U_f = prep.U - mean_U;
    total_U_f(~structure_mask) = NaN;

    tic;
    res = tblR2.identify_structures( ...
        total_U_f, stats.u_rms, stats.X, Y_wall_mm, delta_grid, ...
        structure_mask, opts);
    t_ident(k) = toc;

    n_struct(k) = height(res.structures);
    fprintf('  frame %5d: read %.3f s | preproc %.4f s | identify %.4f s | %4d structures\n', ...
        fid, t_read(k), t_preproc(k), t_ident(k), n_struct(k));
end

%% Statistics
t_compute = t_preproc + t_ident;   % the part a sweep actually repeats
fprintf('\n--- Per-frame timing ---\n');
fprintf('matfile read     : median %.4f s (avoidable if frames are cached in RAM)\n', median(t_read));
fprintf('preprocessing    : median %.4f s\n', median(t_preproc));
fprintf('identification   : median %.4f s\n', median(t_ident));
fprintf('compute subtotal : median %.4f s  (preproc + identify)\n', median(t_compute));
fprintf('structures/frame : median %.0f\n', median(n_struct));

%% Projected sweep cost
t_c = median(t_compute);
t_i = median(t_ident);
t_r = median(t_read);

fprintf('\n--- Projected sweep cost (compute only, frames pre-loaded) ---\n');
% Phase 1: alpha/seed_alpha only change the labeling step; the Gaussian
% preprocessing result can be reused across alpha for a fixed sigma.
fprintf('Phase 1 percolation, 480 frames x 9 alpha x 2 connectivity:\n');
fprintf('   identify-only : %.1f min\n', 480 * 9 * 2 * t_i / 60);
fprintf('   + one preproc pass per frame: %.1f min\n', ...
    (480 * 9 * 2 * t_i + 480 * median(t_preproc)) / 60);
fprintf('Phase 2 orthogonal L16, 120 frames x 16 configs (full preproc each):\n');
fprintf('   %.1f min\n', 120 * 16 * t_c / 60);
fprintf('Phase 2 full grid, 120 frames x 320 configs:\n');
fprintf('   %.1f min = %.1f hrs\n', 120 * 320 * t_c / 60, 120 * 320 * t_c / 3600);

fprintf('\n--- One-time frame ingest cost ---\n');
fprintf('Reading 480 frames from the 4.5 GB matfile: %.1f min\n', 480 * t_r / 60);
fprintf('RAM for 480 frames of U as double: %.2f GB\n', 480 * 89 * 640 * 8 / 1e9);
