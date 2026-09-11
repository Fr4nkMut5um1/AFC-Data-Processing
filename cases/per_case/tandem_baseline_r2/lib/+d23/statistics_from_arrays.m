function stats = statistics_from_arrays(U, V, valid, chunk_size)
%STATISTICS_FROM_ARRAYS Two-pass reference implementation for synthetic tests.
if ~isequal(size(U), size(V), size(valid))
    error('d23:statistics_from_arrays:ShapeMismatch', ...
        'U, V, and valid must have identical shapes.');
end
U = double(U);
V = double(V);
valid = logical(valid) & isfinite(U) & isfinite(V);
nt = size(U, 1);
ny = size(U, 2);
nx = size(U, 3);
sum_u = zeros(ny, nx);
sum_v = zeros(ny, nx);
count_xy = zeros(ny, nx);
for first = 1:chunk_size:nt
    ids = first:min(first + chunk_size - 1, nt);
    u = U(ids, :, :); v = V(ids, :, :); mask = valid(ids, :, :);
    u(~mask) = NaN; v(~mask) = NaN;
    sum_u = sum_u + squeeze(sum(u, 1, 'omitnan'));
    sum_v = sum_v + squeeze(sum(v, 1, 'omitnan'));
    count_xy = count_xy + squeeze(sum(mask, 1));
end
Ubar = sum_u ./ count_xy;
Vbar = sum_v ./ count_xy;
Ubar(count_xy == 0) = NaN;
Vbar(count_xy == 0) = NaN;
sum_sq_y = zeros(ny, 1);
count_y = zeros(ny, 1);
for first = 1:chunk_size:nt
    ids = first:min(first + chunk_size - 1, nt);
    mask = valid(ids, :, :);
    up = U(ids, :, :) - reshape(Ubar, 1, ny, nx);
    up(~mask) = NaN;
    sum_sq_y = sum_sq_y + ...
        reshape(squeeze(sum(sum(up .^ 2, 1, 'omitnan'), 3, 'omitnan')), ny, 1);
    count_y = count_y + reshape(squeeze(sum(sum(mask, 1), 3)), ny, 1);
end
u_rms_y = sqrt(sum_sq_y ./ count_y);
u_rms_y(count_y == 0) = NaN;
stats = struct('Ubar', Ubar, 'Vbar', Vbar, 'valid_count_xy', count_xy, ...
    'valid_count_y', count_y, 'u_rms_y', u_rms_y);
end
