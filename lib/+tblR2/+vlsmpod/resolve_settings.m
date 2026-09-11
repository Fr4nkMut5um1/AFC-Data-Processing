function resolved = resolve_settings(structure_settings, overrides)
%RESOLVE_SETTINGS cfg.structures -> 结构识别所需的全套选项，唯一口径拥有者。
%
% 为什么存在：structure_opts / trusted_domain_spec / structure_preprocessing /
% pick 这一组函数原先是 structure_analysis_cache.m 的私有局部函数，外部取不到，
% 于是被逐字复制到 4 个入口脚本里（run_structure_pod_denoise、run_pod_energy_sweep、
% run_pod_sweep_visual_audit、run_pod_lowrank_structure_diagnostic）。改一处阈值
% 口径要同步改 4 份，漏一份就悄悄跑出不可比的结果。本函数把它收成唯一一处。
%
% 数值口径与被替换的局部函数逐字段一致——这是硬要求，不是设计偏好。POD 与
% Gaussian 分支只有在**完全相同的识别参数**下对比才有意义。
%
% 输入
%   structure_settings : cfg.structures（通常来自 00_case_configuration.mat）
%   overrides          : 可选。要覆盖的字段，例如
%                        struct('alpha', 0.40, 'seed_alpha', 0.70, 'connectivity', 8)
%                        只允许覆盖已存在的字段——打错字段名立刻报错，而不是静默
%                        新增一个永远不会被读到的字段，让人以为参数生效了。
%
% 输出 resolved 结构体
%   .settings        : 应用 overrides 后的 cfg.structures 内存副本
%   .opts            : 传给 tblR2.identify_structures 的选项
%   .trusted_domain  : 传给 tblR2.trusted_domain_mask 的规格
%   .preprocess_spec : 传给 tblR2.preprocess_structure_velocity 的规格（高斯分支用）
%   .merge_enabled   : 是否启用流向合并
%   .merge_opts      : 启用时传给 tblR2.vlsm.merge_streamwise_neighbors 的选项；
%                      未启用时为空结构体

if nargin < 2 || isempty(overrides)
    overrides = struct();
end
if ~isstruct(structure_settings)
    error('tblR2:vlsmpod:resolve_settings:InvalidSettings', ...
        'structure_settings 必须是结构体（通常是 cfg.structures）。');
end
if ~isstruct(overrides)
    error('tblR2:vlsmpod:resolve_settings:InvalidOverrides', ...
        'overrides 必须是结构体。');
end

settings = apply_overrides(structure_settings, overrides);

resolved = struct();
resolved.settings = settings;
resolved.opts = structure_opts(settings);
resolved.trusted_domain = trusted_domain_spec(settings);
resolved.preprocess_spec = structure_preprocessing(settings);
[resolved.merge_enabled, resolved.merge_opts] = merge_spec(settings, resolved.opts);
resolved.stale_config_warning = stale_config_check(settings);
end

% =========================================================================
function settings = apply_overrides(settings, overrides)
names = fieldnames(overrides);
for i = 1:numel(names)
    if ~isfield(settings, names{i})
        error('tblR2:vlsmpod:resolve_settings:UnknownOverride', ...
            'cfg.structures 中不存在字段 %s，无法覆盖。', names{i});
    end
    settings.(names{i}) = overrides.(names{i});
end
end

% =========================================================================
function opts = structure_opts(settings)
%STRUCTURE_OPTS 与 structure_analysis_cache.m 的同名局部函数逐字段一致。
% 改这里等于改主管线的识别口径——任何字段的默认值都不要"顺手优化"。

max_internal_hole_pixels = pick(settings, 'max_internal_hole_pixels', 0);
envelope_closing_radius_cells = pick(settings, 'envelope_closing_radius_cells', 0);
max_aspect_ratio = pick(settings, 'max_aspect_ratio', inf);
reject_trusted_boundary_touching = pick(settings, ...
    'reject_trusted_boundary_touching', false);
seed_alpha = pick(settings, 'seed_alpha', settings.alpha);
min_abs_fluctuation = pick(settings, 'min_abs_fluctuation', 0);
min_abs_seed_fluctuation = pick(settings, 'min_abs_seed_fluctuation', ...
    min_abs_fluctuation);

opts = struct('alpha', settings.alpha, 'min_pixels', settings.min_pixels, ...
    'seed_alpha', seed_alpha, ...
    'connectivity', settings.connectivity, ...
    'max_internal_hole_pixels', max_internal_hole_pixels, ...
    'envelope_closing_radius_cells', envelope_closing_radius_cells, ...
    'max_aspect_ratio', max_aspect_ratio, ...
    'reject_trusted_boundary_touching', reject_trusted_boundary_touching, ...
    'min_lsm_delta', settings.min_lsm_delta, ...
    'min_vlsm_delta', settings.min_vlsm_delta, ...
    'max_wall_normal_delta', settings.max_wall_normal_delta, ...
    'min_abs_fluctuation', min_abs_fluctuation, ...
    'min_abs_seed_fluctuation', min_abs_seed_fluctuation, ...
    'sign_mode', 'both');
end

% =========================================================================
function spec = trusted_domain_spec(settings)
%TRUSTED_DOMAIN_SPEC 与 structure_analysis_cache.m 同名局部函数一致。
spec = struct('streamwise_edge_columns', 0, 'wall_normal_top_rows', 0);
if isfield(settings, 'trusted_domain') && ~isempty(settings.trusted_domain)
    names = fieldnames(spec);
    for i = 1:numel(names)
        if isfield(settings.trusted_domain, names{i})
            spec.(names{i}) = settings.trusted_domain.(names{i});
        end
    end
end
end

% =========================================================================
function spec = structure_preprocessing(settings)
%STRUCTURE_PREPROCESSING 构造高斯分支所需的预处理规格。
% 与 structure_analysis_cache 的同名局部函数保持同一口径：**不预填方向性字段**，
% 让 sigma_cells 原样传导到 simple_gaussian_filter2。早前正是因为预填
% sigma_x_cells=0.8 / radius_x_cells=1，才让 case 脚本里的 9x9 核（sigma=1.5,
% radius=4）悄悄退化成 3x3——那个缺陷让整轮 alpha 标定的转变区都偏了。

source = struct('enabled', true, 'name', 'Gaussian_sigma1p5_9x9');
if isfield(settings, 'preprocessing') && ~isempty(settings.preprocessing)
    source = settings.preprocessing;
end
spec = source;
if ~isfield(spec, 'gaussian') || isempty(spec.gaussian)
    spec.gaussian = struct('enabled', false);
end
if ~isfield(spec.gaussian, 'enabled')
    spec.gaussian.enabled = false;
end
if ~isfield(spec, 'outlier') || isempty(spec.outlier)
    spec.outlier = struct('enabled', false);
end
end

% =========================================================================
function [enabled, merge_opts] = merge_spec(settings, opts)
%MERGE_SPEC 流向合并选项。与 run_structure_pod_denoise 原逻辑一致：
% 只有 merge_gap_cells 字段存在且为正才启用。

merge_opts = struct();
enabled = isfield(settings, 'merge_gap_cells') && ...
    ~isempty(settings.merge_gap_cells) && settings.merge_gap_cells > 0;
if ~enabled
    return;
end
require_y_overlap = true;
if isfield(settings, 'merge_require_y_overlap') && ...
        ~isempty(settings.merge_require_y_overlap)
    require_y_overlap = settings.merge_require_y_overlap;
end
merge_opts = struct( ...
    'merge_gap_cells', settings.merge_gap_cells, ...
    'merge_require_y_overlap', require_y_overlap, ...
    'min_lsm_delta', opts.min_lsm_delta, ...
    'min_vlsm_delta', opts.min_vlsm_delta);
end

% =========================================================================
function msg = stale_config_check(settings)
%STALE_CONFIG_CHECK 检出已知会导致 VLSM=0 的固化旧参数。
%
% 00_case_configuration.mat 里固化的是 alpha=1.77 / seed_alpha=1.97——那是
% 2026-08-24 bootstrap 标定的结果，但实测在 12000 帧上检出 0 个 VLSM（结构翼部
% 幅值约 0.67 sigma 被切断）。case 脚本源码已改成 1.0/1.2，r1 用的是 0.40/0.70，
% 三处不一致。tblR2.load_result 只校验 case_id/帧数/网格/fs，不校验 alpha，所以
% 读这个 mat 的脚本会静默用旧值跑出 VLSM=0 而不报错。
%
% 这里只告警不改值——静默替换用户的参数比让他看到 VLSM=0 更危险。

msg = '';
if ~isfield(settings, 'alpha') || ~isfield(settings, 'seed_alpha')
    return;
end
if abs(settings.alpha - 1.77) < 1e-9 && abs(settings.seed_alpha - 1.97) < 1e-9
    msg = sprintf([ ...
        'alpha=%.2f / seed_alpha=%.2f 是 00_case_configuration.mat 里固化的旧标定值，' ...
        '实测在 12000 帧上 VLSM=0。若要识别出 VLSM，请用 structure_overrides 传入 ' ...
        'r1 参数（alpha=0.40, seed_alpha=0.70, connectivity=8）。'], ...
        settings.alpha, settings.seed_alpha);
    warning('tblR2:vlsmpod:resolve_settings:StaleCalibration', '%s', msg);
end
end

% =========================================================================
function value = pick(settings, name, fallback)
%PICK 取可选字段，缺失或空时用默认值。
value = fallback;
if isfield(settings, name) && ~isempty(settings.(name))
    value = settings.(name);
end
end
