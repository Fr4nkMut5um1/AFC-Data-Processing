function report = run_section4_edge_exclusion_regression()
%RUN_SECTION4_EDGE_EXCLUSION_REGRESSION Read-only regression for FOV-rim SS.
% Reuses saved POD-E50 runs and their statistics.  It never rebuilds a POD
% cache and never writes a canonical Section-4 result.

here = fileparts(mfilename('fullpath'));
repo_root = fileparts(fileparts(fileparts(here)));
addpath(fullfile(repo_root, 'lib'));

cases = struct( ...
    'name', {'baseline','f40a3'}, ...
    'case_dir', {'tandem_baseline_r2','tandem_f40a3_phi0_r2'}, ...
    'run_dir', {fullfile(repo_root,'cases','experiments', ...
        'deshpande2023_baseline','output','runs', ...
        '20260829_172908_786_postproc_pod_e50_full_223b5f53'), ...
        fullfile(repo_root,'cases','per_case','tandem_f40a3_phi0_r2', ...
        'output','section4_vlsm','runs', ...
        '20260831_073739_673_section4_pod_e50_4dee6520')}, ...
    'frames', {[7090 7091 7086], [7748 8622 5497]});

stamp = char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
all_rows = cell(0,1);
figure_files = strings(0,1);
case_reports = struct([]);

for ci = 1:numel(cases)
    run_dir = cases(ci).run_dir;
    result_file = fullfile(run_dir, 'mat', 'final_results.mat');
    if ~isfile(result_file)
        error('r2:edgeRegression:MissingRun', 'Missing saved run: %s', result_file);
    end
    saved = load(result_file, 'context', 'statistics', ...
        'detection_statistics', 'config', 'ss_catalog');
    ctx = saved.context;
    stats = saved.statistics;
    det = saved.detection_statistics;
    dcfg = saved.config;
    dcfg.schema_version = 3;
    dcfg.detection.max_complete_ss_per_sign = Inf;
    dcfg.detection.selection_rule = ...
        'longest_then_pixel_count_then_component_id_nonoverlapping_bbox';
    dcfg.detection.streamwise_edge_exclusion = struct( ...
        'enabled', false, 'buffer_cells', 3);
    if ~isfield(dcfg.preprocessing, 'spatial_exclusion')
        dcfg.preprocessing.spatial_exclusion = struct('enabled', false, ...
            'x_start_mm', [], 'x_end_mm', [], 'wall_y_height_mm', []);
    end
    if ~isfield(ctx, 'spatial_exclusion_mask')
        [ctx.spatial_exclusion_mask, ctx.spatial_exclusion] = ...
            d23.resolve_spatial_exclusion(ctx.X_mm, ctx.wall_distance_mm, ...
            dcfg.preprocessing.spatial_exclusion);
    end
    dcfg.execution.frame_ordinals = 1;
    dcfg.execution.label = 'edge_exclusion_regression';
    if ~isfield(dcfg, 'Uinf') || isempty(dcfg.Uinf)
        dcfg.Uinf = 25;
    end
    pod_file = fullfile(run_dir, 'pod', 'pod_reconstruction.mat');
    if ~isfile(pod_file)
        error('r2:edgeRegression:MissingPod', 'Missing POD cache: %s', pod_file);
    end
    d23.validate_config(dcfg);

    output_root = fullfile(repo_root, 'cases', 'per_case', cases(ci).case_dir, ...
        'output', 'section4_vlsm', 'edge_exclusion_regression', stamp);
    if ~isfolder(output_root), mkdir(output_root); end
    rows = cell(0,1);
    for fi = 1:numel(cases(ci).frames)
        ordinal = cases(ci).frames(fi);
        if ordinal > ctx.cache_size(1)
            error('r2:edgeRegression:FrameRange', 'Frame %d exceeds cache.', ordinal);
        end
        dcfg.execution.frame_ordinals = ordinal;
        fields = d23.fluctuation_chunk(ctx, stats, dcfg, ordinal, pod_file);
        up = squeeze(fields.up(1,:,:));
        valid = squeeze(fields.valid(1,:,:));
        frame_id = uint32(ctx.frame_ids(ordinal));
        for conn = [8 4]
            for sign_value = [1 -1]
                old_cfg = dcfg;
                old_cfg.detection.streamwise_edge_exclusion.enabled = false;
                before = d23.identify_frame(up, valid, det.u_rms_y, ordinal, ...
                    frame_id, conn, sign_value, ctx, old_cfg);
                new_cfg = dcfg;
                new_cfg.detection.streamwise_edge_exclusion.enabled = true;
                after = d23.identify_frame(up, valid, det.u_rms_y, ordinal, ...
                    frame_id, conn, sign_value, ctx, new_cfg);
                canonical = saved.ss_catalog(saved.ss_catalog.FrameOrdinal == ordinal & ...
                    saved.ss_catalog.Connectivity == conn & ...
                    saved.ss_catalog.Sign == sign_value, :);
                before_vlsm = before(before.IsSS3 & ~before.IsCensored, :);
                after_vlsm = after(after.IsSS3 & ~after.IsCensored, :);
                after_rejected = after(after.RejectedByStreamwiseEdge & ...
                    after.PassLength3 & after.PassWallLower & after.PassWallUpper, :);
                assert_saved_edge_vlsm_is_rejected(cases(ci).name, ordinal, ...
                    conn, sign_value, canonical, before, after);
                item = regression_row(cases(ci).name, ordinal, frame_id, conn, ...
                    sign_value, canonical, before_vlsm, after_vlsm, after_rejected);
                rows{end+1,1} = item; %#ok<AGROW>
                plot_file = fullfile(output_root, sprintf( ...
                    'frame_%06d_conn_%d_sign_%+d.png', frame_id, conn, sign_value));
                fig_file = fullfile(output_root, sprintf( ...
                    'frame_%06d_conn_%d_sign_%+d.fig', frame_id, conn, sign_value));
                draw_regression_figure(up, valid, before, after, ctx, det, ...
                    dcfg, ordinal, frame_id, conn, sign_value, fig_file, plot_file);
                figure_files(end+1,1) = string(plot_file); %#ok<AGROW>
            end
        end
    end
    case_table = vertcat(rows{:});
    writetable(case_table, fullfile(output_root, 'edge_exclusion_comparison.csv'));
    case_reports(ci).name = cases(ci).name;
    case_reports(ci).output_root = output_root;
    case_reports(ci).rows = height(case_table);
    case_reports(ci).png_count = numel(dir(fullfile(output_root, '*.png')));
    case_reports(ci).fig_count = numel(dir(fullfile(output_root, '*.fig')));
    all_rows = [all_rows; rows]; %#ok<AGROW>
end

comparison = vertcat(all_rows{:});
% The cell is populated after each case so that a single aggregate file has
% stable columns even when a case has no qualifying canonical row.
aggregate_root = fullfile(repo_root, 'cases', 'per_case', ...
    'tandem_baseline_r2', 'output', 'research', ...
    ['edge_exclusion_regression_' stamp]);
if ~isfolder(aggregate_root), mkdir(aggregate_root); end
writetable(comparison, fullfile(aggregate_root, 'edge_exclusion_comparison.csv'));
manifest = struct('created_local', stamp, 'read_only', true, ...
    'description', ['Saved POD-E50 fields reclassified with streamwise edge ' ...
    'buffer enabled/disabled; canonical results were not overwritten.'], ...
    'buffer_cells', 3, 'cases', case_reports, ...
    'figure_files', figure_files);
fid = fopen(fullfile(aggregate_root, 'manifest.json'), 'w', 'n', 'UTF-8');
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, jsonencode(manifest, 'PrettyPrint', true), 'char');
clear cleanup;
write_report_markdown(fullfile(aggregate_root, 'report.md'), comparison, manifest);
report = manifest;
report.aggregate_root = aggregate_root;
fprintf('[edge regression] %s\n', aggregate_root);
end

function assert_saved_edge_vlsm_is_rejected(case_name, ordinal, conn, ...
        sign_value, canonical, before, after)
% The selected regression frames include known canonical edge VLSM examples.
% For those rows, the enabled rule must retain an auditable component record
% but remove it from every SS tier.  Non-canonical signs are intentionally
% allowed to have no edge VLSM, so they only contribute diagnostic images.
if isempty(canonical)
    return;
end
before_primary = before(before.IsSS3 & ~before.IsCensored, :);
target_ids = intersect(double(canonical.ComponentID), ...
    double(before_primary.ComponentID));
if isempty(target_ids)
    error('r2:edgeRegression:CanonicalMismatch', ...
        ['%s frame %d, %d-neighbor, sign %+d no longer reproduces the ' ...
        'saved canonical primary component.'], ...
        case_name, ordinal, conn, sign_value);
end
before_target = before_primary(ismember(double(before_primary.ComponentID), ...
    target_ids), :);
if ~all(before_target.TouchesStreamwiseLeftBuffer | ...
        before_target.TouchesStreamwiseRightBuffer)
    error('r2:edgeRegression:ExpectedEdgeCandidate', ...
        ['%s frame %d, %d-neighbor, sign %+d canonical VLSM does not ' ...
        'touch the configured streamwise buffer.'], ...
        case_name, ordinal, conn, sign_value);
end
after_target = after(ismember(double(after.ComponentID), target_ids), :);
if height(after_target) ~= numel(target_ids) || ...
        ~all(after_target.RejectedByStreamwiseEdge) || ...
        any(after_target.IsSS3 | after_target.IsSS3p8 | after_target.IsSS4p5)
    error('r2:edgeRegression:EdgeVLSMRetained', ...
        ['%s frame %d, %d-neighbor, sign %+d retains a saved edge VLSM ' ...
        'after streamwise edge exclusion is enabled.'], ...
        case_name, ordinal, conn, sign_value);
end
end

function row = regression_row(case_name, ordinal, frame_id, conn, sign_value, ...
        canonical, before, after, rejected)
canonical_count = height(canonical);
row = table(string(case_name), uint32(ordinal), uint32(frame_id), uint8(conn), ...
    int8(sign_value), uint32(canonical_count), uint32(height(before)), ...
    uint32(height(after)), uint32(height(rejected)), ...
    uint16_or_zero(canonical,'ColMin'), uint16_or_zero(canonical,'ColMax'), ...
    uint16_or_zero(canonical,'RowMin'), uint16_or_zero(canonical,'RowMax'), ...
    double_or_nan(canonical,'Lx_over_delta'), ...
    uint16_or_zero(before,'ColMin'), uint16_or_zero(before,'ColMax'), ...
    uint16_or_zero(after,'ColMin'), uint16_or_zero(after,'ColMax'), ...
    'VariableNames', {'Case','FrameOrdinal','FrameID','Connectivity','Sign', ...
    'CanonicalVLSMCount','BeforeVLSMCount','AfterVLSMCount', ...
    'RejectedByEdgeCount','CanonicalColMin','CanonicalColMax', ...
    'CanonicalRowMin','CanonicalRowMax','CanonicalLengthXOverDelta', ...
    'BeforeColMin','BeforeColMax','AfterColMin','AfterColMax'});
end

function value = uint16_or_zero(T, name)
if isempty(T), value = uint16(0); else, value = uint16(T.(name)(1)); end
end

function value = double_or_nan(T, name)
if isempty(T), value = NaN; else, value = double(T.(name)(1)); end
end

function draw_regression_figure(up, valid, before, after, ctx, det, cfg, ...
        ordinal, frame_id, conn, sign_value, fig_file, png_file)
field = up ./ double(cfg.Uinf); field(~valid) = NaN;
finite_values = field(isfinite(field));
lim = 1;
if ~isempty(finite_values), lim = prctile(abs(finite_values),99.5); end
if ~isfinite(lim) || lim <= 0, lim = 1; end
f = figure('Visible','off','Color','w','Position',[40 40 1600 560]);
ax = axes(f);
imagesc(ax, ctx.x_mm, ctx.wall_y_mm, field);
set(ax,'YDir','normal'); axis(ax,'tight'); daspect(ax,[1 1 1]);
colormap(f, d23.balance_colormap(257)); clim(ax,[-lim lim]); colorbar(ax);
xlabel(ax,'x [mm]'); ylabel(ax,'wall distance [mm]'); hold(ax,'on');
if isfield(ctx,'spatial_exclusion') && ctx.spatial_exclusion.enabled
    d23.draw_spatial_exclusion(ax, ctx);
end
buffer = double(cfg.detection.streamwise_edge_exclusion.buffer_cells);
x_left = ctx.x_mm(1) - 0.5*ctx.dx_mm;
x_right = ctx.x_mm(end) + 0.5*ctx.dx_mm;
x_left_inner = ctx.x_mm(min(numel(ctx.x_mm),1+buffer)) + 0.5*ctx.dx_mm;
x_right_inner = ctx.x_mm(max(1,numel(ctx.x_mm)-buffer)) - 0.5*ctx.dx_mm;
patch(ax,[x_left x_left_inner x_left_inner x_left], ...
    [ctx.wall_y_mm(1)-0.5*ctx.dy_mm ctx.wall_y_mm(1)-0.5*ctx.dy_mm ...
    ctx.wall_y_mm(end)+0.5*ctx.dy_mm ctx.wall_y_mm(end)+0.5*ctx.dy_mm], ...
    [0.75 0.75 0.75],'FaceAlpha',0.18,'EdgeColor',[0.35 0.35 0.35], ...
    'LineStyle','--','DisplayName','left edge buffer');
patch(ax,[x_right_inner x_right x_right x_right_inner], ...
    [ctx.wall_y_mm(1)-0.5*ctx.dy_mm ctx.wall_y_mm(1)-0.5*ctx.dy_mm ...
    ctx.wall_y_mm(end)+0.5*ctx.dy_mm ctx.wall_y_mm(end)+0.5*ctx.dy_mm], ...
    [0.75 0.75 0.75],'FaceAlpha',0.18,'EdgeColor',[0.35 0.35 0.35], ...
    'LineStyle','--','DisplayName','right edge buffer');
before_candidate = before(before.PassLength3 & before.PassWallLower & ...
    before.PassWallUpper, :);
after_kept = after(after.IsSS3 & ~after.IsCensored, :);
for i = 1:height(before_candidate)
    rectangle(ax,'Position',[before_candidate.XMin_mm(i),before_candidate.YMin_mm(i), ...
        before_candidate.XMax_mm(i)-before_candidate.XMin_mm(i), ...
        before_candidate.YMax_mm(i)-before_candidate.YMin_mm(i)], ...
        'EdgeColor',[0.2 0.4 1],'LineWidth',1.3,'LineStyle','-');
end
for i = 1:height(after_kept)
    rectangle(ax,'Position',[after_kept.XMin_mm(i),after_kept.YMin_mm(i), ...
        after_kept.XMax_mm(i)-after_kept.XMin_mm(i), ...
        after_kept.YMax_mm(i)-after_kept.YMin_mm(i)], ...
        'EdgeColor',[0.1 0.65 0.2],'LineWidth',1.8,'LineStyle','-');
end
rejected = after(after.RejectedByStreamwiseEdge & after.PassLength3 & ...
    after.PassWallLower & after.PassWallUpper, :);
for i = 1:height(rejected)
    rectangle(ax,'Position',[rejected.XMin_mm(i),rejected.YMin_mm(i), ...
        rejected.XMax_mm(i)-rejected.XMin_mm(i), ...
        rejected.YMax_mm(i)-rejected.YMin_mm(i)], ...
        'EdgeColor',[0.85 0.1 0.1],'LineWidth',2.2,'LineStyle','--');
end
title(ax,sprintf('edge exclusion regression | frame %d | %d-neighbor | sign %+d | buffer %d cells', ...
    frame_id, conn, sign_value, buffer),'Interpreter','none');
export_figure_pair(f, fig_file, png_file, cfg.output.figure_dpi);
end

function export_figure_pair(f, fig_file, png_file, dpi)
cleanup = onCleanup(@() close_if_valid(f));
savefig(f, fig_file);
exportgraphics(f, png_file, 'Resolution', dpi);
clear cleanup;
end

function close_if_valid(f)
if ~isempty(f) && isgraphics(f), close(f); end
end

function write_report_markdown(filename, comparison, manifest)
lines = strings(0,1);
lines(end+1) = '# Section 4 左右边缘排除隔离回归';
lines(end+1) = '';
lines(end+1) = '- 本报告只读取已保存 POD-E50 run；未重建 POD，未覆盖 canonical 结果。';
lines(end+1) = sprintf('- 边缘缓冲：左右各 %d 个网格间距（左侧含列 1–%d；右侧含列 Nx-%d–Nx）。', ...
    manifest.buffer_cells, 1 + manifest.buffer_cells, manifest.buffer_cells);
lines(end+1) = '';
lines(end+1) = '| case | frame | conn | sign | canonical | before | after | rejected |';
lines(end+1) = '|---|---:|---:|---:|---:|---:|---:|---:|';
for i = 1:height(comparison)
    lines(end+1) = sprintf('| %s | %d | %d | %+d | %d | %d | %d | %d |', ...
        comparison.Case(i), comparison.FrameID(i), comparison.Connectivity(i), ...
        comparison.Sign(i), comparison.CanonicalVLSMCount(i), ...
        comparison.BeforeVLSMCount(i), comparison.AfterVLSMCount(i), ...
        comparison.RejectedByEdgeCount(i));
end
lines(end+1) = '';
lines(end+1) = '蓝框为开启边缘排除前的合格候选，绿框为开启后保留对象，红色虚线框为被边缘规则排除的候选。';
fid = fopen(filename, 'w', 'n', 'UTF-8');
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, strjoin(lines,newline) + newline, 'char');
clear cleanup;
end
