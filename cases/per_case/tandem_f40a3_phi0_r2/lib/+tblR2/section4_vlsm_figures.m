function [manifest, files, contact_files] = section4_vlsm_figures( ...
        catalog8, catalog4, ctx, stats, detection_stats, dcfg, ...
        pod_file, output_root, selection)
%SECTION4_VLSM_FIGURES Independent Section-4 flow-field figure export.
% Images use a symmetric blue-white-red (cmocean/ocean-compatible) map and
% daspect([1 1 1]), so one millimetre in x is drawn with the same length as
% one millimetre in y. Detection statistics retain both connectivities, but
% individual images use only dcfg.section4_figure_connectivity. Each complete
% primary VLSM is assigned its highest passed length tier and rendered once.

if nargin < 9 || isempty(selection)
    selection = table();
end
if ~isfolder(output_root), mkdir(output_root); end
png_root = fullfile(output_root, 'figures', 'png');
fig_root = fullfile(output_root, 'figures', 'fig');
sheet_root = fullfile(output_root, 'figures', 'contact_sheets');
for p = {png_root, fig_root, sheet_root}
    if ~isfolder(p{1}), mkdir(p{1}); end
end

figure_connectivity = 8;
if isfield(dcfg, 'section4_figure_connectivity')
    figure_connectivity = double(dcfg.section4_figure_connectivity);
end
if ~isscalar(figure_connectivity) || ~ismember(figure_connectivity, [4 8])
    error('tblR2:section4_vlsm_figures:FigureConnectivity', ...
        'section4_figure_connectivity must be the scalar value 4 or 8.');
end
if figure_connectivity == 8
    target_catalog = catalog8;
else
    target_catalog = catalog4;
end

section_max = Inf;
if isfield(dcfg, 'section4_max_figure_objects')
    section_max = double(dcfg.section4_max_figure_objects);
end
selected = choose_rows(target_catalog, selection, section_max);

% Build one manifest row per complete primary VLSM for the selected
% connectivity. Length tiers remain cumulative in catalogs/statistics; only
% the image label is exclusive and uses the highest passed threshold.
candidates = target_catalog(target_catalog.IsVLSM & ...
    ~target_catalog.IsCensored, :);
all_rows = cell(0,1);
for i = 1:height(candidates)
    tier = highest_tier(candidates(i,:));
    if tier == 0, continue; end
    all_rows{end+1,1} = manifest_row(candidates(i,:), ...
        figure_connectivity, tier, false, ...
        "not_selected_for_individual_export", "", ""); %#ok<AGROW>
end
if isempty(all_rows)
    manifest = empty_manifest();
else
    manifest = vertcat(all_rows{:});
end
files = strings(0,1);
contact_files = strings(0,1);

% Canonical figure directories represent the current export only. Remove
% files owned by this exporter so a connectivity switch cannot leave stale
% images that appear to belong to the new run.
clear_managed_outputs(png_root, fig_root, sheet_root);

generated_png = strings(0,1);
generated_frame = zeros(0,1);
generated_bin = zeros(0,1);
last_frame = NaN; cached_field = []; cached_valid = [];
% Tables report numel = height*width; iterate over rows only.
for i = 1:height(selected)
    row = selected(i,:);
    if ~row.IsVLSM || row.IsCensored, continue; end
    tier = highest_tier(row);
    if tier == 0, continue; end
    ordinal = double(row.FrameOrdinal);
    if ordinal ~= last_frame
        fields = d23.fluctuation_chunk(ctx, stats, dcfg, ordinal, pod_file);
        cached_field = squeeze(fields.up(1,:,:));
        cached_valid = squeeze(fields.valid(1,:,:));
        last_frame = ordinal;
    end
    stem = sprintf(['frame_%06d_ord_%06d_sign_%+d_conn_%d_' ...
        'sid_%06d_LxGt_%s'], row.FrameID, row.FrameOrdinal, row.Sign, ...
        figure_connectivity, row.StructureID, tier_label(tier));
    png_file = fullfile(png_root, [stem '.png']);
    fig_file = fullfile(fig_root, [stem '.fig']);
    try
        f = draw_field(cached_field, cached_valid, row, ...
            ctx, detection_stats, dcfg, figure_connectivity, tier);
        export_figure_pair(f, fig_file, png_file, dcfg.output.figure_dpi);
        files(end+1,1) = string(png_file); %#ok<AGROW>
        generated_png(end+1,1) = string(png_file); %#ok<AGROW>
        generated_frame(end+1,1) = row.FrameID; %#ok<AGROW>
        generated_bin(end+1,1) = min(5, max(1, ceil(5 * ...
            double(row.FrameOrdinal) / dcfg.data.expected_cache_size(1)))); %#ok<AGROW>
        manifest = mark_generated(manifest, row, figure_connectivity, ...
            tier, png_file, fig_file);
    catch problem
        manifest = mark_failed(manifest, row, figure_connectivity, tier, ...
            problem.message);
        warning('tblR2:section4_vlsm_figures:ExportFailed', ...
            'Figure %s failed: %s', stem, problem.message);
    end
end

% Five compact contact sheets mirror the previous delivery format while
% retaining the physical field image and explicit connectivity overlays.
for b = 1:5
    rows = generated_bin == b;
    if ~any(rows), continue; end
    these = find(rows);
    these = these(1:min(6, numel(these)));
    f = figure('Visible','off','Color','w','Position',[30 30 1500 520]);
    tiledlayout(f,2,3,'TileSpacing','compact','Padding','compact');
    for j = 1:6
        ax = nexttile;
        if j <= numel(these) && isfile(generated_png(these(j)))
            img = imread(generated_png(these(j)));
            image(ax,img); axis(ax,'image','off');
            title(ax, sprintf('frame %d', generated_frame(these(j))), ...
                'Interpreter','none','FontSize',8);
        else
            axis(ax,'off');
        end
    end
    file_png = fullfile(sheet_root, sprintf('contact_sheet_timebin_%d.png',b));
    file_fig = fullfile(fig_root, sprintf('contact_sheet_timebin_%d.fig',b));
    export_figure_pair(f, file_fig, file_png, dcfg.output.figure_dpi);
    contact_files(end+1,1) = string(file_png); %#ok<AGROW>
end
end

function selected = choose_rows(catalog, selection, max_objects)
if isempty(catalog), selected = catalog; return; end
complete = catalog(catalog.IsVLSM & ~catalog.IsCensored,:);
if height(complete) > 0
    complete = sortrows(complete, ...
        {'FrameOrdinal','Sign','LengthX_over_delta'}, ...
        {'ascend','descend','descend'});
end
if ~isscalar(max_objects) || isnan(max_objects) || max_objects < 0
    error('tblR2:section4_vlsm_figures:MaxFigureObjects', ...
        'section4_max_figure_objects must be a nonnegative scalar or Inf.');
end
if isinf(max_objects)
    selected = complete;
    return;
end
max_objects = floor(max_objects);
if max_objects == 0, selected = catalog([],:); return; end
if istable(selection) && height(selection) > 0 && ...
        all(ismember({'Selected','FrameOrdinal','ActualSign','ComponentID'}, ...
        selection.Properties.VariableNames))
    selection = selection(selection.Selected,:);
    selected = catalog([],:);
    for i = 1:height(selection)
        rows = catalog.FrameOrdinal == selection.FrameOrdinal(i) & ...
            catalog.Sign == selection.ActualSign(i) & ...
            catalog.StructureID == selection.ComponentID(i) & ...
            catalog.IsVLSM & ~catalog.IsCensored;
        if any(rows), selected(end+1,:) = catalog(find(rows,1),:); end %#ok<AGROW>
    end
else
    selected = complete;
end
if height(selected) > max_objects
    selected = selected(1:max_objects,:);
end
end

function tier = highest_tier(row)
tier = uint8(0);
eligible = logical(row.PassWallLower) && logical(row.PassWallUpper) && ...
    logical(row.IsVLSM) && ~logical(row.IsCensored);
if ~eligible, return; end
if logical(row.PassLength4p5)
    tier = uint8(3);
elseif logical(row.PassLength3p8)
    tier = uint8(2);
elseif logical(row.PassLength3)
    tier = uint8(1);
end
end

function label = tier_label(tier)
switch tier
    case 1, label = '3';
    case 2, label = '3p8';
    otherwise, label = '4p5';
end
end

function f = draw_field(up, valid, row, ctx, detection_stats, dcfg, conn, tier)
normalization = 'u_over_Uinf';
if isfield(dcfg,'plot_normalization'), normalization = char(dcfg.plot_normalization); end
if strcmpi(normalization,'u_over_urms') || strcmpi(normalization,'u_over_urms_y')
    denom = reshape(double(detection_stats.u_rms_y), [], 1);
    field = up ./ max(denom, eps);
    label = 'u''/u_{rms}(y)';
else
    field = up ./ double(dcfg.Uinf);
    label = 'u''/U_infty';
end
field(~valid) = NaN;
finite_values = field(isfinite(field));
if isempty(finite_values), lim = 1; else, lim = prctile(abs(finite_values),99.5); end
if ~isfinite(lim) || lim <= 0, lim = 1; end

f = figure('Visible','off','Color','w','Position',[50 50 1500 520]);
ax = axes(f);
imagesc(ax, ctx.x_mm, ctx.wall_y_mm, field);
set(ax,'YDir','normal'); axis(ax,'tight'); daspect(ax,[1 1 1]);
colormap(f, d23.balance_colormap(257)); clim(ax,[-lim lim]);
cb = colorbar(ax); cb.Label.String = label;
xlabel(ax,'x [mm]'); ylabel(ax,'wall distance [mm]'); hold(ax,'on');
d23.draw_spatial_exclusion(ax, ctx);
rectangle(ax,'Position',[row.XMin_mm,row.YMin_mm, ...
    row.XMax_mm-row.XMin_mm,row.YMax_mm-row.YMin_mm], ...
    'EdgeColor',[0 0 0],'LineWidth',2.0,'LineStyle','-');
title(ax,sprintf('%s | frame %d | sign %+d | %d-neighbor | L_x/\\delta=%.2f | >%s\\delta', ...
    char(dcfg.experiment_id),row.FrameID,row.Sign,conn, ...
    row.LengthX_over_delta,tier_label(tier)),'Interpreter','tex');
end

function row = manifest_row(C, conn, tier, generated, reason, png, fig)
row = table(uint32(C.FrameOrdinal), uint32(C.FrameID), ...
    uint32(C.StructureID), int8(C.Sign), uint8(conn), uint8(tier), ...
    double(C.LengthX_over_delta), logical(C.IsCensored), ...
    logical(generated), string(reason), string(png), string(fig), ...
    'VariableNames', {'FrameOrdinal','FrameID','StructureID', ...
    'Sign','Connectivity','LengthTier', ...
    'LengthX_over_delta','IsCensored','Generated','Reason','PNG','FIG'});
end

function T = empty_manifest()
T = table(zeros(0,1,'uint32'),zeros(0,1,'uint32'), ...
    zeros(0,1,'uint32'),zeros(0,1,'int8'),zeros(0,1,'uint8'), ...
    zeros(0,1,'uint8'),zeros(0,1),false(0,1),false(0,1), ...
    strings(0,1),strings(0,1),strings(0,1), 'VariableNames', ...
    {'FrameOrdinal','FrameID','StructureID','Sign','Connectivity', ...
    'LengthTier','LengthX_over_delta', ...
    'IsCensored','Generated','Reason','PNG','FIG'});
end

function T = mark_generated(T, row, conn, tier, png, fig)
rows = T.FrameOrdinal == uint32(row.FrameOrdinal) & ...
    T.FrameID == uint32(row.FrameID) & ...
    T.StructureID == uint32(row.StructureID) & T.Sign == int8(row.Sign) & ...
    T.Connectivity == uint8(conn) & T.LengthTier == uint8(tier);
if any(rows)
    idx = find(rows,1);
    T.Generated(idx) = true;
    T.Reason(idx) = "generated";
    T.PNG(idx) = string(png);
    T.FIG(idx) = string(fig);
else
    T(end+1,:) = manifest_row(row,conn,tier,true,"generated",png,fig);
end
end

function T = mark_failed(T, row, conn, tier, message)
rows = T.FrameOrdinal == uint32(row.FrameOrdinal) & ...
    T.FrameID == uint32(row.FrameID) & ...
    T.StructureID == uint32(row.StructureID) & T.Sign == int8(row.Sign) & ...
    T.Connectivity == uint8(conn) & T.LengthTier == uint8(tier);
if any(rows)
    idx = find(rows,1);
    T.Reason(idx) = "export_failed: " + string(message);
end
end

function export_figure_pair(f, fig_file, png_file, dpi)
cleanup = onCleanup(@() close_figure_if_valid(f));
try
    savefig(f, fig_file);
    exportgraphics(f, png_file, 'Resolution', dpi);
catch problem
    delete_file_if_present(fig_file);
    delete_file_if_present(png_file);
    rethrow(problem);
end
close_figure_if_valid(f);
clear cleanup;
end

function close_figure_if_valid(f)
if ~isempty(f) && isgraphics(f)
    close(f);
end
end

function delete_file_if_present(filename)
if isfile(filename)
    delete(filename);
end
end

function clear_managed_outputs(png_root, fig_root, sheet_root)
patterns = {png_root, 'frame_*.png'; fig_root, 'frame_*.fig'; ...
    sheet_root, 'contact_sheet_timebin_*.png'; ...
    fig_root, 'contact_sheet_timebin_*.fig'};
for i = 1:size(patterns,1)
    listing = dir(fullfile(patterns{i,1}, patterns{i,2}));
    for j = 1:numel(listing)
        if ~listing(j).isdir
            delete(fullfile(listing(j).folder, listing(j).name));
        end
    end
end
end
