function phase_stats = phase_stats_cache(cache_file, cfg, stats)
%PHASE_STATS_CACHE 逐块计算受控工况的原生相位平均和三重分解。
% baseline 主脚本保留本阶段的完整编排，但通过 stages.phase='skip' 跳过调用。
% 受控工况将 stages.phase 设为 compute/reuse 后，Section 3-8 共用此结果合同。

if ~strcmp(cfg.case_type, 'controlled') || ...
        ~isfield(cfg, 'phase') || ~isfield(cfg.phase, 'enabled') || ...
        ~logical(cfg.phase.enabled)
    error('tblR2:phase_stats_cache:NotControlled', ...
        '相位统计只适用于启用相位处理的 controlled 工况。');
end
validate_phase_cfg(cfg.phase);
if ~isfield(stats, 'Uavex') || ~isfield(stats, 'Vavex')
    error('tblR2:phase_stats_cache:MissingStatistics', ...
        'phase 阶段需要 statistics.Uavex 和 statistics.Vavex。');
end

cache = matfile(cache_file);
missing = missing_cache_variables(cache, {'U', 'V', 'sampleValid', 'X', 'Y', 'h_mm'});
if ~isempty(missing)
    error('tblR2:phase_stats_cache:MissingCacheVariable', ...
        '序列缓存缺少相位统计所需变量：%s。', strjoin(missing, ', '));
end
item = whos(cache, 'U');
grid_size = size(cache.X);
grid_size(end + 1:2) = 1;
J = grid_size(1);
I = grid_size(2);
cache_size = item.size;
cache_size(end + 1:3) = 1;
n_frames = cache_size(1);
if cache_size(2) * cache_size(3) ~= J * I
    error('tblR2:phase_stats_cache:GridSizeMismatch', ...
        '序列缓存的 U 网格与 X/Y 网格尺寸不一致。');
end
n_bins = double(cfg.phase.n_bins);

% 读取双 repeat 元数据；没有元数据时退化为单序列处理。
frame_to_repeat = ones(n_frames, 1);
n_repeats = 1;
boundaries = [];
if ~isempty(whos(cache, 'cache_meta'))
    metadata = load(cache_file, 'cache_meta');
    cache_meta = metadata.cache_meta;
    if isfield(cache_meta, 'repeat_boundaries') && ...
            ~isempty(cache_meta.repeat_boundaries)
        boundaries = double(cache_meta.repeat_boundaries(:).');
        validate_repeat_boundaries(boundaries, n_frames);
        n_repeats = numel(boundaries) + 1;
        for r = 2:n_repeats
            frame_to_repeat(boundaries(r - 1) + 1:end) = r;
        end
    end
end

% 只用采样帧时钟分配相位，不从数据反推激励相位。
assignment = tblR2.assign_phase((1:n_frames)', cfg.fs, ...
    cfg.phase.f0_hz, n_bins, cfg.phase.phi0_user_deg);
bin_of_frame = assignment.bin_index;

% 第一遍：累计每个相位箱和每个网格点的有效样本数及速度和。
count = zeros(n_bins, J, I);
sum_u = zeros(n_bins, J, I);
sum_v = zeros(n_bins, J, I);
count_rep = zeros(n_repeats, n_bins, J, I);
sum_u_rep = zeros(n_repeats, n_bins, J, I);
sum_v_rep = zeros(n_repeats, n_bins, J, I);
for first = 1:cfg.chunk_frames:n_frames
    last = min(n_frames, first + cfg.chunk_frames - 1);
    ids = first:last;
    U = double(tblR2.read_cache_frames(cache, 'U', ids, J, I));
    V = double(tblR2.read_cache_frames(cache, 'V', ids, J, I));
    valid = logical(tblR2.read_cache_frames(cache, 'sampleValid', ids, J, I)) & ...
        isfinite(U) & isfinite(V);
    local_bins = bin_of_frame(ids);
    local_rep = frame_to_repeat(ids);
    for ib = unique(local_bins)'
        local = local_bins == ib;
        valid_bin = valid(local, :, :);
        U_bin = U(local, :, :);
        V_bin = V(local, :, :);
        U_bin(~valid_bin) = 0;
        V_bin(~valid_bin) = 0;
        count(ib, :, :) = count(ib, :, :) + ...
            reshape(sum(valid_bin, 1), [1 J I]);
        sum_u(ib, :, :) = sum_u(ib, :, :) + ...
            reshape(sum(U_bin, 1), [1 J I]);
        sum_v(ib, :, :) = sum_v(ib, :, :) + ...
            reshape(sum(V_bin, 1), [1 J I]);
        for r = 1:n_repeats
            local_rep_r = local & (local_rep == r);
            if ~any(local_rep_r)
                continue;
            end
            valid_rep = valid(local_rep_r, :, :);
            U_rep = U(local_rep_r, :, :);
            V_rep = V(local_rep_r, :, :);
            U_rep(~valid_rep) = 0;
            V_rep(~valid_rep) = 0;
            count_rep(r, ib, :, :) = count_rep(r, ib, :, :) + ...
                reshape(sum(valid_rep, 1), [1 1 J I]);
            sum_u_rep(r, ib, :, :) = sum_u_rep(r, ib, :, :) + ...
                reshape(sum(U_rep, 1), [1 1 J I]);
            sum_v_rep(r, ib, :, :) = sum_v_rep(r, ib, :, :) + ...
                reshape(sum(V_rep, 1), [1 1 J I]);
        end
    end
end

denominator = max(count, 1);
U_phase = sum_u ./ denominator;
V_phase = sum_v ./ denominator;
accepted = count >= cfg.phase.minimum_samples_per_bin;
U_phase(~accepted) = NaN;
V_phase(~accepted) = NaN;
u_coherent = U_phase - reshape(stats.Uavex, 1, J, I);
v_coherent = V_phase - reshape(stats.Vavex, 1, J, I);

% 双 repeat 使用各自相位均值计算随机支路，去除重复实验之间的系统偏移。
U_phase_rep = [];
V_phase_rep = [];
if n_repeats > 1
    U_phase_rep = zeros(n_repeats, n_bins, J, I);
    V_phase_rep = zeros(n_repeats, n_bins, J, I);
    for r = 1:n_repeats
        den_rep = max(count_rep(r, :, :, :), 1);
        mean_rep_u = sum_u_rep(r, :, :, :) ./ den_rep;
        mean_rep_v = sum_v_rep(r, :, :, :) ./ den_rep;
        accepted_rep = count_rep(r, :, :, :) >= ...
            cfg.phase.minimum_samples_per_bin;
        mean_rep_u(~accepted_rep) = NaN;
        mean_rep_v(~accepted_rep) = NaN;
        U_phase_rep(r, :, :, :) = mean_rep_u;
        V_phase_rep(r, :, :, :) = mean_rep_v;
    end
end

% 第二遍：累计相位随机二阶矩、总体随机矩和三重分解重构误差。
sum_uu = zeros(n_bins, J, I);
sum_vv = zeros(n_bins, J, I);
sum_uv = zeros(n_bins, J, I);
global_count = zeros(J, I);
global_uu = zeros(J, I);
global_vv = zeros(J, I);
global_uv = zeros(J, I);
triple_max_abs = 0;
for first = 1:cfg.chunk_frames:n_frames
    last = min(n_frames, first + cfg.chunk_frames - 1);
    ids = first:last;
    U = double(tblR2.read_cache_frames(cache, 'U', ids, J, I));
    V = double(tblR2.read_cache_frames(cache, 'V', ids, J, I));
    valid = logical(tblR2.read_cache_frames(cache, 'sampleValid', ids, J, I)) & ...
        isfinite(U) & isfinite(V);
    local_bins = bin_of_frame(ids);
    if n_repeats > 1
        local_rep = frame_to_repeat(ids);
        U_phi_frames = zeros(numel(ids), J, I);
        V_phi_frames = zeros(numel(ids), J, I);
        for r = 1:n_repeats
            selected = local_rep == r;
            if ~any(selected)
                continue;
            end
            % 先明确重塑为 [选中帧数,J,I]，避免 MATLAB 对 4-D 索引
            % 自动压缩 singleton 维度后在小网格或单帧分块上赋值失败。
            n_selected = nnz(selected);
            phase_u = U_phase_rep(r, local_bins(selected), :, :);
            phase_v = V_phase_rep(r, local_bins(selected), :, :);
            phase_u = reshape(phase_u, [n_selected, J, I]);
            phase_v = reshape(phase_v, [n_selected, J, I]);
            U_phi_frames(selected, :, :) = phase_u;
            V_phi_frames(selected, :, :) = phase_v;
        end
    else
        U_phi_frames = reshape(U_phase(local_bins, :, :), ...
            [numel(local_bins), J, I]);
        V_phi_frames = reshape(V_phase(local_bins, :, :), ...
            [numel(local_bins), J, I]);
    end
    u_random = U - U_phi_frames;
    v_random = V - V_phi_frames;
    valid = valid & isfinite(u_random) & isfinite(v_random);
    u_random(~valid) = 0;
    v_random(~valid) = 0;

    % 对双 repeat，逐帧相位均值与其相应的相干项共同构成精确重构。
    coherent_frame_u = U_phi_frames - reshape(stats.Uavex, 1, J, I);
    coherent_frame_v = V_phi_frames - reshape(stats.Vavex, 1, J, I);
    residual_u = (U - reshape(stats.Uavex, 1, J, I)) - ...
        (coherent_frame_u + u_random);
    residual_v = (V - reshape(stats.Vavex, 1, J, I)) - ...
        (coherent_frame_v + v_random);
    residual = [residual_u(valid); residual_v(valid)];
    if ~isempty(residual)
        triple_max_abs = max(triple_max_abs, max(abs(residual)));
    end

    global_count = global_count + reshape(sum(valid, 1), [J I]);
    global_uu = global_uu + reshape(sum(u_random .^ 2, 1), [J I]);
    global_vv = global_vv + reshape(sum(v_random .^ 2, 1), [J I]);
    global_uv = global_uv + reshape(sum(u_random .* v_random, 1), [J I]);
    for ib = unique(local_bins)'
        local = local_bins == ib;
        sum_uu(ib, :, :) = sum_uu(ib, :, :) + ...
            reshape(sum(u_random(local, :, :) .^ 2, 1), [1 J I]);
        sum_vv(ib, :, :) = sum_vv(ib, :, :) + ...
            reshape(sum(v_random(local, :, :) .^ 2, 1), [1 J I]);
        sum_uv(ib, :, :) = sum_uv(ib, :, :) + ...
            reshape(sum(u_random(local, :, :) .* v_random(local, :, :), 1), [1 J I]);
    end
end

random_uu_phase = sum_uu ./ denominator;
random_vv_phase = sum_vv ./ denominator;
random_uv_phase = -sum_uv ./ denominator;
random_uu_phase(~accepted) = NaN;
random_vv_phase(~accepted) = NaN;
random_uv_phase(~accepted) = NaN;

global_denominator = max(global_count, 1);
random_global = struct();
random_global.uu_rey = global_uu ./ global_denominator;
random_global.vv_rey = global_vv ./ global_denominator;
random_global.uv_rey = -global_uv ./ global_denominator;
random_global.uu_rey(global_count == 0) = NaN;
random_global.vv_rey(global_count == 0) = NaN;
random_global.uv_rey(global_count == 0) = NaN;
random_global.u_rms = sqrt(max(0, random_global.uu_rey));
random_global.v_rms = sqrt(max(0, random_global.vv_rey));
Uinf = 25;
if isfield(cfg, 'Uinf') && isscalar(cfg.Uinf) && isfinite(cfg.Uinf) && cfg.Uinf > 0
    Uinf = double(cfg.Uinf);
end
random_global.TKE = 0.5 .* (random_global.uu_rey + random_global.vv_rey) ./ (Uinf.^2);
random_global.valid_count = global_count;

coverage = struct();
coverage.total_valid_samples_per_bin = squeeze(sum(sum(count, 3), 2));
coverage.min_count_across_points = squeeze(min(min(count, [], 3), [], 2));
coverage.max_count_across_points = squeeze(max(max(count, [], 3), [], 2));
coverage.bins_accepted_everywhere = all(all(accepted, 3), 2);
coverage.cycles_covered = max(assignment.cycle_index);

phase_stats = struct();
phase_stats.assignment = assignment;
phase_stats.count = count;
phase_stats.U_phase = U_phase;
phase_stats.V_phase = V_phase;
phase_stats.u_coherent = u_coherent;
phase_stats.v_coherent = v_coherent;
phase_stats.coherent_uv = u_coherent .* v_coherent;
phase_stats.coherent_TKE = 0.5 .* (u_coherent.^2 + v_coherent.^2);
phase_stats.random_uu_phase = random_uu_phase;
phase_stats.random_vv_phase = random_vv_phase;
phase_stats.random_uv_phase = random_uv_phase;
phase_stats.random_u_rms_phase = sqrt(max(0, random_uu_phase));
phase_stats.random_v_rms_phase = sqrt(max(0, random_vv_phase));
phase_stats.random_global = random_global;
phase_stats.triple_reconstruction_max_abs_mps = triple_max_abs;
phase_stats.coverage = coverage;
phase_stats.X = double(cache.X);
phase_stats.Y = double(cache.Y);
phase_stats.h = double(cache.h_mm);
phase_stats.definition = ['u''=u-<u>=utilde+u''''; utilde=U_phi-<u>; ' ...
    'u''''=u-U_phi. 相位箱有效样本不足时对应结果为 NaN；相位仅由帧时钟分配。'];
if n_repeats > 1
    phase_stats.U_phase_rep = U_phase_rep;
    phase_stats.V_phase_rep = V_phase_rep;
    phase_stats.n_repeats = n_repeats;
    phase_stats.repeat_boundaries = boundaries;
else
    % 单序列缓存也显式提供该字段，令下游读取逻辑保持统一。
    phase_stats.U_phase_rep = [];
    phase_stats.V_phase_rep = [];
    phase_stats.n_repeats = 1;
    phase_stats.repeat_boundaries = [];
end
end

function validate_phase_cfg(phase)
if ~(isfield(phase, 'enabled') && isfield(phase, 'f0_hz') && ...
        isfield(phase, 'n_bins') && isfield(phase, 'phi0_user_deg') && ...
        isfield(phase, 'minimum_samples_per_bin'))
    error('tblR2:phase_stats_cache:MissingPhaseConfig', ...
        'cfg.phase 必须包含 enabled、f0_hz、n_bins、phi0_user_deg 和 minimum_samples_per_bin。');
end
if ~(isscalar(phase.f0_hz) && isfinite(phase.f0_hz) && phase.f0_hz > 0)
    error('tblR2:phase_stats_cache:InvalidF0', ...
        'cfg.phase.f0_hz 必须是有限正标量。');
end
if ~(isscalar(phase.n_bins) && phase.n_bins == fix(phase.n_bins) && phase.n_bins >= 2)
    error('tblR2:phase_stats_cache:InvalidBinCount', ...
        'cfg.phase.n_bins 必须是大于等于 2 的整数。');
end
if ~(isscalar(phase.minimum_samples_per_bin) && ...
        phase.minimum_samples_per_bin == fix(phase.minimum_samples_per_bin) && ...
        phase.minimum_samples_per_bin >= 1)
    error('tblR2:phase_stats_cache:InvalidMinimumSamples', ...
        'cfg.phase.minimum_samples_per_bin 必须是正整数。');
end
end

function missing = missing_cache_variables(cache, names)
missing = {};
for k = 1:numel(names)
    if isempty(whos(cache, names{k}))
        missing{end + 1} = names{k}; %#ok<AGROW>
    end
end
end

function validate_repeat_boundaries(boundaries, n_frames)
%VALIDATE_REPEAT_BOUNDARIES 检查缓存中的 repeat 分界是否可用于索引。
if ~(isvector(boundaries) && all(isfinite(boundaries)) && ...
        all(boundaries == fix(boundaries)) && ...
        all(boundaries >= 1) && all(boundaries < n_frames) && ...
        all(diff(boundaries) > 0))
    error('tblR2:phase_stats_cache:InvalidRepeatBoundaries', ...
        '序列缓存的 repeat 分界必须是 1 到总帧数-1 之间严格递增的整数。');
end
end
