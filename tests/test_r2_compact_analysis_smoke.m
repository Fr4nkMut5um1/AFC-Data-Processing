% TEST_R2_COMPACT_ANALYSIS_SMOKE Exercise the slim analysis and figure paths.
repo_root = fileparts(fileparts(mfilename('fullpath')));
library_root = fullfile(repo_root, 'lib');
addpath(library_root, '-begin');
root = tempname; mkdir(root); cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>

I = 12; J = 8; n_frames = 16;
cache_file = fullfile(root, 'cache.mat');
U = single(zeros(n_frames, J, I)); V = single(zeros(n_frames, J, I));
sampleValid = true(n_frames, J, I);
for k = 1:n_frames
    [xx, yy] = meshgrid(1:I, 1:J);
    U(k,:,:) = single(0.2 * sin((xx + k) / 3) .* exp(-yy / 10));
    V(k,:,:) = single(0.1 * cos((xx - k) / 4) .* exp(-yy / 12));
end
X = repmat(1:I, J, 1); Y = repmat((1:J)', 1, I); h_mm = 1;
cache_meta = struct('schema_version',4,'case_id','test/r2/compact', ...
    'source_role','postproc'); frame_ids = (1:n_frames)';
save(cache_file,'U','V','sampleValid','X','Y','h_mm','frame_ids','cache_meta','-v7.3');

stats = struct(); stats.X = X; stats.Y = Y; stats.h = h_mm; stats.n_frames = n_frames;
stats.accepted_mask = true(J,I); stats.Uavex = squeeze(mean(U,1)); stats.Vavex = squeeze(mean(V,1));
stats.u_rms = squeeze(std(double(U),0,1)); stats.v_rms = squeeze(std(double(V),0,1));
u_mean_3d = reshape(stats.Uavex, [1 J I]);
v_mean_3d = reshape(stats.Vavex, [1 J I]);
stats.uv_rey = -squeeze(mean((double(U)-u_mean_3d).*(double(V)-v_mean_3d),1));
stats.TKE = 0.5*(stats.u_rms.^2 + stats.v_rms.^2); stats.repeat_means = [];
bl = struct('wall_distance_mm',Y,'boundary_layer',struct('x',1:I,'delta99',repmat(7,1,I)));
bl.normalization = struct('u_tau',1); bl.y_plus = Y;
cfg = struct('case_type','baseline','chunk_frames',4,'instantaneous',struct('frame_ids',[1 n_frames],'n_output_frames',2), ...
    'structures',struct('alpha',0.2,'seed_alpha',0.3,'min_pixels',2,'connectivity',8, ...
    'min_lsm_delta',1,'min_vlsm_delta',3,'max_wall_normal_delta',Inf,'catalog_frame_stride',2, ...
    'trusted_domain',struct('streamwise_edge_columns',1,'wall_normal_top_rows',1), ...
    'preprocessing',struct('enabled',false,'gaussian',struct('enabled',false)), ...
    'q2q4',struct('enabled',false,'H_values',[0 1],'frame_stride',2)), ...
    'transport',struct('edge_buffer_cells',[0 0]),'fs',100,'nu',1.48e-5,'temporal',struct('nfft',8,'overlap_fraction',0.5), ...
    'correlations',struct('reference_points_mm',[4 1],'max_time_lag_s',0.02,'max_streamwise_lag_mm',5, ...
    'selected_y_plus',1,'ridge_min_correlation',0.2,'external_signal_file','', ...
    'two_point',false,'space_time',false,'streamwise',false));
cfg.phase = struct('enabled',false);
structures = tblR2.structure_analysis_cache(cache_file,cfg,stats,[],bl);
assert(isfield(structures,'catalog') && isfield(structures,'instantaneous'));
assert(~isfield(structures,'vlsm_gallery') && ~isfield(structures,'sensitivity'));

cfg.temporal.x_interval_mm = [2 11]; cfg.temporal.frequency_band_hz = [1 40];
cfg.temporal.min_valid_fraction = 0.5; cfg.temporal.Uc = struct('fraction',0.8,'nearwall_n',0,'nearwall_plus',10.8,'method','profile_fraction');
temporal = tblR2.temporal_spectra_cache(cache_file,cfg,stats,[],bl,'total');
assert(isfield(temporal,'phi_uu_mean_across_x') && ~isfield(temporal,'Uc_sensitivity'));

correlations = tblR2.correlation_analysis_cache(cache_file,cfg,stats,[],bl,'total');
assert(~correlations.enabled_products.two_point && ~correlations.enabled_products.space_time);
fprintf('test_r2_compact_analysis_smoke: PASS\n');
