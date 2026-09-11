% TEST_R2_POD_CLUSTER_ANALYSIS Full-resolution POD denoising/cluster contracts.
repo_root = fileparts(fileparts(mfilename('fullpath')));
library_root = fullfile(repo_root, 'lib');
addpath(library_root, '-begin');

energy = tblR2.select_energy_modes([5 3 1 1], [0.80 0.90 0.95]);
assert(isequal(energy.n_modes(:).', [2 3 4]));
assert(all(energy.achieved_energy + eps >= energy.targets));

mask = true(4, 5);
sequence_elf = struct('n_spatial', nnz(mask), 'spatial_mask', mask);
[xx, yy] = meshgrid(0:4, 0:3);
smooth1 = ones(size(mask));
smooth2 = cos(pi * xx / 5) .* cos(pi * yy / 4);
rng(12);
joint = zeros(2 * nnz(mask), 6);
fields = {smooth1, randn(size(mask)), smooth2, randn(size(mask)), ...
    randn(size(mask)), randn(size(mask))};
for k = 1:6
    joint(:, k) = [fields{k}(:); fields{k}(:)];
end
elf = tblR2.elf_mode_selection(joint, sequence_elf, struct( ...
    'min_ppr', 0.01, 'min_mask_jaccard', 0, 'min_segment_modes', 2));
assert(isfield(elf, 'mode_indices') && isfield(elf, 'ppr'));
assert(all(ismember([1 3], elf.sorted_mode_indices(1:2))));

root = tempname; mkdir(root); cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
I = 10; J = 6; n_frames = 12;
[X, Y] = meshgrid(1:I, 1:J);
U = zeros(n_frames, J, I, 'single');
V = zeros(size(U), 'single');
for k = 1:n_frames
    coherent = 0.8 * sin(2*pi*k/n_frames) .* exp(-((X-5-k/8).^2)/8) .* exp(-Y/8);
    secondary = 0.25 * cos(4*pi*k/n_frames) .* cos(pi*X/I) .* sin(pi*Y/J);
    U(k,:,:) = single(10 + coherent + secondary + 0.02*randn(J,I));
    V(k,:,:) = single(0.15 * coherent - 0.1 * secondary + 0.02*randn(J,I));
end
sampleValid = true(n_frames, J, I);
cache_file = fullfile(root, 'cache.mat');
h_mm = 1; frame_ids = (1:n_frames)';
cache_meta = struct('schema_version',4,'case_id','test/r2/pod_cluster', ...
    'source_role','postproc');
save(cache_file, 'U','V','sampleValid','X','Y','h_mm','frame_ids', ...
    'cache_meta','-v7.3');

stats = struct('X',X,'Y',Y,'n_frames',n_frames,'accepted_mask',true(J,I), ...
    'Uavex',squeeze(mean(U,1)),'Vavex',squeeze(mean(V,1)), ...
    'u_rms',squeeze(std(double(U),0,1)), ...
    'v_rms',squeeze(std(double(V),0,1)), 'repeat_means',[]);
mean_bl = struct('wall_distance_mm',Y, ...
    'boundary_layer',struct('x',1:I,'delta99',repmat(5,1,I)));

cfg = struct('case_type','baseline','chunk_frames',3,'fs',100);
cfg.instantaneous = struct('frame_ids',[1 n_frames],'n_output_frames',3);
cfg.structures = struct('alpha',0.5,'seed_alpha',0.7, ...
    'min_abs_fluctuation',0,'min_abs_seed_fluctuation',0, ...
    'min_pixels',1,'connectivity',4,'min_lsm_delta',0.5, ...
    'min_vlsm_delta',1.0,'max_wall_normal_delta',Inf, ...
    'max_internal_hole_pixels',0,'envelope_closing_radius_cells',0, ...
    'max_aspect_ratio',Inf,'reject_trusted_boundary_touching',false, ...
    'merge_gap_cells',0,'merge_require_y_overlap',true, ...
    'catalog_frame_stride',1, ...
    'trusted_domain',struct('streamwise_edge_columns',0, ...
    'wall_normal_top_rows',0), ...
    'preprocessing',struct('enabled',true,'gaussian',struct( ...
    'enabled',true,'sigma_cells',1,'radius_cells',1)), ...
    'q2q4',struct('enabled',false,'H_values',0,'frame_stride',1));
cfg.pod_cluster = struct();
cfg.pod_cluster.chunk_frames = 3;
cfg.pod_cluster.representative_frame_ids = [1 6 12];
cfg.pod_cluster.energy_targets = [0.80 0.90 0.95];
cfg.pod_cluster.pod = struct('n_modes',1,'frame_stride',1, ...
    'spatial_stride',[1 1],'x_range_mm',[1 I], ...
    'max_y_over_delta',Inf,'max_frames',[]);
cfg.pod_cluster.elf = struct('min_ppr',0.01,'min_mask_jaccard',0, ...
    'min_segment_modes',2);
cfg.pod_cluster.gaussian_then_pod = struct('enabled',false);
cfg.pod_cluster.fixed_n_stability = struct( ...
    'scalar_relative_tolerance',0.10,'cdf_max_difference',0.10);

gaussian = tblR2.structure_analysis_cache(cache_file, cfg, stats, [], mean_bl);
base_sequence = tblR2.build_pod_cluster_sequence( ...
    cache_file, cfg, stats, [], mean_bl);
gaussian_sequence = tblR2.gaussian_pod_sequence( ...
    cache_file, cfg, stats, [], mean_bl, base_sequence);
assert(isequal(size(gaussian_sequence.X), size(base_sequence.X)));
assert(~isequal(gaussian_sequence.X, base_sequence.X));
out = tblR2.pod_cluster_analysis(cache_file, cfg, stats, [], mean_bl, gaussian);
assert(isequal(out.pod.sampling.spatial_stride, [1 1]));
assert(out.pod.sampling.n_frames == n_frames);
assert(all(diff(out.pod.energy_selection.n_modes) >= 0));
assert(isfield(out, 'raw') && isfield(out, 'gaussian'));
assert(isfield(out.pod, 'POD_E80') && isfield(out.pod.POD_E80, 'primary'));
assert(isfield(out.pod.POD_E80, 'own_rms_sensitivity'));
assert(~contains(out.scope, 'POD-Q2/Q4 product is computed') || ...
    contains(out.scope, 'no POD-Q2/Q4 product is computed'));
assert(height(out.branch_summary) == 6);
assert(isfield(out.fixed_n_recommendation, 'stability'));
fprintf('test_r2_pod_cluster_analysis: PASS\n');
