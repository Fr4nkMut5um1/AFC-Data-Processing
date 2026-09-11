function result = transport_analysis(cache_file, cfg, varargin)
%TRANSPORT_ANALYSIS Source-consistent Section 5, independent of Sections 2-4.
% Legacy input statistics are not consumed: moments must share one source.

[stats, phase] = tblR2.transport_statistics(cache_file, cfg);
options = struct('edge_buffer_cells', [0 0]);
if isfield(cfg, 'transport')
    names = fieldnames(cfg.transport);
    for k = 1:numel(names)
        options.(names{k}) = cfg.transport.(names{k});
    end
end
gradient = tblR2.gradient_y_sensitivity(stats.Uavex, stats.X, stats.Y, ...
    cfg.friction.rbf_epsilon_scale);
base_mask = stats.accepted_mask & isfinite(stats.uv_rey) & ...
    isfinite(gradient.finite_difference) & isfinite(gradient.rbf_fd);
mask = tblR2.buffer_valid_mask(base_mask, options.edge_buffer_cells);
result = struct('schema_version', 2, 'source_role', stats.source_role, ...
    'grid', struct('X', stats.X, 'Y', stats.Y), ...
    'statistics', stats, 'options', options, 'calculation_mask', mask, ...
    'edge_rejected_mask', base_mask & ~mask);
result.total = products(stats.uv_rey, gradient, mask);
result.total.uv_rey = stats.uv_rey;
result.total.dUdy = gradient;
result.total.quadrant = tblR2.quadrant_streaming( ...
    cache_file, cfg, stats, phase, 'total', cfg.friction.hole_thresholds);
result.diagnostics = struct('gradient_relative_rms_difference', ...
    gradient.relative_rms_difference, 'selected_frames', numel(stats.frame_ids), ...
    'accepted_grid_points', nnz(stats.accepted_mask), ...
    'production_grid_points', nnz(mask), ...
    'admitted_samples', sum(stats.valid_count(:)), ...
    'raw_valid_samples', sum(stats.raw_valid_count(:)));
result.diagnostics.total_quadrant_closure = quadrant_closure( ...
    result.total.quadrant, stats.uv_rey);

if strcmp(cfg.case_type, 'controlled')
    J = size(stats.X, 1); I = size(stats.X, 2);
    B = cfg.phase.n_bins;
    phase_mask = repmat(reshape(mask, 1, J, I), B, 1, 1);
    phase_gradient = struct('finite_difference', ...
        repmat(reshape(gradient.finite_difference, 1, J, I), B, 1, 1), ...
        'rbf_fd', repmat(reshape(gradient.rbf_fd, 1, J, I), B, 1, 1));
    result.phase_degrees = phase.assignment.bin_center_relative_deg;
    result.phase_valid_count = phase.count;
    result.total_phase = products(phase.total_uv_phase, phase_gradient, phase_mask);
    result.random_phase = products(phase.random_uv_phase, phase_gradient, phase_mask);
    result.coherent_phase = products(-phase.coherent_uv, phase_gradient, phase_mask);
    result.coherent_phase.negative_utilde_vtilde = result.coherent_phase.negative_uv;
    result.random = products(phase.random_global.uv_rey, gradient, mask);
    result.coherent = products(phase.coherent_global.uv_rey, gradient, mask);
    result.random_phase.quadrant = tblR2.quadrant_streaming( ...
        cache_file, cfg, stats, phase, 'random', cfg.friction.hole_thresholds);
    result.diagnostics.stress_closure = closure(stats.uv_rey, ...
        phase.random_global.uv_rey + phase.coherent_global.uv_rey);
    result.diagnostics.phase_stress_closure = closure(phase.total_uv_phase, ...
        phase.random_uv_phase - phase.coherent_uv);
    result.diagnostics.production_closure = closure(result.total.production_primary_fd, ...
        result.random.production_primary_fd + result.coherent.production_primary_fd);
    result.diagnostics.random_quadrant_closure = quadrant_closure( ...
        result.random_phase.quadrant, phase.random_uv_phase);
end
result.units = struct('stress', 'm^2/s^2', 'gradient', '1/s', ...
    'production', 'm^2/s^3', 'coordinates', 'mm');
result.scope = ['Main shear production only: P=-<uv>*dU/dy. ' ...
    'Total, coherent and random terms use the same time-mean gradient. ' ...
    'All moments use paired finite samples from one source and frame selection. ' ...
    'Controlled moments use repeat-specific means on admitted phase-bin support. ' ...
    'Coherent stress is the sample-weighted mean of repeat-specific products. ' ...
    'No full planar or three-dimensional TKE production is inferred.'];
end

function value = products(stress, gradient, mask)
fd = stress .* gradient.finite_difference;
rbf = stress .* gradient.rbf_fd;
masked_stress = stress; masked_stress(~mask) = NaN;
masked_fd = fd; masked_fd(~mask) = NaN;
masked_rbf = rbf; masked_rbf(~mask) = NaN;
value = struct('negative_uv', masked_stress, ...
    'production_primary_fd', masked_fd, 'production_sensitivity_rbf', masked_rbf, ...
    'production_unmasked_fd', fd, 'production_unmasked_rbf', rbf);
end

function check = quadrant_closure(q, stress)
ih = find(q.hole_thresholds == 0, 1);
if isempty(ih)
    check = struct('checked', false, 'max_abs', NaN, 'relative_rms', NaN);
    return;
end
values = q.mean_negative_uv_contribution;
idx = repmat({':'}, 1, ndims(values)); idx{1} = ih;
summed = reshape(sum(values(idx{:}), 2), size(stress));
check = closure(stress, summed);
check.checked = true;
end

function check = closure(reference, reconstructed)
valid = isfinite(reference) & isfinite(reconstructed);
delta = reference(valid) - reconstructed(valid);
if isempty(delta)
    check = struct('count', 0, 'max_abs', NaN, 'relative_rms', NaN);
else
    check = struct('count', nnz(valid), 'max_abs', max(abs(delta)), ...
        'relative_rms', sqrt(mean(delta.^2)) / max(sqrt(mean(reference(valid).^2)), eps));
end
end
