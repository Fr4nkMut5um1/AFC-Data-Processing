function detection_stats = prepare_detection_statistics(ctx, stats, cfg, run_dir, pod_file)
%PREPARE_DETECTION_STATISTICS RMS threshold for the active fluctuation field.
final_file = fullfile(run_dir, 'mat', 'detection_statistics.mat');
config_hash = d23.config_hash(cfg);
if isfile(final_file)
    loaded = load(final_file, 'detection_stats', 'detection_stats_meta');
    meta = loaded.detection_stats_meta;
    if ~strcmp(meta.source_fingerprint, ctx.source_fingerprint) || ...
            ~strcmp(meta.config_hash, config_hash)
        error('d23:prepare_detection_statistics:ReuseMismatch', ...
            'Existing detection statistics do not match source/config.');
    end
    detection_stats = loaded.detection_stats;
    return;
end

if ~cfg.preprocessing.pod.enabled
    detection_stats = direct_statistics(ctx, stats, cfg);
else
    if isempty(pod_file) || ~isfile(pod_file)
        error('d23:prepare_detection_statistics:MissingPod', ...
            'POD reconstruction is required to compute the active-field RMS.');
    end
    detection_stats = pod_reconstruction_statistics( ...
        ctx, stats, cfg, pod_file);
end

detection_stats_meta = struct('schema_version', 1, ...
    'source_fingerprint', ctx.source_fingerprint, ...
    'config_hash', config_hash, 'cache_size', ctx.cache_size, ...
    'created_utc', d23.utc_now());
d23.atomic_save(final_file, struct('detection_stats', detection_stats, ...
    'detection_stats_meta', detection_stats_meta));
end

function value = pod_reconstruction_statistics(ctx, stats, cfg, pod_file)
nt = ctx.cache_size(1);
ny = ctx.cache_size(2);
nx = ctx.cache_size(3);
pod = matfile(pod_file);
sum_pod_y = zeros(ny, 1);
sum_direct_y = zeros(ny, 1);
count_y = zeros(ny, 1, 'uint64');
chunk_size = cfg.statistics.chunk_size;
for first = 1:chunk_size:nt
    ids = first:min(first + chunk_size - 1, nt);
    reconstructed = double(pod.Uprime(ids, :, :));
    source = d23.read_chunk(ctx.cache_file, ids);
    valid = source.valid & ...
        reshape(d23.spatial_active_mask(ctx), 1, ny, nx) & ...
        isfinite(reconstructed);
    direct = double(source.U) - reshape(stats.Ubar, 1, ny, nx);
    reconstructed(~valid) = 0;
    direct(~valid) = 0;
    sum_pod_y = sum_pod_y + ...
        reshape(sum(sum(reconstructed .^ 2, 1), 3), ny, 1);
    sum_direct_y = sum_direct_y + ...
        reshape(sum(sum(direct .^ 2, 1), 3), ny, 1);
    count_y = count_y + uint64(reshape(sum(sum(valid, 1), 3), ny, 1));
end
count_double = double(count_y);
u_rms_y = sqrt(sum_pod_y ./ count_double);
direct_same_domain = sqrt(sum_direct_y ./ count_double);
u_rms_y(count_double == 0) = NaN;
direct_same_domain(count_double == 0) = NaN;
ratio = u_rms_y ./ direct_same_domain;

meta_file = fullfile(fileparts(pod_file), 'pod_metadata.mat');
loaded = load(meta_file, 'pod_meta');
pod_meta = loaded.pod_meta;
eigenvalues = double(pod_meta.eigenvalues(:));
positive = eigenvalues > double(pod_meta.lambda_tolerance);
selected_rank = double(pod_meta.selected_rank);
joint_retained = sum(eigenvalues(1:selected_rank)) / sum(eigenvalues(positive));
u_retained = sum(sum_pod_y) / sum(sum_direct_y);

field_source = pod_field_source(cfg.preprocessing.pod.rank);
if strcmp(char(cfg.preprocessing.pod.rank.kind), 'energy_fraction')
    target_fraction = double(cfg.preprocessing.pod.rank.value);
else
    target_fraction = NaN;
end
retained_spatial_count = field_or(pod_meta, 'retained_spatial_count', 0);
retained_before_count = field_or(pod_meta, ...
    'retained_spatial_count_before_exclusion', retained_spatial_count);
excluded_retained_count = field_or(pod_meta, ...
    'excluded_retained_spatial_count', 0);
joint_dof_count = field_or(pod_meta, 'joint_dof_count', ...
    2 * retained_spatial_count);
value = struct( ...
    'schema_version', 1, ...
    'field_source', field_source, ...
    'u_rms_y', u_rms_y, ...
    'postproc_u_rms_y', stats.u_rms_y, ...
    'postproc_same_domain_u_rms_y', direct_same_domain, ...
    'rms_ratio_to_postproc_same_domain_y', ratio, ...
    'valid_count_y', count_y, ...
    'rms_definition', sprintf([ ...
    'pooled x,t RMS of %s fluctuations about the PostProc global Ubar(x,y)'], ...
    field_source), ...
    'pod_selected_rank', uint32(selected_rank), ...
    'pod_positive_rank', uint32(pod_meta.positive_rank), ...
    'pod_energy_target_fraction', target_fraction, ...
    'pod_joint_energy_retained_fraction', joint_retained, ...
    'u_energy_retained_fraction', u_retained, ...
    'pod_retained_spatial_count_before_exclusion', ...
    uint32(retained_before_count), ...
    'pod_retained_spatial_count', uint32(retained_spatial_count), ...
    'pod_excluded_retained_spatial_count', ...
    uint32(excluded_retained_count), ...
    'pod_joint_dof_count', uint32(joint_dof_count), ...
    'created_utc', d23.utc_now());
end

function value = direct_statistics(ctx, stats, cfg)
ny = ctx.cache_size(2);
nx = ctx.cache_size(3);
active = d23.spatial_active_mask(ctx);
if all(active, 'all')
    active_rms = stats.u_rms_y;
    count_y = stats.valid_count_y;
else
    sum_y = zeros(ny, 1);
    count_y = zeros(ny, 1, 'uint64');
    nt = ctx.cache_size(1);
    for first = 1:cfg.statistics.chunk_size:nt
        ids = first:min(first + cfg.statistics.chunk_size - 1, nt);
        source = d23.read_chunk(ctx.cache_file, ids);
        valid = source.valid & reshape(active, 1, ny, nx);
        direct = double(source.U) - reshape(stats.Ubar, 1, ny, nx);
        direct(~valid) = 0;
        sum_y = sum_y + reshape(sum(sum(direct .^ 2, 1), 3), ny, 1);
        count_y = count_y + uint64(reshape(sum(sum(valid, 1), 3), ny, 1));
    end
    active_rms = sqrt(sum_y ./ double(count_y));
    active_rms(count_y == 0) = NaN;
end
ratio = ones(size(active_rms));
ratio(~isfinite(active_rms)) = NaN;
value = struct( ...
    'schema_version', 1, 'field_source', 'PostProc-direct', ...
    'u_rms_y', active_rms, 'postproc_u_rms_y', stats.u_rms_y, ...
    'postproc_same_domain_u_rms_y', active_rms, ...
    'rms_ratio_to_postproc_same_domain_y', ratio, ...
    'valid_count_y', count_y, ...
    'rms_definition', ...
    ['pooled x,t RMS of PostProc fluctuations about global Ubar(x,y) ' ...
    'over the active Section-4 spatial domain'], ...
    'pod_selected_rank', uint32(0), 'pod_positive_rank', uint32(0), ...
    'pod_energy_target_fraction', 1, ...
    'pod_joint_energy_retained_fraction', 1, ...
    'u_energy_retained_fraction', 1, ...
    'pod_retained_spatial_count_before_exclusion', uint32(0), ...
    'pod_retained_spatial_count', uint32(0), ...
    'pod_excluded_retained_spatial_count', uint32(0), ...
    'pod_joint_dof_count', uint32(0), 'created_utc', d23.utc_now());
end

function value = field_or(input, name, fallback)
if isfield(input, name)
    value = input.(name);
else
    value = fallback;
end
end

function label = pod_field_source(rank_cfg)
kind = char(rank_cfg.kind);
if strcmp(kind, 'energy_fraction')
    percent = 100 * double(rank_cfg.value);
    if abs(percent - round(percent)) < 1e-12
        label = sprintf('PostProc-POD-E%d', round(percent));
    else
        label = sprintf('PostProc-POD-E%.6g', percent);
    end
else
    label = sprintf('PostProc-POD-N%d', double(rank_cfg.n));
end
end
