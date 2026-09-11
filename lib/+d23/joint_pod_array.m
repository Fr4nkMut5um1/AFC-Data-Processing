function result = joint_pod_array(U, V, valid, pod_cfg)
%JOINT_POD_ARRAY Exact double joint u/v snapshot POD for synthetic tests.
if ~isequal(size(U), size(V), size(valid)) || ndims(U) ~= 3
    error('d23:joint_pod_array:ShapeMismatch', ...
        'U, V, and valid must have identical [Nt Ny Nx] shapes.');
end
U = double(U);
V = double(V);
valid = logical(valid) & isfinite(U) & isfinite(V);
nt = size(U, 1);
ny = size(U, 2);
nx = size(U, 3);
m = ny * nx;
valid_flat = reshape(permute(valid, [2 3 1]), m, nt);
valid_fraction = sum(valid_flat, 2) / nt;
retained = valid_fraction >= pod_cfg.min_valid_fraction;
if ~any(retained)
    error('d23:joint_pod_array:NoDofs', ...
        'No spatial degrees of freedom pass min_valid_fraction.');
end
u_flat = reshape(permute(U, [2 3 1]), m, nt);
v_flat = reshape(permute(V, [2 3 1]), m, nt);
u_flat(~valid_flat) = 0;
v_flat(~valid_flat) = 0;
X = [u_flat(retained, :); v_flat(retained, :)];
mu = mean(X, 2);
F = X - mu;
dof_count = size(F, 1);
C = (F.' * F) / dof_count;
C = (C + C.') / 2;
[vectors, eigenvalues] = eig(C, 'vector');
[eigenvalues, order] = sort(real(eigenvalues), 'descend');
vectors = real(vectors(:, order));
[rank_value, positive_rank, lambda_tol] = d23.select_pod_rank( ...
    eigenvalues, dof_count, pod_cfg);
vectors_r = vectors(:, 1:rank_value);
raw_modes = F * vectors_r;
mode_norms = sqrt(sum(raw_modes .^ 2, 1));
Phi = raw_modes ./ mode_norms;
A = Phi.' * F;
Xhat = mu + Phi * A;
u_reconstructed = nan(m, nt);
v_reconstructed = nan(m, nt);
u_reconstructed(retained, :) = Xhat(1:nnz(retained), :);
v_reconstructed(retained, :) = Xhat(nnz(retained)+1:end, :);
result = struct('eigenvalues', eigenvalues, 'time_vectors', vectors, ...
    'modes', Phi, 'coefficients', A, 'mean', mu, ...
    'snapshot_matrix', X, 'centered_matrix', F, ...
    'reconstructed_matrix', Xhat, ...
    'U_reconstructed', permute(reshape(u_reconstructed, ny, nx, nt), [3 1 2]), ...
    'V_reconstructed', permute(reshape(v_reconstructed, ny, nx, nt), [3 1 2]), ...
    'retained_spatial_mask', reshape(retained, ny, nx), ...
    'valid_fraction', reshape(valid_fraction, ny, nx), ...
    'selected_rank', rank_value, 'positive_rank', positive_rank, ...
    'lambda_tolerance', lambda_tol, ...
    'missing_policy', 'nonfinite deviations replaced by zero');
end
