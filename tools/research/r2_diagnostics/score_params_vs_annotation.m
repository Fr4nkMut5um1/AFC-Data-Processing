function results = score_params_vs_annotation(varargin)
%SCORE_PARAMS_VS_ANNOTATION 用人工标注给检测参数打分。
%
% 走真管线：tblR2.vlsmpod.prepare_context -> frame_field -> identify_frame。
% 不复刻掩膜逻辑——复刻出来的东西一旦和主管线漂移，打分就没有意义。
%
% 匹配判据：检出结构与标注框**同号**，且 x 向重叠长度 / 标注框长度 >= min_overlap。
% 只用 x 重叠，因为人工标的是 x 窗口；y 边界是推导来的，不该当作硬真值去卡。
%
% 指标
%   recall    = 命中的标注框数 / 标注框总数
%   FP/frame  = 18 个"无 VLSM"帧上误检出的 VLSM 数 / 帧数
%   这两个必须一起看：把 alpha 压到 0 能让 recall=1，但 FP 会爆。
%
% pending 帧（5297）两边都不计入——没标注的帧既不是正样本也不是负样本。

p = inputParser;
addParameter(p, 'sample_dir', 'tmp/annotation_samples/e60', @ischar);
addParameter(p, 'case_name', 'tandem_baseline_r2', @ischar);
addParameter(p, 'min_overlap', 0.5, @(x) isnumeric(x) && x > 0 && x <= 1);
addParameter(p, 'param_sets', [], @(x) isempty(x) || iscell(x));
addParameter(p, 'output_file', '', @ischar);
parse(p, varargin{:});
opts = p.Results;

repo = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
case_dir = fullfile(repo, 'cases', 'per_case', opts.case_name);
addpath(fullfile(repo, 'lib'));
mat_dir = fullfile(case_dir, 'output', 'mat');

cfg = load(fullfile(mat_dir, '00_case_configuration.mat'), 'cfg'); cfg = cfg.cfg;
stats = tblR2.load_result(fullfile(mat_dir, '02_statistics.mat'), cfg, 'statistics');
mean_bl = tblR2.load_result(fullfile(mat_dir, ...
    '02_mean_boundary_layer_friction.mat'), cfg, 'mean_bl');
ann = jsondecode(fileread(fullfile(opts.sample_dir, 'annotations.json')));

basis_file = fullfile(repo, 'tmp/pod_energy_sweep/pod_energy_sweep_basis.mat');
denoise = load(basis_file, 'denoise'); denoise = denoise.denoise;
cumulative = cumsum(denoise.eigenvalues) / sum(denoise.eigenvalues);
rank_r = find(cumulative >= ann.metadata.energy_target, 1, 'first');
fprintf('[POD] E=%g%% -> rank=%d\n', ann.metadata.energy_target*100, rank_r);

% 待评参数组。默认覆盖三处已知不一致口径 + 一条中间带。
param_sets = opts.param_sets;
if isempty(param_sets)
    param_sets = {
        struct('label', 'cfg_current  a1.00/s1.20', 'alpha', 1.00, 'seed_alpha', 1.20)
        struct('label', 'stale_cache  a1.77/s1.97', 'alpha', 1.77, 'seed_alpha', 1.97)
        struct('label', 'r1_params    a0.40/s0.70', 'alpha', 0.40, 'seed_alpha', 0.70)
        struct('label', 'mid_A        a0.50/s0.80', 'alpha', 0.50, 'seed_alpha', 0.80)
        struct('label', 'mid_B        a0.60/s0.90', 'alpha', 0.60, 'seed_alpha', 0.90)
        struct('label', 'mid_C        a0.70/s1.00', 'alpha', 0.70, 'seed_alpha', 1.00)
        struct('label', 'mid_D        a0.50/s1.00', 'alpha', 0.50, 'seed_alpha', 1.00)
        struct('label', 'mid_E        a0.40/s0.90', 'alpha', 0.40, 'seed_alpha', 0.90)
    };
end

% 拆出正/负样本帧
keys = fieldnames(ann.frames);
pos_frames = {}; neg_frames = {};
for k = 1:numel(keys)
    rec = ann.frames.(keys{k});
    if strcmp(rec.annotation_status, 'pending'); continue; end
    if isempty(rec.vlsm_boxes); neg_frames{end+1} = keys{k}; %#ok<AGROW>
    else; pos_frames{end+1} = keys{k}; end %#ok<AGROW>
end
n_ann_boxes = 0;
for k = 1:numel(pos_frames)
    b = ann.frames.(pos_frames{k}).vlsm_boxes;
    if ~iscell(b); b = num2cell(b); end
    n_ann_boxes = n_ann_boxes + numel(b);
end
fprintf('[样本] 正样本 %d 帧 / %d 框，负样本 %d 帧，pending 已排除\n\n', ...
    numel(pos_frames), n_ann_boxes, numel(neg_frames));

results = struct('label', {}, 'alpha', {}, 'seed_alpha', {}, ...
    'recall', {}, 'n_hit', {}, 'n_ann', {}, 'fp_per_frame', {}, ...
    'n_fp', {}, 'n_neg_frames', {}, 'mean_len_ratio', {}, 'detail', {});

fprintf('%-26s %7s %8s %9s %10s %9s\n', 'param set', 'recall', 'hit/ann', ...
    'FP/frame', 'n_FP', 'Lhat/Lann');
fprintf('%s\n', repmat('-', 1, 76));

for s = 1:numel(param_sets)
    ps = param_sets{s};
    % 把 param set 里除 label 外的所有字段都当 override 传下去。早前这里硬写成
    % 只传 alpha/seed_alpha，于是 merge_gap_cells 扫描的 6 个档位跑出逐字节相同
    % 的结果——参数根本没进管线。resolve_settings 对未知字段会报错，所以这里多
    % 传字段是安全的：打错名字立刻炸，不会静默失效。
    ov = rmfield(ps, 'label');
    resolved = tblR2.vlsmpod.resolve_settings(cfg.structures, ov);
    ctx = tblR2.vlsmpod.prepare_context(cfg, stats, mean_bl, resolved);
    source = struct('preprocessing', 'pod_denoise', 'denoise', denoise, ...
        'mode_indices', 1:rank_r);

    n_hit = 0; len_ratios = []; detail = {};

    % --- 正样本：算 recall
    for k = 1:numel(pos_frames)
        key = pos_frames{k};
        rec = ann.frames.(key);
        boxes = rec.vlsm_boxes; if ~iscell(boxes); boxes = num2cell(boxes); end

        T = detect_vlsm(ctx, source, resolved, rec.frame_id);

        for b = 1:numel(boxes)
            bx = boxes{b};
            [hit, ratio] = match_box(T, bx, opts.min_overlap);
            if hit
                n_hit = n_hit + 1;
                len_ratios(end+1) = ratio; %#ok<AGROW>
            end
            detail{end+1} = struct('frame', key, 'box', b, ...
                'hit', hit, 'len_ratio', ratio); %#ok<AGROW>
        end
    end

    % --- 负样本：算 FP
    n_fp = 0;
    for k = 1:numel(neg_frames)
        rec = ann.frames.(neg_frames{k});
        T = detect_vlsm(ctx, source, resolved, rec.frame_id);
        n_fp = n_fp + height(T);
    end

    r = struct('label', ps.label, 'alpha', ps.alpha, 'seed_alpha', ps.seed_alpha, ...
        'recall', n_hit / n_ann_boxes, 'n_hit', n_hit, 'n_ann', n_ann_boxes, ...
        'fp_per_frame', n_fp / numel(neg_frames), 'n_fp', n_fp, ...
        'n_neg_frames', numel(neg_frames), ...
        'mean_len_ratio', mean_or_nan(len_ratios), 'detail', {detail});
    results(end+1) = r; %#ok<AGROW>

    fprintf('%-26s %6.1f%% %4d/%-3d %9.2f %10d %9.2f\n', ps.label, ...
        100*r.recall, n_hit, n_ann_boxes, r.fp_per_frame, n_fp, r.mean_len_ratio);
end

fprintf('%s\n', repmat('-', 1, 76));
fprintf('Lhat/Lann = 命中结构的检出长度 / 标注长度（<1 表示检出的结构被截短）\n');

if ~isempty(opts.output_file)
    save(opts.output_file, 'results', '-v7.3');
    fprintf('\n[保存] %s\n', opts.output_file);
end
end

% =========================================================================
function T = detect_vlsm(ctx, source, resolved, frame_id)
%DETECT_VLSM 跑真管线，只留 IsVLSM 行。
field = tblR2.vlsmpod.frame_field(ctx, frame_id, source);
ident = tblR2.vlsmpod.identify_frame(ctx, field, resolved);
T = ident.structures;
if height(T) == 0; T = T([], :); return; end
if ismember('IsVLSM', T.Properties.VariableNames)
    T = T(T.IsVLSM, :);
else
    T = T(T.LengthX_over_delta >= resolved.opts.min_vlsm_delta, :);
end
end

% =========================================================================
function [hit, best_ratio] = match_box(T, bx, min_overlap)
%MATCH_BOX 同号 + x 向重叠达标即命中。返回命中结构的长度比。
hit = false; best_ratio = NaN;
if height(T) == 0; return; end
ann_len = bx.x_max - bx.x_min;
if ann_len <= 0; return; end

best_ov = 0;
for i = 1:height(T)
    if T.Sign(i) ~= bx.sign; continue; end
    ov = min(T.XMax_mm(i), bx.x_max) - max(T.XMin_mm(i), bx.x_min);
    if ov <= 0; continue; end
    frac = ov / ann_len;
    if frac > best_ov
        best_ov = frac;
        best_ratio = T.LengthX_mm(i) / ann_len;
    end
end
hit = best_ov >= min_overlap;
if ~hit; best_ratio = NaN; end
end

% =========================================================================
function m = mean_or_nan(v)
if isempty(v); m = NaN; else; m = mean(v); end
end
