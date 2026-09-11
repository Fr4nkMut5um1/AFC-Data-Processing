function sequence = build_pod_cluster_sequence(cache_file, cfg, stats, ...
    phase_stats, mean_bl)
%BUILD_POD_CLUSTER_SEQUENCE Full-resolution POD sequence on the structure domain.

modal_cfg = cfg.pod_cluster.pod;
if ~isequal(double(modal_cfg.spatial_stride(:).'), [1 1])
    error('tblR2:build_pod_cluster_sequence:SpatialStrideForbidden', ...
        'POD 聚类序列必须使用 spatial_stride=[1 1]；本路径不允许降空间精度。');
end
if modal_cfg.frame_stride ~= 1
    error('tblR2:build_pod_cluster_sequence:FrameStrideForbidden', ...
        'POD 聚类序列必须使用 frame_stride=1。');
end

sequence = tblR2.modal_snapshot_matrix(cache_file, cfg, stats, phase_stats, ...
    mean_bl, 'total', modal_cfg);
trusted = sequence.spatial_mask;
if isfield(cfg.structures, 'trusted_domain')
    trusted = tblR2.trusted_domain_mask(trusted, sequence.Y_grid_mm, ...
        cfg.structures.trusted_domain);
end
old_mask = sequence.spatial_mask;
keep = trusted(old_mask);
old_n = sequence.n_spatial;
u_rows = find(keep);
v_rows = old_n + u_rows;
sequence.X = sequence.X([u_rows; v_rows], :);
sequence.spatial_mask = trusted;
sequence.n_spatial = nnz(trusted);
sequence.sampling.n_joint_dof = 2 * sequence.n_spatial;
sequence.sampling.trusted_domain_applied = true;
sequence.sampling.precision_contract = ...
    'all frames; full retained grid; spatial_stride=[1 1]; no interpolation';
end
