function result = pod_module(source, varargin)
%POD_MODULE Standalone r2 POD entry point with optional reconstruction.
%
% The cache signature mirrors tandem_baseline_r2_case.m.  Keeping this thin
% wrapper separate makes the numerical module discoverable while preserving
% the historical pod_cache name used by existing scripts and tests.
if isnumeric(source) && numel(varargin) >= 1 && isnumeric(varargin{1})
    U = double(source);
    V = double(varargin{1});
    n_modes = [];
    if numel(varargin) >= 2 && ~isempty(varargin{2}); n_modes = varargin{2}; end
    if isempty(n_modes)
        % After mean removal the snapshot rank cannot exceed the number of
        % frames.  Clamp the convenience API here so its default has the
        % same meaning as the cache API rather than silently requesting an
        % unnecessarily large spatial rank.
        n_modes = min([max(1, size(U, 1) - 1), size(U, 2) * size(U, 3)]);
    end
    result = array_pod(U, V, n_modes);
    return;
end
if numel(varargin) < 5
    error('tblR2:pod_module:InvalidCacheCall', ...
        '缓存接口需要 cache,cfg,stats,phase_stats,mean_bl,branch。');
end
cache_file = source;
cfg = varargin{1}; stats = varargin{2}; phase_stats = varargin{3};
mean_bl = varargin{4}; branch = varargin{5};
result = tblR2.pod_cache(cache_file, cfg, stats, phase_stats, mean_bl, branch);
end

function result = array_pod(U, V, n_modes)
if ~isequal(size(U), size(V)) || ndims(U) ~= 3
    error('tblR2:pod_module:InvalidArrays', ...
        'U/V 必须是同尺寸的 nFrames×J×I 数组。');
end
[n_frames, J, I] = size(U);
if n_frames < 2
    error('tblR2:pod_module:TooFewFrames', 'POD 至少需要两个快照。');
end
valid = all(isfinite(U), 1) & all(isfinite(V), 1);
spatial_mask = reshape(valid, [J I]);
U0 = reshape(U, n_frames, []); V0 = reshape(V, n_frames, []);
u_mean = zeros(1, size(U0, 2)); v_mean = zeros(1, size(V0, 2));
u_mean(valid(:).') = mean(U0(:, valid(:).'), 1);
v_mean(valid(:).') = mean(V0(:, valid(:).'), 1);
X = [(U0 - u_mean).'; (V0 - v_mean).'];
X(~isfinite(X)) = 0;
ref = tblR2.pod.snapshot_decomposition(X, n_modes);
N = J * I;
result = struct();
result.joint_modes = ref.modes;
result.temporal_coefficients = ref.coefficients.';
result.coeffs = result.temporal_coefficients;
result.modes_U = reshape(ref.modes(1:N, :).', [ref.n_modes J I]);
result.modes_V = reshape(ref.modes(N + 1:end, :).', [ref.n_modes J I]);
tmp_u = reshape(result.modes_U, [ref.n_modes N]);
tmp_v = reshape(result.modes_V, [ref.n_modes N]);
tmp_u(:, ~spatial_mask(:).') = NaN;
tmp_v(:, ~spatial_mask(:).') = NaN;
result.modes_U = reshape(tmp_u, [ref.n_modes J I]);
result.modes_V = reshape(tmp_v, [ref.n_modes J I]);
% Keep the same mapped-field field names as the cache API.  Direct array
% callers do not have physical coordinates, so the plotting entry point uses
% the X/Y grids supplied by the caller instead of inventing coordinates here.
result.modes = struct('U', result.modes_U, 'V', result.modes_V, ...
    'mask', spatial_mask, 'row_ids', 1:J, 'col_ids', 1:I);
result.spatial_mask = spatial_mask;
result.mean_U = reshape(u_mean, [J I]);
result.mean_V = reshape(v_mean, [J I]);
result.lambda = ref.lambda;
result.mean_snapshot = zeros(2 * N, 1);
result.energy_ratio = ref.lambda ./ ref.total_energy;
result.energy_ratio_per_mode = result.energy_ratio;
result.cumulative_energy_ratio = cumsum(result.energy_ratio);
result.total_energy = ref.total_energy;
result.n_modes = ref.n_modes;
result.n_frames = n_frames;
result.sampling = struct('n_frames', n_frames, 'n_joint_dof', 2 * N, ...
    'row_ids', 1:J, 'col_ids', 1:I, 'spatial_mask', spatial_mask);
positions = unique([1, ceil(n_frames / 2), n_frames]);
fluctuation = ref.modes * ref.coefficients(:, positions);
mean_joint = [u_mean(:); v_mean(:)];
total = fluctuation + mean_joint;
R = struct();
R.frame_positions = positions(:);
R.frame_ids = positions(:);
R.n_modes = ref.n_modes;
R.reconstructed_fluctuation_U = reshape(fluctuation(1:N, :).', ...
    [numel(positions) J I]);
R.reconstructed_fluctuation_V = reshape(fluctuation(N + 1:end, :).', ...
    [numel(positions) J I]);
R.reconstructed_U = reshape(total(1:N, :).', [numel(positions) J I]);
R.reconstructed_V = reshape(total(N + 1:end, :).', [numel(positions) J I]);
tmp_u = reshape(R.reconstructed_fluctuation_U, [numel(positions) N]);
tmp_v = reshape(R.reconstructed_fluctuation_V, [numel(positions) N]);
tmp_ut = reshape(R.reconstructed_U, [numel(positions) N]);
tmp_vt = reshape(R.reconstructed_V, [numel(positions) N]);
tmp_u(:, ~spatial_mask(:).') = NaN;
tmp_v(:, ~spatial_mask(:).') = NaN;
tmp_ut(:, ~spatial_mask(:).') = NaN;
tmp_vt(:, ~spatial_mask(:).') = NaN;
R.reconstructed_fluctuation_U = reshape(tmp_u, [numel(positions) J I]);
R.reconstructed_fluctuation_V = reshape(tmp_v, [numel(positions) J I]);
R.reconstructed_U = reshape(tmp_ut, [numel(positions) J I]);
R.reconstructed_V = reshape(tmp_vt, [numel(positions) J I]);
R.raw_U = U(positions, :, :);
R.raw_V = V(positions, :, :);
R.residual_U = R.raw_U - R.reconstructed_U;
R.residual_V = R.raw_V - R.reconstructed_V;
result.reconstruction = R;
result.definition = ['Array POD: fixed finite DOF mask, temporal mean removal, ' ...
    'r2 reference snapshot eigendecomposition, and unit-normalized modes.'];
end
