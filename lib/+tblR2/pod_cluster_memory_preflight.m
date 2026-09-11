function report = pod_cluster_memory_preflight(cfg, stats, mean_bl)
%POD_CLUSTER_MEMORY_PREFLIGHT Guard the exact full-rank snapshot POD peak.
%
% The estimate follows the actual legacy-equivalent implementation: caller
% single X plus double X/Xf/Phi, and several N-by-N covariance/eigen/coefficient
% arrays.  It is deliberately conservative and does not authorize any spatial,
% temporal, or numeric-precision reduction.

modal_cfg = cfg.pod_cluster.pod;
rows = 1:size(stats.X, 1);
candidate_cols = find(stats.X(1, :) >= modal_cfg.x_range_mm(1) & ...
    stats.X(1, :) <= modal_cfg.x_range_mm(2));
X_sub = stats.X(rows, candidate_cols);
Y_sub = mean_bl.wall_distance_mm(rows, candidate_cols);
delta = interp1(mean_bl.boundary_layer.x, mean_bl.boundary_layer.delta99, ...
    X_sub, 'linear', NaN);
mask = stats.accepted_mask(rows, candidate_cols) & isfinite(delta) & ...
    delta > 0 & Y_sub <= modal_cfg.max_y_over_delta .* delta;
if isfield(cfg.structures, 'trusted_domain')
    mask = tblR2.trusted_domain_mask(mask, Y_sub, cfg.structures.trusted_domain);
end
n_spatial = nnz(mask);
n_joint_dof = 2 * n_spatial;
n_frames = stats.n_frames;

safety = 1.25;
if isfield(cfg.pod_cluster, 'memory_guard') && ...
        isfield(cfg.pod_cluster.memory_guard, 'safety_factor')
    safety = cfg.pod_cluster.memory_guard.safety_factor;
end
% Approximate simultaneous storage in snapshot_decomposition:
%   caller single X: 4*D*N
%   double X, Xf, Phi: 24*D*N
%   covariance/eigenvectors/eigenvalues/sorted vectors/coefficients: ~40*N^2
estimated_bytes = safety * (28 * n_joint_dof * n_frames + ...
    40 * n_frames ^ 2);
largest_array_bytes = 8 * n_joint_dof * n_frames;
available_bytes = Inf;
max_array_bytes = Inf;
try
    info = memory;
    available_bytes = double(info.MemAvailableAllArrays);
    max_array_bytes = double(info.MaxPossibleArrayBytes);
catch
    % Non-Windows MATLAB may not expose memory(); leave availability unknown.
end

report = struct();
report.n_spatial = n_spatial;
report.n_joint_dof = n_joint_dof;
report.n_frames = n_frames;
report.estimated_peak_bytes = estimated_bytes;
report.estimated_peak_gib = estimated_bytes / 2^30;
report.largest_double_array_bytes = largest_array_bytes;
report.largest_double_array_gib = largest_array_bytes / 2^30;
report.available_bytes = available_bytes;
report.available_gib = available_bytes / 2^30;
report.max_array_bytes = max_array_bytes;
report.max_array_gib = max_array_bytes / 2^30;
report.safety_factor = safety;
report.sufficient = estimated_bytes <= available_bytes && ...
    largest_array_bytes <= max_array_bytes;
report.definition = ['Conservative peak estimate for the unchanged exact ' ...
    'double-precision snapshot_decomposition implementation.'];
end
