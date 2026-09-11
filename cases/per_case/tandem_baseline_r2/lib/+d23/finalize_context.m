function ctx = finalize_context(ctx, stats, cfg)
%FINALIZE_CONTEXT Derive delta99, Re_tau, criteria rows, and preflight checks.
x_selected = ctx.x_mm >= cfg.data.reference_x_mm(1) & ...
    ctx.x_mm <= cfg.data.reference_x_mm(2);
if ~any(x_selected)
    error('d23:finalize_context:ReferenceRange', ...
        'No measured x columns lie in the requested reference range.');
end
profile_u = mean(stats.Ubar(:, x_selected), 2, 'omitnan');
profile_y_mm = median(ctx.wall_distance_mm(:, x_selected), 2, 'omitnan');
delta = d23.delta99_from_profile(profile_y_mm, profile_u, 5);
ctx.delta99_mm = delta.delta99_mm;
ctx.u_edge_m_s = delta.u_edge_m_s;
ctx.profile_target_m_s = delta.target_m_s;
ctx.reference_profile = table(profile_y_mm, profile_u, ...
    'VariableNames', {'WallDistance_mm', 'MeanU_m_s'});
ctx.reference_x_columns = find(x_selected(:));
ctx.nu_m2_s = cfg.data.nu_m2_s;
ctx.Re_tau = (ctx.delta99_mm / 1000) * ctx.u_tau_m_s / ctx.nu_m2_s;
ctx.lower_plus_limit = 2.6 * sqrt(ctx.Re_tau);
ctx.upper_plus_limit = 0.5 * ctx.Re_tau;
ctx.wall_y_mm = median(ctx.wall_distance_mm, 2, 'omitnan');
ctx.wall_y_plus = ctx.wall_y_mm / 1000 * ctx.u_tau_m_s / ctx.nu_m2_s;
[~, ctx.lower_spectrum_row] = min(abs(ctx.wall_y_plus - ctx.lower_plus_limit));
[~, ctx.upper_spectrum_row] = min(abs(ctx.wall_y_plus - ctx.upper_plus_limit));
ctx.fov_length_mm = ctx.cache_size(3) * ctx.dx_mm;
ctx.fov_height_mm = max(ctx.wall_y_mm);
if ctx.fov_length_mm < 3 * ctx.delta99_mm
    error('d23:finalize_context:StreamwiseFOV', ...
        'The measured streamwise FOV is shorter than 3*delta99.');
end
if ctx.fov_height_mm < 0.5 * ctx.delta99_mm
    error('d23:finalize_context:NormalFOV', ...
        'The highest measured row lies below 0.5*delta99.');
end
ctx.applicability_limited = ctx.Re_tau < 2000;
ctx.applicability_note = '';
if ctx.applicability_limited
    ctx.applicability_note = sprintf([ ...
        'Re_tau=%.3f is below 2000; comparison with the paper is limited.'], ...
        ctx.Re_tau);
end
end
