function result = streamwise_development_analysis(results, cfg)
%STREAMWISE_DEVELOPMENT_ANALYSIS Compact P18 links across Level-1 products.

if ~isfield(results, 'statistics') || isempty(results.statistics) || ...
        ~isfield(results, 'mean_bl') || isempty(results.mean_bl)
    error('tblR2:streamwise_development_analysis:MissingCoreResults', ...
        '沿程发展分析需要 statistics 和 mean_bl 结果。');
end
S = results.statistics;
M = results.mean_bl;
x = S.X(1, :);
Y_wall_mm = M.wall_distance_mm;
delta99 = interp1(M.boundary_layer.x, M.boundary_layer.delta99, ...
    x, 'linear', NaN);
mask = S.accepted_mask & isfinite(delta99) & delta99 > 0 & ...
    Y_wall_mm <= delta99;
development_options = struct('edge_buffer_columns', 2);
if isfield(cfg, 'streamwise_development') && ...
        ~isempty(cfg.streamwise_development)
    names = fieldnames(cfg.streamwise_development);
    for i = 1:numel(names)
        development_options.(names{i}) = ...
            cfg.streamwise_development.(names{i});
    end
end
streamwise_valid = true(1, numel(x));
edge_columns = development_options.edge_buffer_columns;
if edge_columns > 0
    streamwise_valid(1:min(edge_columns, numel(x))) = false;
    streamwise_valid(max(1, numel(x) - edge_columns + 1):end) = false;
end
mask(:, ~streamwise_valid) = false;

nonphase = struct();
nonphase.x_mm = x;
nonphase.streamwise_valid_mask = streamwise_valid;
nonphase.options = development_options;
nonphase.delta99_mm = delta99;
nonphase.u_rms = column_metrics(S.u_rms, mask);
nonphase.v_rms = column_metrics(S.v_rms, mask);
nonphase.negative_uv = column_metrics(S.uv_rey, mask);
nonphase.TKE = column_metrics(S.TKE, mask);
nonphase.structure_catalog = structure_summary();
nonphase.temporal_peak_scale = temporal_peak_summary();
nonphase.spatial_peak_scale = spatial_peak_summary();
nonphase.modal_streamwise = modal_summary();
nonphase.transport = transport_summary();
nonphase.correlation_links = correlation_link_summary();

if strcmp(cfg.case_type, 'controlled')
    if ~isfield(results, 'phase') || isempty(results.phase)
        error('tblR2:streamwise_development_analysis:MissingPhase', ...
        'controlled 沿程发展分析需要原生相对相位结果。');
    end
    harmonic = tblR2.harmonic_analysis( ...
        results.phase, cfg, S, M);
    names = fieldnames(harmonic);
    for i = 1:numel(names)
        result.(names{i}) = harmonic.(names{i});
    end
    result.coherent_response = coherent_summary(results.phase);
    result.harmonic_status = 'computed_from_native_relative_phase';
else
    result.harmonic_number = [];
    result.frequency_hz = [];
    result.harmonic_status = 'not_applicable_to_baseline';
    result.coherent_response = [];
end
result.nonphase = nonphase;
result.missing_optional_inputs = missing_optional();
result.definition = ['P18 streamwise handoff links non-phase turbulence, ' ...
    'quadrant/production, structure, temporal/spatial scale, modal, and ' ...
    'correlation (P16) summaries. Controlled cases additionally retain ' ...
    'f0/2f0/3f0 native-phase maps. No formation/decay zone is named ' ...
    'automatically without a declared classification threshold.'];

    function mapped = column_metrics(field, valid)
        values = double(field);
        values(~valid) = NaN;
        mapped = struct( ...
            'peak', max(values, [], 1, 'omitnan'), ...
            'wall_normal_mean', mean(values, 1, 'omitnan'), ...
            'valid_row_count', sum(isfinite(values), 1));
    end

    function summary = structure_summary()
        summary = table();
        if ~isfield(results, 'structures') || isempty(results.structures) || ...
                isempty(results.structures.catalog)
            return;
        end
        T = results.structures.catalog;
        edges = [-Inf, 0.5 .* (x(1:end - 1) + x(2:end)), Inf];
        bin = discretize(T.CentroidX_mm, edges);
        keep = isfinite(bin);
        bin = bin(keep);
        T = T(keep, :);
        count = accumarray(bin, 1, [numel(x), 1], @sum, 0);
        lsm = accumarray(bin, double(T.IsLSM), [numel(x), 1], @sum, 0);
        vlsm = accumarray(bin, double(T.IsVLSM), [numel(x), 1], @sum, 0);
        mean_length = accumarray(bin, T.LengthX_over_delta, ...
            [numel(x), 1], @(v) mean(v, 'omitnan'), NaN);
        mean_area = accumarray(bin, T.Area_over_delta2, ...
            [numel(x), 1], @(v) mean(v, 'omitnan'), NaN);
        summary = table(x(:), count, lsm, vlsm, mean_length, mean_area, ...
            'VariableNames', {'X_mm', 'StructureCount', 'LSMCount', ...
            'VLSMCount', 'MeanLengthXOverDelta', 'MeanAreaOverDelta2'});
    end

    function summary = temporal_peak_summary()
        summary = struct();
        if ~isfield(results, 'temporal') || isempty(results.temporal)
            return;
        end
        branches = fieldnames(results.temporal);
        for ib = 1:numel(branches)
            value = results.temporal.(branches{ib});
            requested = cfg.spatial.selected_y_plus(:);
            rows = zeros(numel(requested), 1);
            for iy = 1:numel(rows)
                [~, rows(iy)] = min(abs(value.y_plus - requested(iy)));
            end
            peak_frequency = nan(numel(rows), numel(value.x_columns));
            peak_lambda_plus = nan(size(peak_frequency));
            peak_level = nan(size(peak_frequency));
            for iy = 1:numel(rows)
                row = rows(iy);
                spectra = squeeze(double(value.phi_uu_by_x(row, :, :))) .* ...
                    value.frequency_hz;
                if isvector(spectra)
                    spectra = reshape(spectra, numel(value.frequency_hz), []);
                end
                [peak_level(iy, :), index] = max(spectra, [], 1, 'omitnan');
                peak_frequency(iy, :) = value.frequency_hz(index);
                peak_lambda_plus(iy, :) = value.lambda_x_plus( ...
                    sub2ind(size(value.lambda_x_plus), ...
                    repmat(row, 1, numel(index)), index));
            end
            summary.(branches{ib}) = struct( ...
                'x_mm', value.x_mm, ...
                'selected_y_plus_requested', requested, ...
                'selected_y_plus_actual', value.y_plus(rows), ...
                'peak_frequency_hz', peak_frequency, ...
                'peak_lambda_x_plus', peak_lambda_plus, ...
                'peak_f_phi_level', peak_level);
        end
    end

    function summary = spatial_peak_summary()
        summary = struct();
        if ~isfield(results, 'spatial') || isempty(results.spatial)
            return;
        end
        branches = fieldnames(results.spatial);
        for ib = 1:numel(branches)
            windows = results.spatial.(branches{ib}).windows;
            rows = cell(numel(windows), 1);
            for iw = 1:numel(windows)
                W = windows(iw);
                [level, index] = max(W.selected_curves, [], 2, 'omitnan');
                rows{iw} = table( ...
                    repmat(mean(W.actual_window_mm), numel(index), 1), ...
                    W.selected_y_plus_requested(:), ...
                    W.selected_y_plus_actual(:), ...
                    reshape(W.lambda_x_over_delta99_ref(index(:)), [], 1), ...
                    level(:), ...
                    'VariableNames', {'WindowCenterX_mm', 'RequestedYPlus', ...
                    'ActualYPlus', 'PeakLambdaXOverDelta99', 'PeakLevel'});
            end
            summary.(branches{ib}) = vertcat(rows{:});
        end
    end

    function summary = modal_summary()
        summary = struct();
        names = {'pod', 'dmd', 'spod'};
        for imethod = 1:numel(names)
            name = names{imethod};
            if ~isfield(results, name) || isempty(results.(name))
                continue;
            end
            branches = fieldnames(results.(name));
            for ib = 1:numel(branches)
                value = results.(name).(branches{ib});
                switch name
                    case 'pod'
                        modes = value.modes;
                        mode_index = 1;
                    case 'dmd'
                        [~, mode_index] = max(abs(value.amplitudes));
                        modes = value.modes;
                    otherwise
                        modes = value.selected_modes(1);
                        mode_index = 1;
                end
                U_mode = squeeze(modes.U(mode_index, :, :));
                V_mode = squeeze(modes.V(mode_index, :, :));
                envelope = sqrt(abs(U_mode) .^ 2 + abs(V_mode) .^ 2);
                summary.(name).(branches{ib}) = struct( ...
                    'x_mm', modes.X_mm(1, :), ...
                    'selected_mode_index', mode_index, ...
                    'wall_normal_rms_amplitude', ...
                    sqrt(mean(envelope .^ 2, 1, 'omitnan')));
            end
        end
    end

    function summary = transport_summary()
        summary = struct();
        if ~isfield(results, 'transport') || isempty(results.transport)
            return;
        end
        T = results.transport;
        summary.total_production = column_metrics( ...
            T.total.production_primary_fd, mask);
        probability = T.total.quadrant.probability;
        probability(:, :, :, ~any(mask, 1)) = NaN;
        summary.total_quadrant_probability_wall_normal_mean = ...
            squeeze(mean(probability, 3, 'omitnan'));
        if isfield(T, 'random_phase')
            random_mask = reshape(mask, 1, 1, size(mask, 1), size(mask, 2));
            cycle_probability = ...
                T.random_phase.quadrant.cycle_average.probability;
            cycle_probability(~repmat(random_mask, ...
                size(cycle_probability, 1), size(cycle_probability, 2), 1, 1)) = NaN;
            summary.random_cycle_Q2_Q4_probability_wall_normal_mean = ...
                squeeze(mean(cycle_probability, 3, 'omitnan'));
            phase_production = T.random_phase.production_primary_fd;
            summary.random_phase_production_wall_normal_mean = ...
                squeeze(mean(phase_production, 2, 'omitnan'));
        end
    end

    function summary = correlation_link_summary()
        summary = struct();
        if ~isfield(results, 'correlations') || isempty(results.correlations)
            return;
        end
        value = results.correlations;
        if ~isfield(value, 'total') || isempty(value.total)
            return;
        end
        total = value.total;
        if ~isfield(total, 'temporal') || isempty(total.temporal)
            return;
        end
        T = total.temporal;
        n_ref = numel(T);
        rows = struct('requested_point_mm', [], 'actual_point_mm', [], ...
            'integral_time_scale_s', [], 'ridge_convection_velocity_mps', []);
        rows = repmat(rows, n_ref, 1);
        for i = 1:n_ref
            rows(i).requested_point_mm = T(i).requested_point_mm;
            rows(i).actual_point_mm = T(i).actual_point_mm;
            rows(i).integral_time_scale_s = T(i).integral_time_scale_s;
            if isfield(total, 'space_time') && numel(total.space_time) >= i && ...
                    isfield(total.space_time(i), 'convection_velocity_ridge_mps')
                rows(i).ridge_convection_velocity_mps = ...
                    total.space_time(i).convection_velocity_ridge_mps;
            end
        end
        summary = struct('reference_points', rows, ...
            'definition', ['P16 temporal integral time scale and space-time ' ...
            'ridge convection velocity per declared correlation reference point, ' ...
            'linked into the P18 streamwise handoff without re-reading the cache.']);
    end

    function summary = coherent_summary(P)
        phase_mean_energy = squeeze(mean(P.coherent_TKE, 1, 'omitnan'));
        phase_mean_energy(~mask) = NaN;
        integrated = nan(1, numel(x));
        height90 = nan(1, numel(x));
        for ix = 1:numel(x)
            valid = isfinite(phase_mean_energy(:, ix));
            if nnz(valid) < 2
                continue;
            end
            y = Y_wall_mm(valid, ix);
            energy = phase_mean_energy(valid, ix);
            cumulative = cumtrapz(y, energy);
            integrated(ix) = cumulative(end);
            if cumulative(end) > 0
                index = find(cumulative >= 0.9 .* cumulative(end), 1);
                height90(ix) = y(index);
            end
        end
        summary = struct('x_mm', x, ...
            'phase_mean_coherent_TKE_integral', integrated, ...
            'coherent_energy_height90_mm', height90, ...
            'height_definition', ...
            'wall-normal height containing 90% of phase-mean coherent TKE');
    end

    function names = missing_optional()
        expected = {'structures', 'transport', 'temporal', 'spatial', ...
            'pod', 'dmd', 'spod', 'correlations'};
        names = cell(0, 1);
        for i = 1:numel(expected)
            if ~isfield(results, expected{i}) || isempty(results.(expected{i}))
                names{end + 1, 1} = expected{i}; %#ok<AGROW>
            end
        end
    end
end
