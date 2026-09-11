function denoise = pod_denoise_prepare(cache_file, cfg, stats, options)
%POD_DENOISE_PREPARE 全网格快照 POD 去噪基底：分解、定截断秩、缓存。
%
% 用途与 +tblR2/pod_cache.m 完全不同，不要混用：
%   - pod_cache      : 模态分析用。窄 ROI + spatial_stride，目的是看模态形状与能量谱。
%   - pod_denoise_*  : 结构识别去噪用。全网格全分辨率，目的是替代高斯预处理。
% 两者各自独立分解，互不依赖。本函数不读取也不写入 06_pod_analysis.mat。
%
% 方法（经典快照 POD，Sirovich 1987）：
%   1. 全网格构建脉动矩阵 Uf = [u'; v']，去掉全局集成均值 Um；
%   2. 时间相关矩阵 C = Uf'*Uf / n_spatial，eig(C) 取全部特征值；
%   3. 按 rank_method 定截断秩 r：
%      'gavish_donoho'  —— Gavish & Donoho (2014) 最优硬阈值。σ 未知时用
%                          τ = ω(β) · median(奇异值)，ω 由长宽比 β 决定；
%      'energy_fraction'—— 累计能量首次达到 energy_target 的阶数。
%   4. 只计算前 r 阶模态 Phi_trunc 与系数 A_trunc，避免 10 GB 级的全模态矩阵。
%
% 去均值口径：这里减的是**全局集成均值**（全部帧的时间平均），与参考实现
% Comparison_Re30w_AoA2.m 的 Section 11 一致。结构识别阶段仍按自己的分支
% 均值（repeat/phase）去均值，两者之差是 O(0.05 m/s) 的系统偏差，远小于
% α·u_rms 阈值，不影响连通判定。
%
% 参考文献：
%   Brindise & Vlachos (2017) Exp Fluids 58:28. POD truncation for PIV denoising.
%   Gavish & Donoho (2014) IEEE Trans Inf Theory 60(8):5040. Optimal hard threshold.
%
% 输入
%   cache_file : 序列缓存路径（01_sequence_cache.mat）。
%   cfg        : case 配置，需要 cfg.chunk_frames、cfg.total_frames。
%   stats      : 统计结果，需要 accepted_mask、X、Y。
%   options    : 结构体，字段见 default_options()。
%
% 输出 denoise 结构体
%   .Phi_trunc      [2*n_spatial × r]  截断后的空间模态（已归一化）
%   .A_trunc        [r × n_frames]     时间系数
%   .mean_snapshot  [2*n_spatial × 1]  全局集成均值
%   .spatial_mask   [J × I] logical    有效点掩膜
%   .rank           截断秩 r
%   .eigenvalues    全部特征值（降序）
%   .diagnostics    截断判据的中间量，供审计

if nargin < 4 || isempty(options)
    options = struct();
end
options = merge_options(default_options(), options);

% ---------------------------------------------------------------- 缓存复用
% 参数标定会对同一批帧反复调用结构识别，POD 分解只做一次，之后走缓存。
if ~isempty(options.cache_path) && isfile(options.cache_path) && options.use_cache
    loaded = load(options.cache_path, 'denoise');
    if isfield(loaded, 'denoise') && ...
            cache_is_compatible(loaded.denoise, cache_file, options)
        denoise = loaded.denoise;
        fprintf('[POD去噪] 命中缓存 rank=%d（%s），跳过分解。\n', ...
            denoise.rank, options.cache_path);
        return;
    end
    fprintf('[POD去噪] 缓存与当前参数不符，重新分解。\n');
end

% ------------------------------------------------------- 空间掩膜与帧列表
if ~isfield(stats, 'accepted_mask')
    error('tblR2:pod_denoise_prepare:MissingMask', ...
        'stats 缺少 accepted_mask，无法确定有效空间点。');
end
spatial_mask = logical(stats.accepted_mask);
[J, I] = size(spatial_mask);
linear_mask = spatial_mask(:);
n_spatial = nnz(linear_mask);
if n_spatial < 2
    error('tblR2:pod_denoise_prepare:EmptyMask', ...
        'accepted_mask 中没有有效空间点。');
end

frame_ids = options.frame_ids;
if isempty(frame_ids)
    frame_ids = 1:cfg.total_frames;
end
frame_ids = double(frame_ids(:).');
n_frames = numel(frame_ids);
if n_frames < 2
    error('tblR2:pod_denoise_prepare:TooFewFrames', ...
        'POD 去噪至少需要 2 帧，当前只有 %d 帧。', n_frames);
end

fprintf(['[POD去噪] 开始构建快照矩阵：全网格 %d×%d，有效点 %d，' ...
    '帧数 %d（自由度 %d）。\n'], J, I, n_spatial, n_frames, 2 * n_spatial);

% -------------------------------------------------------- 构建快照矩阵
% 分块读取，避免一次性把 12000 帧全部载入。single 存储把 10.4 GB 压到 5.2 GB，
% 后续 eig 前再按需转 double。
Uf = zeros(2 * n_spatial, n_frames, 'single');
batch = max(1, cfg.chunk_frames);
for first = 1:batch:n_frames
    local = first:min(n_frames, first + batch - 1);
    chunk = tblR2.read_cache_chunk(cache_file, frame_ids(local), ...
        1:J, 1:I, 'raw', [], []);
    U = reshape(chunk.U, numel(local), []);
    V = reshape(chunk.V, numel(local), []);
    U = U(:, linear_mask);
    V = V(:, linear_mask);
    % 掩膜内仍可能出现逐帧无效矢量。补 0 而非丢弃：丢弃会让每帧的自由度
    % 不一致，快照矩阵就不再是同一个空间上的采样。补 0 等价于把该点该帧
    % 的脉动当作均值，是模态分解里的标准处理。
    U(~isfinite(U)) = 0;
    V(~isfinite(V)) = 0;
    Uf(:, local) = single([U'; V']);
    if mod(first - 1, batch * 10) == 0
        fprintf('  读取进度 %d/%d 帧\n', local(end), n_frames);
    end
end

% ------------------------------------------------------------ 去集成均值
mean_snapshot = double(mean(Uf, 2));
Uf = Uf - single(mean_snapshot);

% ------------------------------------------ 时间相关矩阵与全量特征分解
fprintf('[POD去噪] 计算 %d×%d 时间相关矩阵…\n', n_frames, n_frames);
Uf = double(Uf);
C = (Uf' * Uf) / n_spatial;
C = (C + C') / 2;   % 强制对称，消除浮点累积的不对称，保证 eig 返回实特征值

fprintf('[POD去噪] 特征分解…\n');
[eig_vectors, eig_values] = eig(C);
clear C;
lambda = diag(eig_values);
[lambda, order] = sort(lambda, 'descend');
eig_vectors = eig_vectors(:, order);
clear eig_values;

% 去均值后秩上限是 n_frames-1；负特征值是浮点噪声，截断到 0。
lambda(lambda < 0) = 0;
max_rank = min(n_frames - 1, numel(lambda));
lambda = lambda(1:max_rank);
eig_vectors = eig_vectors(:, 1:max_rank);

% ------------------------------------------------------------- 定截断秩
[rank_r, rank_diag] = resolve_rank(lambda, n_spatial, n_frames, options);
fprintf('[POD去噪] 截断秩 r=%d（判据=%s，累计能量=%.2f%%）。\n', ...
    rank_r, options.rank_method, 100 * rank_diag.energy_at_rank);

% -------------------------------------------- 只计算截断范围内的模态
% 全部 n_frames 阶模态是 [2*n_spatial × n_frames]，12000 帧时 ~10 GB。
% 只算前 r 阶把它压到 [2*n_spatial × r]。
fprintf('[POD去噪] 计算前 %d 阶模态…\n', rank_r);
Phi_trunc = Uf * eig_vectors(:, 1:rank_r);
clear eig_vectors;
mode_norms = vecnorm(Phi_trunc, 2, 1);
% 零范数模态对应零特征值（数值退化），保留原向量避免 0/0 产生 NaN。
mode_norms(mode_norms < eps) = 1;
Phi_trunc = Phi_trunc ./ mode_norms;
A_trunc = Phi_trunc' * Uf;
clear Uf;

% -------------------------------------------------------------- 打包输出
denoise = struct();
denoise.Phi_trunc = Phi_trunc;
denoise.A_trunc = A_trunc;
denoise.mean_snapshot = mean_snapshot;
denoise.spatial_mask = spatial_mask;
denoise.grid_size = [J I];
denoise.n_spatial = n_spatial;
denoise.frame_ids = frame_ids(:);
denoise.rank = rank_r;
denoise.eigenvalues = lambda;
denoise.mode_norms = mode_norms(:);
denoise.rank_method = options.rank_method;
denoise.diagnostics = rank_diag;
denoise.source_cache = cache_file;
denoise.options = options;
denoise.definition = ['全网格快照 POD 去噪基底。瞬时场 = Phi_trunc*A_trunc(:,k) ' ...
    '+ mean_snapshot，散布回 spatial_mask 指定的网格点。' ...
    'mean_snapshot 是全局集成均值，与结构识别阶段的分支均值口径不同。'];

if ~isempty(options.cache_path) && options.write_cache
    cache_dir = fileparts(options.cache_path);
    if ~isempty(cache_dir) && ~isfolder(cache_dir)
        mkdir(cache_dir);
    end
    save(options.cache_path, 'denoise', '-v7.3');
    fprintf('[POD去噪] 基底已缓存到 %s\n', options.cache_path);
end
end

% =========================================================================
function opts = default_options()
opts = struct();
opts.rank_method = 'gavish_donoho';   % 'gavish_donoho' | 'energy_fraction'
opts.energy_target = 0.95;            % rank_method='energy_fraction' 时生效
opts.frame_ids = [];                  % 空表示用 1:cfg.total_frames
opts.cache_path = '';                 % 空表示不缓存
opts.use_cache = true;
opts.write_cache = true;
end

% =========================================================================
function opts = merge_options(opts, user)
fields = fieldnames(user);
for k = 1:numel(fields)
    if ~isfield(opts, fields{k})
        error('tblR2:pod_denoise_prepare:UnknownOption', ...
            '未知选项 %s。', fields{k});
    end
    opts.(fields{k}) = user.(fields{k});
end
if ~ismember(opts.rank_method, {'gavish_donoho', 'energy_fraction'})
    error('tblR2:pod_denoise_prepare:InvalidRankMethod', ...
        'rank_method 必须是 gavish_donoho 或 energy_fraction。');
end
if ~(isscalar(opts.energy_target) && opts.energy_target > 0 && ...
        opts.energy_target <= 1)
    error('tblR2:pod_denoise_prepare:InvalidEnergyTarget', ...
        'energy_target 必须落在 (0, 1]。');
end
end

% =========================================================================
function [rank_r, diag_out] = resolve_rank(lambda, n_spatial, n_frames, options)
%RESOLVE_RANK 按选定判据确定截断秩。
%
% 快照法的特征值 lambda 与数据矩阵奇异值 s 的关系：
%   C = Uf'*Uf / n_spatial，所以 lambda = s^2 / n_spatial，
%   即 s = sqrt(lambda * n_spatial)。
% Gavish-Donoho 阈值定义在奇异值上，必须先换算回 s 再比较。

total_energy = sum(lambda);
if total_energy <= 0
    error('tblR2:pod_denoise_prepare:ZeroEnergy', ...
        '特征值全为零，快照矩阵可能是常数场。');
end
cumulative = cumsum(lambda) / total_energy;
singular_values = sqrt(max(lambda, 0) * n_spatial);

diag_out = struct();
diag_out.total_energy = total_energy;
diag_out.cumulative_energy = cumulative;
diag_out.singular_values = singular_values;

switch options.rank_method
    case 'gavish_donoho'
        % 数据矩阵是 [m × n] = [2*n_spatial × n_frames]，m >> n，
        % 长宽比 beta = n/m ∈ (0,1]。
        m = 2 * n_spatial;
        n = n_frames;
        beta = min(m, n) / max(m, n);
        % σ 未知时的公式（Gavish & Donoho 2014, 式(11)）：
        %   tau = omega(beta) * median(singular values)
        % omega(beta) = lambda*(beta) / sqrt(mu_beta)，其中 mu_beta 是
        % Marchenko-Pastur 分布的中位数。用论文给出的多项式近似。
        omega = gavish_donoho_omega(beta);
        median_sv = median(singular_values(singular_values > 0));
        threshold = omega * median_sv;
        rank_r = sum(singular_values > threshold);
        diag_out.beta = beta;
        diag_out.omega = omega;
        diag_out.median_singular_value = median_sv;
        diag_out.threshold = threshold;

    case 'energy_fraction'
        rank_r = find(cumulative >= options.energy_target, 1, 'first');
        if isempty(rank_r)
            rank_r = numel(lambda);
        end
        diag_out.energy_target = options.energy_target;
end

rank_r = max(1, min(rank_r, numel(lambda)));
diag_out.rank = rank_r;
diag_out.energy_at_rank = cumulative(rank_r);
end

% =========================================================================
function omega = gavish_donoho_omega(beta)
%GAVISH_DONOHO_OMEGA 未知噪声水平下的阈值系数 ω(β)。
%
% 来自 Gavish & Donoho (2014) 的多项式近似（论文式 (5) 下方给出）：
%   omega(beta) ≈ 0.56*beta^3 - 0.95*beta^2 + 1.82*beta + 1.43
% β=1（方阵）时 omega ≈ 2.858，与论文摘要给出的常数一致，可作自检。

if ~(isscalar(beta) && beta > 0 && beta <= 1)
    error('tblR2:pod_denoise_prepare:InvalidBeta', ...
        '长宽比 beta 必须落在 (0, 1]，当前为 %g。', beta);
end
omega = 0.56 * beta^3 - 0.95 * beta^2 + 1.82 * beta + 1.43;
end

% =========================================================================
function tf = cache_is_compatible(cached, cache_file, options)
%CACHE_IS_COMPATIBLE 判断缓存的基底能否直接复用。
% 只要源缓存、帧集合或截断判据变了就必须重算——静默复用会让用户以为跑的是
% 新参数，实际用的是旧基底。

tf = false;
required = {'Phi_trunc', 'A_trunc', 'mean_snapshot', 'spatial_mask', ...
    'rank', 'source_cache', 'options', 'frame_ids'};
if ~all(isfield(cached, required))
    return;
end
if ~strcmp(cached.source_cache, cache_file)
    return;
end
if ~strcmp(cached.options.rank_method, options.rank_method)
    return;
end
if strcmp(options.rank_method, 'energy_fraction') && ...
        abs(cached.options.energy_target - options.energy_target) > 1e-12
    return;
end
expected_ids = options.frame_ids;
if ~isempty(expected_ids) && ...
        ~isequal(double(cached.frame_ids(:)), double(expected_ids(:)))
    return;
end
tf = true;
end
