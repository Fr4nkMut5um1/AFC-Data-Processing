function [stats, phase] = transport_statistics(cache_file, cfg)
%TRANSPORT_STATISTICS Source-consistent, repeat-centered Section 5 moments.
% All population moments share the admitted paired U/V sample support.
% Phase products are averaged within repeats before sample-weighted pooling.
if ~(isstruct(cfg) && isscalar(cfg))
    error('tblR2:transport_statistics:InvalidConfig', 'cfg must be a scalar struct.');
end
t = option(cfg, 'transport', struct());
if ~(isstruct(t) && isscalar(t))
    error('tblR2:transport_statistics:InvalidConfig', 'cfg.transport must be a scalar struct.');
end
source = text_option(option(t, 'source', 'raw'), {'raw', 'postproc'}, 'source');
mode = text_option(option(t, 'frame_mode', ...
    option(cfg, 'statistics_frame_mode', 'all')), ...
    {'all', 'first_half', 'second_half'}, 'frame_mode');
case_type = text_option(option(cfg, 'case_type', 'baseline'), ...
    {'baseline', 'controlled'}, 'case_type');
controlled = strcmp(case_type, 'controlled');
chunk_frames = option(cfg, 'chunk_frames', 128);
positive_integer(chunk_frames, 'chunk_frames');
min_fraction = option(cfg, 'min_valid_fraction', 0);
if ~(isnumeric(min_fraction) && isscalar(min_fraction) && isfinite(min_fraction) && ...
        min_fraction >= 0 && min_fraction <= 1)
    error('tblR2:transport_statistics:InvalidConfig', 'min_valid_fraction must be in [0,1].');
end
cache = matfile(cache_file);
names = {'U', 'V', 'sampleValid', 'X', 'Y', 'h_mm', 'cache_meta'};
for k = 1:numel(names)
    if isempty(whos(cache, names{k}))
        error('tblR2:transport_statistics:MissingCacheVariable', ...
            'Cache is missing %s.', names{k});
    end
end
meta = cache.cache_meta;
if ~isstruct(meta) || ~isscalar(meta) || ~isfield(meta, 'source_role') || ...
        ~strcmp(meta.source_role, source)
    error('tblR2:transport_statistics:SourceMismatch', ...
        'cache_meta.source_role must match cfg.transport.source (%s).', source);
end
if isfield(meta, 'case_id') && isfield(cfg, 'case_id') && ...
        ~strcmp(meta.case_id, cfg.case_id)
    error('tblR2:transport_statistics:CaseMismatch', 'Cache case_id does not match cfg.case_id.');
end
info = whos(cache, 'U');
dims = info.size;
dims(end+1:3) = 1;
N = dims(1); J = dims(2); I = dims(3);
if numel(dims) > 3 || N < 1 || ~isequal(size(cache.X), [J I]) || ...
        ~isequal(size(cache.Y), [J I])
    error('tblR2:transport_statistics:GridSizeMismatch', 'Cache grid dimensions do not match U.');
end
for name = {'V', 'sampleValid'}
    item = whos(cache, name{1});
    shape = item.size; shape(end+1:3) = 1;
    if ~isequal(shape, dims)
        error('tblR2:transport_statistics:GridSizeMismatch', 'U/V/sampleValid must have identical sizes.');
    end
end
h = double(cache.h_mm);
if ~(isscalar(h) && isfinite(h) && h > 0)
    error('tblR2:transport_statistics:InvalidSpacing', 'h_mm must be finite and positive.');
end
boundaries = option(meta, 'repeat_boundaries', []);
if ~isempty(boundaries) && ~(isnumeric(boundaries) && isvector(boundaries) && ...
        all(isfinite(boundaries)) && all(boundaries == fix(boundaries)) && ...
        all(boundaries >= 1 & boundaries < N) && all(diff(boundaries(:)) > 0))
    error('tblR2:transport_statistics:InvalidRepeatBoundaries', ...
        'repeat_boundaries must be increasing integer end frames strictly inside the cache.');
end
boundaries = double(boundaries(:).');
R = numel(boundaries) + 1;
edges = [0 boundaries N];
repeat = ones(N, 1);
for r = 2:R
    repeat(edges(r)+1:edges(r+1)) = r;
end
range = option(t, 'frame_range', []);
if isempty(range)
    range = [1 N];
    if ~strcmp(mode, 'all')
        if R < 2
            error('tblR2:transport_statistics:MissingRepeatBoundaries', ...
                'first_half/second_half require cache repeat boundaries.');
        end
        r = 1 + strcmp(mode, 'second_half');
        range = [edges(r)+1 edges(r+1)];
    end
end
if ~(isnumeric(range) && isvector(range) && numel(range) == 2 && ...
        all(isfinite(range)) && all(range == fix(range)) && ...
        range(1) >= 1 && range(2) <= N && range(1) <= range(2))
    error('tblR2:transport_statistics:InvalidFrameRange', 'frame_range must be [first last] inside the cache.');
end
frame_ids = (double(range(1)):double(range(2))).';
B = 1; minimum = 1; phase = [];
bins = ones(N, 1);
if controlled
    if ~isfield(cfg, 'phase') || ~isstruct(cfg.phase) || ~isscalar(cfg.phase) || ...
            ~isfield(cfg, 'fs') || ~isfield(cfg.phase, 'f0_hz') || ...
            ~isfield(cfg.phase, 'n_bins') || ~isfield(cfg.phase, 'minimum_samples_per_bin')
        error('tblR2:transport_statistics:InvalidPhaseConfig', 'Controlled statistics require phase frequencies, bins and minimum samples.');
    end
    B = cfg.phase.n_bins;
    positive_integer(B, 'phase.n_bins');
    minimum = cfg.phase.minimum_samples_per_bin;
    positive_integer(minimum, 'phase.minimum_samples_per_bin');
    assignment = tblR2.assign_phase((1:N)', cfg.fs, cfg.phase.f0_hz, ...
        B, option(cfg.phase, 'phi0_user_deg', []));
    bins = assignment.bin_index;
end

raw_count = zeros(R, B, J, I);
sum_u = zeros(R, B, J, I);
sum_v = zeros(R, B, J, I);
for first = range(1):chunk_frames:range(2)
    ids = first:min(range(2), first+chunk_frames-1);
    chunk = tblR2.read_cache_chunk(cache_file, ids, 1:J, 1:I, 'raw');
    for r = unique(repeat(ids)).'
        for b = unique(bins(ids)).'
            sel = repeat(ids) == r & bins(ids) == b;
            if ~any(sel); continue; end
            valid = chunk.sampleValid(sel, :, :);
            U = chunk.U(sel, :, :); V = chunk.V(sel, :, :);
            U(~valid) = 0; V(~valid) = 0;
            raw_count(r,b,:,:) = raw_count(r,b,:,:) + reshape(sum(valid,1), [1 1 J I]);
            sum_u(r,b,:,:) = sum_u(r,b,:,:) + reshape(sum(U,1), [1 1 J I]);
            sum_v(r,b,:,:) = sum_v(r,b,:,:) + reshape(sum(V,1), [1 1 J I]);
        end
    end
end
support = raw_count >= minimum;
count_rep = raw_count;
count_rep(~support) = 0;
sum_u(~support) = 0; sum_v(~support) = 0;
mean_phase_u = observed_ratio(sum_u, count_rep);
mean_phase_v = observed_ratio(sum_v, count_rep);
time_count = sum(count_rep, 2);
mean_time_u = observed_ratio(sum(sum_u, 2), time_count);
mean_time_v = observed_ratio(sum(sum_v, 2), time_count);
repeat_means = nan(2, R, J, I);
repeat_means(1,:,:,:) = reshape(mean_time_u, [1 R J I]);
repeat_means(2,:,:,:) = reshape(mean_time_v, [1 R J I]);
count = reshape(sum(sum(count_rep, 1), 2), [J I]);
phase_count = reshape(sum(count_rep, 1), [B J I]);
total_uu = zeros(B,J,I); total_vv = zeros(B,J,I); total_uv = zeros(B,J,I);
random_uu = zeros(B,J,I); random_vv = zeros(B,J,I); random_uv = zeros(B,J,I);
coherent_uu = zeros(B,J,I); coherent_vv = zeros(B,J,I); coherent_uv = zeros(B,J,I);

% Center the raw values before multiplying; never subtract large raw moments.
for first = range(1):chunk_frames:range(2)
    ids = first:min(range(2), first+chunk_frames-1);
    chunk = tblR2.read_cache_chunk(cache_file, ids, 1:J, 1:I, 'raw');
    for r = unique(repeat(ids)).'
        for b = unique(bins(ids)).'
            sel = repeat(ids) == r & bins(ids) == b;
            if ~any(sel); continue; end
            valid = chunk.sampleValid(sel,:,:) & reshape(support(r,b,:,:), [1 J I]);
            U = chunk.U(sel,:,:); V = chunk.V(sel,:,:);
            tu = reshape(mean_time_u(r,1,:,:), [1 J I]);
            tv = reshape(mean_time_v(r,1,:,:), [1 J I]);
            pu = reshape(mean_phase_u(r,b,:,:), [1 J I]);
            pv = reshape(mean_phase_v(r,b,:,:), [1 J I]);
            u = U-tu; v = V-tv; ur = U-pu; vr = V-pv;
            u(~valid) = 0; v(~valid) = 0;
            ur(~valid) = 0; vr(~valid) = 0;
            total_uu(b,:,:) = total_uu(b,:,:) + sum(u.^2,1);
            total_vv(b,:,:) = total_vv(b,:,:) + sum(v.^2,1);
            total_uv(b,:,:) = total_uv(b,:,:) + sum(u.*v,1);
            random_uu(b,:,:) = random_uu(b,:,:) + sum(ur.^2,1);
            random_vv(b,:,:) = random_vv(b,:,:) + sum(vr.^2,1);
            random_uv(b,:,:) = random_uv(b,:,:) + sum(ur.*vr,1);
            cu = pu-tu; cv = pv-tv;
            cu(~reshape(support(r,b,:,:), [1 J I])) = 0;
            cv(~reshape(support(r,b,:,:), [1 J I])) = 0;
            n = sum(valid,1);
            coherent_uu(b,:,:) = coherent_uu(b,:,:) + n.*cu.^2;
            coherent_vv(b,:,:) = coherent_vv(b,:,:) + n.*cv.^2;
            coherent_uv(b,:,:) = coherent_uv(b,:,:) + n.*cu.*cv;
        end
    end
end
stats = global_moments(total_uu, total_vv, total_uv, count, J, I);
stats.X = double(cache.X); stats.Y = double(cache.Y); stats.h = h;
stats.Uavex = observed_ratio(reshape(sum(sum(sum_u,1),2), [J I]), count);
stats.Vavex = observed_ratio(reshape(sum(sum(sum_v,1),2), [J I]), count);
stats.accepted_mask = count >= 2 & count ./ numel(frame_ids) >= min_fraction;
stats.raw_valid_count = reshape(sum(sum(raw_count,1),2), [J I]);
stats.repeat_means = repeat_means;
stats.repeat_boundaries = boundaries;
stats.frame_ids = frame_ids;
stats.n_frames = numel(frame_ids);
stats.valid_fraction = count ./ numel(frame_ids);
stats.source_role = source;
stats.frame_mode = mode;
stats.raw_count_rep = raw_count;
stats.accepted_count_rep = count_rep;
stats.definition = 'Paired valid samples; admitted repeat/phase bins; repeat-centered population moments.';
if isfield(meta, 'case_id'); stats.case_id = meta.case_id; end
fields = {'Uavex', 'Vavex', 'uu_rey', 'vv_rey', 'uv_rey', 'u_rms', 'v_rms'};
for k = 1:numel(fields)
    value = stats.(fields{k}); value(~stats.accepted_mask) = NaN;
    stats.(fields{k}) = value;
end
if controlled
    stats.support_rep_bin = support;
    stats.bin_index = bins;
    phase = struct();
    phase.assignment = assignment;
    phase.repeat_boundaries = boundaries;
    phase.U_phase_rep = mean_phase_u; phase.V_phase_rep = mean_phase_v;
    phase.U_phase = observed_ratio(reshape(sum(sum_u,1), [B J I]), phase_count);
    phase.V_phase = observed_ratio(reshape(sum(sum_v,1), [B J I]), phase_count);
    phase.count = phase_count;
    phase.total_uv_phase = -observed_ratio(total_uv, phase_count);
    phase.total_uu_phase = observed_ratio(total_uu, phase_count);
    phase.total_vv_phase = observed_ratio(total_vv, phase_count);
    phase.random_uv_phase = -observed_ratio(random_uv, phase_count);
    phase.random_uu_phase = observed_ratio(random_uu, phase_count);
    phase.random_vv_phase = observed_ratio(random_vv, phase_count);
    phase.random_u_rms_phase = sqrt(phase.random_uu_phase);
    phase.random_v_rms_phase = sqrt(phase.random_vv_phase);
    phase.coherent_uv = observed_ratio(coherent_uv, phase_count);
    phase.random_global = global_moments(random_uu, random_vv, random_uv, count, J, I);
    phase.coherent_global = global_moments(coherent_uu, coherent_vv, coherent_uv, count, J, I);
    phase.raw_count_rep = raw_count;
    phase.accepted_count_rep = count_rep;
    phase.support_rep_bin = support;
    phase.accepted_mask = phase_count > 0;
    phase.source_role = source;
    phase.frame_ids = frame_ids;
    fields = {'U_phase_rep', 'V_phase_rep', 'U_phase', 'V_phase', ...
        'total_uv_phase', 'total_uu_phase', 'total_vv_phase', ...
        'random_uv_phase', 'random_uu_phase', 'random_vv_phase', ...
        'random_u_rms_phase', 'random_v_rms_phase', 'coherent_uv'};
    for k = 1:numel(fields)
        phase.(fields{k}) = mask_spatial(phase.(fields{k}), stats.accepted_mask);
    end
    phase.accepted_mask = phase.accepted_mask & reshape(stats.accepted_mask, [1 J I]);
    fields = {'uu_rey', 'vv_rey', 'uv_rey', 'u_rms', 'v_rms'};
    for k = 1:numel(fields)
        phase.random_global.(fields{k}) = mask_spatial( ...
            phase.random_global.(fields{k}), stats.accepted_mask);
        phase.coherent_global.(fields{k}) = mask_spatial( ...
            phase.coherent_global.(fields{k}), stats.accepted_mask);
    end
end
end

function value = mask_spatial(value, accepted)
shape = size(value);
value = reshape(value, [], numel(accepted));
value(:, ~accepted(:)) = NaN;
value = reshape(value, shape);
end

function value = option(s, name, fallback)
if isfield(s, name); value = s.(name); else; value = fallback; end
end

function value = text_option(value, choices, name)
if ~(ischar(value) && isrow(value)) && ~(isstring(value) && isscalar(value))
    error('tblR2:transport_statistics:InvalidConfig', '%s must be scalar text.', name);
end
value = char(value);
if ~ismember(value, choices)
    error('tblR2:transport_statistics:InvalidConfig', 'Invalid %s: %s.', name, value);
end
end

function positive_integer(value, name)
if ~(isnumeric(value) && isscalar(value) && isfinite(value) && value >= 1 && value == fix(value))
    error('tblR2:transport_statistics:InvalidConfig', '%s must be a finite positive integer.', name);
end
end

function value = observed_ratio(numerator, count)
value = numerator ./ max(count, 1);
value(count == 0) = NaN;
end

function result = global_moments(uu, vv, uv, count, J, I)
result = struct();
result.uu_rey = observed_ratio(reshape(sum(uu,1), [J I]), count);
result.vv_rey = observed_ratio(reshape(sum(vv,1), [J I]), count);
result.uv_rey = -observed_ratio(reshape(sum(uv,1), [J I]), count);
result.u_rms = sqrt(result.uu_rey); result.v_rms = sqrt(result.vv_rey);
result.valid_count = count;
end
