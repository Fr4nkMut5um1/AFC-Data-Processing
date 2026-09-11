function detection = run_detection(ctx, stats, detection_stats, cfg, run_dir, pod_file)
%RUN_DETECTION Serial 48-frame labeling with atomic batch checkpoint/resume.
if nargin < 5
    pod_file = '';
end
selected = double(cfg.execution.frame_ordinals(:));
if any(selected > ctx.cache_size(1))
    error('d23:run_detection:FrameRange', ...
        'An execution frame ordinal exceeds the cache size.');
end
batch_size = cfg.statistics.chunk_size;
n_batches = ceil(numel(selected) / batch_size);
config_hash = d23.config_hash(cfg);
checkpoint_file = fullfile(run_dir, 'checkpoints', 'detection_checkpoint.mat');
checkpoint = struct('schema_version', 1, 'state', 'RUNNING', ...
    'config_hash', config_hash, 'source_fingerprint', ctx.source_fingerprint, ...
    'completed_batches', zeros(0,1,'uint32'), ...
    'last_committed_selected_index', uint32(0), ...
    'updated_utc', d23.utc_now());
if isfile(checkpoint_file)
    loaded = load(checkpoint_file, 'checkpoint');
    checkpoint = loaded.checkpoint;
    if ~strcmp(checkpoint.config_hash, config_hash) || ...
            ~strcmp(checkpoint.source_fingerprint, ctx.source_fingerprint)
        error('d23:run_detection:ResumeMismatch', ...
            'Detection checkpoint contract changed.');
    end
end
index_rows = cell(n_batches, 1);
for batch_id = 1:n_batches
    first_selected = (batch_id - 1) * batch_size + 1;
    last_selected = min(batch_id * batch_size, numel(selected));
    ordinals = selected(first_selected:last_selected);
    batch_name = sprintf('batch_%04d', batch_id);
    mat_file = fullfile(run_dir, 'catalog_mat', [batch_name '.mat']);
    csv_file = fullfile(run_dir, 'catalog_csv', [batch_name '.csv']);
    if isfile(mat_file)
        loaded = load(mat_file, 'batch_meta', 'catalog', 'frame_summary', ...
            'frame_performance');
        validate_batch(loaded, ordinals, config_hash, ...
            ctx.source_fingerprint, batch_id);
        catalog = loaded.catalog;
        frame_summary = loaded.frame_summary;
        frame_performance = loaded.frame_performance;
        if cfg.output.write_catalog_csv && ~isfile(csv_file)
            d23.atomic_writetable(csv_file, catalog);
        end
    else
        chunk_timer = tic;
        fields = d23.fluctuation_chunk(ctx, stats, cfg, ordinals, pod_file);
        catalog_parts = cell(numel(ordinals) * 4, 1);
        summary_parts = cell(numel(ordinals) * 4, 1);
        elapsed = zeros(numel(ordinals), 1);
        component_count = zeros(numel(ordinals), 1, 'uint32');
        memory_used = nan(numel(ordinals), 1);
        part = 0;
        for local_frame = 1:numel(ordinals)
            frame_timer = tic;
            up = squeeze(fields.up(local_frame, :, :));
            valid = squeeze(fields.valid(local_frame, :, :));
            frame_ordinal = ordinals(local_frame);
            frame_id = ctx.frame_ids(frame_ordinal);
            for connectivity = cfg.detection.connectivities
                for sign_value = [1 -1]
                    part = part + 1;
                    item = d23.identify_frame(up, valid, detection_stats.u_rms_y, ...
                        frame_ordinal, frame_id, connectivity, sign_value, ctx, cfg);
                    catalog_parts{part} = item;
                    summary_parts{part} = d23.summarize_frame(item, ...
                        frame_ordinal, frame_id, sign_value, connectivity);
                    component_count(local_frame) = component_count(local_frame) + ...
                        uint32(height(item));
                end
            end
            elapsed(local_frame) = toc(frame_timer);
            if ismember(lower(cfg.execution.label), {'smoke','benchmark'})
                try
                    memory_info = memory;
                    memory_used(local_frame) = memory_info.MemUsedMATLAB;
                catch
                    memory_used(local_frame) = NaN;
                end
            end
        end
        catalog = vertcat(catalog_parts{:});
        frame_summary = vertcat(summary_parts{:});
        frame_performance = table(uint32(ordinals(:)), ...
            uint32(ctx.frame_ids(ordinals)), elapsed, component_count, memory_used, ...
            'VariableNames', {'FrameOrdinal','FrameID','Elapsed_s', ...
            'ComponentCount','MatlabMemoryBytes'});
        batch_meta = struct('schema_version', 1, 'batch_id', batch_id, ...
            'frame_ordinals', ordinals(:), ...
            'frame_ids', ctx.frame_ids(ordinals), 'config_hash', config_hash, ...
            'source_fingerprint', ctx.source_fingerprint, ...
            'row_count', height(catalog), 'elapsed_s', toc(chunk_timer), ...
            'created_utc', d23.utc_now());
        d23.atomic_save(mat_file, struct('batch_meta', batch_meta, ...
            'catalog', catalog, 'frame_summary', frame_summary, ...
            'frame_performance', frame_performance));
        if cfg.output.write_catalog_csv
            d23.atomic_writetable(csv_file, catalog);
        end
    end
    if cfg.output.write_catalog_csv && cfg.output.verify_catalog_csv
        csv_probe = readtable(csv_file, 'NumHeaderLines', 0);
        if height(csv_probe) ~= height(catalog) || ...
                ~isequal(csv_probe.Properties.VariableNames, ...
                catalog.Properties.VariableNames)
            error('d23:run_detection:CsvMismatch', ...
                'MAT/CSV catalog mismatch in batch %d.', batch_id);
        end
        clear csv_probe;
    end
    index_rows{batch_id} = table(uint32(batch_id), uint32(ordinals(1)), ...
        uint32(ordinals(end)), uint32(numel(ordinals)), uint64(height(catalog)), ...
        string(mat_file), string(csv_file), ...
        'VariableNames', {'BatchID','FirstFrameOrdinal','LastFrameOrdinal', ...
        'FrameCount','CatalogRowCount','MatFile','CsvFile'});
    if ~ismember(uint32(batch_id), checkpoint.completed_batches)
        checkpoint.completed_batches(end+1,1) = uint32(batch_id);
    end
    checkpoint.last_committed_selected_index = uint32(last_selected);
    checkpoint.updated_utc = d23.utc_now();
    d23.atomic_save(checkpoint_file, struct('checkpoint', checkpoint));
    if mod(batch_id, cfg.execution.progress_every_batches) == 0 || ...
            batch_id == n_batches
        fprintf('[d23] detection batch %d/%d committed (%d catalog rows).\n', ...
            batch_id, n_batches, height(catalog));
    end
    clear catalog frame_summary frame_performance;
end
checkpoint.state = 'COMPLETE';
checkpoint.updated_utc = d23.utc_now();
d23.atomic_save(checkpoint_file, struct('checkpoint', checkpoint));
catalog_index = vertcat(index_rows{:});
d23.atomic_writetable(fullfile(run_dir, 'csv', 'catalog_index.csv'), catalog_index);
detection = struct('catalog_index', catalog_index, 'checkpoint', checkpoint, ...
    'n_selected_frames', numel(selected), 'n_batches', n_batches);
end

function validate_batch(loaded, ordinals, config_hash, source_fingerprint, batch_id)
meta = loaded.batch_meta;
if meta.batch_id ~= batch_id || ...
        ~isequal(double(meta.frame_ordinals(:)), double(ordinals(:))) || ...
        ~strcmp(meta.config_hash, config_hash) || ...
        ~strcmp(meta.source_fingerprint, source_fingerprint)
    error('d23:run_detection:BatchMismatch', ...
        'Existing batch %d does not match the current run.', batch_id);
end
if ~istable(loaded.catalog) || ~istable(loaded.frame_summary) || ...
        ~istable(loaded.frame_performance) || ...
        ~isequal(loaded.catalog.Properties.VariableNames, ...
        d23.empty_catalog().Properties.VariableNames) || ...
        ~isequal(loaded.frame_summary.Properties.VariableNames, ...
        d23.empty_frame_summary().Properties.VariableNames) || ...
        height(loaded.catalog) ~= meta.row_count || ...
        height(loaded.frame_summary) ~= 4 * numel(ordinals) || ...
        height(loaded.frame_performance) ~= numel(ordinals) || ...
        ~isequal(double(loaded.frame_performance.FrameOrdinal(:)), ordinals(:)) || ...
        ~isequal(unique(double(loaded.frame_summary.FrameOrdinal(:))), ordinals(:)) || ...
        (~isempty(loaded.catalog) && ...
        any(~ismember(double(loaded.catalog.FrameOrdinal), ordinals)))
    error('d23:run_detection:BatchContentMismatch', ...
        'Existing batch %d has an invalid table schema, row count, or frame coverage.', ...
        batch_id);
end
end
