function report = verify_refactor_equivalence(varargin)
%VERIFY_REFACTOR_EQUIVALENCE 逐位比对重构前后的结构识别输出。
%
% 验收标准：**逐位相同**，不设容差。重构没有改动任何算术，不该出现浮点差异。
% 若出现差异，说明重构改变了运算顺序或口径，必须查到根因——不接受「差异很小」。
%
% 比对四组：
%   gaussian/sampled     走 run_structure_pod_denoise（重构后的薄壳）
%   gaussian/continuous  同上
%   pod_E50/sampled      走 +vlsmpod 模块，与基线的 pod_catalog 路径对照
%   pod_E50/continuous   同上
%
% 前置：先跑过 capture_structure_baseline，tmp/refactor_baseline/ 已有基线。

parser = inputParser;
parser.addParameter('case_name', 'tandem_baseline_r2', @(x) ischar(x) || isstring(x));
parser.addParameter('baseline_dir', '', @(x) ischar(x) || isstring(x));
parser.addParameter('structure_overrides', ...
    struct('alpha', 0.40, 'seed_alpha', 0.70, 'connectivity', 8), @isstruct);
parser.parse(varargin{:});
opt = parser.Results;
case_name = char(opt.case_name);

script_dir = fileparts(mfilename('fullpath'));
if isempty(script_dir) || contains(script_dir, fullfile('Temp', 'Editor_'))
    script_dir = pwd;
end
repo_root = fileparts(fileparts(fileparts(script_dir)));
per_case_root = fullfile(repo_root, 'cases', 'per_case');
library_root = fullfile(repo_root, 'lib');
addpath(library_root);
addpath(fullfile(repo_root, 'tools', 'research'));
case_root = fullfile(per_case_root, case_name);

if isempty(opt.baseline_dir)
    base_dir = fullfile(repo_root, 'tmp', 'refactor_baseline');
else
    base_dir = char(opt.baseline_dir);
end
baseline_file = fullfile(base_dir, 'refactor_baseline.mat');
if ~isfile(baseline_file)
    error('verifyRefactor:MissingBaseline', ...
        ['找不到基线：%s\n请先运行 tools/research/r2_diagnostics/capture_structure_baseline.m。'], ...
        baseline_file);
end
L = load(baseline_file, 'results');
baseline = L.results;

verify_dir = fullfile(base_dir, 'verify');
if ~isfolder(verify_dir); mkdir(verify_dir); end

fprintf('=== 重构等价性验证（逐位，无容差）===\n');
checks = {};

% ------------------------------------------------ 高斯：走重构后的生产入口
fprintf('\n--- [1/4] gaussian / sampled ---\n');
new_gs = run_structure_pod_denoise( ...
    'case_name', case_name, 'preprocessing', 'gaussian', ...
    'frame_stride', 500, 'max_frames', 24, ...
    'structure_overrides', opt.structure_overrides, ...
    'output_dir', fullfile(verify_dir, 'gaussian_sampled'));
checks{end + 1} = compare_run('gaussian/sampled', ...
    baseline.gaussian_sampled, new_gs);

fprintf('\n--- [2/4] gaussian / continuous ---\n');
new_gc = run_structure_pod_denoise( ...
    'case_name', case_name, 'preprocessing', 'gaussian', ...
    'frame_stride', 1, 'max_frames', 48, ...
    'structure_overrides', opt.structure_overrides, ...
    'output_dir', fullfile(verify_dir, 'gaussian_continuous'));
checks{end + 1} = compare_run('gaussian/continuous', ...
    baseline.gaussian_continuous, new_gc);

% ------------------------------------------- POD E=50%：走 +vlsmpod 模块
fprintf('\n--- [3-4/4] pod_denoise E=50%% ---\n');
[new_ps, new_pc] = run_pod_via_module(repo_root, case_root, case_name, ...
    opt.structure_overrides, baseline.pod);
checks{end + 1} = compare_run('pod_E50/sampled', ...
    baseline.pod.sampled, new_ps);
checks{end + 1} = compare_run('pod_E50/continuous', ...
    baseline.pod.continuous, new_pc);

% -------------------------------------------------------------- 汇总
report = struct();
report.checks = vertcat(checks{:});
report.all_identical = all(report.checks.Identical);

fprintf('\n=== 验证汇总 ===\n');
disp(report.checks);
if report.all_identical
    fprintf('结论：四组全部逐位相同。重构未改变任何数值结果。\n');
    fprintf('EQUIVALENCE_PASS\n');
else
    fprintf('结论：存在差异，见上表 FirstDiffColumn 列。\n');
    fprintf('EQUIVALENCE_FAIL\n');
end
save(fullfile(verify_dir, 'equivalence_report.mat'), 'report');
end

% =========================================================================
function [sampled, continuous] = run_pod_via_module(repo_root, case_root, ...
    case_name, overrides, pod_baseline)
%RUN_POD_VIA_MODULE 用 +vlsmpod 跑 POD E=50%，帧集与基线相同。

loaded = load(pod_baseline.basis_cache, 'denoise');
denoise = loaded.denoise;

cfg = tblR2.vlsmpod.load_case_config(case_root, case_name);
paths = tblR2.build_paths(cfg.output_dir);
stats = tblR2.load_result(paths.statistics, cfg, 'statistics');
mean_bl = tblR2.load_result(paths.mean_bl, cfg, 'mean_bl');

resolved = tblR2.vlsmpod.resolve_settings(cfg.structures, overrides);
ctx = tblR2.vlsmpod.prepare_context(cfg, stats, mean_bl, resolved);

source = struct('preprocessing', 'pod_denoise', 'denoise', denoise, ...
    'mode_indices', 1:pod_baseline.rank, ...
    'cache_file', paths.sequence_cache_postproc);

sampled = tblR2.vlsmpod.run_catalog(ctx, source, resolved, ...
    struct('frame_ids', pod_baseline.sampled.frame_ids, 'progress_steps', 4));
continuous = tblR2.vlsmpod.run_catalog(ctx, source, resolved, ...
    struct('frame_ids', pod_baseline.continuous.frame_ids, 'progress_steps', 4));
end

% =========================================================================
function row = compare_run(label, base, new)
%COMPARE_RUN 比对 catalog 全部列 + per_frame + summary。

[cat_ok, first_diff, n_cols] = compare_tables(base.catalog, new.catalog);
pf_ok = isequaln(base.per_frame, new.per_frame);
sum_ok = isequaln(base.summary, new.summary);
ids_ok = isequaln(base.frame_ids, new.frame_ids);

identical = cat_ok && pf_ok && sum_ok && ids_ok;
notes = '';
if ~pf_ok; notes = [notes 'per_frame 不一致; ']; end
if ~sum_ok; notes = [notes 'summary 不一致; ']; end
if ~ids_ok; notes = [notes 'frame_ids 不一致; ']; end

row = table({label}, identical, height(base.catalog), height(new.catalog), ...
    n_cols, {first_diff}, {notes}, 'VariableNames', ...
    {'Condition', 'Identical', 'BaseRows', 'NewRows', 'ColumnsCompared', ...
    'FirstDiffColumn', 'Notes'});

if identical
    fprintf('  %-22s 逐位相同（%d 行 × %d 列）\n', label, ...
        height(base.catalog), n_cols);
else
    fprintf('  %-22s **有差异**：%s%s\n', label, first_diff, notes);
end
end

% =========================================================================
function [ok, first_diff, n_cols] = compare_tables(A, B)
%COMPARE_TABLES 逐列 isequaln。cell 列逐元素比。

first_diff = '';
names_a = A.Properties.VariableNames;
names_b = B.Properties.VariableNames;
n_cols = numel(names_a);

if ~isequal(names_a, names_b)
    ok = false;
    only_a = setdiff(names_a, names_b);
    only_b = setdiff(names_b, names_a);
    first_diff = sprintf('列集合不同（仅基线有：%s；仅新版有：%s）', ...
        strjoin(only_a, ','), strjoin(only_b, ','));
    return;
end
if height(A) ~= height(B)
    ok = false;
    first_diff = sprintf('行数不同（%d vs %d）', height(A), height(B));
    return;
end

for k = 1:numel(names_a)
    va = A.(names_a{k});
    vb = B.(names_a{k});
    if ~isequaln(va, vb)
        ok = false;
        first_diff = names_a{k};
        if isnumeric(va) && isnumeric(vb) && isequal(size(va), size(vb))
            d = abs(double(va) - double(vb));
            first_diff = sprintf('%s（最大绝对差 %.3g，差异 %d 处）', ...
                names_a{k}, max(d(:), [], 'omitnan'), ...
                nnz(d > 0 | (isnan(va) ~= isnan(vb))));
        end
        return;
    end
end
ok = true;
end
