function inspect_false_positives(varargin)
%INSPECT_FALSE_POSITIVES 查"无 VLSM"帧上检出的结构到底是什么。
%
% FP 未必是检测器的错。人工标注是目视判断，而 IsVLSM 只看 L/delta99>=3。一条
% 幅值弱但够长的条纹，人眼可能不觉得它是 VLSM，判据却认。这两种情形要分开：
%   - 若 FP 的幅值分布显著弱于标注结构 -> 是"人眼没看见的弱结构"，判据偏宽
%   - 若 FP 幅值与标注结构相当          -> 是人工漏标，负样本不干净
%
% 这个区分决定 FP/frame 该不该当成惩罚项。

p = inputParser;
addParameter(p, 'sample_dir', 'tmp/annotation_samples/e60', @ischar);
addParameter(p, 'case_name', 'tandem_baseline_r2', @ischar);
addParameter(p, 'alpha', 0.66, @isnumeric);
addParameter(p, 'seed_alpha', 0.75, @isnumeric);
addParameter(p, 'merge_gap_cells', 40, @isnumeric);
addParameter(p, 'make_figures', true, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opts = p.Results;

warning('off', 'tblR2:vlsmpod:resolve_settings:StaleCalibration');

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

ov = struct('alpha', opts.alpha, 'seed_alpha', opts.seed_alpha, ...
    'merge_gap_cells', opts.merge_gap_cells);
resolved = tblR2.vlsmpod.resolve_settings(cfg.structures, ov);
ctx = tblR2.vlsmpod.prepare_context(cfg, stats, mean_bl, resolved);
source = struct('preprocessing', 'pod_denoise', 'denoise', denoise, ...
    'mode_indices', 1:rank_r);

fprintf('params: alpha=%.2f seed=%.2f gap=%d, E=%g%% rank=%d\n\n', ...
    opts.alpha, opts.seed_alpha, opts.merge_gap_cells, ...
    ann.metadata.energy_target*100, rank_r);

keys = fieldnames(ann.frames);

% --- 先量出标注结构（真正样本）的幅值基线
tp_peak = []; tp_len = []; tp_ld = [];
for k = 1:numel(keys)
    rec = ann.frames.(keys{k});
    if strcmp(rec.annotation_status, 'pending') || isempty(rec.vlsm_boxes); continue; end
    field = tblR2.vlsmpod.frame_field(ctx, rec.frame_id, source);
    ident = tblR2.vlsmpod.identify_frame(ctx, field, resolved);
    T = vlsm_rows(ident.structures, resolved);
    boxes = rec.vlsm_boxes; if ~iscell(boxes); boxes = num2cell(boxes); end
    for b = 1:numel(boxes)
        bx = boxes{b};
        i = best_match(T, bx);
        if isnan(i); continue; end
        tp_peak(end+1) = abs(T.peakAmp(i)); %#ok<AGROW>
        tp_len(end+1) = T.LengthX_mm(i); %#ok<AGROW>
        tp_ld(end+1) = T.LengthX_over_delta(i); %#ok<AGROW>
    end
end

fprintf('=== matched (true positive) structures, n=%d ===\n', numel(tp_peak));
report_dist('peakAmp m/s', tp_peak);
report_dist('LengthX mm ', tp_len);
report_dist('L/delta99  ', tp_ld);

% --- 再量 FP
fp_peak = []; fp_len = []; fp_ld = []; fp_rows = {};
neg_keys = {};
for k = 1:numel(keys)
    rec = ann.frames.(keys{k});
    if strcmp(rec.annotation_status, 'pending') || ~isempty(rec.vlsm_boxes); continue; end
    neg_keys{end+1} = keys{k}; %#ok<AGROW>
    field = tblR2.vlsmpod.frame_field(ctx, rec.frame_id, source);
    ident = tblR2.vlsmpod.identify_frame(ctx, field, resolved);
    T = vlsm_rows(ident.structures, resolved);
    for i = 1:height(T)
        fp_peak(end+1) = abs(T.peakAmp(i)); %#ok<AGROW>
        fp_len(end+1) = T.LengthX_mm(i); %#ok<AGROW>
        fp_ld(end+1) = T.LengthX_over_delta(i); %#ok<AGROW>
        fp_rows{end+1} = sprintf(['  %-12s x[%6.1f %6.1f] y[%5.2f %5.2f] ' ...
            'L=%5.1f L/d=%4.2f peak=%5.2f %s'], keys{k}, ...
            T.XMin_mm(i), T.XMax_mm(i), T.YMin_mm(i), T.YMax_mm(i), ...
            T.LengthX_mm(i), T.LengthX_over_delta(i), abs(T.peakAmp(i)), ...
            tern(T.Sign(i) > 0, 'HIGH', 'LOW')); %#ok<AGROW>
    end
end

fprintf('\n=== false-positive structures on %d "no VLSM" frames, n=%d ===\n', ...
    numel(neg_keys), numel(fp_peak));
report_dist('peakAmp m/s', fp_peak);
report_dist('LengthX mm ', fp_len);
report_dist('L/delta99  ', fp_ld);

fprintf('\n--- individual FP list ---\n');
for i = 1:numel(fp_rows); fprintf('%s\n', fp_rows{i}); end

if ~isempty(tp_peak) && ~isempty(fp_peak)
    fprintf('\n=== verdict ===\n');
    fprintf('median peakAmp: TP=%.3f  FP=%.3f  ratio=%.2f\n', ...
        median(tp_peak), median(fp_peak), median(fp_peak)/median(tp_peak));
    fprintf('median L/d99  : TP=%.2f   FP=%.2f\n', median(tp_ld), median(fp_ld));
    if median(fp_peak) < 0.7 * median(tp_peak)
        fprintf('-> FP 幅值显著弱于标注结构：判据偏宽，FP 多为人眼不认的弱结构\n');
    else
        fprintf('-> FP 幅值与标注结构相当：负样本可能有漏标，需人工复核这些帧\n');
    end
end

% --- 输出 FP 叠框图供人工复核
if opts.make_figures && ~isempty(neg_keys)
    fig_dir = fullfile(opts.sample_dir, 'false_positives');
    if ~isfolder(fig_dir); mkdir(fig_dir); end
    x_mm = stats.X(1, :); y_mm = mean_bl.wall_distance_mm(:, 1);
    n_made = 0;
    for k = 1:numel(neg_keys)
        rec = ann.frames.(neg_keys{k});
        field = tblR2.vlsmpod.frame_field(ctx, rec.frame_id, source);
        ident = tblR2.vlsmpod.identify_frame(ctx, field, resolved);
        T = vlsm_rows(ident.structures, resolved);
        if height(T) == 0; continue; end
        u_norm = field.u_fluct ./ stats.u_rms;
        draw_frame(fig_dir, rec.frame_id, x_mm, y_mm, u_norm, T, cfg, ...
            ann.metadata.energy_target, rank_r, opts);
        n_made = n_made + 1;
    end
    fprintf('\n[图] %d 张 FP 复核图 -> %s\n', n_made, fig_dir);
end
end

% =========================================================================
function T = vlsm_rows(T, resolved)
if height(T) == 0; T = T([], :); return; end
if ismember('IsVLSM', T.Properties.VariableNames)
    T = T(T.IsVLSM, :);
else
    T = T(T.LengthX_over_delta >= resolved.opts.min_vlsm_delta, :);
end
end

% =========================================================================
function idx = best_match(T, bx)
idx = NaN; best = 0;
if height(T) == 0; return; end
ann_len = bx.x_max - bx.x_min;
for i = 1:height(T)
    if T.Sign(i) ~= bx.sign; continue; end
    ov = min(T.XMax_mm(i), bx.x_max) - max(T.XMin_mm(i), bx.x_min);
    if ov <= 0; continue; end
    f = ov / ann_len;
    if f > best; best = f; idx = i; end
end
if best < 0.5; idx = NaN; end
end

% =========================================================================
function report_dist(name, v)
if isempty(v); fprintf('  %s : (none)\n', name); return; end
fprintf('  %s : min=%6.2f  p25=%6.2f  med=%6.2f  p75=%6.2f  max=%6.2f\n', ...
    name, min(v), quantile(v, .25), median(v), quantile(v, .75), max(v));
end

% =========================================================================
function draw_frame(dir_out, fid, x_mm, y_mm, u_norm, T, cfg, e_t, rank_r, opts)
fig = figure('Visible', 'off', 'Position', [100 100 1200 400]);
ax = axes(fig);
contourf(ax, x_mm, y_mm, u_norm, 60, 'LineStyle', 'none');
axis(ax, 'tight'); set(ax, 'YDir', 'normal');
fv = u_norm(isfinite(u_norm));
cl = quantile(abs(fv), 0.995);
clim(ax, [-cl, cl]);
colormap(ax, tblR2.viz.resolve_case_colormap('balance', 256));
colorbar(ax); hold(ax, 'on');
for i = 1:height(T)
    rectangle(ax, 'Position', [T.XMin_mm(i), T.YMin_mm(i), ...
        T.XMax_mm(i)-T.XMin_mm(i), T.YMax_mm(i)-T.YMin_mm(i)], ...
        'EdgeColor', 'm', 'LineWidth', 2, 'LineStyle', '--');
    text(ax, 0.5*(T.XMin_mm(i)+T.XMax_mm(i)), T.YMax_mm(i), ...
        sprintf('L/\\delta=%.1f pk=%.2f', T.LengthX_over_delta(i), ...
        abs(T.peakAmp(i))), 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'bottom', 'FontWeight', 'bold', ...
        'BackgroundColor', [1 1 1 0.7]);
end
hold(ax, 'off');
xlabel(ax, 'x (mm)'); ylabel(ax, '离壁距离 (mm)');
title(ax, sprintf(['Frame %d 人工判无 VLSM，检出 %d 个 | ' ...
    'a=%.2f s=%.2f g=%d | E=%g%%'], fid, height(T), opts.alpha, ...
    opts.seed_alpha, opts.merge_gap_cells, e_t*100), 'Interpreter', 'tex');
tblR2.viz.apply_fov_aspect(ax, cfg);
saveas(fig, fullfile(dir_out, sprintf('frame_%04d.png', fid)));
close(fig);
end

% =========================================================================
function out = tern(c, a, b)
if c; out = a; else; out = b; end
end
