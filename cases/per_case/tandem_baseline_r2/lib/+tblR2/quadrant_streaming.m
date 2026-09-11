function result = quadrant_streaming(cache_file, cfg, stats, phase_stats, branch, hole_thresholds)
%QUADRANT_STREAMING Q1-Q4 statistics on the transport-statistics support.
if nargin < 6 || isempty(hole_thresholds)
    hole_thresholds = [0 1 2];
    if isfield(cfg, 'friction') && isfield(cfg.friction, 'hole_thresholds') && ...
            ~isempty(cfg.friction.hole_thresholds)
        hole_thresholds = cfg.friction.hole_thresholds;
    end
end
validateattributes(hole_thresholds, {'numeric'}, {'vector', 'finite', 'nonnegative', 'nonempty'});
if ~ismember(branch, {'total', 'random'})
    error('tblR2:quadrant_streaming:InvalidBranch', 'Invalid branch.');
end
is_random = strcmp(branch, 'random');
if is_random && isempty(phase_stats)
    error('tblR2:quadrant_streaming:MissingPhaseStatistics', 'Phase statistics required.');
end
fraction_floor = 1e-6;
if isfield(cfg, 'transport') && isfield(cfg.transport, 'stress_fraction_floor')
    fraction_floor = cfg.transport.stress_fraction_floor;
end
validateattributes(fraction_floor, {'numeric'}, {'scalar', 'finite', 'nonnegative'});
cache = matfile(cache_file);
item = whos(cache, 'U');
grid_size = size(cache.X);
grid_size(end + 1:2) = 1;
J = grid_size(1);
I = grid_size(2);
frame_ids = 1:item.size(1);
if isfield(stats, 'frame_ids')
    frame_ids = double(stats.frame_ids(:).');
end
n_h = numel(hole_thresholds);
if is_random
    n_bins = size(phase_stats.random_uv_phase, 1);
    reference_stress = reshape(phase_stats.random_uv_phase, n_bins, J, I);
    hole_scale = reshape(phase_stats.random_u_rms_phase .* ...
        phase_stats.random_v_rms_phase, n_bins, J, I);
else
    n_bins = 1;
    reference_stress = reshape(stats.uv_rey, 1, J, I);
    hole_scale = reshape(stats.u_rms .* stats.v_rms, 1, J, I);
end
event_count = zeros(n_h, 4, n_bins, J, I);
event_sum = zeros(n_h, 4, n_bins, J, I);
valid_count = zeros(n_bins, J, I);
stress_sum = zeros(n_bins, J, I);
u2_sum = zeros(n_bins, J, I);
v2_sum = zeros(n_bins, J, I);
for first = 1:cfg.chunk_frames:numel(frame_ids)
    ids = frame_ids(first:min(numel(frame_ids), first + cfg.chunk_frames - 1));
    chunk = tblR2.read_cache_chunk(cache_file, ids, 1:J, 1:I, branch, stats, phase_stats);
    U = chunk.U;
    V = chunk.V;
    valid = chunk.sampleValid & isfinite(U) & isfinite(V);
    valid = apply_support(valid, ids, stats, J, I);
    bins = ones(numel(ids), 1);
    if is_random
        bins = phase_stats.assignment.bin_index(ids);
        bins = double(bins(:));
    end
    for ib = unique(bins(:)).'
        local = bins == ib;
        ub = U(local, :, :);
        vb = V(local, :, :);
        observed = valid(local, :, :);
        stress = -ub .* vb;
        stress(~observed) = 0;
        u2 = ub.^2;
        v2 = vb.^2;
        u2(~observed) = 0;
        v2(~observed) = 0;
        valid_count(ib, :, :) = valid_count(ib, :, :) + sum(observed, 1);
        stress_sum(ib, :, :) = stress_sum(ib, :, :) + sum(stress, 1);
        u2_sum(ib, :, :) = u2_sum(ib, :, :) + sum(u2, 1);
        v2_sum(ib, :, :) = v2_sum(ib, :, :) + sum(v2, 1);
        for ih = 1:n_h
            masks = tblR2.stats.quadrant_mask(ub, vb, hole_thresholds(ih), ...
                reshape(hole_scale(ib, :, :), 1, J, I));
            for iq = 1:4
                event = observed & masks{iq};
                values = stress;
                values(~event) = 0;
                event_count(ih, iq, ib, :, :) = event_count(ih, iq, ib, :, :) + ...
                    reshape(sum(event, 1), 1, 1, 1, J, I);
                event_sum(ih, iq, ib, :, :) = event_sum(ih, iq, ib, :, :) + ...
                    reshape(sum(values, 1), 1, 1, 1, J, I);
            end
        end
    end
end
if is_random
    output_size = [n_h, 4, n_bins, J, I];
    point_size = [n_bins, J, I];
else
    output_size = [n_h, 4, J, I];
    point_size = [J, I];
end
result = summarize(event_count, event_sum, valid_count, stress_sum, ...
    u2_sum, v2_sum, output_size, point_size, fraction_floor);
result.branch = branch;
result.frame_ids = frame_ids(:);
result.hole_thresholds = hole_thresholds(:);
result.quadrant_names = {'Q1', 'Q2', 'Q3', 'Q4'};
result.hole_scale_definition = 'H times local u_rms*v_rms';
result.stress_fraction_floor = fraction_floor;
result.stress_fraction_definition = ['Signed mean negative-uv contribution / ' ...
    'mean negative-uv on identical observed support; undefined when abs(stress) ' ...
    '<= max(eps, stress_fraction_floor*u_rms*v_rms).'];
result.h0_stress_closure_max_abs = closure_error(event_sum, stress_sum, valid_count, hole_thresholds);
result.reference_stress_mismatch_max_abs = ...
    finite_max_abs(result.mean_negative_uv(:) - reference_stress(:));
result.reference_stress_missing_mismatch_count = ...
    nnz(isfinite(result.mean_negative_uv(:)) ~= isfinite(reference_stress(:)));
if is_random
    if isfield(phase_stats.assignment, 'bin_center_relative_deg')
        result.phase_bin_center_relative_deg = phase_stats.assignment.bin_center_relative_deg;
    end
    cycle = summarize(sum(event_count, 3), sum(event_sum, 3), sum(valid_count, 1), ...
        sum(stress_sum, 1), sum(u2_sum, 1), sum(v2_sum, 1), ...
        [n_h, 4, J, I], [J, I], fraction_floor);
    cycle.contribution_fraction_of_cycle_stress = cycle.contribution_fraction_of_total_stress;
    cycle.cycle_mean_uv = -cycle.mean_negative_uv;
    cycle.h0_stress_closure_max_abs = closure_error(sum(event_sum, 3), ...
        sum(stress_sum, 1), sum(valid_count, 1), hole_thresholds);
    result.cycle_average = cycle;
end
result.definition = ['All four quadrants use valid samples satisfying the strict ' ...
    'inequality |u_fluct*v_fluct| > H*u_rms*v_rms. Random statistics use ' ...
    'phase-resolved fluctuations and rms. Missing observations yield NaN; ' ...
    'observed bins without events yield zero probability and contribution ' ...
    'and NaN conditional intensity. Cycle statistics pool actual sample moments.'];
end

function valid = apply_support(valid, ids, stats, J, I)
if isfield(stats, 'accepted_mask') && ~isempty(stats.accepted_mask)
    valid = valid & reshape(stats.accepted_mask, 1, J, I);
end
if ~isfield(stats, 'support_rep_bin') || isempty(stats.support_rep_bin)
    return;
end
rep = ones(numel(ids), 1);
if isfield(stats, 'repeat_boundaries')
    for boundary = double(stats.repeat_boundaries(:).')
        rep = rep + (ids(:) > boundary);
    end
end
bins = ones(numel(ids), 1);
if isfield(stats, 'bin_index') && ~isempty(stats.bin_index)
    bins = stats.bin_index(ids);
end
for k = 1:numel(ids)
    valid(k, :, :) = valid(k, :, :) & ...
        reshape(stats.support_rep_bin(rep(k), bins(k), :, :), 1, J, I);
end
end

function result = summarize(events, sums, count, stress, u2, v2, out_size, point_size, floor_value)
count = reshape(count, point_size);
denominator = count;
denominator(count == 0) = NaN;
mean_stress = reshape(stress, point_size) ./ denominator;
scale = sqrt(reshape(u2, point_size) ./ denominator) .* ...
    sqrt(reshape(v2, point_size) ./ denominator);
signed_denominator = mean_stress;
signed_denominator(abs(mean_stress) <= max(eps, floor_value .* scale)) = NaN;
events = reshape(events, out_size);
sums = reshape(sums, out_size);
denom_shape = [1, 1, point_size];
contribution = sums ./ reshape(denominator, denom_shape);
conditional_count = events;
conditional_count(events == 0) = NaN;
result = struct('event_count', events, 'valid_count', count, ...
    'probability', events ./ reshape(denominator, denom_shape), ...
    'mean_event_negative_uv', sums ./ conditional_count, ...
    'mean_negative_uv_contribution', contribution, ...
    'contribution_fraction_of_total_stress', ...
        contribution ./ reshape(signed_denominator, denom_shape), ...
    'mean_negative_uv', mean_stress);
end

function value = closure_error(event_sum, stress_sum, count, thresholds)
ih = find(thresholds == 0, 1);
value = NaN;
if ~isempty(ih)
    actual = reshape(sum(event_sum(ih, :, :, :, :), 2), size(stress_sum));
    difference = (actual - stress_sum) ./ max(count, 1);
    difference(count == 0) = NaN;
    value = finite_max_abs(difference);
end
end

function value = finite_max_abs(values)
values = abs(values(isfinite(values)));
value = NaN;
if ~isempty(values)
    value = max(values);
end
end
