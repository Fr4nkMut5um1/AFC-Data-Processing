function result = pod_cluster_analysis(cache_file, cfg, stats, phase_stats, ...
    mean_bl, gaussian_structures)
%POD_CLUSTER_ANALYSIS Full-resolution POD denoising for LSM/VLSM connectivity.
%
% This extension deliberately leaves tandem_baseline_r2_case.m and its
% Gaussian Section-4 artifact unchanged.  It reuses the legacy-equivalent
% snapshot POD, POD reconstruction, and signed connectivity functions.

validate_inputs(cfg, stats, mean_bl);
preflight = tblR2.pod_cluster_memory_preflight(cfg, stats, mean_bl);
guard_enabled = ~isfield(cfg.pod_cluster, 'memory_guard') || ...
    ~isfield(cfg.pod_cluster.memory_guard, 'enabled') || ...
    logical(cfg.pod_cluster.memory_guard.enabled);
if guard_enabled && ~preflight.sufficient
    error('tblR2:pod_cluster_analysis:InsufficientMemory', ...
        ['精确全帧、[1 1] snapshot POD 预计峰值 %.2f GiB，当前 MATLAB ' ...
        '可用 %.2f GiB（最大单数组 %.2f GiB，需求 %.2f GiB）。' ...
        '未降低空间/时间/数值精度，已在分解前停止；请在更大内存机器运行。'], ...
        preflight.estimated_peak_gib, preflight.available_gib, ...
        preflight.max_array_gib, preflight.largest_double_array_gib);
end
sequence = tblR2.build_pod_cluster_sequence(cache_file, cfg, stats, ...
    phase_stats, mean_bl);

result = struct();
result.schema_version = 1;
result.memory_preflight = preflight;
result.precision_contract = ['All available frames, spatial_stride=[1 1], ' ...
    'no spatial interpolation or reduced-precision cluster grid.'];
result.threshold_contract = ['All primary Raw/Gaussian/POD branches use the ' ...
    'same original statistics.u_rms field and physical thresholds. POD-own-RMS ' ...
    'results are separately labelled sensitivity products.'];
result.raw = tblR2.cluster_raw_sequence(cache_file, cfg, stats, phase_stats, ...
    sequence, 'Raw');
result.gaussian = gaussian_branch(gaussian_structures, sequence);

result.pod = process_family(sequence, 'POD');
if cfg.pod_cluster.gaussian_then_pod.enabled
    gaussian_sequence = tblR2.gaussian_pod_sequence(cache_file, cfg, stats, ...
        phase_stats, mean_bl, sequence);
    result.gaussian_then_pod = process_family(gaussian_sequence, 'Gaussian_POD');
else
    result.gaussian_then_pod = struct('enabled', false, ...
        'status', 'disabled_by_default', ...
        'definition', 'Optional Gaussian -> POD sensitivity; no POD -> Gaussian branch.');
end

result.fixed_n_recommendation = fixed_n_recommendation( ...
    result.pod.ELF_POD.selection.valid, result.pod.POD_E90, ...
    result.pod.POD_E95, cfg.pod_cluster.fixed_n_stability);
result.branch_summary = summarize_primary_branches(result);
result.scope = ['POD-reconstructed instantaneous u'' only enters signed 2-D ' ...
    'cluster-connectivity LSM/VLSM identification. Existing Gaussian Q2/Q4 ' ...
    'products are untouched; no POD-Q2/Q4 product is computed.'];
result.references = struct( ...
    'pod_error_minimization', 'Raiola et al. (2015), doi:10.1007/s00348-015-1940-8', ...
    'elf_denoising', 'Brindise and Vlachos (2017), doi:10.1007/s00348-017-2320-3', ...
    'lsm_pod_context', 'Shehzad et al. (2021), doi:10.1016/j.expthermflusci.2021.110469');

    function family = process_family(local_sequence, prefix)
        % The mode count equals the snapshot count so ELF can select genuinely
        % non-contiguous modes.  The function is the same exact snapshot POD
        % used by Comparison_Re30w_AoA2.m; no randomized replacement is used.
        ref = tblR2.pod.snapshot_decomposition(local_sequence.X, ...
            size(local_sequence.X, 2));
        pod_result = struct( ...
            'joint_modes', ref.modes, ...
            'temporal_coefficients', ref.coefficients.', ...
            'mean_snapshot', ref.mean_snapshot, ...
            'sampling', local_sequence.sampling);
        energy = tblR2.select_energy_modes(ref.lambda_all, ...
            cfg.pod_cluster.energy_targets);
        elf = tblR2.elf_mode_selection(ref.modes, local_sequence, ...
            cfg.pod_cluster.elf);

        family = struct();
        family.definition = ref.definition;
        family.sampling = local_sequence.sampling;
        family.lambda_all = ref.lambda_all;
        family.energy_selection = energy;
        family.ELF_POD = struct('selection', elf, 'status', 'invalid_fail_closed');
        if elf.valid
            family.ELF_POD = tblR2.cluster_pod_reconstruction( ...
                cache_file, cfg, stats, phase_stats, mean_bl, local_sequence, ...
                pod_result, elf.mode_indices, [prefix '_ELF']);
            family.ELF_POD.selection = elf;
            family.ELF_POD.status = 'completed';
        end
        labels = {'E80','E90','E95'};
        for i = 1:numel(labels)
            field = [prefix '_' labels{i}];
            branch = tblR2.cluster_pod_reconstruction(cache_file, cfg, stats, ...
                phase_stats, mean_bl, local_sequence, pod_result, ...
                1:energy.n_modes(i), field);
            branch.energy_target = energy.targets(i);
            branch.achieved_energy = energy.achieved_energy(i);
            family.(['POD_' labels{i}]) = branch;
        end
    end
end

function validate_inputs(cfg, stats, mean_bl)
if ~isfield(cfg, 'pod_cluster') || ~isstruct(cfg.pod_cluster)
    error('tblR2:pod_cluster_analysis:MissingConfig', ...
        '缺少 cfg.pod_cluster 配置。');
end
required = {'pod','energy_targets','elf','chunk_frames', ...
    'gaussian_then_pod','fixed_n_stability'};
missing = required(~isfield(cfg.pod_cluster, required));
if ~isempty(missing)
    error('tblR2:pod_cluster_analysis:MissingConfig', ...
        'cfg.pod_cluster 缺少字段：%s。', strjoin(missing, ', '));
end
if isempty(stats) || isempty(mean_bl)
    error('tblR2:pod_cluster_analysis:MissingInputs', ...
        'POD 聚类需要 statistics 和 mean_bl。');
end
end

function branch = gaussian_branch(existing, sequence)
branch = struct('status', 'unavailable', 'name', 'Gaussian');
if isempty(existing) || ~isstruct(existing) || ~isfield(existing, 'catalog')
    branch.reason = 'Existing Section-4 Gaussian structure artifact was not supplied.';
    return;
end
catalog = existing.catalog;
if ~isempty(catalog) && ismember('Branch', catalog.Properties.VariableNames)
    catalog = catalog(strcmp(catalog.Branch, 'total'), :);
    catalog.Branch = repmat({'Gaussian'}, height(catalog), 1);
end
if ~isempty(catalog) && ~ismember('RMSBasis', catalog.Properties.VariableNames)
    catalog = addvars(catalog, repmat({'raw_u_rms'}, height(catalog), 1), ...
        'After', 'Branch', 'NewVariableNames', 'RMSBasis');
end
branch = tblR2.catalog_branch_metrics(catalog, sequence.frame_ids, ...
    nnz(sequence.spatial_mask), 'Gaussian', 'raw_u_rms');
branch.status = 'reused_existing_section4_artifact';
branch.name = 'Gaussian';
branch.definition = ['Independent existing Section-4 branch: PostProc physical ' ...
    'instantaneous -> ordinary Gaussian -> subtract mean -> connectivity.'];
end

function recommendation = fixed_n_recommendation(elf_valid, e90, e95, opts)
comparison = compare_branches(e90.primary, e95.primary, opts);
recommendation = struct();
recommendation.triggered = ~elf_valid;
recommendation.elf_valid = elf_valid;
recommendation.stability = comparison;
recommendation.recommended = ~elf_valid && comparison.stable;
if recommendation.recommended
    recommendation.N = e90.n_modes;
    recommendation.message = sprintf([ ...
        'ELF invalid; E90 and E95 structures are stable, so fixed leading ' ...
        'N=N90=%d is recommended.'], e90.n_modes);
elseif ~elf_valid
    recommendation.N = NaN;
    recommendation.message = ['ELF invalid and E90/E95 structures are not stable; ' ...
        'do not recommend a fixed N. Increase snapshots and inspect PIV/mask quality.'];
else
    recommendation.N = NaN;
    recommendation.message = ['ELF is valid; fixed-N advice is retained only as a ' ...
        'documented contingency and is not activated.'];
end
end

function comparison = compare_branches(a, b, opts)
ma = a.frame_metrics; mb = b.frame_metrics;
scalar_names = {'LSMCount','VLSMCount','OccupiedAreaFraction', ...
    'MedianLengthXOverDelta','P90LengthXOverDelta'};
relative = nan(numel(scalar_names), 1);
value_a = nan(numel(scalar_names), 1);
value_b = nan(numel(scalar_names), 1);
for k = 1:numel(scalar_names)
    value_a(k) = mean(ma.(scalar_names{k}), 'omitnan');
    value_b(k) = mean(mb.(scalar_names{k}), 'omitnan');
    relative(k) = relative_difference(value_a(k), value_b(k));
end
cdf_difference = empirical_cdf_difference(a.length_cdf, b.length_cdf);
comparison = struct();
comparison.scalar = table(scalar_names(:), value_a, value_b, relative, ...
    'VariableNames', {'Metric','E90','E95','RelativeChange'});
comparison.cdf_max_difference = cdf_difference;
comparison.scalar_tolerance = opts.scalar_relative_tolerance;
comparison.cdf_tolerance = opts.cdf_max_difference;
comparison.stable = all(relative <= opts.scalar_relative_tolerance) && ...
    cdf_difference <= opts.cdf_max_difference;
end

function value = relative_difference(a, b)
if isnan(a) || isnan(b)
    value = Inf;
elseif a == 0 && b == 0
    value = 0;
else
    value = abs(a - b) / max([abs(a), abs(b), eps]);
end
end

function difference = empirical_cdf_difference(a, b)
if a.n == 0 && b.n == 0
    difference = 0;
    return;
elseif a.n == 0 || b.n == 0
    difference = 1;
    return;
end
grid = unique([a.x(:); b.x(:)]);
Fa = arrayfun(@(x) nnz(a.x <= x) / a.n, grid);
Fb = arrayfun(@(x) nnz(b.x <= x) / b.n, grid);
difference = max(abs(Fa - Fb));
end

function summary = summarize_primary_branches(result)
names = {'Raw','Gaussian','ELF_POD','POD_E80','POD_E90','POD_E95'};
sources = {result.raw, result.gaussian, result.pod.ELF_POD, ...
    result.pod.POD_E80, result.pod.POD_E90, result.pod.POD_E95};
rows = cell(numel(names), 1);
for k = 1:numel(names)
    source = sources{k};
    available = isstruct(source) && isfield(source, 'primary') && ...
        isfield(source.primary, 'frame_metrics');
    if strcmp(names{k}, 'Raw') || strcmp(names{k}, 'Gaussian')
        available = isstruct(source) && isfield(source, 'frame_metrics');
        if available; metrics = source.frame_metrics; catalog = source.catalog; end
    elseif available
        metrics = source.primary.frame_metrics; catalog = source.primary.catalog;
    end
    if available
        rows{k} = table(names(k), true, mean(metrics.LSMCount, 'omitnan'), ...
            mean(metrics.VLSMCount, 'omitnan'), ...
            mean(metrics.OccupiedAreaFraction, 'omitnan'), ...
            median_finite(catalog, 0.50), median_finite(catalog, 0.90), ...
            'VariableNames', {'Branch','Available','MeanLSMCountPerFrame', ...
            'MeanVLSMCountPerFrame','MeanOccupiedAreaFraction', ...
            'MedianLengthXOverDelta','P90LengthXOverDelta'});
    else
        rows{k} = table(names(k), false, NaN, NaN, NaN, NaN, NaN, ...
            'VariableNames', {'Branch','Available','MeanLSMCountPerFrame', ...
            'MeanVLSMCountPerFrame','MeanOccupiedAreaFraction', ...
            'MedianLengthXOverDelta','P90LengthXOverDelta'});
    end
end
summary = vertcat(rows{:});
end

function value = median_finite(catalog, probability)
if isempty(catalog) || height(catalog) == 0
    value = NaN;
    return;
end
values = sort(double(catalog.LengthX_over_delta));
values = values(isfinite(values));
if isempty(values); value = NaN; return; end
position = 1 + (numel(values) - 1) * probability;
lo = floor(position); hi = ceil(position);
if lo == hi; value = values(lo); else
    value = values(lo) + (position - lo) * (values(hi) - values(lo));
end
end
