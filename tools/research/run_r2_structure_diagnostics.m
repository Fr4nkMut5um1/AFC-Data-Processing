% Research utility with historical cache/parameter assumptions; see tools/README.md.
% Not a daily entry or formal Section 4 acceptance test. Runtime not revalidated.
%% run_r2_structure_diagnostics — 聚类联通法诊断扫描入口
% 两个独立阶段，均不改动正式识别逻辑，只读取已缓存数据并复跑识别：
%   Phase 1  percolation_sweep   逾渗主阈值 + 连通性 扫描
%   Phase 2  sensitivity_sweep   预处理 / 形态学 / seed 阈值 扫描
%
% 运行方式（MATLAB R2022b，batch 或交互式均可）：
%   >> run('tools/research/run_r2_structure_diagnostics.m')
%
% 输出：
%   cases/per_case/tandem_baseline_r2/output/mat/09d_percolation_sweep.mat
%   cases/per_case/tandem_baseline_r2/output/mat/09d_sensitivity_sweep.mat
%
% 注意：+package 目录本身不能进 path，其父目录必须进 path，因此这里只用
% 普通 addpath，绝不用 genpath（genpath 会把 +tblR2 目录直接加入并报错）。

base_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(base_dir, 'lib'));
addpath(fullfile(base_dir, 'tools/research/r2_diagnostics'));
addpath(base_dir);

mat_dir = fullfile(base_dir, 'cases/per_case/tandem_baseline_r2/output/mat');

% ------------------------- 阶段开关 -------------------------
run_phase1 = true;
run_phase2 = true;

% ------------------------- 帧抽样 -------------------------
% 在两个 repeat 内均匀抽样 480 帧。RNG 固定保证可复现。
rng(20260824);
n_repeat = 2;
n_per_repeat = 240;
frame_ids = [];
for r = 1:n_repeat
    lo = (r - 1) * 6000 + 1;
    hi = r * 6000;
    frame_ids = [frame_ids, sort(randperm(hi - lo + 1, n_per_repeat) + (lo - 1))]; %#ok<AGROW>
end
fprintf('抽样帧数：%d（每个 repeat %d 帧）\n', numel(frame_ids), n_per_repeat);

ctx = load_sweep_frames(mat_dir, frame_ids);

% ------------------------- Phase 1：逾渗扫描 -------------------------
% 在两种平滑水平下各跑一遍逾渗曲线：
%   as_cached  = 生产缓存实际生效的核（经实测为 sigma 0.8 / 3x3，
%                并非配置与 README 声称的 sigma 1.5 / 9x9）
%   intended   = 配置本意的 sigma 1.5 / 9x9
% 最优 alpha 依赖于其前置平滑强度，因此两者必须分开标定，不能混用。
if run_phase1
    fprintf('\n======== Phase 1：逾渗主阈值 + 连通性扫描 ========\n');

    variants = struct( ...
        'name', {'as_cached', 'intended_sigma1p5'}, ...
        'preprocess', {ctx.baseline_preprocess, ...
                       make_gaussian_spec(ctx.baseline_preprocess, 1.5, 4)});

    sweep1 = struct('variant', {}, 'result', {}, 'stability', {});
    for iv = 1:numel(variants)
        fprintf('\n-- 平滑变体：%s --\n', variants(iv).name);
        p1 = struct();
        p1.alphas         = 0.25:0.05:0.65;
        p1.seed_alphas    = 0.70;            % 锁定 seed，先孤立主阈值
        p1.connectivities = [4 8];
        p1.preprocess     = variants(iv).preprocess;
        p1.per_frame_field = 'preprocessed';

        tic;
        r = percolation_sweep(ctx, p1);
        el = toc;
        fprintf('   %s 用时 %.1f s\n', variants(iv).name, el);

        % 对每条 (seed, connectivity) 曲线沿 alpha 做 bootstrap 稳定区推断。
        % 必须按 alpha 排列成一行曲线，而不是把所有组合混在一起。
        stab = struct('connectivity', {}, 'seed_alpha', {}, ...
            'alphas', {}, 'stability', {});
        conns = unique(r.connectivity);
        seeds = unique(r.seed_alpha);
        for ic = 1:numel(conns)
            for is = 1:numel(seeds)
                sel = find(r.connectivity == conns(ic) & ...
                           r.seed_alpha == seeds(is));
                [av, ord] = sort(r.alpha(sel));
                sel = sel(ord);
                curve = zeros(ctx.n_frames, numel(sel));
                for jj = 1:numel(sel)
                    curve(:, jj) = r.per_frame{sel(jj)}.max_component_ratio;
                end
                bs = bootstrap_stability(curve, struct( ...
                    'n_boot', 500, 'ci_level', 0.95, ...
                    'max_rel_change', 0.10, 'min_run', 3, ...
                    'rng_seed', 20260824));
                stab(end + 1) = struct('connectivity', conns(ic), ...
                    'seed_alpha', seeds(is), 'alphas', av, ...
                    'stability', bs); %#ok<AGROW>
            end
        end

        sweep1(end + 1) = struct('variant', variants(iv).name, ...
            'result', r, 'stability', stab); %#ok<AGROW>
    end

    save(fullfile(mat_dir, '09d_percolation_sweep.mat'), 'sweep1', '-v7.3');
    fprintf('\nPhase 1 完成，已保存 09d_percolation_sweep.mat\n');
end

% ------------------------- Phase 2：预处理 / 形态学扫描 -------------------------
if run_phase2
    fprintf('\n======== Phase 2：预处理 + 形态学 + seed 扫描 ========\n');
    p2 = struct();
    p2.sigma_cells   = [0.8 1.0 1.5 2.0 2.5];
    p2.seed_alphas   = [0.50 0.60 0.70 0.80];
    p2.closing_radii = [0 1 2 3];
    p2.hole_pixels   = [16 32 64 128];
    p2.connectivities = [4 8];
    p2.base_options  = ctx.baseline_options;
    p2.base_preprocess = ctx.baseline_preprocess;
    p2.production_alpha = ctx.baseline_options.alpha;   % 锁定 0.40

    % Phase 2 的参数组合数是 5*4*4*4*2 = 640，远多于 Phase 1，
    % 因此在已抽样的 480 帧内再等距取 120 帧，把成本控制在约 1 小时。
    sub = round(linspace(1, ctx.n_frames, 120));
    sub = unique(sub);
    ctx2 = ctx;
    ctx2.frame_ids = ctx.frame_ids(sub);
    ctx2.n_frames  = numel(sub);
    ctx2.raw_U     = ctx.raw_U(:, :, sub);
    ctx2.raw_V     = ctx.raw_V(:, :, sub);
    ctx2.raw_valid = ctx.raw_valid(:, :, sub);
    ctx2.mean_U    = ctx.mean_U(:, :, sub);
    ctx2.mean_V    = ctx.mean_V(:, :, sub);
    fprintf('Phase 2 使用 %d 帧子样本。\n', ctx2.n_frames);

    tic;
    sweep2 = sensitivity_sweep(ctx2, p2);
    elapsed2 = toc;

    save(fullfile(mat_dir, '09d_sensitivity_sweep.mat'), 'sweep2', '-v7.3');
    fprintf('Phase 2 完成：%.1f s，已保存 09d_sensitivity_sweep.mat\n', elapsed2);
end

fprintf('\n诊断扫描全部完成。\n');
