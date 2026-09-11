function result = run_structure_pod_denoise(varargin)
%RUN_STRUCTURE_POD_DENOISE 用 POD 去噪场替代高斯预处理，做 LSM/VLSM 识别。
%
% Research extension; not a daily entry point. Defaults write separate POD
% artifacts to the selected case output/mat directory. Runtime not revalidated.
% 它复用 case 文件产出的上游结果（序列缓存、statistics、mean_bl），
% 把结构识别环节的预处理从「9×9 高斯模糊」换成「全网格 POD 低秩重构」。
%
% 流程对比：
%   现有主管线 : raw 瞬时 → 高斯 σ=1.5 → 减分支均值 → identify_structures
%   本脚本     : raw 瞬时 → POD 去噪重构 → 减分支均值 → identify_structures
%
% 为什么换：9×9 高斯在抹掉测量噪声的同时也抹平了结构边界，这正是 α 标定时
% 「结构翼部被切断」的成因之一。POD 截断按能量而非空间尺度取舍，去掉的是
% 不相干的噪声子空间，结构边界保持锐利。
%
% 2026-08-25 重构：识别流程本体已迁到 +tblR2/+vlsmpod/ 子包，本函数只保留
% 「解析参数 → 载入上游结果 → 调用模块 → 落盘打印」这层外壳。签名、返回字段与
% 落盘内容都与重构前一致。原先内嵌的 7 个局部函数（structure_opts /
% trusted_domain_spec / structure_preprocessing / pick / load_case_config /
% mean_field_for_frame / annotate_structures）在 4 个入口脚本里各有一份逐字副本，
% 现已收进 tblR2.vlsmpod.resolve_settings 等唯一实现。
%
% 用法
%   result = run_structure_pod_denoise();                       % 默认 baseline
%   result = run_structure_pod_denoise('case_name', 'tandem_f40a3_phi0_r2');
%   result = run_structure_pod_denoise('rank_method', 'energy_fraction', ...
%                                      'energy_target', 0.95);
%   result = run_structure_pod_denoise('frame_stride', 100);    % 快速试跑
%
% 三个功能扩展（默认全关，关闭时输出与重构前逐位相同）
%   result = run_structure_pod_denoise('wall_attached', true);
%   result = run_structure_pod_denoise('superstructure', true);
%   result = run_structure_pod_denoise('tracking', true, 'frame_stride', 1, ...
%                                      'max_frames', 48);
%
% 参考文献
%   Brindise & Vlachos (2017) Exp Fluids 58:28.
%   Gavish & Donoho (2014) IEEE Trans Inf Theory 60(8):5040.
%   Hwang & Sung (2018) JFM 856:958-983.          （wall-attached 分类）
%   Deshpande & Marusic (2023) JFM 969:A10.        （超结构自相似分解）
%   Lozano-Duran & Jimenez (2014) JFM 759:432-471. （时间分辨追踪）

parser = inputParser;
parser.addParameter('case_name', 'tandem_baseline_r2', @(x) ischar(x) || isstring(x));
parser.addParameter('rank_method', 'gavish_donoho', @(x) ...
    ismember(char(x), {'gavish_donoho', 'energy_fraction'}));
parser.addParameter('energy_target', 0.95, @(x) isscalar(x) && x > 0 && x <= 1);
parser.addParameter('frame_stride', [], @(x) isempty(x) || ...
    (isscalar(x) && x >= 1 && x == fix(x)));
parser.addParameter('max_frames', [], @(x) isempty(x) || ...
    (isscalar(x) && x >= 2 && x == fix(x)));
parser.addParameter('output_dir', '', @(x) ischar(x) || isstring(x));
parser.addParameter('use_cache', true, @(x) islogical(x) || isnumeric(x));
% 预处理方式：pod_denoise 走 POD 低秩重构；gaussian 走原有的 9×9 模糊。
% 保留 gaussian 是为了在**完全相同的识别参数**下做对照——否则「POD 好还是
% 高斯好」这个问题会被识别参数的差异污染。
parser.addParameter('preprocessing', 'pod_denoise', @(x) ...
    ismember(char(x), {'pod_denoise', 'gaussian'}));
% 结构识别参数覆盖。用于在不修改 case 文件的前提下试不同阈值组合，
% 例如回退到 r1 的 alpha=0.40/seed=0.70/8-连通。
parser.addParameter('structure_overrides', struct(), @isstruct);
% 只取 POD 基底的前 r 阶。空表示用全部 1:rank。用已有高能量档基底跑低能量档时
% 传 1:r——POD 模态与截断秩无关，低档就是高档的前缀，省掉重新分解。
parser.addParameter('mode_indices', [], @(x) isempty(x) || isnumeric(x));
% 三个功能扩展。true 用默认参数，或传结构体细调。
parser.addParameter('wall_attached', false, @(x) islogical(x) || ...
    isnumeric(x) || isstruct(x));
parser.addParameter('superstructure', false, @(x) islogical(x) || ...
    isnumeric(x) || isstruct(x));
parser.addParameter('tracking', false, @(x) islogical(x) || ...
    isnumeric(x) || isstruct(x));
parser.parse(varargin{:});
opt = parser.Results;
case_name = char(opt.case_name);
rank_method = char(opt.rank_method);
preprocessing = char(opt.preprocessing);

% ------------------------------------------------------------------ 路径
script_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(fileparts(script_dir));
per_case_root = fullfile(repo_root, 'cases', 'per_case');
case_root = fullfile(per_case_root, case_name);
if ~isfolder(case_root)
    error('runStructurePodDenoise:MissingCase', ...
        '找不到工况目录：%s', case_root);
end
% Both r2 cases share the packages in lib.
library_root = fullfile(repo_root, 'lib');
addpath(library_root);

% -------------------------------------------------------- 载入 case 配置
cfg = tblR2.vlsmpod.load_case_config(case_root, case_name);
paths = tblR2.build_paths(cfg.output_dir);

if ~isfile(paths.statistics)
    error('runStructurePodDenoise:MissingStatistics', ...
        ['缺少 statistics 结果：%s\n' ...
        '请先运行 %s_case.m 完成 statistics 与 mean_bl 阶段。'], ...
        paths.statistics, case_name);
end
stats = tblR2.load_result(paths.statistics, cfg, 'statistics');
mean_bl = tblR2.load_result(paths.mean_bl, cfg, 'mean_bl');

% 产物落到独立目录，绝不覆盖 09_structure_analysis.mat。
if isempty(opt.output_dir)
    out_dir = fullfile(cfg.output_dir, 'mat');
else
    out_dir = char(opt.output_dir);
end
if ~isfolder(out_dir); mkdir(out_dir); end
basis_cache = fullfile(out_dir, '09_structure_pod_denoise_basis.mat');
result_path = fullfile(out_dir, '09_structure_pod_denoise.mat');

% -------------------------------------------------------- POD 去噪基底
% gaussian 对照模式不需要 POD 基底，跳过分解省掉几分钟。
denoise = [];
if strcmp(preprocessing, 'pod_denoise')
    denoise_options = struct( ...
        'rank_method', rank_method, ...
        'energy_target', opt.energy_target, ...
        'cache_path', basis_cache, ...
        'use_cache', logical(opt.use_cache), ...
        'write_cache', true);
    denoise = tblR2.pod_denoise_prepare(paths.sequence_cache_postproc, cfg, ...
        stats, denoise_options);
end

% ------------------------------------------------- 识别参数与几何上下文
resolved = tblR2.vlsmpod.resolve_settings(cfg.structures, opt.structure_overrides);
ctx = tblR2.vlsmpod.prepare_context(cfg, stats, mean_bl, resolved);

source = struct('preprocessing', preprocessing, ...
    'denoise', denoise, ...
    'mode_indices', opt.mode_indices, ...
    'cache_file', paths.sequence_cache_postproc);

% ------------------------------------------------------------- 帧列表
stride = cfg.structures.catalog_frame_stride;
if ~isempty(opt.frame_stride); stride = opt.frame_stride; end
catalog_ids = 1:stride:stats.n_frames;
if ~isempty(opt.max_frames)
    catalog_ids = catalog_ids(1:min(numel(catalog_ids), opt.max_frames));
end

% --------------------------------------------------------- 逐帧识别
catalog_options = struct( ...
    'frame_ids', catalog_ids, ...
    'branch', 'total', ...
    'wall_attached', extension_spec(opt.wall_attached), ...
    'superstructure', extension_spec(opt.superstructure), ...
    'tracking', extension_spec(opt.tracking));
run_out = tblR2.vlsmpod.run_catalog(ctx, source, resolved, catalog_options);

% -------------------------------------------------------------- 汇总输出
result = struct();
result.catalog = run_out.catalog;
result.per_frame = run_out.per_frame;
result.frame_ids = run_out.frame_ids;
result.preprocessing = preprocessing;
if isempty(denoise)
    result.pod_rank = NaN;
    result.pod_rank_method = 'n/a';
    result.pod_energy_at_rank = NaN;
    result.pod_eigenvalues = [];
    result.pod_diagnostics = struct();
else
    result.pod_rank = denoise.rank;
    result.pod_rank_method = rank_method;
    result.pod_energy_at_rank = denoise.diagnostics.energy_at_rank;
    result.pod_eigenvalues = denoise.eigenvalues;
    result.pod_diagnostics = denoise.diagnostics;
end
result.structure_opts = resolved.opts;
result.structure_overrides = opt.structure_overrides;
result.trusted_domain = resolved.trusted_domain;
result.merge_enabled = resolved.merge_enabled;
result.case_name = case_name;
result.summary = run_out.summary;
result.wall_attached = run_out.wall_attached;
result.superstructure = run_out.superstructure;
result.tracking = run_out.tracking;
result.definition = ['POD 去噪场上的 LSM/VLSM 识别结果。预处理为全网格 ' ...
    'POD 低秩重构（替代高斯模糊），识别参数与主管线 structure_analysis 一致。'];

save(result_path, 'result', '-v7.3');

fprintf('\n=== POD 去噪结构识别完成 ===\n');
if isempty(denoise)
    fprintf('  预处理            : 高斯 9×9（对照组）\n');
else
    fprintf('  预处理            : POD 去噪\n');
    fprintf('  截断秩            : %d（%s，累计能量 %.2f%%）\n', ...
        denoise.rank, rank_method, 100 * denoise.diagnostics.energy_at_rank);
end
fprintf('  识别参数          : alpha=%.2f seed=%.2f conn=%d\n', ...
    resolved.opts.alpha, resolved.opts.seed_alpha, resolved.opts.connectivity);
fprintf('  识别帧数          : %d\n', result.summary.n_frames);
fprintf('  结构总数          : %d\n', result.summary.total_structures);
fprintf('  平均每帧结构数    : %.2f\n', result.summary.mean_structures_per_frame);
fprintf('  平均每帧 LSM      : %.2f\n', result.summary.mean_lsm_per_frame);
fprintf('  平均每帧 VLSM     : %.2f\n', result.summary.mean_vlsm_per_frame);
print_extensions(result);
fprintf('  结果已保存        : %s\n', result_path);
end

% =========================================================================
function spec = extension_spec(value)
%EXTENSION_SPEC 把 true/false 或结构体统一成 run_catalog 认的规格。
if isstruct(value)
    spec = value;
    if ~isfield(spec, 'enabled'); spec.enabled = true; end
else
    spec = struct('enabled', logical(value));
end
end

% =========================================================================
function print_extensions(result)
%PRINT_EXTENSIONS 三个扩展开启时才打印各自的关键数。

if isfield(result.wall_attached, 'attached_fraction')
    w = result.wall_attached;
    fprintf('  wall-attached     : %d/%d（%.1f%%），面积占比 %.1f%%\n', ...
        w.n_attached, w.n_total, 100 * w.attached_fraction, ...
        100 * w.attached_area_fraction);
end
if isfield(result.superstructure, 'n_vlsm_analyzed')
    s = result.superstructure;
    fprintf('  超结构分解        : %d 个 VLSM，子结构数中位 %.1f，段长中位 %.2f δ99\n', ...
        s.n_vlsm_analyzed, s.n_sub_median, s.sub_length_median_over_delta);
    fprintf('                      总长-段长相关 %.3f（接近 0 支持自相似拼接）\n', ...
        s.total_vs_sub_correlation);
end
if isfield(result.tracking, 'summary') && ~isempty(fieldnames(result.tracking))
    t = result.tracking.summary;
    fprintf('  时间追踪          : %d 条 track，截断 %d（%.1f%%）\n', ...
        t.n_tracks, t.n_censored, 100 * t.censored_fraction);
    fprintf('                      FOV 穿越 %.1f 帧；未截断寿命中位 %.1f 帧\n', ...
        t.fov_transit_frames, t.lifetime_median_uncensored);
    fprintf('                      split %.2f/帧对，merge %.2f/帧对（链接口径）\n', ...
        t.splits_per_frame_pair, t.merges_per_frame_pair);
    if t.caveats.lifetime_ceiling_is_fov
        fprintf('                      [注意] 寿命上限由 FOV 决定，非物理寿命\n');
    end
end
end
