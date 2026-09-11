function sequence = gaussian_pod_sequence(cache_file, cfg, stats, phase_stats, ...
    mean_bl, base_sequence)
%GAUSSIAN_POD_SEQUENCE Optional Gaussian -> POD sensitivity input sequence.
%
% The order matches the established Section-4 convention: PostProc physical
% instantaneous U/V -> ordinary Gaussian -> subtract the corresponding repeat
% mean.  The resulting full-resolution joint u-v fluctuation snapshots use the
% exact same frames and trusted mask as base_sequence.

sequence = base_sequence;
J = size(stats.X, 1); I = size(stats.X, 2);
delta_grid = interp1(mean_bl.boundary_layer.x, ...
    mean_bl.boundary_layer.delta99, stats.X, 'linear', NaN);
base_valid = stats.accepted_mask & isfinite(delta_grid) & delta_grid > 0;
analysis_domain = base_valid;
if isfield(cfg.structures, 'trusted_domain')
    analysis_domain = tblR2.trusted_domain_mask(base_valid, ...
        mean_bl.wall_distance_mm, cfg.structures.trusted_domain);
end
preprocess = cfg.structures.preprocessing;
if ~isfield(preprocess, 'gaussian') || ~preprocess.gaussian.enabled
    error('tblR2:gaussian_pod_sequence:GaussianDisabled', ...
        'Gaussian -> POD 分支要求 structures.preprocessing.gaussian.enabled=true。');
end

n_frames = numel(sequence.frame_ids);
X_snap = zeros(2 * sequence.n_spatial, n_frames, 'single');
batch = max(1, cfg.pod_cluster.chunk_frames);
linear_mask = sequence.spatial_mask(:);
for first = 1:batch:n_frames
    local = first:min(n_frames, first + batch - 1);
    ids = double(sequence.frame_ids(local));
    raw = tblR2.read_cache_chunk(cache_file, ids, 1:J, 1:I, ...
        'raw', stats, phase_stats);
    for k = 1:numel(ids)
        raw_U = squeeze(raw.U(k, :, :));
        raw_V = squeeze(raw.V(k, :, :));
        raw_valid = squeeze(raw.sampleValid(k, :, :)) & base_valid;
        filtered = tblR2.preprocess_structure_velocity(raw_U, raw_V, ...
            raw_valid, analysis_domain, preprocess);
        [mean_U, mean_V] = frame_mean(stats, ids(k));
        u_prime = filtered.U - mean_U;
        v_prime = filtered.V - mean_V;
        u_sub = u_prime(sequence.row_ids, sequence.col_ids);
        v_sub = v_prime(sequence.row_ids, sequence.col_ids);
        u_vec = u_sub(linear_mask);
        v_vec = v_sub(linear_mask);
        u_vec(~isfinite(u_vec)) = 0;
        v_vec(~isfinite(v_vec)) = 0;
        X_snap(:, local(k)) = single([u_vec; v_vec]);
    end
end
sequence.X = X_snap;
sequence.sampling.preprocessing = 'ordinary Gaussian -> subtract physical repeat mean';
sequence.sampling.gaussian = preprocess.gaussian;
end

function [mean_U, mean_V] = frame_mean(stats, frame_id)
if isfield(stats, 'repeat_means') && ~isempty(stats.repeat_means) && ...
        isfield(stats, 'repeat_boundaries') && ~isempty(stats.repeat_boundaries)
    rep = 1 + nnz(frame_id > stats.repeat_boundaries(:)');
    mean_U = squeeze(stats.repeat_means(1, rep, :, :));
    mean_V = squeeze(stats.repeat_means(2, rep, :, :));
else
    mean_U = stats.Uavex;
    mean_V = stats.Vavex;
end
end
