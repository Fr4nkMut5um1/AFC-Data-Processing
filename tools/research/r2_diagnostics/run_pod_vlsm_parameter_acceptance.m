function result = run_pod_vlsm_parameter_acceptance(varargin)
%RUN_POD_VLSM_PARAMETER_ACCEPTANCE Generate auditable POD VLSM acceptance data.
%
% The acceptance sample is three independent rounds of 36 random POD frames.
% Pure contourf fields are exported for blind vision review, while separate
% overlays and JSON catalogs retain the cluster result. FOV-edge structures are
% included. This tool does not modify the case configuration or other branches.

parser = inputParser;
parser.addParameter('case_name', 'tandem_baseline_r2', @(x)ischar(x)||isstring(x));
parser.addParameter('energy_target', 0.50, @(x)isscalar(x)&&x>0&&x<=1);
parser.addParameter('n_rounds', 3, @(x)isscalar(x)&&x==fix(x)&&x>=1);
parser.addParameter('n_frames_per_round', 36, @(x)isscalar(x)&&x==fix(x)&&x>=1);
parser.addParameter('random_seed', 20260828, @(x)isscalar(x));
parser.addParameter('attempt_id', 1, @(x)isscalar(x)&&x==fix(x)&&x>=1);
parser.addParameter('parameter_overrides', struct(), @isstruct);
% Use one fixed symmetric range for blind and cluster-overlay figures.  A
% per-frame robust range can clip high-amplitude POD fluctuations into white
% and makes visual comparisons across frames inconsistent.
parser.addParameter('colorbar_abs_limit', 3.0, @(x)isscalar(x)&&isfinite(x)&&x>0);
parser.addParameter('output_dir', '', @(x)ischar(x)||isstring(x));
parser.parse(varargin{:});
opt = parser.Results;

script_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(fileparts(fileparts(script_dir)));
case_root = fullfile(repo_root, 'cases', 'per_case', char(opt.case_name));
addpath(fullfile(repo_root, 'lib'));
addpath(fullfile(repo_root, 'tools', 'research'));
addpath(script_dir);

cfg = tblR2.vlsmpod.load_case_config(case_root, char(opt.case_name));
paths = tblR2.build_paths(cfg.output_dir);
stats = tblR2.load_result(paths.statistics, cfg, 'statistics');
mean_bl = tblR2.load_result(paths.mean_bl, cfg, 'mean_bl');

basis_file = fullfile(repo_root, 'tmp', 'pod_energy_sweep', ...
    'pod_energy_sweep_basis.mat');
if ~isfile(basis_file)
    error('podVlsmAcceptance:MissingBasis', 'Missing POD basis: %s', basis_file);
end
loaded = load(basis_file, 'denoise');
denoise = loaded.denoise;
cumulative = cumsum(denoise.eigenvalues) ./ sum(denoise.eigenvalues);
rank_r = find(cumulative >= opt.energy_target, 1, 'first');
if isempty(rank_r); rank_r = numel(cumulative); end
rank_r = min(rank_r, denoise.rank);

if isempty(opt.output_dir)
    out_root = fullfile(repo_root, 'tmp', ...
        'pod_vlsm_parameter_acceptance_36x3');
else
    out_root = char(opt.output_dir);
end
attempt_dir = fullfile(out_root, sprintf('attempt_%02d', opt.attempt_id));
if ~isfolder(attempt_dir); mkdir(attempt_dir); end

settings = acceptance_settings(cfg.structures, opt.parameter_overrides);
resolved = tblR2.vlsmpod.resolve_settings(settings, struct());
ctx = tblR2.vlsmpod.prepare_context(cfg, stats, mean_bl, resolved);
ctx.analysis_domain_mask = ctx.valid_mask;
source = struct('preprocessing', 'pod_denoise', 'denoise', denoise, ...
    'mode_indices', 1:rank_r);

fov = fov_metadata(ctx);
delta_samples = sample_delta99(ctx, fov, 7);
all_frame_ids = double(denoise.frame_ids(:));
round_records = repmat(empty_round_record(), opt.n_rounds, 1);

for rr = 1:opt.n_rounds
    round_seed = double(opt.random_seed) + 1000 * (opt.attempt_id - 1) + rr - 1;
    rng(round_seed, 'twister');
    n_pick = min(opt.n_frames_per_round, numel(all_frame_ids));
    frame_ids = sort(all_frame_ids(randperm(numel(all_frame_ids), n_pick)));

    round_dir = fullfile(attempt_dir, sprintf('round_%02d', rr));
    pure_dir = fullfile(round_dir, 'pure_frames');
    overlay_dir = fullfile(round_dir, 'cluster_frames');
    if ~isfolder(pure_dir); mkdir(pure_dir); end
    if ~isfolder(overlay_dir); mkdir(overlay_dir); end

    frame_records = repmat(empty_frame_record(), n_pick, 1);
    catalogs = cell(n_pick, 1);
    for k = 1:n_pick
        frame_id = frame_ids(k);
        field = tblR2.vlsmpod.frame_field(ctx, frame_id, source);
        identified = tblR2.vlsmpod.identify_frame(ctx, field, resolved);
        T = identified.structures;
        catalogs{k} = annotate_frame(T, frame_id);
        cluster_objects = extract_vlsm_objects(T, fov, ctx);

        % Keep pure and overlay figures on the same fixed +/- limit so that
        % out-of-range values are represented by saturated end colors rather
        % than being mistaken for missing/white data.
        clim_val = double(opt.colorbar_abs_limit);
        pure_file = fullfile(pure_dir, sprintf('frame_%06d.png', frame_id));
        overlay_file = fullfile(overlay_dir, sprintf('frame_%06d.png', frame_id));
        export_pure_field(pure_file, ctx, field.u_fluct, clim_val, ...
            frame_id, opt.energy_target);
        export_cluster_overlay(overlay_file, ctx, field.u_fluct, T, ...
            clim_val, frame_id, opt.energy_target);

        frame_records(k) = struct( ...
            'frame_id', frame_id, ...
            'pure_image', pure_file, ...
            'cluster_image', overlay_file, ...
            'clim_abs_m_per_s', clim_val, ...
            'all_structure_count', height(T), ...
            'lsm_count', sum(T.IsLSM), ...
            'vlsm_count', sum(T.IsVLSM), ...
            'cluster_objects', cluster_objects);
    end

    cluster_file = fullfile(round_dir, sprintf( ...
        'round_%02d_cluster_objects.json', rr));
    visual_context_file = fullfile(round_dir, sprintf( ...
        'round_%02d_visual_context.json', rr));
    write_json(cluster_file, struct('round', rr, 'seed', round_seed, ...
        'frame_ids', frame_ids(:).', 'fov', fov, ...
        'delta99_samples', delta_samples, 'frames', frame_records));
    write_json(visual_context_file, struct('round', rr, ...
        'frame_ids', frame_ids(:).', 'fov', fov, ...
        'delta99_samples', delta_samples, ...
        'colorbar_abs_limit_m_per_s', double(opt.colorbar_abs_limit), ...
        'pure_images', {reshape({frame_records.pure_image}, 1, [])}));
    save(fullfile(round_dir, sprintf('round_%02d_generation.mat', rr)), ...
        'rr', 'round_seed', 'frame_ids', 'settings', 'resolved', ...
        'rank_r', 'cumulative', 'catalogs', 'frame_records', 'fov', ...
        'delta_samples');

    round_records(rr) = struct('round', rr, 'seed', round_seed, ...
        'frame_ids', frame_ids(:).', 'round_dir', round_dir, ...
        'cluster_objects_file', cluster_file, ...
        'visual_context_file', visual_context_file, ...
        'visual_review_file', fullfile(round_dir, sprintf( ...
        'round_%02d_visual_review.json', rr)), ...
        'n_frames', n_pick, ...
        'total_cluster_vlsm', sum([frame_records.vlsm_count]), ...
        'frames_with_cluster_vlsm', nnz([frame_records.vlsm_count] > 0));
    fprintf('Acceptance attempt %02d round %02d: %d frames, %d cluster VLSM\n', ...
        opt.attempt_id, rr, n_pick, round_records(rr).total_cluster_vlsm);
end

manifest = struct( ...
    'schema_version', 2, ...
    'status', 'awaiting_gpt_5_6_sol_visual_review', ...
    'case_name', char(opt.case_name), ...
    'attempt_id', opt.attempt_id, ...
    'energy_target', opt.energy_target, ...
    'pod_rank', rank_r, ...
    'cumulative_energy', cumulative(rank_r), ...
    'random_seed', opt.random_seed, ...
    'n_rounds', opt.n_rounds, ...
    'n_frames_per_round', opt.n_frames_per_round, ...
    'colorbar_abs_limit_m_per_s', double(opt.colorbar_abs_limit), ...
    'parameters', public_parameters(settings), ...
    'edge_policy', 'include_fov_edges_for_pod', ...
    'fov', fov, ...
    'delta99_samples', delta_samples, ...
    'rounds', round_records, ...
    'vision_model_required', 'gpt-5.6-sol', ...
    'interpretation_limit', ...
    ['Operational comparison of connected structures in a 2C-2D XOY ' ...
     'POD reconstruction; neither GPT vision nor clustering is 3-D truth.']);
manifest_file = fullfile(attempt_dir, 'manifest.json');
write_json(manifest_file, manifest);

result = struct('manifest', manifest, 'manifest_file', manifest_file, ...
    'attempt_dir', attempt_dir, 'rounds', round_records);
save(fullfile(attempt_dir, 'acceptance_generation.mat'), 'result', '-v7.3');
end

function settings = acceptance_settings(base, overrides)
settings = base;
settings.alpha = 0.40;
settings.seed_alpha = 0.60;
settings.connectivity = 8;
% Pin every value from the accepted optimization candidate. In particular,
% do not inherit stale cfg.structures values for min_abs_fluctuation or
% merge_gap_cells: the case cache may contain 1 and 40 from another branch.
settings.min_pixels = 3;
settings.min_lsm_delta = 1.0;
settings.min_vlsm_delta = 3.0;
settings.max_wall_normal_delta = Inf;
settings.max_internal_hole_pixels = 64;
settings.envelope_closing_radius_cells = 2;
settings.max_aspect_ratio = Inf;
settings.reject_trusted_boundary_touching = false;
settings.min_abs_fluctuation = 0;
settings.min_abs_seed_fluctuation = 0;
settings.merge_gap_cells = 0;
settings.merge_require_y_overlap = true;
names = fieldnames(overrides);
for i = 1:numel(names)
    if ~isfield(settings, names{i})
        error('podVlsmAcceptance:UnknownOverride', ...
            'Unknown structure setting override: %s', names{i});
    end
    settings.(names{i}) = overrides.(names{i});
end
settings.trusted_domain = struct('streamwise_edge_columns', 0, ...
    'wall_normal_top_rows', 0);
settings.reject_trusted_boundary_touching = false;
end

function out = public_parameters(s)
names = {'alpha','seed_alpha','connectivity','min_pixels','min_lsm_delta', ...
    'min_vlsm_delta','max_internal_hole_pixels', ...
    'envelope_closing_radius_cells','min_abs_fluctuation', ...
    'min_abs_seed_fluctuation','merge_gap_cells','merge_require_y_overlap', ...
    'reject_trusted_boundary_touching'};
out = struct();
for i = 1:numel(names); out.(names{i}) = s.(names{i}); end
out.trusted_domain = s.trusted_domain;
end

function fov = fov_metadata(ctx)
valid = ctx.valid_mask & isfinite(ctx.X_mm) & isfinite(ctx.Y_wall_mm);
x = double(ctx.X_mm(valid));
y = double(ctx.Y_wall_mm(valid));
fov = struct('x_min_mm', min(x), 'x_max_mm', max(x), ...
    'y_min_mm', min(y), 'y_max_mm', max(y), ...
    'width_mm', max(x)-min(x), 'height_mm', max(y)-min(y));
end

function samples = sample_delta99(ctx, fov, n)
anchors = linspace(fov.x_min_mm, fov.x_max_mm, n);
samples = repmat(struct('x_mm', NaN, 'delta99_mm', NaN, ...
    'three_delta99_mm', NaN), n, 1);
dx = max(abs(double(ctx.dx_mm)), eps);
for i = 1:n
    mask = ctx.valid_mask & isfinite(ctx.delta_grid) & ...
        abs(double(ctx.X_mm) - anchors(i)) <= 0.75 * dx;
    vals = double(ctx.delta_grid(mask));
    if isempty(vals)
        [~, linear_idx] = min(abs(double(ctx.X_mm(ctx.valid_mask)) - anchors(i)));
        all_delta = double(ctx.delta_grid(ctx.valid_mask));
        vals = all_delta(linear_idx);
    end
    d = median(vals, 'omitnan');
    samples(i) = struct('x_mm', anchors(i), 'delta99_mm', d, ...
        'three_delta99_mm', 3*d);
end
end

function objects = extract_vlsm_objects(T, fov, ctx)
template = struct('cluster_id', NaN, 'sign', '', ...
    'x_min_mm', NaN, 'x_max_mm', NaN, 'y_min_mm', NaN, 'y_max_mm', NaN, ...
    'centroid_x_mm', NaN, 'centroid_y_mm', NaN, ...
    'length_x_mm', NaN, 'length_over_delta', NaN, ...
    'delta99_ref_mm', NaN, 'pixel_count', NaN, ...
    'touches_fov_edge', false, ...
    'edge_sides', struct('left',false,'right',false,'bottom',false,'top',false));
idx = find(T.IsVLSM);
objects = repmat(template, numel(idx), 1);
tol_x = 0.55 * max(abs(double(ctx.dx_mm)), eps);
tol_y = 0.55 * max(abs(double(ctx.dy_mm)), eps);
for k = 1:numel(idx)
    i = idx(k);
    sides = struct( ...
        'left', T.XMin_mm(i) <= fov.x_min_mm + tol_x, ...
        'right', T.XMax_mm(i) >= fov.x_max_mm - tol_x, ...
        'bottom', T.YMin_mm(i) <= fov.y_min_mm + tol_y, ...
        'top', T.YMax_mm(i) >= fov.y_max_mm - tol_y);
    sign_name = 'positive';
    if T.Sign(i) < 0; sign_name = 'negative'; end
    objects(k) = struct( ...
        'cluster_id', double(T.StructureID(i)), ...
        'sign', sign_name, ...
        'x_min_mm', double(T.XMin_mm(i)), ...
        'x_max_mm', double(T.XMax_mm(i)), ...
        'y_min_mm', double(T.YMin_mm(i)), ...
        'y_max_mm', double(T.YMax_mm(i)), ...
        'centroid_x_mm', double(T.CentroidX_mm(i)), ...
        'centroid_y_mm', double(T.CentroidY_mm(i)), ...
        'length_x_mm', double(T.LengthX_mm(i)), ...
        'length_over_delta', double(T.LengthX_over_delta(i)), ...
        'delta99_ref_mm', double(T.Delta99Ref_mm(i)), ...
        'pixel_count', double(T.PixelCount(i)), ...
        'touches_fov_edge', any(cell2mat(struct2cell(sides))), ...
        'edge_sides', sides);
end
end

function export_pure_field(file, ctx, values, clim_val, frame_id, energy_target)
fig = figure('Visible','off','Color','w','Units','centimeters', ...
    'Position',[1 1 24 6.8]);
ax = axes(fig);
levels = contour_levels_with_overflow(values, clim_val, 25);
contourf(ax, ctx.X_mm, ctx.Y_wall_mm, values, levels, 'LineStyle','none');
colormap(ax, blue_white_red(256));
caxis(ax, [-clim_val clim_val]);
axis(ax, 'tight');
set(ax, 'YDir','normal','FontSize',8,'TickDir','out','Layer','top');
xlabel(ax, 'x (mm)'); ylabel(ax, 'y_{wall} (mm)');
cb = colorbar(ax); ylabel(cb, "u' (m/s)");
title(ax, sprintf('POD E=%.0f%% | frame %d | blind visual review field', ...
    100*energy_target, frame_id), 'FontSize',9,'FontWeight','normal');
exportgraphics(fig, file, 'Resolution', 180);
close(fig);
end

function export_cluster_overlay(file, ctx, values, T, clim_val, frame_id, energy_target)
fig = figure('Visible','off','Color','w','Units','centimeters', ...
    'Position',[1 1 24 6.8]);
ax = axes(fig);
opts = struct('levels',contour_levels_with_overflow(values, clim_val, 25), ...
    'clim_val',clim_val,'show_xlabel',true);
info = plot_structure_field(ax, ctx, values, T, opts);
draw_vlsm_ids(ax, T);
title(ax, sprintf(['POD E=%.0f%% | frame %d | cluster: all=%d, ' ...
    'LSM=%d, VLSM=%d'], 100*energy_target, frame_id, height(T), ...
    info.n_lsm, info.n_vlsm), 'FontSize',9,'FontWeight','normal');
exportgraphics(fig, file, 'Resolution', 180);
close(fig);
end

function levels = contour_levels_with_overflow(values, clim_val, n_levels)
%CONTOUR_LEVELS_WITH_OVERFLOW Keep out-of-range data visible at saturated ends.
% contourf leaves values outside its outermost level unfilled.  Add the actual
% finite extrema as outer levels, while caxis remains fixed at +/-clim_val.
levels = linspace(-double(clim_val), double(clim_val), n_levels);
finite = double(values(isfinite(values)));
if ~isempty(finite)
    vmin = min(finite);
    vmax = max(finite);
    if vmin < levels(1); levels = [vmin levels]; end
    if vmax > levels(end); levels = [levels vmax]; end
end
levels = unique(levels, 'sorted');
if numel(levels) < 2
    levels = [-double(clim_val) double(clim_val)];
end
end

function draw_vlsm_ids(ax, T)
idx = find(T.IsVLSM);
for k = 1:numel(idx)
    i = idx(k);
    if T.Sign(i) > 0; prefix = '+'; else; prefix = '-'; end
    text(ax, T.XMin_mm(i), T.YMax_mm(i), ...
        sprintf('%sC%d', prefix, T.StructureID(i)), ...
        'Color','k','BackgroundColor','w','Margin',1, ...
        'FontSize',7,'FontWeight','bold','VerticalAlignment','bottom', ...
        'Clipping','on');
end
end

function T = annotate_frame(T, frame_id)
if isempty(T); return; end
T = addvars(T, repmat(frame_id,height(T),1), 'Before',1, ...
    'NewVariableNames','FrameID');
end

function r = empty_round_record()
r = struct('round',NaN,'seed',NaN,'frame_ids',[], ...
    'round_dir','','cluster_objects_file','','visual_context_file','', ...
    'visual_review_file','','n_frames',0,'total_cluster_vlsm',0, ...
    'frames_with_cluster_vlsm',0);
end

function r = empty_frame_record()
r = struct('frame_id',NaN,'pure_image','','cluster_image','', ...
    'clim_abs_m_per_s',NaN,'all_structure_count',0,'lsm_count',0, ...
    'vlsm_count',0,'cluster_objects',struct([]));
end

function write_json(file, value)
fid = fopen(file, 'w', 'n', 'UTF-8');
if fid < 0; error('podVlsmAcceptance:WriteJSON', 'Cannot write %s', file); end
cleanup = onCleanup(@()fclose(fid));
fwrite(fid, jsonencode(value, 'PrettyPrint', true), 'char');
end

function cmap = blue_white_red(n)
half = floor(n/2);
blue = [linspace(0,1,half)',linspace(0,1,half)',ones(half,1)];
red = [ones(half,1),linspace(1,0,half)',linspace(1,0,half)'];
if mod(n,2); cmap = [blue; 1 1 1; red]; else; cmap = [blue; red]; end
end
