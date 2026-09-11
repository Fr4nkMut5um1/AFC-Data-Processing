% Research utility with historical cache/parameter assumptions; see tools/README.md.
% Not a daily entry or formal Section 4 acceptance test. Runtime not revalidated.
function iterate_frame_calibration(frame_id, alpha, seed_alpha, min_abs, merge_gap, tag)
%ITERATE_FRAME_CALIBRATION 单帧标定迭代：输出干净 turbo 场图 + 带框对比图
%   iterate_frame_calibration(frame_id, alpha, seed_alpha, min_abs, merge_gap, tag)

if nargin < 2, alpha = 1.0; end
if nargin < 3, seed_alpha = 1.2; end
if nargin < 4, min_abs = 1.0; end
if nargin < 5, merge_gap = 40; end
if nargin < 6, tag = 'v1'; end

base_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(base_dir, 'lib'));
mat_dir = fullfile(base_dir, 'cases/per_case/tandem_baseline_r2/output/mat');
out_dir = fullfile(base_dir, 'cases/per_case/tandem_baseline_r2/output/research/calibration_loop');
if ~isfolder(out_dir), mkdir(out_dir); end

S = load(fullfile(mat_dir, '02_statistics.mat'), 'data'); stats = S.data;
B = load(fullfile(mat_dir, '02_mean_boundary_layer_friction.mat'), 'data'); mean_bl = B.data;
cache_file = fullfile(mat_dir, '01_sequence_cache_postproc.mat');

J = size(stats.X,1); I = size(stats.X,2);
Y_wall_mm = mean_bl.wall_distance_mm;
delta_grid = interp1(mean_bl.boundary_layer.x, mean_bl.boundary_layer.delta99, stats.X, 'linear', NaN);
valid_mask = stats.accepted_mask & isfinite(delta_grid) & delta_grid > 0;

preprocess_spec = struct('name','G','enabled',true,'edge_buffer_cells',[0 0], ...
    'outlier', struct('enabled',false,'radius_cells',1,'threshold',2, ...
        'residual_epsilon',0.1,'min_neighbors',5), ...
    'gaussian', struct('enabled',true,'sigma_cells',1.5,'radius_cells',4, ...
        'sigma_x_cells',1.5,'sigma_y_cells',1.5,'radius_x_cells',4,'radius_y_cells',4, ...
        'kernel_type','gaussian','kernel_normalization','sum1','boundary_mode','legacy_zero', ...
        'mask_aware',false,'min_support_fraction',0.5,'apply_to',{{'u','v'}}, ...
        'apply_stage','instantaneous_before_mean_subtraction'));

td = struct('streamwise_edge_columns',16,'wall_normal_top_rows',2);
analysis_domain_mask = tblR2.trusted_domain_mask(valid_mask, Y_wall_mm, td);

raw_batch = tblR2.read_cache_chunk(cache_file, frame_id, 1:J, 1:I, 'raw', stats, []);
raw_U = squeeze(raw_batch.U(1,:,:)); raw_V = squeeze(raw_batch.V(1,:,:));
raw_valid = valid_mask & squeeze(raw_batch.sampleValid(1,:,:));
prep = tblR2.preprocess_structure_velocity(raw_U, raw_V, raw_valid, analysis_domain_mask, preprocess_spec);
rep = 1 + nnz(frame_id > stats.repeat_boundaries(:)');
mean_U = squeeze(stats.repeat_means(1,rep,:,:));
structure_mask = prep.output_valid_mask & isfinite(mean_U);
u_f = prep.U - mean_U; u_f(~structure_mask) = NaN;

opts = struct('alpha',alpha,'seed_alpha',seed_alpha,'min_pixels',3,'connectivity',4, ...
    'min_lsm_delta',1.0,'min_vlsm_delta',3.0,'max_wall_normal_delta',Inf, ...
    'max_internal_hole_pixels',64,'envelope_closing_radius_cells',2, ...
    'max_aspect_ratio',Inf,'reject_trusted_boundary_touching',true, ...
    'sign_mode','both','min_abs_fluctuation',min_abs,'min_abs_seed_fluctuation',min_abs);

id = tblR2.identify_structures(u_f, stats.u_rms, stats.X, Y_wall_mm, delta_grid, structure_mask, opts);
dx = median(abs(diff(stats.X(1,:))),'omitnan');
dy = median(abs(diff(Y_wall_mm(:,1))),'omitnan');
m_opts = struct('merge_gap_cells',merge_gap,'merge_require_y_overlap',true, ...
    'min_lsm_delta',1.0,'min_vlsm_delta',3.0);
[tbl, mlog] = tblR2.vlsm.merge_streamwise_neighbors(id.structures, ...
    id.positive_labels, id.negative_labels, stats.X, Y_wall_mm, delta_grid, ...
    dx, dy, u_f, m_opts);

%% 图1: 干净 turbo 场（供识图）
f1 = figure('Position',[50 50 1500 520],'Color','w','Visible','off');
pcolor(stats.X, Y_wall_mm, u_f); shading flat;
colormap(turbo(256)); caxis([-3 3]);
cb = colorbar; cb.Label.String = "u' (m/s)";
xlabel('x (mm)'); ylabel('y (mm)');
title(sprintf('Frame %d — fluctuation field (turbo, no annotation)', frame_id));
set(gca,'FontSize',11);
p1 = fullfile(out_dir, sprintf('f%05d_%s_clean.png', frame_id, tag));
exportgraphics(f1, p1, 'Resolution', 170); close(f1);

%% 图2: 带检测框
f2 = figure('Position',[50 50 1500 520],'Color','w','Visible','off');
pcolor(stats.X, Y_wall_mm, u_f); shading flat;
colormap(turbo(256)); caxis([-3 3]);
cb = colorbar; cb.Label.String = "u' (m/s)";
hold on;
for is = 1:height(tbl)
    r = tbl(is,:);
    if r.IsVLSM, lw=3.0; ls='-';
    elseif r.IsLSM, lw=1.8; ls='--';
    else, continue; end
    if r.Sign > 0, clr=[1 1 1]; else, clr=[0 0 0]; end
    plot([r.XMin_mm r.XMax_mm r.XMax_mm r.XMin_mm r.XMin_mm], ...
         [r.YMin_mm r.YMin_mm r.YMax_mm r.YMax_mm r.YMin_mm], ...
         'Color',clr,'LineWidth',lw,'LineStyle',ls);
    if r.IsVLSM
        text(r.XMin_mm+2, r.YMax_mm-2, sprintf('%.1f\\delta', r.LengthX_over_delta), ...
            'Color',clr,'FontSize',10,'FontWeight','bold');
    end
end
xlabel('x (mm)'); ylabel('y (mm)');
title(sprintf('Frame %d — \\alpha=%.2f seed=%.2f minabs=%.2f gap=%d | struct=%d LSM=%d VLSM=%d', ...
    frame_id, alpha, seed_alpha, min_abs, merge_gap, height(tbl), sum(tbl.IsLSM), sum(tbl.IsVLSM)));
set(gca,'FontSize',11);
p2 = fullfile(out_dir, sprintf('f%05d_%s_boxed.png', frame_id, tag));
exportgraphics(f2, p2, 'Resolution', 170); close(f2);

%% 文本报告
fprintf('\n===== Frame %d | %s =====\n', frame_id, tag);
fprintf('params: alpha=%.2f seed=%.2f min_abs=%.2f merge_gap=%d\n', alpha, seed_alpha, min_abs, merge_gap);
fprintf('total=%d LSM=%d VLSM=%d merges=%d rejected_boundary=%d\n', ...
    height(tbl), sum(tbl.IsLSM), sum(tbl.IsVLSM), mlog.n_merges, id.rejected_trusted_boundary_count);
fprintf('occupancy: pos=%.1f%% neg=%.1f%%\n', ...
    100*nnz(id.growth_positive_mask)/nnz(structure_mask), ...
    100*nnz(id.growth_negative_mask)/nnz(structure_mask));
big = tbl(tbl.IsLSM, :);
if height(big) > 0
    fprintf('--- LSM/VLSM list ---\n');
    [~,ord] = sort(big.LengthX_over_delta,'descend');
    big = big(ord,:);
    for i = 1:height(big)
        fprintf('  %s Lx=%6.1fmm Lx/d=%.2f x=[%5.1f,%5.1f] y=[%4.1f,%4.1f] %s\n', ...
            ternary_str(big.Sign(i)>0,'HIGH','LOW '), big.LengthX_mm(i), ...
            big.LengthX_over_delta(i), big.XMin_mm(i), big.XMax_mm(i), ...
            big.YMin_mm(i), big.YMax_mm(i), ternary_str(big.IsVLSM(i),'<VLSM>',''));
    end
end
fprintf('figs: %s\n      %s\n', p1, p2);
end

function s = ternary_str(c,a,b)
if c, s=a; else, s=b; end
end
