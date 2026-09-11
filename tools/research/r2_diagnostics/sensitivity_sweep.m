function res = sensitivity_sweep(ctx, opts)
%SENSITIVITY_SWEEP Full-pipeline geometric sensitivity over preprocessing
%   and morphological parameters, holding the identification threshold fixed.
%
%   ctx  : context from load_sweep_frames
%   opts : struct with fields
%            sigma_cells        1-D array (required)
%            seed_alphas        1-D array (required)
%            closing_radii      1-D array (required)
%            hole_pixels        1-D array (required)
%            connectivities     integer array (required)
%            base_options       the locked identification options (required)
%            base_preprocess    the baseline preprocessing options (required)
%            production_alpha   scalar, the locked growth threshold
%
%   Unlike percolation_sweep (which strips topology cleanup to measure the
%   raw threshold), this runs the FULL production identify_structures with
%   size filter, hole fill, closing, aspect and boundary rejection.  The
%   returned per-frame geometric metrics therefore describe exactly what the
%   analysis would report under each preprocessing choice.

sigmas   = opts.sigma_cells(:)';
seeds    = opts.seed_alphas(:)';
closings = opts.closing_radii(:)';
holes    = opts.hole_pixels(:)';
conns    = opts.connectivities(:)';
base_opts = opts.base_options;
base_pre  = opts.base_preprocess;

[isg, isd, icl, ihh, icc] = ndgrid( ...
    1:numel(sigmas), 1:numel(seeds), 1:numel(closings), ...
    1:numel(holes), 1:numel(conns));
n_combo = numel(isg);

% reshape(...,[],1), not indexing followed by a transpose: A(I) preserves
% A's own orientation only when A has more than one element.  Any factor
% swept with a SINGLE level (a real case here -- Phase 2 sometimes locks a
% dimension) makes A scalar, and A(I) then takes I's shape instead, which
% would silently misalign this field against the other four.  See the
% identical bug fixed in percolation_sweep.m for the failure mode this
% causes (a row vs. column & broadcasting into an n_combo x n_combo matrix).
combo = struct( ...
    'sigma_cells', reshape(sigmas(isg(:)), [], 1), ...
    'seed_alpha', reshape(seeds(isd(:)), [], 1), ...
    'closing_radius', reshape(closings(icl(:)), [], 1), ...
    'hole_pixels', reshape(holes(ihh(:)), [], 1), ...
    'connectivity', reshape(conns(icc(:)), [], 1));

bad = combo.seed_alpha < opts.production_alpha;
if any(bad)
    error('tblR2:sensitivity_sweep:InvalidHysteresis', ...
        '存在 seed_alpha < production_alpha 的组合，违反滞回约束。');
end

n_frames = ctx.n_frames;
per_frame = cell(n_combo, 1);
for j = 1:n_combo
    per_frame{j} = struct( ...
        'sigma_cells', combo.sigma_cells(j), ...
        'seed_alpha', combo.seed_alpha(j), ...
        'closing_radius', combo.closing_radius(j), ...
        'hole_pixels', combo.hole_pixels(j), ...
        'connectivity', combo.connectivity(j), ...
        'n_structures', nan(n_frames, 1), ...
        'mean_area', nan(n_frames, 1), ...
        'median_area', nan(n_frames, 1), ...
        'p90_area', nan(n_frames, 1), ...
        'total_area', nan(n_frames, 1), ...
        'tail_area_share', nan(n_frames, 1), ...
        'mean_aspect_ratio', nan(n_frames, 1), ...
        'median_aspect_ratio', nan(n_frames, 1), ...
        'p95_aspect_ratio', nan(n_frames, 1), ...
        'rejected_boundary', nan(n_frames, 1), ...
        'rejected_aspect', nan(n_frames, 1), ...
        'occupancy', nan(n_frames, 1), ...
        'closed_pixels', nan(n_frames, 1), ...
        'filled_pixels', nan(n_frames, 1), ...
        'small_component_fraction', nan(n_frames, 1), ...
        'lsm_count', nan(n_frames, 1), ...
        'vlsm_count', nan(n_frames, 1), ...
        'max_length_over_delta', nan(n_frames, 1));
end

% The Gaussian step depends only on sigma, so for each frame it is computed
% once per unique sigma and shared by every morphological/hysteresis combo
% at that sigma.  The cache is rebuilt for every frame -- it must NOT persist
% across frames, or later frames would silently reuse frame 1's field.
uniq_sigma = unique(combo.sigma_cells);
n_sigma = numel(uniq_sigma);
fprintf('[敏感性扫描] 共 %d 个参数组合 x %d 帧。\n', n_combo, n_frames);
fprintf('[敏感性扫描] 预处理 sigma 取值：%s\n', mat2str(uniq_sigma));

for k = 1:n_frames
    raw_U = ctx.raw_U(:, :, k);
    raw_V = ctx.raw_V(:, :, k);
    raw_valid = ctx.raw_valid(:, :, k);
    mean_U = ctx.mean_U(:, :, k);

    frame_cache = cell(n_sigma, 1);   % rebuilt per frame, never reused
    for js = 1:n_sigma
        sg = uniq_sigma(js);
        % make_gaussian_spec sets the directional kernel fields, which is
        % mandatory: the scalar sigma_cells alias alone does NOT reach the
        % kernel when the base spec already carries non-empty directional
        % defaults.  See make_gaussian_spec for the full explanation.
        pre = make_gaussian_spec(base_pre, sg);
        p = tblR2.preprocess_structure_velocity( ...
            raw_U, raw_V, raw_valid, ctx.analysis_domain_mask, pre);
        struct_mask = p.output_valid_mask & isfinite(mean_U);
        u_fluct = p.U - mean_U;
        u_fluct(~struct_mask) = NaN;
        frame_cache{js} = struct('u_fluct', u_fluct, 'mask', struct_mask);
    end

    for js = 1:n_sigma
        sg = uniq_sigma(js);
        c = frame_cache{js};

        for j = 1:n_combo
            if combo.sigma_cells(j) ~= sg
                continue;
            end
            local_opts = base_opts;
            local_opts.seed_alpha = combo.seed_alpha(j);
            local_opts.connectivity = combo.connectivity(j);
            local_opts.envelope_closing_radius_cells = combo.closing_radius(j);
            local_opts.max_internal_hole_pixels = combo.hole_pixels(j);
            local_opts.alpha = opts.production_alpha;

            id = tblR2.identify_structures( ...
                c.u_fluct, ctx.u_rms, ctx.X, ctx.Y_wall_mm, ctx.delta_grid, ...
                c.mask, local_opts);
            gm = structure_geometry_metrics(id, c.mask);

            f = per_frame{j};
            f.n_structures(k)             = gm.n_structures;
            f.mean_area(k)                = gm.mean_area;
            f.median_area(k)              = gm.median_area;
            f.p90_area(k)                 = gm.p90_area;
            f.total_area(k)               = gm.total_area;
            f.tail_area_share(k)          = gm.tail_area_share;
            f.mean_aspect_ratio(k)        = gm.mean_aspect_ratio;
            f.median_aspect_ratio(k)      = gm.median_aspect_ratio;
            f.p95_aspect_ratio(k)         = gm.p95_aspect_ratio;
            f.rejected_boundary(k)        = gm.rejected_boundary;
            f.rejected_aspect(k)          = gm.rejected_aspect;
            f.occupancy(k)                = gm.occupancy;
            f.closed_pixels(k)            = gm.closed_pixels;
            f.filled_pixels(k)            = gm.filled_pixels;
            f.small_component_fraction(k) = gm.small_component_fraction;
            f.lsm_count(k)                = gm.lsm_count;
            f.vlsm_count(k)               = gm.vlsm_count;
            f.max_length_over_delta(k)    = gm.max_length_over_delta;
            per_frame{j} = f;
        end
    end

    if mod(k, 25) == 0 || k == n_frames
        fprintf('[敏感性扫描] 进度 %d / %d 帧\n', k, n_frames);
    end
end

res = struct();
res.sigma_cells     = combo.sigma_cells;
res.seed_alpha      = combo.seed_alpha;
res.closing_radius  = combo.closing_radius;
res.hole_pixels     = combo.hole_pixels;
res.connectivity    = combo.connectivity;
res.per_frame       = per_frame;
res.n_frames        = n_frames;
res.frame_ids       = ctx.frame_ids;
res.production_alpha = opts.production_alpha;
end
