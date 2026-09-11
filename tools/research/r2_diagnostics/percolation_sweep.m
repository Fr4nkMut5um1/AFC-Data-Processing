function res = percolation_sweep(ctx, opts)
%PERCOLATION_SWEEP Signed percolation scan over threshold and connectivity.
%   ctx  : context from load_sweep_frames
%   opts : struct with fields
%            alphas        1-D array of growth thresholds (required)
%            seed_alphas   1-D array of seed thresholds (required)
%            connectivities integer array, e.g. [4 8] (required)
%            preprocess    preprocessing options struct (required)
%            per_frame_field  'preprocessed' | 'raw' (default 'preprocessed')
%
%   For every (alpha, seed_alpha, connectivity) combination, every frame is
%   thresholded and labeled, and percolation_metrics is accumulated into a
%   frame-level table.  Bootstrap / stable-region inference is left to the
%   caller via bootstrap_stability, so the raw per-frame table stays
%   resamplable.
%
%   NOTE: the preprocessing pass is done ONCE per frame (it depends only on
%   the smoothing config, not on alpha/connectivity), then all threshold and
%   connectivity combinations reuse the smoothed u' field.  This is what
%   keeps the sweep cheap.

% --- argument handling ---------------------------------------------------
alphas = opts.alphas(:)';
seed_alphas = opts.seed_alphas(:)';
conns = opts.connectivities(:)';
preprocess = opts.preprocess;
if nargin < 2 || ~isfield(opts, 'per_frame_field') || ...
        isempty(opts.per_frame_field)
    per_frame_field = 'preprocessed';
else
    per_frame_field = opts.per_frame_field;
end

n_alpha = numel(alphas);
n_seed  = numel(seed_alphas);
n_conn  = numel(conns);
n_frames = ctx.n_frames;
grid_size = size(ctx.X);

% Build the full parameter grid and a frame-level accumulator table.
% reshape(...,[],1), not a transpose after indexing: A(I)' only gives a
% column when A(I) itself came out as a row, and MATLAB's indexing of a
% VECTOR by a vector index preserves A's own orientation -- EXCEPT when A is
% scalar (here, whenever a sweep dimension has exactly one level), in which
% case A(I) instead takes the shape of I.  Phase 1 calls this with a
% single-element seed_alphas, which silently produced a row where the other
% two combo arrays were columns, and a later row-vs-column & broadcast into
% an n_combo x n_combo matrix instead of the intended element-wise mask.
[aa, ss, cc] = ndgrid(1:n_alpha, 1:n_seed, 1:n_conn);
n_combo = numel(aa);
combo_alpha = reshape(alphas(aa(:)), [], 1);
combo_seed  = reshape(seed_alphas(ss(:)), [], 1);
combo_conn  = reshape(conns(cc(:)), [], 1);

% Validate the seed >= alpha constraint up front, per the production rule.
bad = combo_seed < combo_alpha;
if any(bad)
    error('tblR2:percolation_sweep:InvalidHysteresis', ...
        '存在 seed_alpha < alpha 的组合，违反滞回阈值约束。');
end

per_frame = cell(n_combo, 1);
for j = 1:n_combo
    per_frame{j} = struct( ...
        'alpha', combo_alpha(j), ...
        'seed_alpha', combo_seed(j), ...
        'connectivity', combo_conn(j), ...
        'max_component_ratio', nan(n_frames, 1), ...
        'n_components', nan(n_frames, 1), ...
        'occupancy', nan(n_frames, 1), ...
        'mean_component_size', nan(n_frames, 1), ...
        'susceptibility', nan(n_frames, 1), ...
        'small_component_fraction', nan(n_frames, 1));
end

% --- per-frame loop ------------------------------------------------------
fprintf('[逾渗扫描] 共 %d 个阈值组合 x %d 帧，开始逐帧处理。\n', n_combo, n_frames);
for k = 1:n_frames
    raw_U = ctx.raw_U(:, :, k);
    raw_V = ctx.raw_V(:, :, k);
    raw_valid = ctx.raw_valid(:, :, k);

    % Preprocess once (smoothing does not depend on alpha/connectivity).
    prep = tblR2.preprocess_structure_velocity( ...
        raw_U, raw_V, raw_valid, ctx.analysis_domain_mask, preprocess);
    if strcmp(per_frame_field, 'preprocessed')
        u_prep = prep.U;
        struct_mask = prep.output_valid_mask & isfinite(ctx.mean_U(:, :, k));
    else
        u_prep = raw_U;
        struct_mask = raw_valid & isfinite(ctx.mean_U(:, :, k));
    end
    u_fluct = u_prep - ctx.mean_U(:, :, k);
    u_fluct(~struct_mask) = NaN;

    for j = 1:n_combo
        local_opts = struct( ...
            'alpha', combo_alpha(j), ...
            'seed_alpha', combo_seed(j), ...
            'connectivity', combo_conn(j), ...
            'min_pixels', 1, ...            % census-level: do not size-filter
            'min_lsm_delta', inf, ...
            'min_vlsm_delta', inf, ...
            'max_wall_normal_delta', inf, ...
            'max_aspect_ratio', inf, ...
            'reject_trusted_boundary_touching', false, ...
            'max_internal_hole_pixels', 0, ...   % no topology cleanup
            'envelope_closing_radius_cells', 0, ...
            'sign_mode', 'both');
        id = tblR2.identify_structures( ...
            u_fluct, ctx.u_rms, ctx.X, ctx.Y_wall_mm, ctx.delta_grid, ...
            struct_mask, local_opts);
        m = percolation_metrics( ...
            id.positive_mask, id.negative_mask, ...
            struct_mask, combo_conn(j), height(id.structures));

        f = per_frame{j};
        f.max_component_ratio(k)      = m.max_component_ratio;
        f.n_components(k)             = m.n_components;
        f.occupancy(k)                = m.occupancy;
        f.mean_component_size(k)      = m.mean_component_size;
        f.susceptibility(k)           = m.susceptibility;
        f.small_component_fraction(k) = m.small_component_fraction;
        per_frame{j} = f;
    end

    if mod(k, 50) == 0 || k == n_frames
        fprintf('[逾渗扫描] 进度 %d / %d 帧\n', k, n_frames);
    end
end

res = struct();
res.alpha        = combo_alpha;
res.seed_alpha   = combo_seed;
res.connectivity = combo_conn;
res.per_frame    = per_frame;
res.n_frames     = n_frames;
res.per_frame_field = per_frame_field;
res.frame_ids    = ctx.frame_ids;
res.grid_size    = grid_size;
end
