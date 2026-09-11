function result = build_section4_spatial_exclusion_comparison(workspace_root)
%BUILD_SECTION4_SPATIAL_EXCLUSION_COMPARISON Audit the f40A3 Section-4 mask.
% The diagnostic is read-only with respect to PostProc and Section-4 runs.
% It compares the baseline, unmasked f40A3, and masked f40A3 POD spectra,
% then computes the exact 40 Hz harmonic energy from the f40A3 PostProc
% fluctuations over the same 100%-valid spatial DOFs used by POD.

if nargin < 1 || isempty(workspace_root)
    here = fileparts(mfilename('fullpath'));
    workspace_root = fileparts(fileparts(fileparts(here)));
end
workspace_root = char(workspace_root);

addpath(fullfile(workspace_root, 'lib'), '-begin');

baseline_root = fullfile(workspace_root, 'cases', 'per_case', ...
    'tandem_baseline_r2');
f40_root = fullfile(workspace_root, 'cases', 'per_case', ...
    'tandem_f40a3_phi0_r2');
f40_section4_root = fullfile(f40_root, 'output', 'section4_vlsm');

baseline_summary_file = fullfile(baseline_root, 'output', ...
    'section4_vlsm', 'summary.json');
baseline_result_file = fullfile(baseline_root, 'output', 'mat', ...
    '09_structure_analysis.mat');
[unmasked_run, masked_run] = find_full_f40_runs(f40_section4_root);

baseline_summary = read_json(baseline_summary_file);
unmasked_summary = read_json(fullfile(unmasked_run, 'json', 'summary.json'));
masked_summary = read_json(fullfile(masked_run, 'json', 'summary.json'));

B = load(baseline_result_file, 'data');
baseline_pod = B.data.pod_metadata;
U = load(fullfile(unmasked_run, 'pod', 'pod_metadata.mat'), 'pod_meta');
M = load(fullfile(masked_run, 'pod', 'pod_metadata.mat'), 'pod_meta');
unmasked_pod = U.pod_meta;
masked_pod = M.pod_meta;

[~, masked_name] = fileparts(masked_run);
output_root = fullfile(f40_section4_root, 'comparisons', ...
    [masked_name '_vs_unmasked']);
if ~isfolder(output_root), mkdir(output_root); end

case_table = build_case_table(baseline_summary, unmasked_summary, ...
    masked_summary, baseline_pod, unmasked_pod, masked_pod);
case_csv = fullfile(output_root, 'case_comparison.csv');
d23.atomic_writetable(case_csv, case_table);

[curve_table, curve_series] = build_cumulative_curves( ...
    baseline_pod, unmasked_pod, masked_pod);
curve_csv = fullfile(output_root, 'pod_cumulative_energy.csv');
d23.atomic_writetable(curve_csv, curve_table);
[curve_png, curve_fig] = plot_cumulative_curves(output_root, curve_series, ...
    baseline_pod, unmasked_pod, masked_pod);

masked_final = fullfile(masked_run, 'mat', 'final_results.mat');
F = load(masked_final, 'context', 'statistics');
[frequency_table, frequency_map, frequency_meta] = ...
    exact_frequency_diagnostic(F.context, F.statistics, unmasked_pod, ...
    masked_pod, 40, 960, 48);
frequency_csv = fullfile(output_root, 'exact_40hz_energy.csv');
d23.atomic_writetable(frequency_csv, frequency_table);
[frequency_png, frequency_fig] = plot_frequency_comparison( ...
    output_root, frequency_table);
[map_png, map_fig] = plot_frequency_map(output_root, frequency_map, ...
    F.context);
map_mat = fullfile(output_root, 'exact_40hz_energy_map.mat');
atomic_save(map_mat, struct('frequency_map', frequency_map, ...
    'frequency_meta', frequency_meta));

figure_manifest_file = fullfile(f40_section4_root, 'figure_manifest.csv');
figure_audit = audit_section4_figures(figure_manifest_file, ...
    fullfile(f40_section4_root, 'figures'));

result = struct();
result.schema_version = 1;
result.created_utc = utc_now();
result.baseline_summary_file = baseline_summary_file;
result.baseline_result_file = baseline_result_file;
result.f40_unmasked_run = unmasked_run;
result.f40_masked_run = masked_run;
result.output_root = output_root;
result.case_comparison = case_table;
result.cumulative_energy = curve_table;
result.exact_40hz = frequency_table;
result.exact_40hz_metadata = frequency_meta;
result.figure_audit = figure_audit;

result_mat = fullfile(output_root, 'comparison_results.mat');
atomic_save(result_mat, struct('result', result));

json_payload = struct();
json_payload.schema_version = result.schema_version;
json_payload.created_utc = result.created_utc;
json_payload.paths = struct('baseline_summary', baseline_summary_file, ...
    'baseline_result', baseline_result_file, ...
    'f40_unmasked_run', unmasked_run, 'f40_masked_run', masked_run, ...
    'output_root', output_root);
json_payload.case_comparison = table2struct(case_table);
json_payload.exact_40hz = table2struct(frequency_table);
json_payload.exact_40hz_metadata = frequency_meta;
json_payload.figure_audit = figure_audit;
json_file = fullfile(output_root, 'comparison_summary.json');
d23.atomic_write_text(json_file, jsonencode(json_payload, 'PrettyPrint', true));

report_file = fullfile(output_root, 'comparison_report.md');
d23.atomic_write_text(report_file, build_report(result));

artifacts = string({case_csv; curve_csv; frequency_csv; curve_png; ...
    curve_fig; frequency_png; frequency_fig; map_png; map_fig; map_mat; ...
    result_mat; json_file; report_file});
artifact_manifest = build_artifact_manifest(artifacts);
artifact_manifest_file = fullfile(output_root, 'artifact_manifest.csv');
d23.atomic_writetable(artifact_manifest_file, artifact_manifest);
result.artifact_manifest = artifact_manifest;

fprintf('[section4 comparison] output: %s\n', output_root);
fprintf('[section4 comparison] exact 40 Hz removed: %.3f%% joint harmonic energy\n', ...
    100 * (1 - frequency_table.FractionOfUnmaskedExact40Hz(2)));
end

function [unmasked_run, masked_run] = find_full_f40_runs(section4_root)
items = dir(fullfile(section4_root, 'runs', '*'));
best_unmasked = -Inf;
best_masked = -Inf;
unmasked_run = '';
masked_run = '';
for i = 1:numel(items)
    if ~items(i).isdir || startsWith(items(i).name, '.'), continue; end
    run_dir = fullfile(items(i).folder, items(i).name);
    summary_file = fullfile(run_dir, 'json', 'summary.json');
    manifest_file = fullfile(run_dir, 'manifest.mat');
    if ~isfile(summary_file) || ~isfile(manifest_file), continue; end
    try
        payload = read_json(summary_file);
        state = load(manifest_file, 'manifest');
        if ~strcmp(state.manifest.state, 'COMPLETE') || ...
                payload.frames.detected_frames ~= 12000
            continue;
        end
        enabled = isfield(payload, 'spatial_exclusion') && ...
            logical(payload.spatial_exclusion.enabled);
        if enabled && items(i).datenum > best_masked
            best_masked = items(i).datenum;
            masked_run = run_dir;
        elseif ~enabled && items(i).datenum > best_unmasked
            best_unmasked = items(i).datenum;
            unmasked_run = run_dir;
        end
    catch
        continue;
    end
end
assert(~isempty(unmasked_run), 'No COMPLETE 12000-frame unmasked f40A3 run found.');
assert(~isempty(masked_run), 'No COMPLETE 12000-frame masked f40A3 run found.');
end

function payload = read_json(filename)
payload = jsondecode(fileread(filename));
end

function T = build_case_table(B, U, M, BP, UP, MP)
labels = ["baseline"; "f40A3_unmasked"; "f40A3_masked"];
summaries = {B; U; M};
pods = {BP; UP; MP};
n = numel(labels);
enabled = false(n,1);
rank = zeros(n,1);
positive_rank = zeros(n,1);
e50 = zeros(n,1);
retained = zeros(n,1);
joint_dof = zeros(n,1);
rms_min = zeros(n,1);
rms_median = zeros(n,1);
rms_max = zeros(n,1);
c8 = zeros(n,3);
c4 = zeros(n,3);
touch8 = nan(n,3);
touch4 = nan(n,3);
thresholds = [3 3.8 4.5];
for i = 1:n
    S = summaries{i};
    P = pods{i};
    enabled(i) = isfield(S, 'spatial_exclusion') && ...
        logical(S.spatial_exclusion.enabled);
    rank(i) = double(P.selected_rank);
    positive_rank(i) = double(P.positive_rank);
    retained(i) = double(P.retained_spatial_count);
    joint_dof(i) = double(P.joint_dof_count);
    ev = double(P.eigenvalues(:));
    positive = ev > double(P.lambda_tolerance);
    e50(i) = sum(ev(1:rank(i))) / sum(ev(positive));
    rms_min(i) = double(S.detection_statistics.rms_ratio_min);
    rms_median(i) = double(S.detection_statistics.rms_ratio_median);
    rms_max(i) = double(S.detection_statistics.rms_ratio_max);
    for j = 1:3
        [c8(i,j), touch8(i,j)] = count_value(S, 8, thresholds(j));
        [c4(i,j), touch4(i,j)] = count_value(S, 4, thresholds(j));
    end
end
T = table(labels, enabled, rank, positive_rank, e50, retained, joint_dof, ...
    rms_min, rms_median, rms_max, c8(:,1), c8(:,2), c8(:,3), ...
    c4(:,1), c4(:,2), c4(:,3), touch8(:,1), touch8(:,2), ...
    touch8(:,3), touch4(:,1), touch4(:,2), touch4(:,3), ...
    'VariableNames', {'Dataset','SpatialExclusionEnabled','PODRank', ...
    'PositiveRank','E50Achieved','RetainedSpatialPoints','JointDOF', ...
    'RMSRatioMin','RMSRatioMedian','RMSRatioMax', ...
    'Complete8_L3','Complete8_L3p8','Complete8_L4p5', ...
    'Complete4_L3','Complete4_L3p8','Complete4_L4p5', ...
    'Touch8_L3','Touch8_L3p8','Touch8_L4p5', ...
    'Touch4_L3','Touch4_L3p8','Touch4_L4p5'});
end

function [count, touching] = count_value(S, connectivity, threshold)
items = S.counts;
idx = find([items.connectivity] == connectivity & ...
    abs([items.length_threshold] - threshold) < 1e-12, 1);
assert(~isempty(idx), 'Missing count row for connectivity %d, threshold %.1f.', ...
    connectivity, threshold);
count = double(items(idx).complete_ss);
if isfield(items, 'touching_user_exclusion_complete')
    touching = double(items(idx).touching_user_exclusion_complete);
else
    touching = NaN;
end
end

function [T, series] = build_cumulative_curves(B, U, M)
series = struct();
series.baseline = cumulative(B);
series.f40_unmasked = cumulative(U);
series.f40_masked = cumulative(M);
n = max([numel(series.baseline), numel(series.f40_unmasked), ...
    numel(series.f40_masked)]);
mode = (1:n).';
baseline = pad_curve(series.baseline, n);
f40_unmasked = pad_curve(series.f40_unmasked, n);
f40_masked = pad_curve(series.f40_masked, n);
T = table(mode, baseline, f40_unmasked, f40_masked, ...
    'VariableNames', {'Mode','BaselineCumulativeEnergy', ...
    'F40UnmaskedCumulativeEnergy','F40MaskedCumulativeEnergy'});
end

function c = cumulative(P)
ev = double(P.eigenvalues(:));
ev = ev(ev > double(P.lambda_tolerance));
c = cumsum(ev) ./ sum(ev);
end

function out = pad_curve(in, n)
out = nan(n,1);
out(1:numel(in)) = in;
end

function [png_file, fig_file] = plot_cumulative_curves(root, S, B, U, M)
png_file = fullfile(root, 'pod_cumulative_energy.png');
fig_file = fullfile(root, 'pod_cumulative_energy.fig');
f = figure('Visible','off','Color','w','Position',[80 80 1050 650]);
ax = axes(f); hold(ax,'on');
semilogx(ax, 1:numel(S.baseline), S.baseline, 'k-', 'LineWidth',1.8);
semilogx(ax, 1:numel(S.f40_unmasked), S.f40_unmasked, '-', ...
    'Color',[0.80 0.20 0.16], 'LineWidth',1.8);
semilogx(ax, 1:numel(S.f40_masked), S.f40_masked, '-', ...
    'Color',[0.10 0.42 0.75], 'LineWidth',1.8);
yline(ax,0.5,'--','50%','Color',[0.35 0.35 0.35]);
plot(ax,B.selected_rank,S.baseline(B.selected_rank),'ko','MarkerFaceColor','k');
plot(ax,U.selected_rank,S.f40_unmasked(U.selected_rank),'o', ...
    'Color',[0.80 0.20 0.16],'MarkerFaceColor',[0.80 0.20 0.16]);
plot(ax,M.selected_rank,S.f40_masked(M.selected_rank),'o', ...
    'Color',[0.10 0.42 0.75],'MarkerFaceColor',[0.10 0.42 0.75]);
grid(ax,'on'); box(ax,'on'); ylim(ax,[0 1]);
xlabel(ax,'POD mode count'); ylabel(ax,'Cumulative joint u-v energy fraction');
title(ax,'Section 4 POD cumulative energy');
legend(ax, {sprintf('baseline (E50 rank %d)',B.selected_rank), ...
    sprintf('f40A3 unmasked (E50 rank %d)',U.selected_rank), ...
    sprintf('f40A3 masked (E50 rank %d)',M.selected_rank)}, ...
    'Location','southeast');
savefig(f, fig_file);
exportgraphics(f, png_file, 'Resolution', 180);
close(f);
end

function [T, map, meta] = exact_frequency_diagnostic(ctx, stats, ...
        unmasked_pod, masked_pod, target_hz, fs_hz, chunk_size)
nt = double(ctx.cache_size(1));
assert(abs(nt * target_hz / fs_hz - round(nt * target_hz / fs_hz)) < 1e-12, ...
    'The record must contain an integer number of target-frequency cycles.');
min_valid = double(unmasked_pod.min_valid_fraction);
pre_mask = double(stats.valid_count_xy) ./ nt >= min_valid;
post_mask = pre_mask & ~logical(ctx.spatial_exclusion_mask);
assert(nnz(pre_mask) == double(unmasked_pod.retained_spatial_count), ...
    'Unmasked retained spatial count does not match the POD metadata.');
assert(nnz(post_mask) == double(masked_pod.retained_spatial_count), ...
    'Masked retained spatial count does not match the POD metadata.');

idx = find(pre_mask);
post_selector = post_mask(idx);
ubar = double(stats.Ubar(idx)).';
vbar = double(stats.Vbar(idx)).';
n_space = numel(idx);
uc = zeros(1,n_space); us = uc; vc = uc; vs = uc;
sum_u2 = zeros(1,n_space); sum_v2 = zeros(1,n_space);
source = matfile(ctx.cache_file);

n_chunks = ceil(nt / chunk_size);
for chunk = 1:n_chunks
    first = (chunk-1) * chunk_size + 1;
    last = min(nt, first + chunk_size - 1);
    ord = (first:last).';
    phase = 2*pi*target_hz*(ord-1)/fs_hz;
    c = cos(phase);
    s = sin(phase);
    u_chunk = reshape(double(source.U(first:last,:,:)), numel(ord), []);
    v_chunk = reshape(double(source.V(first:last,:,:)), numel(ord), []);
    up = u_chunk(:,idx) - ubar;
    vp = v_chunk(:,idx) - vbar;
    uc = uc + c.' * up;
    us = us + s.' * up;
    vc = vc + c.' * vp;
    vs = vs + s.' * vp;
    sum_u2 = sum_u2 + sum(up.^2,1);
    sum_v2 = sum_v2 + sum(vp.^2,1);
    if mod(chunk,25) == 0 || chunk == n_chunks
        fprintf('[section4 comparison] 40 Hz projection %d/%d chunks\n', ...
            chunk, n_chunks);
    end
end

scale = 2 / nt;
e40_u = 0.5 * ((scale*uc).^2 + (scale*us).^2);
e40_v = 0.5 * ((scale*vc).^2 + (scale*vs).^2);
mean_u2 = sum_u2 / nt;
mean_v2 = sum_v2 / nt;
e40_joint = e40_u + e40_v;
mean_joint = mean_u2 + mean_v2;

selectors = {true(1,n_space), post_selector(:).', ~post_selector(:).'};
labels = ["unmasked_pod_domain"; "masked_active_domain"; ...
    "excluded_retained_roi"];
n = numel(labels);
point_count = zeros(n,1);
total_u = zeros(n,1); total_v = zeros(n,1); total_joint = zeros(n,1);
exact_u = zeros(n,1); exact_v = zeros(n,1); exact_joint = zeros(n,1);
mean_exact = zeros(n,1); share = zeros(n,1);
for i = 1:n
    sel = selectors{i};
    point_count(i) = nnz(sel);
    total_u(i) = sum(mean_u2(sel));
    total_v(i) = sum(mean_v2(sel));
    total_joint(i) = sum(mean_joint(sel));
    exact_u(i) = sum(e40_u(sel));
    exact_v(i) = sum(e40_v(sel));
    exact_joint(i) = sum(e40_joint(sel));
    mean_exact(i) = exact_joint(i) / point_count(i);
    share(i) = exact_joint(i) / total_joint(i);
end
fraction_total = total_joint / total_joint(1);
fraction_exact = exact_joint / exact_joint(1);
T = table(labels, point_count, total_u, total_v, total_joint, exact_u, ...
    exact_v, exact_joint, mean_exact, 100*share, fraction_total, ...
    fraction_exact, 'VariableNames', {'Domain','SpatialPointCount', ...
    'SpatialSumTotalU','SpatialSumTotalV','SpatialSumTotalJoint', ...
    'SpatialSumExact40HzU','SpatialSumExact40HzV', ...
    'SpatialSumExact40HzJoint','MeanExact40HzJointPerPoint', ...
    'Exact40HzFractionOfTotalPercent','FractionOfUnmaskedTotal', ...
    'FractionOfUnmaskedExact40Hz'});

map = struct();
map.frequency_hz = target_hz;
map.pre_mask = pre_mask;
map.post_mask = post_mask;
map.exact_u = nan(size(pre_mask));
map.exact_v = nan(size(pre_mask));
map.exact_joint = nan(size(pre_mask));
map.total_joint = nan(size(pre_mask));
map.exact_u(idx) = e40_u;
map.exact_v(idx) = e40_v;
map.exact_joint(idx) = e40_joint;
map.total_joint(idx) = mean_joint;

meta = struct();
meta.definition = ['Exact least-squares-equivalent sinusoidal projection ' ...
    'of PostProc u'' and v'' about the full-field temporal means; spatial ' ...
    'sums use the 100%-valid POD DOFs.'];
meta.frequency_hz = target_hz;
meta.sample_rate_hz = fs_hz;
meta.frame_count = nt;
meta.record_cycles = nt * target_hz / fs_hz;
meta.chunk_size = chunk_size;
meta.unmasked_retained_spatial_count = nnz(pre_mask);
meta.masked_retained_spatial_count = nnz(post_mask);
meta.excluded_retained_spatial_count = nnz(pre_mask & ~post_mask);
meta.source_cache = ctx.cache_file;
end

function [png_file, fig_file] = plot_frequency_comparison(root, T)
png_file = fullfile(root, 'exact_40hz_energy_comparison.png');
fig_file = fullfile(root, 'exact_40hz_energy_comparison.fig');
f = figure('Visible','off','Color','w','Position',[80 80 1050 520]);
tiledlayout(f,1,2,'TileSpacing','compact','Padding','compact');
ax = nexttile;
Y = [T.FractionOfUnmaskedTotal(1:2), T.FractionOfUnmaskedExact40Hz(1:2)];
bar(ax, categorical({'unmasked','masked'}), Y, 'grouped');
yline(ax,1,'--','unmasked reference'); grid(ax,'on'); box(ax,'on');
ylabel(ax,'Fraction of unmasked spatial-sum energy');
legend(ax,{'all fluctuation energy','exact 40 Hz harmonic energy'}, ...
    'Location','southwest');
title(ax,'Static exclusion effect');
ax = nexttile;
bar(ax, categorical({'unmasked','masked'}), ...
    T.Exact40HzFractionOfTotalPercent(1:2), 0.55, ...
    'FaceColor',[0.18 0.48 0.67]);
grid(ax,'on'); box(ax,'on');
ylabel(ax,'Exact 40 Hz / total joint energy [%]');
title(ax,'40 Hz share in retained POD domain');
savefig(f, fig_file);
exportgraphics(f, png_file, 'Resolution', 180);
close(f);
end

function [png_file, fig_file] = plot_frequency_map(root, map, ctx)
png_file = fullfile(root, 'exact_40hz_energy_map.png');
fig_file = fullfile(root, 'exact_40hz_energy_map.fig');
field = map.exact_joint;
positive = field(isfinite(field) & field > 0);
floor_value = max(min(positive), realmin('double'));
field = log10(max(field, floor_value));
f = figure('Visible','off','Color','w','Position',[80 80 1500 520]);
ax = axes(f);
imagesc(ax, ctx.x_mm, ctx.wall_y_mm, field);
set(ax,'YDir','normal'); axis(ax,'tight'); daspect(ax,[1 1 1]);
colormap(ax,parula(256)); cb = colorbar(ax);
cb.Label.String = 'log_{10} exact 40 Hz joint energy [(m/s)^2]';
xlabel(ax,'x [mm]'); ylabel(ax,'wall distance [mm]');
title(ax,'f40A3 PostProc exact 40 Hz harmonic energy and Section 4 exclusion');
hold(ax,'on');
d23.draw_spatial_exclusion(ax,ctx);
savefig(f, fig_file);
exportgraphics(f, png_file, 'Resolution', 180);
close(f);
end

function audit = audit_section4_figures(manifest_file, figure_root)
opts = detectImportOptions(manifest_file, 'TextType', 'string');
opts = setvartype(opts, {'PNG','FIG'}, 'string');
T = readtable(manifest_file, opts);
generated = logical(T.Generated);
png_exists = arrayfun(@(s)isfile(s), T.PNG(generated));
fig_exists = arrayfun(@(s)isfile(s), T.FIG(generated));
sheets_png = dir(fullfile(figure_root, 'contact_sheets', ...
    'contact_sheet_timebin_*.png'));
sheets_fig = dir(fullfile(figure_root, 'fig', ...
    'contact_sheet_timebin_*.fig'));
audit = struct('manifest_file', manifest_file, ...
    'manifest_rows', height(T), 'generated_rows', nnz(generated), ...
    'generated_png_existing', nnz(png_exists), ...
    'generated_fig_existing', nnz(fig_exists), ...
    'contact_sheet_png_count', numel(sheets_png), ...
    'contact_sheet_fig_count', numel(sheets_fig), ...
    'all_generated_paths_exist', all(png_exists) && all(fig_exists));
end

function text = build_report(result)
T = result.case_comparison;
F = result.exact_40hz;
S = read_json(fullfile(result.f40_masked_run, 'json', 'summary.json'));
E = S.spatial_exclusion;
lines = strings(0,1);
lines(end+1) = '# Section 4 spatial-exclusion comparison';
lines(end+1) = '';
lines(end+1) = sprintf('- Created UTC: %s', result.created_utc);
lines(end+1) = sprintf('- f40A3 unmasked run: `%s`', result.f40_unmasked_run);
lines(end+1) = sprintf('- f40A3 masked run: `%s`', result.f40_masked_run);
lines(end+1) = sprintf(['- Requested exclusion: x=[%.6g, %.6g] mm, ' ...
    'wall-y=[0, %.6g] mm'], E.requested_x_start_mm, ...
    E.requested_x_end_mm, E.requested_wall_y_height_mm);
lines(end+1) = sprintf(['- Actual grid exclusion: rows %d:%d, cols %d:%d, ' ...
    '%d points; x=[%.6f, %.6f] mm, wall-y=[%.6f, %.6f] mm'], ...
    E.row_indices(1), E.row_indices(end), E.column_indices(1), ...
    E.column_indices(end), E.excluded_grid_point_count, ...
    E.realized_x_min_mm, E.realized_x_max_mm, ...
    E.realized_wall_y_min_mm, E.realized_wall_y_max_mm);
lines(end+1) = '';
lines(end+1) = '## POD E50 and VLSM counts';
lines(end+1) = '';
lines(end+1) = ['| dataset | E50 rank | achieved energy | retained points | ' ...
    '8-neighbor >3 / >3.8 / >4.5 | 4-neighbor >3 / >3.8 / >4.5 |'];
lines(end+1) = '|---|---:|---:|---:|---:|---:|';
for i = 1:height(T)
    lines(end+1) = sprintf('| %s | %d | %.6f | %d | %d / %d / %d | %d / %d / %d |', ...
        T.Dataset(i), T.PODRank(i), T.E50Achieved(i), ...
        T.RetainedSpatialPoints(i), T.Complete8_L3(i), ...
        T.Complete8_L3p8(i), T.Complete8_L4p5(i), ...
        T.Complete4_L3(i), T.Complete4_L3p8(i), T.Complete4_L4p5(i));
end
lines(end+1) = '';
lines(end+1) = '## Exact 40 Hz diagnostic';
lines(end+1) = '';
lines(end+1) = ['This is an exact 40 Hz sinusoidal projection of PostProc u'' and v'' ' ...
    'over 12,000 frames at 960 Hz (500 complete cycles). It is not a Welch-bin ' ...
    'approximation and does not filter or rewrite the source cache. Spatial sums ' ...
    'use the same 100%-valid DOFs admitted to the Section 4 POD.'];
lines(end+1) = '';
lines(end+1) = '| domain | points | total joint energy sum | exact 40 Hz sum | 40 Hz share | fraction of unmasked 40 Hz |';
lines(end+1) = '|---|---:|---:|---:|---:|---:|';
for i = 1:height(F)
    lines(end+1) = sprintf('| %s | %d | %.9g | %.9g | %.6f%% | %.6f |', ...
        F.Domain(i), F.SpatialPointCount(i), F.SpatialSumTotalJoint(i), ...
        F.SpatialSumExact40HzJoint(i), ...
        F.Exact40HzFractionOfTotalPercent(i), ...
        F.FractionOfUnmaskedExact40Hz(i));
end
lines(end+1) = '';
lines(end+1) = sprintf(['The exclusion removes %.3f%% of the exact 40 Hz joint ' ...
    'harmonic energy while removing %.3f%% of the total joint fluctuation energy ' ...
    'from the POD spatial sum. This is descriptive; no post-hoc pass threshold ' ...
    'is applied.'], 100*(1-F.FractionOfUnmaskedExact40Hz(2)), ...
    100*(1-F.FractionOfUnmaskedTotal(2)));
lines(end+1) = '';
lines(end+1) = '## Figure audit';
lines(end+1) = '';
A = result.figure_audit;
lines(end+1) = sprintf(['The canonical Section 4 manifest marks %d rows generated; ' ...
    '%d PNG and %d FIG paths exist. Contact sheets: %d PNG and %d FIG.'], ...
    A.generated_rows, A.generated_png_existing, A.generated_fig_existing, ...
    A.contact_sheet_png_count, A.contact_sheet_fig_count);
lines(end+1) = '';
lines(end+1) = 'The static exclusion changes the POD analysis domain; it is not a dynamic film mask and it does not modify the full-field mean, delta99, u_tau, or Re_tau definitions.';
text = strjoin(lines,newline) + newline;
end

function T = build_artifact_manifest(files)
n = numel(files);
exists = false(n,1);
bytes = zeros(n,1);
kind = strings(n,1);
for i = 1:n
    exists(i) = isfile(files(i));
    if exists(i)
        info = dir(files(i));
        bytes(i) = info.bytes;
    end
    [~,~,ext] = fileparts(files(i));
    kind(i) = erase(lower(string(ext)), '.');
end
T = table(files(:), kind, exists, bytes, ...
    'VariableNames', {'Path','Kind','Exists','Bytes'});
end

function atomic_save(filename, payload)
folder = fileparts(filename);
if ~isfolder(folder), mkdir(folder); end
tmp = [tempname(tempdir) '.mat'];
cleanup = onCleanup(@() cleanup_file(tmp));
save(tmp, '-struct', 'payload', '-v7.3');
movefile(tmp, filename, 'f');
clear cleanup;
end

function cleanup_file(filename)
if isfile(filename), delete(filename); end
end

function stamp = utc_now()
stamp = char(datetime('now','TimeZone','UTC', ...
    'Format','yyyy-MM-dd''T''HH:mm:ss.SSS''Z'''));
end
