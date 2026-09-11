function result = pod_cache(cache_file, cfg, stats, phase_stats, mean_bl, branch)
%POD_CACHE Joint u-v snapshot POD for total or random fluctuations.
%
% Contract: the fluctuation matrix Xf is formed by removing the temporal
% mean snapshot, C = Xf'*Xf/size(Xf,1) is formed, eigenvalues are obtained
% from eig(C) sorted descending, spatial modes are Phi = Xf*As normalized
% to unit norm, and temporal coefficients are Ac = Phi'*Xf (reference
% snapshot POD, mirroring Comparison_Re30w_AoA2.m). All ROI, frame and
% spatial decimation, max_frames and n_modes sampling knobs are read from
% cfg.pod via modal_snapshot_matrix; nothing is hard-coded here.
%
% Output semantics: energy_ratio is the PER-MODE ratio lambda_k / total
% energy, while cumulative_energy_ratio is its cumulative sum. This differs
% from tblR2.pod.snapshot_decomposition.POD.energy_ratio, which is already
% cumulative; keep the two contracts distinct.

sequence = tblR2.modal_snapshot_matrix(cache_file, cfg, stats, ...
    phase_stats, mean_bl, branch, cfg.pod);
ref = tblR2.pod.snapshot_decomposition(sequence.X, cfg.pod.n_modes);
modes = ref.modes;
coefficients = ref.coefficients.';
lambda = ref.lambda;
total_energy = ref.total_energy;
energy_ratio = lambda ./ max(total_energy, eps);
orthogonality = modes' * modes;
mapped = tblR2.map_joint_modes(modes, sequence);

selected = unique([1, ceil(size(sequence.X, 2) / 2), size(sequence.X, 2)]);
reconstruction_error = nan(numel(selected), 1);
for i = 1:numel(selected)
    idx = selected(i);
    reconstructed = modes * ref.coefficients(:, idx) + ref.mean_snapshot;
    raw = double(sequence.X(:, idx));
    reconstruction_error(i) = norm(raw - reconstructed) / max(norm(raw), eps);
end

result = struct();
result.branch = branch;
result.lambda = lambda;
result.energy_ratio = energy_ratio;
result.cumulative_energy_ratio = cumsum(energy_ratio);
result.temporal_coefficients = coefficients;
result.modes = mapped;
% Keep the joint representation alongside the mapped fields.  The former is
% the stable numerical contract used by POD reconstruction; the latter is
% convenient for plotting on the sampled ROI.
result.joint_modes = modes;
result.mean_snapshot = ref.mean_snapshot;
result.orthogonality_matrix = orthogonality;
result.max_orthogonality_error = max(abs( ...
    orthogonality - eye(size(orthogonality))), [], 'all');
result.reconstruction_frame_positions = selected(:);
result.reconstruction_frame_ids = sequence.frame_ids(selected);
result.reconstruction_relative_error = reconstruction_error;
result.sampling = sequence.sampling;
result.svd_diagnostics = struct('method', ref.definition, ...
    'rank_actual', ref.n_modes, 'n_snapshots', size(sequence.X, 2));
result.definition = ['Reference snapshot POD from Comparison_Re30w_AoA2.m: ' ...
    'C=Xf''*Xf/size(Xf,1), eig-based modes, unit-normalized Phi, and ' ...
    'Ac=Phi''*Xf. Total and controlled random branches are computed separately.'];

% Optional legacy-style instantaneous reconstruction.  It is deliberately
% opt-in at the library level so existing lightweight callers do not incur a
% second cache scan; the r2 case enables it in cfg.pod.reconstruction.
result.reconstruction = [];
if isfield(cfg.pod, 'reconstruction') && ...
        isfield(cfg.pod.reconstruction, 'enabled') && ...
        logical(cfg.pod.reconstruction.enabled)
    recon_cfg = cfg.pod.reconstruction;
    args = {};
    if isfield(recon_cfg, 'frame_positions') && ...
            ~isempty(recon_cfg.frame_positions)
        args = [args, {'frame_positions', recon_cfg.frame_positions}]; %#ok<AGROW>
    end
    if isfield(recon_cfg, 'frame_start') && ~isempty(recon_cfg.frame_start)
        args = [args, {'frame_start', recon_cfg.frame_start}]; %#ok<AGROW>
    end
    if isfield(recon_cfg, 'frame_count') && ~isempty(recon_cfg.frame_count)
        args = [args, {'frame_count', recon_cfg.frame_count}]; %#ok<AGROW>
    end
    if isfield(recon_cfg, 'n_modes') && ~isempty(recon_cfg.n_modes)
        args = [args, {'n_modes', recon_cfg.n_modes}]; %#ok<AGROW>
    end
    if isfield(recon_cfg, 'mode_indices') && ~isempty(recon_cfg.mode_indices)
        args = [args, {'mode_indices', recon_cfg.mode_indices}]; %#ok<AGROW>
    end
    if isfield(recon_cfg, 'add_mean')
        args = [args, {'add_mean', recon_cfg.add_mean}]; %#ok<AGROW>
    end
    if isfield(recon_cfg, 'include_raw')
        args = [args, {'include_raw', recon_cfg.include_raw}]; %#ok<AGROW>
    end
    args = [args, {'sequence', sequence}]; %#ok<AGROW>
    result.reconstruction = tblR2.pod_reconstruction(cache_file, cfg, ...
        stats, phase_stats, mean_bl, branch, result, args{:});
end
end
