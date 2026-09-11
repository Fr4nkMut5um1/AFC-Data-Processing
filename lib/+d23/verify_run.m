function acceptance = verify_run(run_dir)
%VERIFY_RUN Independently verify a completed Deshpande experiment bundle.
manifest_data = load(fullfile(run_dir, 'manifest.mat'), 'manifest');
result_data = load(fullfile(run_dir, 'mat', 'final_results.mat'), ...
    'context', 'statistics', 'detection_statistics', ...
    'detection_rms_profile', 'frame_summary', 'frame_performance', ...
    'ss_catalog', 'censored_ss_catalog', 'catalog_index', 'noss_pairs', ...
    'conditional_spectra', 'gallery_selection', ...
    'connectivity_length_distribution', 'connectivity_comparison', ...
    'summary', 'config');
checkpoint_data = load(fullfile(run_dir, 'checkpoints', ...
    'detection_checkpoint.mat'), 'checkpoint');
manifest = manifest_data.manifest;
result = result_data;
checkpoint = checkpoint_data.checkpoint;

checks = struct();
checks.manifest_complete = strcmp(manifest.state, 'COMPLETE');
checks.preprocessing_contract = verify_preprocessing_contract(result);
checks.spatial_exclusion_contract = verify_spatial_exclusion_contract(result);
checks.detection_statistics_contract = verify_detection_statistics(result);
checks.statistics_uses_12000 = result.statistics.n_frames == 12000;
checks.execution_uses_12000 = height(result.frame_performance) == 12000;
checks.frame_ordinals_exact = isequal(double(result.frame_performance.FrameOrdinal(:)), ...
    (1:12000).');
checks.frame_ids_exact = isequal(double(result.frame_performance.FrameID(:)), ...
    result.context.frame_ids);
checks.frame_summary_rows = height(result.frame_summary) == 4 * 12000;
checks.frame_summary_coverage = isequal( ...
    unique(double(result.frame_summary.FrameOrdinal(:))), (1:12000).');
checks.batch_count = height(result.catalog_index) == 250;
checks.batch_frame_count = all(result.catalog_index.FrameCount == 48);
checks.batch_bounds_contiguous = isequal( ...
    double(result.catalog_index.FirstFrameOrdinal(:)), (1:48:11953).') && ...
    isequal(double(result.catalog_index.LastFrameOrdinal(:)), (48:48:12000).');
checks.catalog_row_total = sum(double(result.catalog_index.CatalogRowCount)) == ...
    result.summary.frames.catalog_rows;
checks.checkpoint_complete = strcmp(checkpoint.state, 'COMPLETE') && ...
    isequal(double(checkpoint.completed_batches(:)), (1:250).') && ...
    checkpoint.last_committed_selected_index == 12000;
checks.batch_files_exist = all(isfile(result.catalog_index.MatFile)) && ...
    all(isfile(result.catalog_index.CsvFile));
checks.batch_metadata_match = verify_batch_metadata(result.catalog_index, ...
    manifest.config_hash, manifest.source_fingerprint);

checks.ss_schema_consistent = isequal(result.ss_catalog.Properties.VariableNames, ...
    d23.empty_catalog().Properties.VariableNames);
checks.ss_all_pass_primary_length = all(result.ss_catalog.IsSS3 & ...
    result.ss_catalog.PassLength3 & result.ss_catalog.PassWallLower & ...
    result.ss_catalog.PassWallUpper);
checks.per_sign_ss_nonoverlap = verify_per_sign_nonoverlap(result.ss_catalog);
checks.edge_rejected_not_primary = ...
    ~ismember('RejectedByStreamwiseEdge', result.ss_catalog.Properties.VariableNames) || ...
    ~any(result.ss_catalog.IsSS3 & result.ss_catalog.RejectedByStreamwiseEdge);
checks.censored_partition = height(result.censored_ss_catalog) == ...
    nnz(result.ss_catalog.IsCensored);
checks.summary_counts_match = verify_summary_counts(result);
checks.connectivity_comparison_match = verify_connectivity_comparison(result);

[pair_geometry_ok, pair_obstacle_ok] = verify_pairs(result.noss_pairs, ...
    result.ss_catalog, result.context.cache_size(3));
checks.noss_same_size_and_height = pair_geometry_ok;
checks.noss_avoids_all_primary_ss = pair_obstacle_ok;
checks.noss_pair_ids_unique = numel(unique(result.noss_pairs.PairID)) == ...
    height(result.noss_pairs);

spectra = result.conditional_spectra.spectra_table;
checks.spectrum_count_nan_contract = all( ...
    isfinite(spectra.SSPremultiplied(spectra.EnsembleCount > 0))) && ...
    all(isfinite(spectra.NoSSPremultiplied(spectra.EnsembleCount > 0))) && ...
    all(isnan(spectra.SSPremultiplied(spectra.EnsembleCount == 0))) && ...
    all(isnan(spectra.NoSSPremultiplied(spectra.EnsembleCount == 0)));
selection = result.gallery_selection;
expected = d23.optional_artifact_contract(selection, ...
    result.conditional_spectra);
checks.spectrum_energy_rows = height(result.conditional_spectra.energy_table) == ...
    expected.energy_row_count;
checks.spectrum_pair_denominators = all( ...
    result.conditional_spectra.energy_table.PairCount <= nnz(result.noss_pairs.Matched));

checks.gallery_has_30_slots = height(selection) == 30;
not_selected = ~selection.Selected;
checks.gallery_selection_is_explicit = ...
    all(selection.SelectionReason(selection.Selected) ~= "") && ...
    all(selection.SelectionReason(not_selected) == "no_unused_complete_ss_object") && ...
    all(selection.FrameOrdinal(not_selected) == 0) && ...
    all(selection.FrameID(not_selected) == 0) && ...
    all(selection.ComponentID(not_selected) == 0) && ...
    all(isnan(selection.Lx_over_delta(not_selected)));
checks.gallery_objects_unique = gallery_objects_unique(selection);
checks.gallery_catalog_reconstructable = verify_gallery(selection, result.ss_catalog);
checks.gallery_png_count = numel(dir(fullfile(run_dir, 'png', 'gallery', ...
    'slot_*.png'))) == expected.selected_gallery_count;
checks.contact_sheet_png_count = numel(dir(fullfile(run_dir, 'png', ...
    'contact_sheets', 'contact_sheet_timebin_*.png'))) == ...
    expected.contact_sheet_count;
checks.summary_png_count = numel(dir(fullfile(run_dir, 'png', ...
    'summary_*.png'))) == expected.summary_plot_count;
checks.fig_count = numel(dir(fullfile(run_dir, 'fig', '*.fig'))) == ...
    expected.fig_count;
checks.gallery_figure_style = verify_gallery_figure_style( ...
    run_dir, selection, result.config);

checks.compact_csv_match = verify_compact_csv(run_dir, result);
names = fieldnames(checks);
values = false(numel(names), 1);
for i = 1:numel(names)
    values(i) = islogical(checks.(names{i})) && isscalar(checks.(names{i})) && ...
        checks.(names{i});
end
acceptance = struct('schema_version', 1, 'run_dir', run_dir, ...
    'verified_utc', d23.utc_now(), 'checks', checks, ...
    'check_names', {names}, 'check_values', values, ...
    'passed_count', nnz(values), 'check_count', numel(values), ...
    'all_passed', all(values));
d23.atomic_save(fullfile(run_dir, 'mat', 'acceptance.mat'), ...
    struct('acceptance', acceptance));
d23.atomic_write_text(fullfile(run_dir, 'json', 'acceptance.json'), ...
    jsonencode(acceptance, 'PrettyPrint', true));
d23.atomic_write_text(fullfile(run_dir, 'md', 'acceptance.md'), ...
    acceptance_markdown(acceptance));
if ~acceptance.all_passed
    failed = names(~values);
    error('d23:verify_run:AcceptanceFailed', ...
        'Acceptance failed: %s', strjoin(failed, ', '));
end
end

function ok = verify_preprocessing_contract(result)
cfg = result.config;
stats = result.detection_statistics;
ok = ~cfg.preprocessing.gaussian.enabled;
if cfg.preprocessing.pod.enabled
    pod = cfg.preprocessing.pod;
    ok = ok && strcmp(char(pod.rank.kind), 'energy_fraction') && ...
        isfinite(pod.rank.value) && abs(double(pod.rank.value) - 0.5) < 1e-12 && ...
        isfinite(pod.min_valid_fraction) && pod.min_valid_fraction == 1 && ...
        strcmp(pod.rms_source, 'reconstruction') && ...
        strcmp(stats.field_source, 'PostProc-POD-E50');
else
    ok = ok && strcmp(stats.field_source, 'PostProc-direct');
end
end

function ok = verify_detection_statistics(result)
stats = result.detection_statistics;
ny = result.context.cache_size(2);
required = {'u_rms_y','postproc_u_rms_y', ...
    'postproc_same_domain_u_rms_y','rms_ratio_to_postproc_same_domain_y', ...
    'valid_count_y','rms_definition','field_source','pod_selected_rank', ...
    'pod_joint_energy_retained_fraction','u_energy_retained_fraction'};
ok = all(isfield(stats, required)) && numel(stats.u_rms_y) == ny && ...
    numel(stats.valid_count_y) == ny && height(result.detection_rms_profile) == ny;
if ~ok
    return;
end
active = double(stats.u_rms_y(:));
reference = double(stats.postproc_same_domain_u_rms_y(:));
ratio = double(stats.rms_ratio_to_postproc_same_domain_y(:));
valid_rows = double(stats.valid_count_y(:)) > 0;
ok = all(isfinite(active(valid_rows)) & active(valid_rows) >= 0) && ...
    all(isfinite(reference(valid_rows)) & reference(valid_rows) >= 0) && ...
    all(abs(ratio(valid_rows) - active(valid_rows) ./ reference(valid_rows)) < 1e-10);
if result.config.preprocessing.pod.enabled
    ok = ok && stats.pod_selected_rank > 0 && ...
        stats.pod_joint_energy_retained_fraction >= 0.5 && ...
        stats.pod_joint_energy_retained_fraction <= 1 && ...
        stats.u_energy_retained_fraction >= 0;
else
    ok = ok && stats.pod_selected_rank == 0 && ...
        isequaln(active, reference);
end
end

function ok = verify_spatial_exclusion_contract(result)
ctx = result.context;
cfg = result.config.preprocessing.spatial_exclusion;
active = d23.spatial_active_mask(ctx);
ok = isfield(ctx, 'spatial_exclusion') && ...
    logical(ctx.spatial_exclusion.enabled) == logical(cfg.enabled) && ...
    nnz(~active) == double(ctx.spatial_exclusion.excluded_grid_point_count);
if logical(cfg.enabled)
    ok = ok && nnz(~active) > 0 && ...
        all(~active(ctx.spatial_exclusion_mask)) && ...
        isequal(ctx.spatial_exclusion.mask_hash, ...
        d23.sha256_text(jsonencode(uint32(find(ctx.spatial_exclusion_mask)))));
else
    ok = ok && all(active, 'all');
end
end

function ok = verify_per_sign_nonoverlap(ss_catalog)
ok = true;
flags = {'IsSS3','IsSS3p8','IsSS4p5'};
for connectivity = [8 4]
    for k = 1:numel(flags)
        rows = ss_catalog.Connectivity == connectivity & ...
            ss_catalog.(flags{k}) & ~ss_catalog.IsCensored;
        T = ss_catalog(rows,:);
        if height(T) < 2, continue; end
        [~,~,group] = unique([double(T.FrameOrdinal), double(T.Sign)], 'rows');
        for g = 1:max(group)
            idx = find(group == g);
            for i = 1:numel(idx)-1
                for j = i+1:numel(idx)
                    a = idx(i); b = idx(j);
                    x_overlap = min(double(T.ColMax(a)), double(T.ColMax(b))) >= ...
                        max(double(T.ColMin(a)), double(T.ColMin(b)));
                    y_overlap = min(double(T.RowMax(a)), double(T.RowMax(b))) >= ...
                        max(double(T.RowMin(a)), double(T.RowMin(b)));
                    ok = ok && ~(x_overlap && y_overlap);
                end
            end
        end
    end
end
end

function ok = gallery_objects_unique(selection)
selected = selection(selection.Selected,:);
if isempty(selected)
    ok = true;
    return;
end
keys = [double(selected.FrameOrdinal), double(selected.ActualSign), ...
    double(selected.ComponentID)];
ok = size(unique(keys, 'rows'), 1) == height(selected);
end

function ok = verify_connectivity_comparison(result)
expected = d23.connectivity_comparison(result.ss_catalog, ...
    result.context, result.config);
actual = result.connectivity_comparison;
ok = isequaln(actual.summary_table, expected.summary_table) && ...
    isequaln(actual.frame_sign_table, expected.frame_sign_table) && ...
    isequaln(actual.paired_table, expected.paired_table) && ...
    isequaln(table2struct(actual.summary_table), ...
    result.summary.connectivity_frame_sign_comparison);
end

function ok = verify_gallery_figure_style(run_dir, selection, cfg)
selected = find(selection.Selected, 1, 'first');
if isempty(selected)
    ok = true;
    return;
end
row = selection(selected, :);
filename = fullfile(run_dir, 'fig', sprintf('slot_%02d_frame_%05d.fig', ...
    row.SlotID, row.FrameID));
ok = false;
if ~isfile(filename)
    return;
end
try
    fig = openfig(filename, 'invisible');
    cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
    images = findobj(fig, 'Type', 'Image');
    if isempty(images)
        return;
    end
    ax = ancestor(images(1), 'axes');
    cmap = colormap(fig);
    center = (size(cmap, 1) + 1) / 2;
    ok = isequal(size(cmap), [cfg.output.field_colormap_levels 3]) && ...
        mod(size(cmap,1), 2) == 1 && ...
        max(abs(cmap(center,:) - [1 1 1])) < 1e-14 && ...
        max(abs(double(ax.DataAspectRatio) - [1 1 1])) < 1e-12 && ...
        max(abs(double(ax.CLim) - double(cfg.output.field_clim))) < 1e-12;
catch
    ok = false;
end
end

function ok = verify_batch_metadata(index, config_hash, source_fingerprint)
ok = true;
for i = 1:height(index)
    loaded = load(char(index.MatFile(i)), 'batch_meta');
    meta = loaded.batch_meta;
    expected = double(index.FirstFrameOrdinal(i):index.LastFrameOrdinal(i)).';
    ok = ok && meta.batch_id == double(index.BatchID(i)) && ...
        isequal(double(meta.frame_ordinals(:)), expected) && ...
        meta.row_count == double(index.CatalogRowCount(i)) && ...
        strcmp(meta.config_hash, config_hash) && ...
        strcmp(meta.source_fingerprint, source_fingerprint);
    if ~ok
        return;
    end
end
end

function ok = verify_summary_counts(result)
ok = true;
thresholds = [3 3.8 4.5];
flag_names = {'IsSS3','IsSS3p8','IsSS4p5'};
slot = 0;
for connectivity = [8 4]
    for k = 1:3
        slot = slot + 1;
        item = result.summary.counts(slot);
        selected = result.ss_catalog.Connectivity == connectivity & ...
            result.ss_catalog.(flag_names{k});
        complete = selected & ~result.ss_catalog.IsCensored;
        ok = ok && item.connectivity == connectivity && ...
            item.length_threshold == thresholds(k) && ...
            item.all_ss == nnz(selected) && ...
            item.complete_ss == nnz(complete) && ...
            item.censored_ss == nnz(selected & result.ss_catalog.IsCensored) && ...
            item.positive_complete == nnz(complete & result.ss_catalog.Sign == 1) && ...
            item.negative_complete == nnz(complete & result.ss_catalog.Sign == -1) && ...
            item.frames_with_complete_ss == ...
            numel(unique(result.ss_catalog.FrameOrdinal(complete))) && ...
            item.touching_user_exclusion_complete == ...
            nnz(complete & result.ss_catalog.TouchesUserExclusion);
        if nnz(complete) > 0
            ok = ok && abs(item.touching_user_exclusion_fraction - ...
                nnz(complete & result.ss_catalog.TouchesUserExclusion) / ...
                nnz(complete)) < 1e-12;
        else
            ok = ok && isnan(item.touching_user_exclusion_fraction);
        end
    end
end
end

function [geometry_ok, obstacle_ok] = verify_pairs(pairs, ss_catalog, nx)
geometry_ok = true;
obstacle_ok = true;
obstacles = ss_catalog(ss_catalog.Connectivity == 8 & ss_catalog.IsSS3, :);
for i = 1:height(pairs)
    pair = pairs(i, :);
    if ~pair.Matched
        geometry_ok = geometry_ok && pair.NoSSColMin == 0 && ...
            pair.NoSSColMax == 0 && isnan(pair.CenterShift_cells);
        continue;
    end
    ss_width = double(pair.SSColMax - pair.SSColMin + 1);
    no_width = double(pair.NoSSColMax - pair.NoSSColMin + 1);
    geometry_ok = geometry_ok && ss_width == no_width && ...
        pair.NoSSColMin >= 1 && pair.NoSSColMax <= nx && ...
        pair.RowMin <= pair.RowMax;
    same_frame = obstacles.FrameOrdinal == pair.FrameOrdinal;
    frame_obstacles = obstacles(same_frame, :);
    for j = 1:height(frame_obstacles)
        y_overlap = pair.RowMin <= frame_obstacles.RowMax(j) && ...
            pair.RowMax >= frame_obstacles.RowMin(j);
        x_overlap = pair.NoSSColMin <= frame_obstacles.ColMax(j) && ...
            pair.NoSSColMax >= frame_obstacles.ColMin(j);
        obstacle_ok = obstacle_ok && ~(x_overlap && y_overlap);
    end
end
end

function ok = verify_gallery(selection, ss_catalog)
ok = true;
for i = find(selection.Selected).'
    row = selection(i, :);
    found = ss_catalog.Connectivity == 8 & ~ss_catalog.IsCensored & ...
        ss_catalog.FrameOrdinal == row.FrameOrdinal & ...
        ss_catalog.FrameID == row.FrameID & ss_catalog.Sign == row.ActualSign & ...
        ss_catalog.ComponentID == row.ComponentID & ...
        abs(ss_catalog.Lx_over_delta - row.Lx_over_delta) < 1e-12;
    ok = ok && nnz(found) == 1;
end
end

function ok = verify_compact_csv(run_dir, result)
contracts = {
    'frame_summary.csv', result.frame_summary;
    'frame_performance.csv', result.frame_performance;
    'ss_catalog.csv', result.ss_catalog;
    'censored_ss_catalog.csv', result.censored_ss_catalog;
    'noss_pairs.csv', result.noss_pairs;
    'conditional_spectra.csv', result.conditional_spectra.spectra_table;
    'large_scale_energy.csv', result.conditional_spectra.energy_table;
    'gallery_selection.csv', result.gallery_selection;
    'detection_rms_profile.csv', result.detection_rms_profile;
    'connectivity_frame_sign_comparison.csv', ...
        result.connectivity_comparison.frame_sign_table;
    'connectivity_paired_objects.csv', ...
        result.connectivity_comparison.paired_table;
    'connectivity_comparison_summary.csv', ...
        result.connectivity_comparison.summary_table;
    'connectivity_length_distribution.csv', ...
        result.connectivity_length_distribution.table
    };
ok = true;
for i = 1:size(contracts, 1)
    csv_value = readtable(fullfile(run_dir, 'csv', contracts{i,1}), ...
        'NumHeaderLines', 0);
    mat_value = contracts{i,2};
    ok = ok && height(csv_value) == height(mat_value) && ...
        isequal(csv_value.Properties.VariableNames, mat_value.Properties.VariableNames);
end
end

function text_value = acceptance_markdown(acceptance)
lines = ["# Full-run acceptance"; ""; ...
    sprintf('- Verified UTC: %s', acceptance.verified_utc); ...
    sprintf('- Result: **%s** (%d/%d checks passed)', ...
    pass_label(acceptance.all_passed), acceptance.passed_count, acceptance.check_count); ...
    ""; "| Check | Result |"; "|---|---|"];
for i = 1:acceptance.check_count
    lines(end+1) = sprintf('| %s | %s |', acceptance.check_names{i}, ...
        pass_label(acceptance.check_values(i))); %#ok<AGROW>
end
text_value = strjoin(lines, newline) + newline;
end

function value = pass_label(tf)
if tf
    value = 'PASS';
else
    value = 'FAIL';
end
end
