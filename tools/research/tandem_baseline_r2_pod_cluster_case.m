%% 0. 复用 r2 基准流程（原文件保持不变）
% Research extension; full execution can run the daily case and all-frame POD.
% This relocated entry has only received static path checks.
% POD 低阶重构去噪 + 聚类联通法扩展入口。
%
% 本文件不修改 tandem_baseline_r2_case.m。完整运行时先执行原 r2 脚本，
% 然后在 Section 10 追加 Raw / Gaussian / ELF-POD / POD-E80/E90/E95 比较。
% 若原 r2 结果已经在工作区，也可以只运行 Section 10。

extension_file = mfilename('fullpath');
extension_root = fileparts(extension_file);
repo_root = fileparts(fileparts(extension_root));
addpath(fullfile(repo_root, 'lib'));
source_case_file = fullfile(repo_root, 'cases', 'per_case', ...
    'tandem_baseline_r2', 'tandem_baseline_r2_case.m');
if ~isfile(source_case_file)
    error('tblR2:podClusterCase:MissingSourceCase', ...
        '找不到原 r2 入口：%s', source_case_file);
end
run(source_case_file);

%% 10. 全分辨率 POD 重构瞬时 u' → LSM/VLSM 聚类联通识别
% 关键合同：
%   1) 时间步长=1、空间步长=[1 1]，不使用 [2 2] 或插值回填；
%   2) 主方法 ELF-POD；备选为联合 u-v 总能量 E80/E90/E95；
%   3) Raw 与现有 Gaussian 是独立对照；Gaussian->POD 默认关闭；
%   4) 所有主分支共用原 statistics.u_rms；POD 自有 RMS 仅作独立敏感性；
%   5) POD 重构只进入 u' 的 LSM/VLSM 联通识别，不生成 POD-Q2/Q4。

extension_file = mfilename('fullpath');                             % 原脚本 clearvars 后重新建立扩展入口路径。
extension_root = fileparts(extension_file);
repo_root = fileparts(fileparts(extension_root));
addpath(fullfile(repo_root, 'lib'));
source_case_file = fullfile(repo_root, 'cases', 'per_case', ...
    'tandem_baseline_r2', 'tandem_baseline_r2_case.m');
required_workspace = {'cfg','results','analysis_cache'};
for i_required = 1:numel(required_workspace)
    if ~exist(required_workspace{i_required}, 'var')
        error('tblR2:podClusterCase:MissingWorkspace', ...
            'Section 10 缺少变量 %s；请先运行本文件 Section 0。', ...
            required_workspace{i_required});
    end
end
if isempty(results.statistics) || isempty(results.mean_bl)
    error('tblR2:podClusterCase:MissingInputs', ...
        'Section 10 需要 Section 2 的 statistics 和 mean_bl。');
end

cfg.pod_cluster = struct();
cfg.pod_cluster.stage = 'compute';                                  % compute 或 reuse。
cfg.pod_cluster.energy_targets = [0.80 0.90 0.95];                  % 联合 u-v 累计总能量档。
cfg.pod_cluster.chunk_frames = 16;                                  % 仅控制流式重构峰值内存，不改变精度。
cfg.pod_cluster.representative_frame_ids = [];                      % 空：沿用 cfg.instantaneous 代表帧。
cfg.pod_cluster.pod = cfg.pod;                                     % 复用现有 POD 参数结构。
cfg.pod_cluster.pod.n_modes = 1;                                   % 只用于建序列的自由度合法性检查。
cfg.pod_cluster.pod.frame_stride = 1;                              % 使用所有帧。
cfg.pod_cluster.pod.spatial_stride = [1 1];                        % 全空间分辨率；禁止 [2 2]。
cfg.pod_cluster.pod.x_range_mm = [min(results.statistics.X(:)), ...
    max(results.statistics.X(:))];                                 % 覆盖完整有效流向范围。
cfg.pod_cluster.pod.max_y_over_delta = Inf;                        % 法向范围由结构可信域决定。
cfg.pod_cluster.pod.max_frames = [];                               % 不截断时间序列。
cfg.pod_cluster.elf = struct( ...
    'min_ppr', 1.8, ...                                             % Brindise/Vlachos ELF 失败判据。
    'min_mask_jaccard', 0.90, ...                                  % 掩膜填充敏感性最低一致度。
    'min_segment_modes', 3);                                       % 两线拟合每段最少模态数。
cfg.pod_cluster.memory_guard = struct('enabled', true, ...
    'safety_factor', 1.25);                                        % 内存不足时分解前停止，不静默降精度。
cfg.pod_cluster.gaussian_then_pod = struct('enabled', false);       % 备选：Gaussian -> POD，默认关闭。
cfg.pod_cluster.fixed_n_stability = struct( ...
    'scalar_relative_tolerance', 0.10, ...                          % 标量结构指标相对变化上限。
    'cdf_max_difference', 0.10);                                   % Lx/delta 经验 CDF 最大差上限。

pod_cluster_file = fullfile(cfg.output_dir, 'mat', ...
    '13_pod_cluster_analysis.mat');
if strcmp(cfg.pod_cluster.stage, 'reuse')
    if ~isfile(pod_cluster_file)
        error('tblR2:podClusterCase:MissingReuseArtifact', ...
            'reuse 请求的 POD 聚类结果不存在：%s', pod_cluster_file);
    end
    loaded_pod_cluster = load(pod_cluster_file, 'data');
    results.pod_cluster = loaded_pod_cluster.data;
elseif strcmp(cfg.pod_cluster.stage, 'compute')
    fprintf(['[Section 10] 开始全帧、[1 1] 全分辨率 POD/聚类分析。' ...
        '精确 snapshot POD 可能需要较长时间和较大内存。\n']);
    existing_gaussian = [];
    if isfield(results, 'structures')
        existing_gaussian = results.structures;
    end
    results.pod_cluster = tblR2.pod_cluster_analysis(analysis_cache, cfg, ...
        results.statistics, results.phase, results.mean_bl, existing_gaussian);
    output_mat_dir = fileparts(pod_cluster_file);
    if ~isfolder(output_mat_dir); mkdir(output_mat_dir); end
    data = results.pod_cluster;
    meta = struct('case_id', cfg.case_id, ...
        'stage', 'pod_cluster', ...
        'created_utc', char(datetime('now', 'TimeZone', 'UTC', ...
        'Format', 'yyyy-MM-dd''T''HH:mm:ssXXX')), ...
        'script_file', extension_file, ...
        'source_case_file', source_case_file, ...
        'spatial_stride', [1 1], ...
        'energy_targets', cfg.pod_cluster.energy_targets);
    save(pod_cluster_file, 'data', 'meta', '-v7.3');
    fprintf('[Section 10] POD 聚类结果已保存：%s\n', pod_cluster_file);
else
    error('tblR2:podClusterCase:InvalidStage', ...
        'cfg.pod_cluster.stage 只能是 compute 或 reuse。');
end

disp(results.pod_cluster.branch_summary);
disp(results.pod_cluster.fixed_n_recommendation);
