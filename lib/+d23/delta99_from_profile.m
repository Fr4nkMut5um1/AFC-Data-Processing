function result = delta99_from_profile(y_mm, mean_u, n_edge_points)
%DELTA99_FROM_PROFILE First upward 0.99*Ue crossing with linear interpolation.
if nargin < 3
    n_edge_points = 5;
end
y_mm = double(y_mm(:));
mean_u = double(mean_u(:));
valid = isfinite(y_mm) & isfinite(mean_u);
y_mm = y_mm(valid);
mean_u = mean_u(valid);
[y_mm, order] = sort(y_mm, 'ascend');
mean_u = mean_u(order);
if numel(y_mm) < n_edge_points + 1 || any(diff(y_mm) <= 0)
    error('d23:delta99_from_profile:InsufficientProfile', ...
        'The reference profile has too few ordered valid points.');
end
edge_rows = (numel(mean_u) - n_edge_points + 1):numel(mean_u);
u_edge = mean(mean_u(edge_rows));
target = 0.99 * u_edge;
crossing = find(mean_u(1:end-1) < target & mean_u(2:end) >= target, 1, 'first');
if isempty(crossing)
    error('d23:delta99_from_profile:NoCrossing', ...
        'No first upward 0.99*Ue crossing exists in the measured profile.');
end
u0 = mean_u(crossing);
u1 = mean_u(crossing + 1);
if u1 == u0
    error('d23:delta99_from_profile:FlatCrossing', ...
        'The 0.99*Ue crossing interval has zero velocity slope.');
end
fraction = (target - u0) / (u1 - u0);
delta_mm = y_mm(crossing) + fraction * (y_mm(crossing + 1) - y_mm(crossing));
result = struct('delta99_mm', delta_mm, 'u_edge_m_s', u_edge, ...
    'target_m_s', target, 'lower_index', crossing, ...
    'upper_index', crossing + 1, 'fraction', fraction, ...
    'edge_indices', edge_rows(:));
end
