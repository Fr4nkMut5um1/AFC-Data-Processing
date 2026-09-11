function tests = test_deshpande2023_baseline
%TEST_DESHPANDE2023_BASELINE Synthetic contract tests for the isolated experiment.
tests = functiontests(localfunctions);
end

function setupOnce(test_case)
repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repo_root, 'lib'), '-begin');
test_case.TestData.repo_root = repo_root;
end

function testChunkStatisticsMatchDirect(test_case)
rng(41);
U = randn(7, 3, 5);
V = randn(size(U));
valid = rand(size(U)) > 0.2;
U(~valid) = NaN; V(~valid) = NaN;
actual = d23.statistics_from_arrays(U, V, valid, 3);
u_ref = squeeze(sum(U, 1, 'omitnan')) ./ squeeze(sum(valid, 1));
v_ref = squeeze(sum(V, 1, 'omitnan')) ./ squeeze(sum(valid, 1));
up = U - reshape(u_ref, 1, 3, 5);
up(~valid) = NaN;
rms_ref = sqrt(squeeze(sum(sum(up.^2, 1, 'omitnan'), 3, 'omitnan')) ./ ...
    squeeze(sum(sum(valid, 1), 3)));
rms_ref = rms_ref(:);
verifyEqual(test_case, actual.Ubar, u_ref, 'AbsTol', 1e-13);
verifyEqual(test_case, actual.Vbar, v_ref, 'AbsTol', 1e-13);
verifyEqual(test_case, actual.u_rms_y, rms_ref, 'AbsTol', 1e-13);
end

function testDeltaInterpolation(test_case)
y = (0:6).';
u = [0; 2; 4; 6; 8; 10; 10];
result = d23.delta99_from_profile(y, u, 2);
verifyEqual(test_case, result.u_edge_m_s, 10, 'AbsTol', 1e-14);
verifyEqual(test_case, result.delta99_mm, 4.95, 'AbsTol', 1e-14);
end

function testDynamicUtauLoader(test_case)
folder = tempname;
mkdir(folder);
cleanup = onCleanup(@() rmdir(folder, 's'));
filename = fullfile(folder, 'utau.mat');
meta = struct('case_id', 'case/test', 'total_frames', 12, ...
    'grid_size', [4 3], 'created_utc', 'test');
data = struct('normalization', struct('u_tau', 0.42), ...
    'wall_distance_mm', repmat((1:2).', 1, 3));
save(filename, 'meta', 'data');
source = d23.load_utau(filename, 'case/test', 12, [2 3]);
verifyEqual(test_case, source.u_tau_m_s, 0.42, 'AbsTol', 0);
verifyEqual(test_case, source.wall_distance_mm, data.wall_distance_mm);
end

function testSpatialExclusionClosedMappingAndConfigHash(test_case)
[X, wall_y] = meshgrid(0:4, 0:3);
options = struct('enabled', true, 'x_start_mm', 1, ...
    'x_end_mm', 3, 'wall_y_height_mm', 2);
[mask, info] = d23.resolve_spatial_exclusion(X, wall_y, options);
expected = false(4,5); expected(1:3,2:4) = true;
verifyEqual(test_case, mask, expected);
verifyEqual(test_case, info.excluded_grid_point_count, uint32(9));
verifyEqual(test_case, info.realized_x_min_mm, 1);
verifyEqual(test_case, info.realized_x_max_mm, 3);
verifyEqual(test_case, info.realized_wall_y_min_mm, 0);
verifyEqual(test_case, info.realized_wall_y_max_mm, 2);
verifyEqual(test_case, double(info.row_indices(:)).', 1:3);
verifyEqual(test_case, double(info.column_indices(:)).', 2:4);

cfg = d23.default_config(test_case.TestData.repo_root);
disabled_hash = d23.config_hash(cfg);
cfg.preprocessing.spatial_exclusion = options;
d23.validate_config(cfg);
verifyNotEqual(test_case, d23.config_hash(cfg), disabled_hash);
edge_hash = d23.config_hash(cfg);
cfg.detection.streamwise_edge_exclusion.enabled = true;
d23.validate_config(cfg);
verifyNotEqual(test_case, d23.config_hash(cfg), edge_hash);
cfg.preprocessing.spatial_exclusion.x_start_mm = 4;
cfg.preprocessing.spatial_exclusion.x_end_mm = 3;
verifyError(test_case, @() d23.validate_config(cfg), ...
    'd23:validate_config:SpatialExclusionBounds');
cfg = d23.default_config(test_case.TestData.repo_root);
cfg.detection.max_complete_ss_per_sign = Inf;
cfg.detection.selection_rule = ...
    'longest_then_pixel_count_then_component_id_nonoverlapping_bbox';
cfg.detection.streamwise_edge_exclusion.buffer_cells = 3.5;
verifyError(test_case, @() d23.validate_config(cfg), ...
    'd23:validate_config:StreamwiseEdgeExclusion');
end

function testConnectivityStrictThresholdAndNonoverlappingRetention(test_case)
[ctx, cfg] = synthetic_context(10, 45);
cfg.detection.max_complete_ss_per_sign = Inf;
cfg.detection.selection_rule = ...
    'longest_then_pixel_count_then_component_id_nonoverlapping_bbox';
up = zeros(10, 45); valid = true(size(up)); urms = ones(10,1);
up(1:7, 2:11) = 2;
up(1:7, 20:29) = 2;
up(1:7, 34:42) = 2;
positive = d23.identify_frame(up, valid, urms, 1, 1, 8, 1, ctx, cfg);
verifyEqual(test_case, nnz(positive.IsSS3 & ~positive.IsCensored), 2);
verifyFalse(test_case, any(positive.SuppressedByBBoxOverlap));

diag_field = zeros(10,45);
diag_field(4,10) = 2; diag_field(5,11) = 2;
c4 = d23.identify_frame(diag_field, valid, urms, 1, 1, 4, 1, ctx, cfg);
c8 = d23.identify_frame(diag_field, valid, urms, 1, 1, 8, 1, ctx, cfg);
verifyEqual(test_case, height(c4), 2);
verifyEqual(test_case, height(c8), 1);

negative_field = -up;
negative = d23.identify_frame(negative_field, valid, urms, ...
    1, 1, 8, -1, ctx, cfg);
verifyEqual(test_case, nnz(negative.IsSS3 & ~negative.IsCensored), 2);
end

function testStreamwiseEdgeExclusionAndInteriorFallback(test_case)
[ctx, cfg] = synthetic_context(10, 45);
cfg.detection.max_complete_ss_per_sign = Inf;
cfg.detection.selection_rule = ...
    'longest_then_pixel_count_then_component_id_nonoverlapping_bbox';
cfg.detection.streamwise_edge_exclusion = struct('enabled', false, ...
    'buffer_cells', 3);
up = zeros(10,45);
up(1:7,4:18) = 2;       % Longest left-buffer candidate: ColMin=4.
up(1:7,23:33) = 2;      % Interior fallback.
disabled = d23.identify_frame(up, true(size(up)), ones(10,1), ...
    1, 1, 8, 1, ctx, cfg);
verifyEqual(test_case, nnz(disabled.IsSS3 & ~disabled.IsCensored), 2);
verifyTrue(test_case, any(disabled.TouchesStreamwiseLeftBuffer));
verifyFalse(test_case, any(disabled.RejectedByStreamwiseEdge));

cfg.detection.streamwise_edge_exclusion.enabled = true;
enabled = d23.identify_frame(up, true(size(up)), ones(10,1), ...
    1, 1, 8, 1, ctx, cfg);
left = enabled.TouchesStreamwiseLeftBuffer;
verifyTrue(test_case, any(left));
verifyTrue(test_case, all(enabled.RejectedByStreamwiseEdge(left)));
verifyFalse(test_case, any(enabled.IsSS3(left)));
verifyEqual(test_case, nnz(enabled.IsSS3 & ~enabled.IsCensored), 1);
verifyTrue(test_case, any(enabled.IsSS3 & enabled.ColMin == 23));

right_field = zeros(10,45); right_field(1:7,32:42) = 2;
right = d23.identify_frame(right_field, true(size(right_field)), ones(10,1), ...
    1, 1, 8, 1, ctx, cfg);
verifyTrue(test_case, right.TouchesStreamwiseRightBuffer);
verifyTrue(test_case, right.RejectedByStreamwiseEdge);
verifyFalse(test_case, right.IsSS3);

% Exact FOV-boundary components are also censored.  Enabling the optional
% edge rule must nevertheless clear every primary length-tier flag while
% retaining the censor flag and geometric audit fields.
boundary_field = zeros(10,45);
boundary_field(1:7,1:15) = 2;
boundary_field(1:7,31:45) = 2;
boundary = d23.identify_frame(boundary_field, true(size(boundary_field)), ...
    ones(10,1), 1, 1, 8, 1, ctx, cfg);
verifyEqual(test_case, height(boundary), 2);
verifyTrue(test_case, all(boundary.IsCensored));
verifyTrue(test_case, all(boundary.RejectedByStreamwiseEdge));
verifyFalse(test_case, any(boundary.IsSS3));
verifyFalse(test_case, any(boundary.IsSS3p8));
verifyFalse(test_case, any(boundary.IsSS4p5));
end

function testOverlappingBoundingBoxesKeepLongest(test_case)
[ctx, cfg] = synthetic_context(10, 45);
cfg.detection.max_complete_ss_per_sign = Inf;
cfg.detection.selection_rule = ...
    'longest_then_pixel_count_then_component_id_nonoverlapping_bbox';
up = zeros(10,45);
% Disconnected L-shapes whose bounding boxes share pixels in columns 15:24.
up(1:7,5) = 2; up(1,5:24) = 2;
up(1:7,30) = 2; up(7,15:30) = 2;
catalog = d23.identify_frame(up, true(size(up)), ones(10,1), ...
    1, 1, 8, 1, ctx, cfg);
eligible = catalog.PassLength3 & catalog.PassWallLower & ...
    catalog.PassWallUpper & ~catalog.IsCensored;
verifyEqual(test_case, nnz(eligible), 2);
verifyEqual(test_case, nnz(catalog.IsSS3 & ~catalog.IsCensored), 1);
verifyEqual(test_case, nnz(catalog.SuppressedByBBoxOverlap), 1);
kept = catalog(catalog.IsSS3,:);
verifyEqual(test_case, kept.ColMin, uint16(5));
end

function testCensorFillAndWallEquality(test_case)
[ctx, cfg] = synthetic_context(10, 30);
up = zeros(10,30); valid = true(size(up)); urms = ones(10,1);
up(1:7,1:10) = 2;
catalog = d23.identify_frame(up, valid, urms, 1, 1, 8, 1, ctx, cfg);
verifyTrue(test_case, catalog.TouchesUpstream);
verifyTrue(test_case, catalog.TouchesWall);
verifyTrue(test_case, catalog.IsCensored);
verifyEqual(test_case, catalog.FillFraction, 1, 'AbsTol', 1e-14);
ctx.lower_plus_limit = catalog.YMin_plus;
ctx.upper_plus_limit = catalog.YMax_plus;
again = d23.identify_frame(up, valid, urms, 1, 1, 8, 1, ctx, cfg);
verifyTrue(test_case, again.PassWallLower);
verifyTrue(test_case, again.PassWallUpper);
end

function testSpatialExclusionCutsAndMarksWithoutCensor(test_case)
[ctx, cfg] = synthetic_context(10, 45);
excluded = false(10,45); excluded(1:7,15:18) = true;
ctx.spatial_exclusion_mask = excluded;
ctx.spatial_exclusion.enabled = true;
up = zeros(10,45); up(1:7,2:30) = 2;
valid = true(size(up)) & ~excluded;
catalog = d23.identify_frame(up, valid, ones(10,1), ...
    1, 1, 8, 1, ctx, cfg);
verifyEqual(test_case, height(catalog), 2);
verifyTrue(test_case, all(catalog.TouchesUserExclusion));
verifyFalse(test_case, any(catalog.TouchesInvalid));
verifyFalse(test_case, any(catalog.IsCensored));
verifyEqual(test_case, nnz(catalog.IsSS3), 1);
verifyLessThan(test_case, double(catalog.ColMax(1)), 15);
verifyGreaterThan(test_case, double(catalog.ColMin(2)), 18);
end

function testNoSSTieBreakAndNoCandidate(test_case)
[ctx, cfg] = synthetic_context(10, 40);
up = zeros(10,40); up(1:7,16:25) = 2;
catalog = d23.identify_frame(up, true(size(up)), ones(10,1), ...
    1, 1, 8, 1, ctx, cfg);
target = catalog(catalog.IsSS3, :);
pairs = d23.match_noss(target, ctx, cfg);
verifyTrue(test_case, pairs.Matched);
verifyEqual(test_case, pairs.NoSSColMin, uint16(6));
verifyLessThan(test_case, pairs.CenterShift_cells, 0);

wide = target;
wide.ColMin = uint16(10); wide.ColMax = uint16(30);
wide.BBoxWidth_px = 21; wide.Lx_over_delta = 7;
pairs_wide = d23.match_noss(wide, ctx, cfg);
verifyFalse(test_case, pairs_wide.Matched);
verifyEqual(test_case, pairs_wide.NoSSReasonCode, uint8(1));
end

function testSpectrumParsevalAndLongWave(test_case)
n = 64; dx = 0.01; x = (0:n-1) * dx;
base = sin(2*pi*20*x);
s = d23.spatial_periodogram(base, dx, 4);
verifyEqual(test_case, s.df_cpm * sum(s.psd_per_cpm), ...
    s.weighted_mean_square, 'RelTol', 2e-13);
same_ratio = sum(s.psd_per_cpm(2:5)) / sum(s.psd_per_cpm(2:5));
verifyEqual(test_case, same_ratio, 1, 'AbsTol', 0);
long_wave = base + 2*sin(2*pi*(1/(n*dx))*x);
s_long = d23.spatial_periodogram(long_wave, dx, 4);
cutoff = 3 / (n*dx);
low = s.frequency_cpm > 0 & s.frequency_cpm <= cutoff;
verifyGreaterThan(test_case, sum(s_long.psd_per_cpm(low)), ...
    sum(s.psd_per_cpm(low)));
p2 = dx/s.window_energy * abs(fft(base.*hamming(n,'periodic').',s.nfft)).^2;
verifyEqual(test_case, s.psd_per_cpm(1), p2(1), 'AbsTol', 1e-14);
verifyEqual(test_case, s.psd_per_cpm(end), p2(s.nfft/2+1), 'AbsTol', 1e-14);
verifyEqual(test_case, s.psd_per_cpm(2:end-1), ...
    2*p2(2:s.nfft/2), 'AbsTol', 1e-14);
non_power = d23.spatial_periodogram(1:10, dx, 4);
verifyEqual(test_case, non_power.nfft, 2^nextpow2(4*10));
end

function testGaussianMatchesDirect(test_case)
rng(2);
up = randn(2,7,9); vp = randn(size(up)); valid = true(size(up));
g = struct('enabled', true, 'sigma_cells', 1.2, ...
    'filter_size', 7, 'padding', 'replicate');
[actual_u, actual_v, meta] = d23.apply_gaussian(up, vp, valid, g);
for i = 1:2
    verifyEqual(test_case, squeeze(actual_u(i,:,:)), ...
        imgaussfilt(squeeze(up(i,:,:)),1.2,'FilterSize',7,'Padding','replicate'), ...
        'AbsTol', 1e-14);
    verifyEqual(test_case, squeeze(actual_v(i,:,:)), ...
        imgaussfilt(squeeze(vp(i,:,:)),1.2,'FilterSize',7,'Padding','replicate'), ...
        'AbsTol', 1e-14);
end
verifyEqual(test_case, meta.filter_size, 7);
end

function testJointPodRankMissingAndReconstruction(test_case)
a = [1 -1 1 -1]; b = [1 1 -1 -1];
X = [1;2;0;0;0;0;1;-1]*a + [0;0;1;-1;1;-1;0;0]*b;
U = permute(reshape(X(1:4,:),2,2,4),[3 1 2]);
V = permute(reshape(X(5:8,:),2,2,4),[3 1 2]);
valid = true(size(U));
pod_cfg = struct('min_valid_fraction',1, ...
    'rank',struct('kind','fixed_n','n',2));
result = d23.joint_pod_array(U,V,valid,pod_cfg);
verifyEqual(test_case, result.reconstructed_matrix, result.snapshot_matrix, ...
    'AbsTol', 2e-12);
verifyEqual(test_case, result.modes.'*result.modes, eye(2), 'AbsTol', 2e-12);
reference = sort(eig((result.centered_matrix.'*result.centered_matrix)/8), 'descend');
verifyEqual(test_case, result.eigenvalues, reference, 'AbsTol', 2e-12);

valid_missing = valid;
valid_missing(1,1,1) = false;
valid_missing(1:2,2,2) = false;
U_missing = U; V_missing = V;
U_missing(~valid_missing) = NaN; V_missing(~valid_missing) = NaN;
pod_cfg.min_valid_fraction = 0.75;
missing = d23.joint_pod_array(U_missing,V_missing,valid_missing,pod_cfg);
verifyTrue(test_case, missing.retained_spatial_mask(1,1));
verifyFalse(test_case, missing.retained_spatial_mask(2,2));

too_many = pod_cfg; too_many.rank.n = 4;
verifyError(test_case, @() d23.joint_pod_array(U,V,valid,too_many), ...
    'd23:select_pod_rank:RankTooLarge');
end

function testJointPodEnergySelection(test_case)
rng(3);
U = randn(6,2,3); V = 0.3*randn(size(U)); valid = true(size(U));
fixed = struct('min_valid_fraction',1,'rank',struct('kind','fixed_n','n',5));
reference = d23.joint_pod_array(U,V,valid,fixed);
positive = reference.eigenvalues(reference.eigenvalues > reference.lambda_tolerance);
target = sum(positive(1:2))/sum(positive) - 1e-12;
energy = struct('min_valid_fraction',1, ...
    'rank',struct('kind','energy_fraction','value',target));
selected = d23.joint_pod_array(U,V,valid,energy);
verifyEqual(test_case, selected.selected_rank, 2);
end

function testOutOfCorePodCache(test_case)
folder = tempname; mkdir(folder); mkdir(fullfile(folder,'pod'));
cleanup = onCleanup(@() rmdir(folder,'s'));
rng(8);
U = randn(5,2,2); V = randn(size(U)); sampleValid = true(size(U));
U = U - mean(U,1); V = V - mean(V,1);
cache_file = fullfile(folder,'cache.mat');
save(cache_file,'U','V','sampleValid','-v7.3');
stats = d23.statistics_from_arrays(U,V,sampleValid,2);
ctx = struct('cache_size',[5 2 2],'cache_file',cache_file, ...
    'source_fingerprint','synthetic');
cfg = d23.default_config(test_case.TestData.repo_root);
cfg.preprocessing.pod.enabled = true;
cfg.preprocessing.pod.min_valid_fraction = 1;
cfg.preprocessing.pod.rank = struct('kind','fixed_n','n',3);
cfg.preprocessing.pod.spatial_block_dof = 2;
cfg.preprocessing.pod.time_tile_frames = 2;
cfg.statistics.chunk_size = 48;
cfg.execution.label = 'pod_test';
pod_file = d23.build_pod_cache(ctx,stats,cfg,folder);
verifyTrue(test_case,isfile(pod_file));
out = matfile(pod_file);
info = whos(out,'Uprime','Vprime');
verifyEqual(test_case,info(1).class,'double');
verifyEqual(test_case,info(1).size,[5 2 2]);
metadata = load(fullfile(folder,'pod','pod_metadata.mat'),'pod_meta');
verifyEqual(test_case,metadata.pod_meta.state,'COMPLETE');
verifyEqual(test_case,metadata.pod_meta.selected_rank,3);
up = U - reshape(stats.Ubar,1,2,2);
vp = V - reshape(stats.Vbar,1,2,2);
reference_cfg = cfg.preprocessing.pod;
reference = d23.joint_pod_array(up,vp,sampleValid,reference_cfg);
verifyEqual(test_case,double(out.Uprime),reference.U_reconstructed,'AbsTol',3e-12);
verifyEqual(test_case,double(out.Vprime),reference.V_reconstructed,'AbsTol',3e-12);
end

function testPodSpatialExclusionRemovesPeriodicContamination(test_case)
folder = tempname; mkdir(folder); mkdir(fullfile(folder,'pod'));
cleanup = onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
nt = 8; ny = 2; nx = 3;
t = (0:nt-1).';
U = zeros(nt,ny,nx); V = zeros(size(U));
for row = 1:ny
    for col = 1:nx
        U(:,row,col) = (0.2*row + 0.1*col) * sin(2*pi*t/nt);
        V(:,row,col) = (0.1*row - 0.05*col) * cos(2*pi*t/nt);
    end
end
U(:,1,1) = 100 * (-1).^t;
V(:,1,1) = -80 * (-1).^t;
sampleValid = true(size(U));
cache_file = fullfile(folder,'cache.mat');
save(cache_file,'U','V','sampleValid','-v7.3');
stats = d23.statistics_from_arrays(U,V,sampleValid,3);
[X, wall_y] = meshgrid(0:nx-1,0:ny-1);
options = struct('enabled',true,'x_start_mm',0,'x_end_mm',0, ...
    'wall_y_height_mm',0);
[excluded, info] = d23.resolve_spatial_exclusion(X,wall_y,options);
ctx = struct('cache_size',[nt ny nx],'cache_file',cache_file, ...
    'source_fingerprint','masked-pod-test', ...
    'spatial_exclusion_mask',excluded,'spatial_exclusion',info);
cfg = d23.default_config(test_case.TestData.repo_root);
cfg.preprocessing.spatial_exclusion = options;
cfg.preprocessing.pod.enabled = true;
cfg.preprocessing.pod.min_valid_fraction = 1;
cfg.preprocessing.pod.rank = struct('kind','energy_fraction','value',0.5);
cfg.preprocessing.pod.spatial_block_dof = 2;
cfg.preprocessing.pod.time_tile_frames = 2;
pod_file = d23.build_pod_cache(ctx,stats,cfg,folder);
meta = load(fullfile(folder,'pod','pod_metadata.mat'),'pod_meta');

active_valid = sampleValid & ~reshape(excluded,1,ny,nx);
up = U - reshape(stats.Ubar,1,ny,nx);
vp = V - reshape(stats.Vbar,1,ny,nx);
reference = d23.joint_pod_array(up,vp,active_valid,cfg.preprocessing.pod);
verifyEqual(test_case,meta.pod_meta.selected_rank,reference.selected_rank);
verifyEqual(test_case,meta.pod_meta.eigenvalues,reference.eigenvalues, ...
    'AbsTol',2e-11);
verifyEqual(test_case,meta.pod_meta.retained_spatial_count_before_exclusion,6);
verifyEqual(test_case,meta.pod_meta.retained_spatial_count,5);
verifyEqual(test_case,meta.pod_meta.excluded_retained_spatial_count,1);
out = matfile(pod_file);
actual_u = double(out.Uprime);
verifyTrue(test_case,all(isnan(actual_u(:,1,1))));
verifyEqual(test_case,actual_u(:,~excluded), ...
    reference.U_reconstructed(:,~excluded),'AbsTol',3e-11);
end

function testPodConfigRejectsNonfiniteValues(test_case)
cfg = d23.default_config(test_case.TestData.repo_root);
cfg.execution.label = 'pod_test';
cfg.preprocessing.pod.enabled = true;
cfg.preprocessing.pod.min_valid_fraction = NaN;
cfg.preprocessing.pod.rank = struct('kind','fixed_n','n',2);
verifyError(test_case,@() d23.validate_config(cfg), ...
    'd23:validate_config:PodValidity');
cfg.preprocessing.pod.min_valid_fraction = 1;
cfg.preprocessing.pod.rank = struct('kind','energy_fraction','value',NaN);
verifyError(test_case,@() d23.validate_config(cfg), ...
    'd23:validate_config:PodRank');
end

function testPodDetectionRmsUsesReconstruction(test_case)
folder = tempname;
mkdir(folder); mkdir(fullfile(folder,'mat')); mkdir(fullfile(folder,'pod'));
cleanup = onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
rng(17);
U = randn(4,2,3); V = 0.2*randn(size(U)); sampleValid = true(size(U));
sampleValid(4,2,3) = false; U(~sampleValid) = NaN; V(~sampleValid) = NaN;
cache_file = fullfile(folder,'cache.mat');
save(cache_file,'U','V','sampleValid','-v7.3');
stats = d23.statistics_from_arrays(U,V,sampleValid,2);
Uprime = 0.5 * (U - reshape(stats.Ubar,1,2,3));
Vprime = zeros(size(Uprime));
Uprime(:,2,3) = NaN; Vprime(:,2,3) = NaN;
pod_file = fullfile(folder,'pod','pod_reconstruction.mat');
save(pod_file,'Uprime','Vprime','-v7.3');
pod_meta = struct('eigenvalues',[4;2;1;0], 'lambda_tolerance',1e-12, ...
    'selected_rank',1,'positive_rank',3);
save(fullfile(folder,'pod','pod_metadata.mat'),'pod_meta');

cfg = d23.default_config(test_case.TestData.repo_root);
cfg.execution.label = 'pod_detection_test';
cfg.preprocessing.pod.enabled = true;
cfg.preprocessing.pod.min_valid_fraction = 1;
cfg.preprocessing.pod.rank = struct('kind','energy_fraction','value',0.5);
excluded = false(2,3); excluded(1,1) = true;
ctx = struct('cache_size',[4 2 3], 'cache_file',cache_file, ...
    'source_fingerprint','pod-rms-test', ...
    'spatial_exclusion_mask',excluded);
actual = d23.prepare_detection_statistics(ctx,stats,cfg,folder,pod_file);
valid = sampleValid & ~reshape(excluded,1,2,3) & isfinite(Uprime);
work = Uprime; work(~valid) = 0;
count = reshape(sum(sum(valid,1),3),2,1);
expected = sqrt(reshape(sum(sum(work.^2,1),3),2,1) ./ count);
verifyEqual(test_case,actual.u_rms_y,expected,'AbsTol',1e-14);
verifyEqual(test_case,actual.valid_count_y,uint64(count));
verifyEqual(test_case,actual.field_source,'PostProc-POD-E50');
verifyEqual(test_case,actual.pod_selected_rank,uint32(1));
verifyEqual(test_case,actual.pod_joint_energy_retained_fraction,4/7, ...
    'AbsTol',1e-14);
end

function testDirectDetectionRmsUsesSpatialExclusion(test_case)
folder = tempname; mkdir(folder); mkdir(fullfile(folder,'mat'));
cleanup = onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
U = reshape(1:24,4,2,3); V = zeros(size(U));
U(:,1,1) = [100;-100;100;-100];
sampleValid = true(size(U));
cache_file = fullfile(folder,'cache.mat');
save(cache_file,'U','V','sampleValid','-v7.3');
stats = d23.statistics_from_arrays(U,V,sampleValid,2);
excluded = false(2,3); excluded(1,1) = true;
ctx = struct('cache_size',[4 2 3],'cache_file',cache_file, ...
    'source_fingerprint','direct-rms-mask', ...
    'spatial_exclusion_mask',excluded);
cfg = d23.default_config(test_case.TestData.repo_root);
actual = d23.prepare_detection_statistics(ctx,stats,cfg,folder,'');
valid = sampleValid & ~reshape(excluded,1,2,3);
direct = U - reshape(stats.Ubar,1,2,3); direct(~valid) = 0;
count = reshape(sum(sum(valid,1),3),2,1);
expected = sqrt(reshape(sum(sum(direct.^2,1),3),2,1) ./ count);
verifyEqual(test_case,actual.u_rms_y,expected,'AbsTol',1e-14);
verifyEqual(test_case,actual.postproc_same_domain_u_rms_y,expected, ...
    'AbsTol',1e-14);
verifyNotEqual(test_case,actual.u_rms_y,stats.u_rms_y);
end

function testBalanceColormapHasWhiteCenter(test_case)
cmap = d23.balance_colormap(257);
verifySize(test_case,cmap,[257 3]);
verifyEqual(test_case,cmap(129,:),[1 1 1],'AbsTol',0);
verifyGreaterThan(test_case,cmap(1,3),cmap(1,1));
verifyGreaterThan(test_case,cmap(end,1),cmap(end,3));
verifyGreaterThanOrEqual(test_case,min(cmap,[],'all'),0);
verifyLessThanOrEqual(test_case,max(cmap,[],'all'),1);
end

function testGalleryUsesBalanceAndPhysicalAspect(test_case)
folder = tempname;
mkdir(folder); mkdir(fullfile(folder,'png')); mkdir(fullfile(folder,'png','gallery'));
mkdir(fullfile(folder,'png','contact_sheets')); mkdir(fullfile(folder,'fig'));
cleanup = onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
[ctx,cfg] = synthetic_context(10,45);
options = struct('enabled',true,'x_start_mm',30,'x_end_mm',35, ...
    'wall_y_height_mm',2);
[ctx.spatial_exclusion_mask,ctx.spatial_exclusion] = ...
    d23.resolve_spatial_exclusion(repmat(ctx.x_mm,10,1), ...
    ctx.wall_distance_mm,options);
cfg.preprocessing.spatial_exclusion = options;
U = zeros(1,10,45); U(1,1:7,2:17)=2;
V = zeros(size(U)); sampleValid = true(size(U));
cache_file = fullfile(folder,'cache.mat');
save(cache_file,'U','V','sampleValid','-v7.3');
ctx.cache_file=cache_file; ctx.cache_size=[1 10 45]; ctx.frame_ids=uint32(1);
ctx.wall_y_mm=median(ctx.wall_distance_mm,2);
stats=struct('Ubar',zeros(10,45),'Vbar',zeros(10,45),'u_rms_y',ones(10,1));
catalog=d23.identify_frame(squeeze(U),squeeze(sampleValid),ones(10,1), ...
    1,1,8,1,ctx,cfg);
catalog=catalog(catalog.IsSS3,:);
selection=d23.select_gallery(catalog,1);
detection_stats=struct('u_rms_y',ones(10,1),'field_source','PostProc-direct');
cfg.output.figure_dpi=30;
files=d23.create_gallery(selection,catalog,ctx,stats,detection_stats, ...
    cfg,folder,'');
verifyEqual(test_case,numel(files),6);
fig_file=fullfile(folder,'fig','slot_01_frame_00001.fig');
fig=openfig(fig_file,'invisible');
fig_cleanup=onCleanup(@() close(fig)); %#ok<NASGU>
images=findobj(fig,'Type','Image');
ax=ancestor(images(1),'axes');
cmap=colormap(fig);
verifyEqual(test_case,cmap(129,:),[1 1 1],'AbsTol',0);
verifyEqual(test_case,ax.DataAspectRatio,[1 1 1],'AbsTol',1e-14);
verifyEqual(test_case,ax.CLim,[-3 3],'AbsTol',1e-14);
mask_patch=findobj(fig,'Tag','UserSpatialExclusion');
verifyEqual(test_case,numel(mask_patch),1);
verifyEqual(test_case,mask_patch.FaceColor,[0.86 0.86 0.86],'AbsTol',1e-14);
end

function testConnectivityComparisonUsesFrameSignUnits(test_case)
[ctx,cfg] = synthetic_context(10,45);
up = zeros(10,45); up(1:7,2:17) = 2;
seed = d23.identify_frame(up,true(size(up)),ones(10,1), ...
    1,101,8,1,ctx,cfg);
seed = seed(seed.IsSS3 & ~seed.IsCensored,:);
both8 = seed; both8.FrameOrdinal(:)=uint32(1); both8.FrameID(:)=uint32(101);
both4 = both8; both4.Connectivity(:)=uint8(4); both4.ColMax(:)=uint16(16);
both4.BBoxWidth_px(:)=15; both4.Lx_mm(:)=15;
both4.Lx_over_delta(:)=15/ctx.delta99_mm;
only8 = both8; only8.FrameOrdinal(:)=uint32(2); only8.FrameID(:)=uint32(102);
only4 = both4; only4.FrameOrdinal(:)=uint32(3); only4.FrameID(:)=uint32(103);
only4.Sign(:)=int8(-1);
catalog = [both8;both4;only8;only4];
ctx.cache_size(1)=3; ctx.frame_ids=uint32([101;102;103]);
cfg.execution.frame_ordinals=(1:3).';
comparison = d23.connectivity_comparison(catalog,ctx,cfg);
row = comparison.summary_table(comparison.summary_table.LengthThreshold==3,:);
verifyEqual(test_case,row.Detected8,uint32(2));
verifyEqual(test_case,row.Detected4,uint32(2));
verifyEqual(test_case,row.Both,uint32(1));
verifyEqual(test_case,row.Only8,uint32(1));
verifyEqual(test_case,row.Only4,uint32(1));
verifyEqual(test_case,row.FrameSignJaccard,1/3,'AbsTol',1e-14);
verifyEqual(test_case,height(comparison.frame_sign_table),18);
verifyEqual(test_case,height(comparison.paired_table),3);
end

function testMultiObjectConnectivityAndGalleryAreObjectBased(test_case)
[ctx,cfg] = synthetic_context(10,45);
cfg.detection.max_complete_ss_per_sign = Inf;
cfg.detection.selection_rule = ...
    'longest_then_pixel_count_then_component_id_nonoverlapping_bbox';
ctx.frame_ids = uint32(101);
cfg.execution.frame_ordinals = 1;
up = zeros(10,45); up(1:7,2:12) = 2; up(1:7,21:33) = 2;
catalog8 = d23.identify_frame(up,true(size(up)),ones(10,1), ...
    1,101,8,1,ctx,cfg);
catalog8 = catalog8(catalog8.IsSS3 & ~catalog8.IsCensored,:);
catalog4 = catalog8; catalog4.Connectivity(:) = uint8(4);
catalog = [catalog8;catalog4];
comparison = d23.connectivity_comparison(catalog,ctx,cfg);
row = comparison.summary_table(comparison.summary_table.LengthThreshold == 3,:);
verifyEqual(test_case,row.Detected8,uint32(1));
verifyEqual(test_case,row.Detected4,uint32(1));
verifyEqual(test_case,row.ObjectCount8,uint32(2));
verifyEqual(test_case,row.ObjectCount4,uint32(2));
verifyEqual(test_case,comparison.frame_sign_table.ObjectCount8(1),uint32(2));

selection = d23.select_gallery(catalog8,12000,8);
verifyEqual(test_case,nnz(selection.Selected),2);
chosen = selection(selection.Selected,:);
verifyEqual(test_case,numel(unique(chosen.ComponentID)),2);
verifyEqual(test_case,numel(unique(chosen.FrameOrdinal)),1);
end

function testGalleryShortageIsExplicit(test_case)
[ctx,cfg] = synthetic_context(10,45);
up = zeros(10,45); up(1:7,2:11)=2; up(1:7,20:29)=2;
catalog = d23.identify_frame(up,true(size(up)),ones(10,1), ...
    1,1,8,1,ctx,cfg);
selection = d23.select_gallery(catalog,12000);
verifyEqual(test_case,nnz(selection.Selected),1);
verifyEqual(test_case,height(selection),30);
verifyEqual(test_case,numel(unique(selection.FrameID(selection.Selected))),1);
spectra = populated_spectra_contract();
expected = d23.optional_artifact_contract(selection,spectra);
verifyEqual(test_case,expected.selected_gallery_count,1);
verifyEqual(test_case,expected.energy_row_count,6);
verifyEqual(test_case,expected.summary_plot_count,6);
verifyEqual(test_case,expected.fig_count,12);
end

function testZeroMatchedNoSSAllowsEmptySpectralOutputs(test_case)
[ctx,cfg] = synthetic_context(10,40);
up = zeros(10,40); up(1:7,16:25) = 2;
catalog = d23.identify_frame(up,true(size(up)),ones(10,1), ...
    1,1,8,1,ctx,cfg);
target = catalog(catalog.IsSS3,:);
target.ColMin = uint16(10);
target.ColMax = uint16(30);
target.BBoxWidth_px = 21;
target.Lx_over_delta = 7;
pairs = d23.match_noss(target,ctx,cfg);
verifyFalse(test_case,pairs.Matched);
ctx.lower_spectrum_row = 1;
ctx.upper_spectrum_row = 7;
spectra = d23.conditional_spectra(pairs,ctx,struct(),cfg);
verifyEmpty(test_case,spectra.spectra_table);
verifyEmpty(test_case,spectra.energy_table);
selection = d23.select_gallery(target,12000);
expected = d23.optional_artifact_contract(selection,spectra);
verifyEqual(test_case,expected.selected_gallery_count,1);
verifyEqual(test_case,expected.energy_row_count,0);
verifyEqual(test_case,expected.summary_plot_count,4);
verifyEqual(test_case,expected.fig_count,10);
end

function testConnectivityLengthDistribution(test_case)
[ctx,cfg] = synthetic_context(10,45);
up = zeros(10,45); up(1:7,2:11)=2; up(1:7,20:31)=2;
catalog8 = d23.identify_frame(up,true(size(up)),ones(10,1), ...
    1,1,8,1,ctx,cfg);
catalog8 = catalog8(catalog8.IsSS3 & ~catalog8.IsCensored,:);
catalog4 = catalog8;
catalog4.Connectivity(:) = uint8(4);
catalog = [catalog8;catalog4];
distribution = d23.connectivity_length_distribution(catalog);
for connectivity = [8 4]
    rows = distribution.table.Connectivity == connectivity;
    verifyEqual(test_case,sum(distribution.table.Count(rows)), ...
        double(height(catalog8)));
    verifyEqual(test_case,sum(distribution.table.Probability(rows)),1, ...
        'AbsTol',1e-14);
end
verifyEqual(test_case,distribution.statistics(1).median, ...
    median(catalog8.Lx_over_delta),'AbsTol',1e-14);
end

function [ctx,cfg] = synthetic_context(ny,nx)
cfg = d23.default_config(tempdir);
ctx = struct();
ctx.cache_size = [1 ny nx];
ctx.dx_mm = 1; ctx.dy_mm = 1; ctx.delta99_mm = 3;
ctx.x_mm = 0.5 + (0:nx-1);
ctx.wall_distance_mm = repmat((0.5:1:(ny-0.5)).',1,nx);
ctx.spatial_exclusion_mask = false(ny,nx);
ctx.spatial_exclusion = struct('enabled',false, ...
    'excluded_grid_point_count',uint32(0));
ctx.u_tau_m_s = 1; ctx.nu_m2_s = 1e-3;
ctx.lower_plus_limit = 1; ctx.upper_plus_limit = 6;
end

function spectra = populated_spectra_contract()
spectra = struct('spectra_table',table(1), ...
    'energy_table',table(), ...
    'thresholds',[3;3.8;4.5], ...
    'row_ids',[1 2]);
end
