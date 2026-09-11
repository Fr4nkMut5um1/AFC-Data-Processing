function result = dmd_module(source, cfg, stats, phase_stats, mean_bl, branch)
%DMD_MODULE Exact reduced DMD with an r2-compatible cache/array interface.
%
% The source may be an already assembled sequence struct, a joint numeric
% snapshot matrix, or a cache filename.  Cache callers use the latter form:
% dmd_module(cache, cfg, stats, phase, mean_bl, 'total').

if nargin < 2 || isempty(cfg); cfg = struct(); end
if nargin < 3; stats = []; end
if nargin < 4; phase_stats = []; end
if nargin < 5; mean_bl = []; end
if nargin < 6 || isempty(branch); branch = 'total'; end

if isstruct(source) && isfield(source, 'X')
    sequence = source;
elseif isnumeric(source)
    sequence = numeric_sequence(source, cfg);
else
    if ~isfield(cfg, 'dmd')
        error('tblR2:dmd_module:MissingConfig', 'cfg.dmd 配置不能为空。');
    end
    sequence = tblR2.modal_snapshot_matrix(source, cfg, stats, ...
        phase_stats, mean_bl, branch, cfg.dmd);
end

if ~isfield(sequence, 'X') || size(sequence.X, 2) < 3
    error('tblR2:dmd_module:TooFewFrames', ...
        'DMD 至少需要三个等时间间隔快照。');
end
if ~isfield(sequence, 'sampling')
    sequence.sampling = struct('n_frames', size(sequence.X, 2), ...
        'n_joint_dof', size(sequence.X, 1));
end
if ~isfield(sequence, 'dt_s') || ~(isscalar(sequence.dt_s) && ...
        isfinite(sequence.dt_s) && sequence.dt_s > 0)
    error('tblR2:dmd_module:InvalidTimeStep', ...
        'sequence.dt_s 必须是有限正标量。');
end
if isfield(sequence, 'frame_ids') && numel(sequence.frame_ids) > 2
    ids = double(sequence.frame_ids(:));
    if any(diff(ids) ~= diff(ids(1:2)))
        error('tblR2:dmd_module:UnequalTimeStep', ...
            'DMD 帧 ID 必须等间隔。');
    end
end

Xraw = double(sequence.X);
if any(~isfinite(Xraw(:)))
    error('tblR2:dmd_module:InvalidSnapshotMatrix', ...
        'DMD 快照矩阵必须全部为有限值。');
end
X1 = Xraw(:, 1:end - 1);
X2 = Xraw(:, 2:end);
rank_requested = size(X1, 1);
if isfield(cfg, 'dmd') && isfield(cfg.dmd, 'n_modes')
    rank_requested = min(rank_requested, double(cfg.dmd.n_modes));
end
rank_requested = min(rank_requested, size(X1, 2));
% Do not pass numerically null SVD directions to piDMD. Its exact-mode
% normalization divides by the eigenvalue, so an oversized rank can create
% Inf/NaN columns even when the input matrix itself is finite.
[~, singular_values_matrix, ~] = svd(X1, 0);
singular_values = diag(singular_values_matrix);
if isempty(singular_values) || ~any(isfinite(singular_values))
    error('tblR2:dmd_module:InvalidSnapshotMatrix', ...
        'DMD 快照矩阵没有有限的奇异值。');
end
scale = max(singular_values(isfinite(singular_values)));
svd_tol = max(size(X1)) * eps(max(scale, 1));
rank_numerical = nnz(singular_values > svd_tol);
rank_requested = min(rank_requested, rank_numerical);
if rank_requested < 1 || rank_requested ~= fix(rank_requested)
    error('tblR2:dmd_module:InvalidRank', 'DMD 秩必须是正整数。');
end

toolbox_cfg = cfg;
if ~isfield(toolbox_cfg, 'stages') || ~isfield(toolbox_cfg.stages, 'dmd')
    toolbox_cfg.stages.dmd = 'compute';
end
toolbox_info = tblR2.ensure_external_toolboxes(toolbox_cfg, {'dmd'});
[~, eigenvalues, modes] = piDMD(X1, X2, 'exact', rank_requested);
eigenvalues = eigenvalues(:);
finite_eigs = eigenvalues(isfinite(eigenvalues));
eig_scale = max([1; abs(finite_eigs)]);
eig_log_floor = max(1e-12, 100 * eps(eig_scale));
mode_fallback = false;
invalid_modes = false(1, size(modes, 2));
for im = 1:size(modes, 2)
    invalid_modes(im) = any(~isfinite(modes(:, im))) || ...
        norm(modes(:, im)) <= eps || abs(eigenvalues(im)) < eig_log_floor;
end
if any(invalid_modes)
    [fallback_modes, fallback_eigs] = safe_exact_modes(X1, X2, rank_requested);
    [modes, ~] = replace_invalid_modes(eigenvalues, modes, ...
        fallback_eigs, fallback_modes, invalid_modes);
    mode_fallback = true;
end
for im = 1:size(modes, 2)
    nrm = norm(modes(:, im));
    if nrm > 0; modes(:, im) = modes(:, im) ./ nrm; end
end
% A zero eigenvalue has no finite continuous-time logarithm. Use an explicit
% floor and retain the mask in diagnostics so downstream plots stay finite.
small_eigenvalue = ~isfinite(eigenvalues) | abs(eigenvalues) < eig_log_floor;
log_eigenvalues = log(eigenvalues);
if any(small_eigenvalue)
    phases = angle(eigenvalues(small_eigenvalue));
    phases(~isfinite(phases)) = 0;
    log_eigenvalues(small_eigenvalue) = log(eig_log_floor) + 1i * phases;
end
omega = log_eigenvalues ./ sequence.dt_s;
frequency_hz = imag(omega) ./ (2 * pi);
growth_rate_per_s = real(omega);
amplitudes = pinv(modes) * Xraw(:, 1);

selected = unique([1, ceil(size(Xraw, 2) / 2), size(Xraw, 2)]);
reconstruction_error = nan(numel(selected), 1);
reconstructed = cell(numel(selected), 1);
for k = 1:numel(selected)
    position = selected(k);
    dynamics = amplitudes .* exp(omega .* ((position - 1) * sequence.dt_s));
    reconstructed{k} = modes * dynamics;
    raw = Xraw(:, position);
    reconstruction_error(k) = norm(raw - reconstructed{k}) / max(norm(raw), eps);
end

if isfield(cfg, 'case_type') && strcmp(cfg.case_type, 'controlled') && ...
        isfield(cfg, 'phase') && isfield(cfg.phase, 'f0_hz') && ...
        ~isempty(cfg.phase.f0_hz)
    harmonic_number = round(abs(frequency_hz) ./ cfg.phase.f0_hz);
    harmonic_mismatch_hz = abs(abs(frequency_hz) - ...
        harmonic_number .* cfg.phase.f0_hz);
else
    harmonic_number = nan(size(frequency_hz));
    harmonic_mismatch_hz = nan(size(frequency_hz));
end

if isfield(sequence, 'n_spatial') && isfield(sequence, 'spatial_mask')
    mapped = tblR2.map_joint_modes(modes, sequence);
else
    mapped = struct('joint', modes);
end
result = struct();
result.branch = branch;
result.eigenvalues = eigenvalues;
result.lambda = eigenvalues;
result.omega_per_s = omega;
result.mu = omega;
result.frequency_hz = frequency_hz;
result.growth_rate_per_s = growth_rate_per_s;
result.amplitudes = amplitudes;
result.modes = mapped;
result.joint_modes = modes;
result.harmonic_number_nearest = harmonic_number;
result.harmonic_mismatch_hz = harmonic_mismatch_hz;
result.reconstruction_frame_positions = selected(:);
if isfield(sequence, 'frame_ids')
    result.reconstruction_frame_ids = sequence.frame_ids(selected);
else
    result.reconstruction_frame_ids = selected(:);
end
result.reconstruction_relative_error = reconstruction_error;
result.reconstruction = struct();
result.reconstruction.frame_positions = selected(:);
result.reconstruction.frame_ids = result.reconstruction_frame_ids;
result.reconstruction.joint = reconstructed;
result.sampling = sequence.sampling;
result.svd_diagnostics = struct('method', 'piDMD exact SVD', ...
    'rank', rank_requested, 'rank_numerical', rank_numerical, ...
    'singular_values', singular_values, 'svd_tolerance', svd_tol, ...
    'piDMD_path', toolbox_info.piDMD, 'mode_fallback', mode_fallback, ...
    'small_eigenvalue_mask', small_eigenvalue, ...
    'eigenvalue_log_floor', eig_log_floor);
result.definition = ['Reduced exact DMD from the MIT-licensed piDMD library ' ...
    '(method=exact). The reconstruction starts at t=0, and frequency/growth ' ...
    'are derived from log(eigenvalue)/dt.'];
end

function sequence = numeric_sequence(X, cfg)
if ~ismatrix(X) || ~isnumeric(X) || isempty(X)
    error('tblR2:dmd_module:InvalidMatrix', '数值输入必须是非空 DOF×frame 矩阵。');
end
sequence = struct('X', double(X));
if isfield(cfg, 'fs') && isfinite(cfg.fs) && cfg.fs > 0
    sequence.dt_s = 1 / cfg.fs;
else
    sequence.dt_s = 1;
end
sequence.frame_ids = (1:size(X, 2)).';
sequence.sampling = struct('n_frames', size(X, 2), ...
    'n_joint_dof', size(X, 1));
end

function [modes, eigenvalues] = safe_exact_modes(X1, X2, r)
[Ux, Sx, Vx] = svd(X1, 0);
Ux = Ux(:, 1:r);
Sx = Sx(1:r, 1:r);
Vx = Vx(:, 1:r);
Atilde = (Ux' * X2) * Vx * pinv(Sx);
[eVecs, eVals] = eig(Atilde);
eigenvalues = diag(eVals);
% This is the same exact-DMD spatial mode formula as piDMD, without its
% additional division by eigenvalue that is undefined for a zero eigenvalue.
modes = X2 * Vx * pinv(Sx) * eVecs;
end

function [aligned_modes, aligned_eigs] = replace_invalid_modes(target_eigs, ...
        original_modes, fallback_eigs, fallback_modes, invalid_modes)
target_eigs = target_eigs(:);
fallback_eigs = fallback_eigs(:);
aligned_eigs = target_eigs;
aligned_modes = original_modes;
unused = true(numel(fallback_eigs), 1);
for k = 1:numel(target_eigs)
    distances = abs(fallback_eigs - target_eigs(k));
    distances(~unused) = Inf;
    [best, idx] = min(distances);
    if isfinite(best)
        if invalid_modes(k)
            aligned_modes(:, k) = fallback_modes(:, idx);
        end
        unused(idx) = false;
    end
end
for k = find(invalid_modes)
    if any(~isfinite(aligned_modes(:, k)))
        aligned_modes(:, k) = fallback_modes(:, k);
    end
end
end
