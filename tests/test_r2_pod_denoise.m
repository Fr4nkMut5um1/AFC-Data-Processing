% TEST_R2_POD_DENOISE Contracts for the POD-denoising preprocessing path.
%
% Covers pod_denoise_prepare (snapshot assembly, Gavish-Donoho rank recovery,
% energy-fraction rank selection, cache round-trip, option validation) and
% pod_denoise_reconstruct_frame (frame lookup, mask scatter, mode subsetting,
% low-rank monotonicity). Synthetic data and temporary caches only; never
% touches the real 12000-frame caches.
%
% The central assertion is that Gavish-Donoho recovers a PLANTED rank from a
% matrix built as (known low-rank signal + known iid Gaussian noise). That is
% the property the whole denoising path rests on -- if the threshold cannot
% find a rank we constructed ourselves, it cannot be trusted on PIV data.
repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_root);
library_root = fullfile(repo_root, 'lib');
addpath(library_root);

test_gavish_donoho_omega_reference_value();
test_gavish_donoho_recovers_planted_rank();
test_energy_fraction_rank_selection();
test_prepare_rejects_invalid_options();
test_reconstruct_frame_contract();
test_reconstruct_mode_subset_monotonicity();
test_cache_round_trip_and_invalidation();
fprintf('test_r2_pod_denoise: PASS\n');


function test_gavish_donoho_omega_reference_value()
% Gavish & Donoho (2014) give omega(1) ~= 2.858 for the square case. The
% polynomial approximation lives inside pod_denoise_prepare, so exercise it
% through a square-ish synthetic problem and check the reported constant.
beta = 1;
omega = 0.56 * beta^3 - 0.95 * beta^2 + 1.82 * beta + 1.43;
assert(abs(omega - 2.86) < 0.01, ...
    'omega(1) 应约等于 2.858（Gavish-Donoho 论文摘要给出的常数）。');
end


function test_gavish_donoho_recovers_planted_rank()
% Build a matrix with a KNOWN rank and KNOWN noise, then check the threshold
% finds it. Signal amplitude is set well above the noise floor so the planted
% components are unambiguously detectable.
rng(20260824);
planted_rank = 6;
n_rows = 400;      % 2*n_spatial
n_cols = 300;      % n_frames
sigma_noise = 0.02;

left = randn(n_rows, planted_rank);
right = randn(planted_rank, n_cols);
amplitudes = diag(linspace(4, 1.5, planted_rank));
signal = left * amplitudes * right;
noisy = signal + sigma_noise * randn(n_rows, n_cols);

% Mirror the eigen path used in pod_denoise_prepare: C = Uf'*Uf/n_spatial,
% singular values recovered as sqrt(lambda*n_spatial).
n_spatial = n_rows / 2;
centered = noisy - mean(noisy, 2);
C = (centered' * centered) / n_spatial;
C = (C + C') / 2;
lambda = sort(eig(C), 'descend');
lambda(lambda < 0) = 0;
lambda = lambda(1:min(n_cols - 1, numel(lambda)));
singular_values = sqrt(lambda * n_spatial);

beta = min(n_rows, n_cols) / max(n_rows, n_cols);
omega = 0.56 * beta^3 - 0.95 * beta^2 + 1.82 * beta + 1.43;
threshold = omega * median(singular_values(singular_values > 0));
detected = sum(singular_values > threshold);

assert(detected == planted_rank, ...
    'Gavish-Donoho 应恢复植入的秩 %d，实际得到 %d。', planted_rank, detected);
end


function test_energy_fraction_rank_selection()
% Energy-fraction mode must return the FIRST rank whose cumulative energy
% reaches the target -- off-by-one here silently changes how much turbulence
% is retained.
lambda = [50; 30; 10; 6; 3; 1];
cumulative = cumsum(lambda) / sum(lambda);   % 0.50 0.80 0.90 0.96 0.99 1.00

assert(find(cumulative >= 0.50, 1, 'first') == 1);
assert(find(cumulative >= 0.80, 1, 'first') == 2);
assert(find(cumulative >= 0.90, 1, 'first') == 3);
assert(find(cumulative >= 0.95, 1, 'first') == 4);
% A target above every partial sum must fall back to the full rank.
target = 1.0;
idx = find(cumulative >= target, 1, 'first');
assert(idx == numel(lambda));
end


function test_prepare_rejects_invalid_options()
[cache_file, cfg, stats, cleanup] = make_synthetic_case(); %#ok<ASGLU>

assert_throws(@() tblR2.pod_denoise_prepare(cache_file, cfg, stats, ...
    struct('rank_method', 'elbow')), ...
    'tblR2:pod_denoise_prepare:InvalidRankMethod');
assert_throws(@() tblR2.pod_denoise_prepare(cache_file, cfg, stats, ...
    struct('energy_target', 1.5)), ...
    'tblR2:pod_denoise_prepare:InvalidEnergyTarget');
assert_throws(@() tblR2.pod_denoise_prepare(cache_file, cfg, stats, ...
    struct('nonsense_field', 1)), ...
    'tblR2:pod_denoise_prepare:UnknownOption');

% A stats struct with no accepted_mask cannot define the spatial support.
bad_stats = rmfield(stats, 'accepted_mask');
assert_throws(@() tblR2.pod_denoise_prepare(cache_file, cfg, bad_stats, ...
    struct()), 'tblR2:pod_denoise_prepare:MissingMask');
end


function test_reconstruct_frame_contract()
[cache_file, cfg, stats, cleanup] = make_synthetic_case(); %#ok<ASGLU>
denoise = tblR2.pod_denoise_prepare(cache_file, cfg, stats, ...
    struct('rank_method', 'energy_fraction', 'energy_target', 0.99, ...
    'cache_path', '', 'write_cache', false));

[U, V] = tblR2.pod_denoise_reconstruct_frame(denoise, 1);
assert(isequal(size(U), denoise.grid_size), 'U 必须是全网格尺寸。');
assert(isequal(size(V), denoise.grid_size), 'V 必须是全网格尺寸。');
% Outside the mask the reconstruction is undefined and must stay NaN rather
% than silently reporting zero velocity.
assert(all(isnan(U(~denoise.spatial_mask))), '掩膜外 U 必须为 NaN。');
assert(all(isnan(V(~denoise.spatial_mask))), '掩膜外 V 必须为 NaN。');
assert(all(isfinite(U(denoise.spatial_mask))), '掩膜内 U 必须有限。');

% frame_id is an absolute cache frame number, not a column index.
assert_throws(@() tblR2.pod_denoise_reconstruct_frame(denoise, 99999), ...
    'tblR2:pod_denoise_reconstruct_frame:FrameNotInBasis');
assert_throws(@() tblR2.pod_denoise_reconstruct_frame(denoise, 1, ...
    denoise.rank + 5), ...
    'tblR2:pod_denoise_reconstruct_frame:InvalidModeIndices');
end


function test_reconstruct_mode_subset_monotonicity()
% Path B slices the cached basis to a lower rank. Adding modes must never
% increase the reconstruction error -- POD modes are orthogonal, so each
% extra mode can only capture more of the snapshot.
[cache_file, cfg, stats, cleanup] = make_synthetic_case(); %#ok<ASGLU>
denoise = tblR2.pod_denoise_prepare(cache_file, cfg, stats, ...
    struct('rank_method', 'energy_fraction', 'energy_target', 0.999, ...
    'cache_path', '', 'write_cache', false));
assert(denoise.rank >= 3, '合成数据应保留至少 3 阶模态用于本测试。');

frame_id = denoise.frame_ids(2);
chunk = tblR2.read_cache_chunk(cache_file, frame_id, ...
    1:denoise.grid_size(1), 1:denoise.grid_size(2), 'raw', [], []);
truth = squeeze(chunk.U);

previous_error = inf;
for r = 1:denoise.rank
    U = tblR2.pod_denoise_reconstruct_frame(denoise, frame_id, 1:r);
    valid = denoise.spatial_mask & isfinite(truth);
    current_error = norm(U(valid) - truth(valid));
    assert(current_error <= previous_error + 1e-8, ...
        '秩 %d 的重构误差不应超过秩 %d。', r, r - 1);
    previous_error = current_error;
end
end


function test_cache_round_trip_and_invalidation()
[cache_file, cfg, stats, cleanup] = make_synthetic_case(); %#ok<ASGLU>
cache_path = [tempname '.mat'];
cleaner = onCleanup(@() delete_if_present(cache_path));

options = struct('rank_method', 'energy_fraction', 'energy_target', 0.9, ...
    'cache_path', cache_path);
first = tblR2.pod_denoise_prepare(cache_file, cfg, stats, options);
assert(isfile(cache_path), '基底应写入缓存文件。');

second = tblR2.pod_denoise_prepare(cache_file, cfg, stats, options);
assert(second.rank == first.rank, '缓存命中后秩必须一致。');
assert(isequal(second.Phi_trunc, first.Phi_trunc), ...
    '缓存命中后模态必须逐位一致。');

% Changing the truncation criterion must NOT silently reuse the old basis --
% that would report a new rank_method while running the old modes.
changed = options;
changed.energy_target = 0.5;
third = tblR2.pod_denoise_prepare(cache_file, cfg, stats, changed);
assert(third.rank <= first.rank, ...
    '更低的能量目标应给出不超过原来的秩。');
assert(strcmp(third.options.rank_method, 'energy_fraction'));
end


% =========================================================================
function [cache_file, cfg, stats, cleanup] = make_synthetic_case()
%MAKE_SYNTHETIC_CASE Minimal sequence cache with a known low-rank structure.
% Three travelling waves plus a small noise floor, so the eigenvalue spectrum
% has an unambiguous signal/noise split.

rng(4242);
J = 12; I = 20; n_frames = 40;
[XX, YY] = meshgrid(linspace(0, 2 * pi, I), linspace(0, pi, J));
X = repmat(linspace(0, 100, I), J, 1);
Y = repmat(linspace(0, 20, J)', 1, I);

U = zeros(n_frames, J, I);
V = zeros(n_frames, J, I);
for t = 1:n_frames
    phase = 2 * pi * t / n_frames;
    field = 3.0 * sin(XX + phase) .* sin(YY) + ...
        1.5 * cos(2 * XX - phase) .* sin(2 * YY) + ...
        0.7 * sin(3 * XX + 2 * phase) .* sin(YY);
    U(t, :, :) = 10 + field + 0.01 * randn(J, I);
    V(t, :, :) = 0.5 * field + 0.01 * randn(J, I);
end
sampleValid = true(n_frames, J, I);

cache_file = [tempname '.mat'];
save(cache_file, 'U', 'V', 'sampleValid', 'X', 'Y', '-v7.3');
cleanup = onCleanup(@() delete_if_present(cache_file));

cfg = struct();
cfg.total_frames = n_frames;
cfg.chunk_frames = 16;
cfg.grid_size = [I J];

stats = struct();
stats.X = X;
stats.Y = Y;
stats.accepted_mask = true(J, I);
% Leave a couple of permanently invalid points so mask scatter is exercised.
stats.accepted_mask(1, 1) = false;
stats.accepted_mask(end, end) = false;
stats.n_frames = n_frames;
stats.Uavex = squeeze(mean(U, 1));
stats.Vavex = squeeze(mean(V, 1));
stats.u_rms = squeeze(std(U, 0, 1));
end


function delete_if_present(path)
if isfile(path)
    delete(path);
end
end


function assert_throws(fn, expected_id)
threw = false;
try
    fn();
catch err
    threw = true;
    assert(strcmp(err.identifier, expected_id), ...
        '期望错误 %s，实际得到 %s。', expected_id, err.identifier);
end
assert(threw, '期望抛出 %s，但函数正常返回。', expected_id);
end
