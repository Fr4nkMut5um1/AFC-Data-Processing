function derive_annotation_boxes(varargin)
%DERIVE_ANNOTATION_BOXES 把人工标的 x 窗口补全成完整 VLSM 标注框。
%
% 人工标注只给了流向范围（肉眼从 PNG 横轴读的），法向范围从重构场里定出来。
%
% y 边界判据：**半峰宽**，不是 alpha 阈值。
%   在人工 x 窗口内对 u'/u_rms 做 x 向平均得到剖面 p(y)，取 |p| 峰值定主导符号
%   s，再从峰值行向两侧连续生长，直到 s*p 落到峰值的 half_peak_fraction 以下。
%
%   为什么不用 cfg.structures.alpha：alpha 正是这轮要标定的参数。用它定 ground
%   truth 会让"真值"随检测器参数漂移——标定就变成了自证。半峰宽只依赖结构自身
%   的幅值形状，换任何 alpha 都不动。
%
% 调用
%   derive_annotation_boxes()                        % 用默认路径
%   derive_annotation_boxes('half_peak_fraction', 0.5)
%
% 输入（Name-Value）
%   sample_dir         : 样本目录，默认 'tmp/annotation_samples/e60'
%   half_peak_fraction : y 生长阈值占峰值的比例，默认 0.5
%   case_name          : 默认 'tandem_baseline_r2'
%   make_overlays      : 是否输出叠框校核图，默认 true
%
% 输出
%   <sample_dir>/annotations.json          : 完整标注（vlsm_boxes 已填）
%   <sample_dir>/overlays/frame_XXXX.png   : 原图叠框，供人工校核

p = inputParser;
addParameter(p, 'sample_dir', 'tmp/annotation_samples/e60', @ischar);
addParameter(p, 'half_peak_fraction', 0.5, @(x) isnumeric(x) && x > 0 && x < 1);
addParameter(p, 'case_name', 'tandem_baseline_r2', @ischar);
addParameter(p, 'make_overlays', true, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opts = p.Results;

repo = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
case_dir = fullfile(repo, 'cases', 'per_case', opts.case_name);
addpath(fullfile(repo, 'lib'));
mat_dir = fullfile(case_dir, 'output', 'mat');

%% 1. 读 case 数据与人工窗口
cfg = load(fullfile(mat_dir, '00_case_configuration.mat'), 'cfg'); cfg = cfg.cfg;
stats = tblR2.load_result(fullfile(mat_dir, '02_statistics.mat'), cfg, 'statistics');
mean_bl = tblR2.load_result(fullfile(mat_dir, ...
    '02_mean_boundary_layer_friction.mat'), cfg, 'mean_bl');

manual = jsondecode(fileread(fullfile(opts.sample_dir, 'manual_x_windows.json')));
meta_in = jsondecode(fileread(fullfile(opts.sample_dir, 'metadata.json')));

basis_file = fullfile(repo, 'tmp/pod_energy_sweep/pod_energy_sweep_basis.mat');
denoise = load(basis_file, 'denoise'); denoise = denoise.denoise;
cumulative = cumsum(denoise.eigenvalues) / sum(denoise.eigenvalues);
rank_r = find(cumulative >= meta_in.energy_target, 1, 'first');
mode_indices = 1:rank_r;
fprintf('[POD] E=%g%% -> rank=%d\n', meta_in.energy_target*100, rank_r);

%% 2. 网格与可信域
x_mm = stats.X(1, :);
y_mm = mean_bl.wall_distance_mm(:, 1);
delta_grid = interp1(mean_bl.boundary_layer.x, ...
    mean_bl.boundary_layer.delta99, stats.X, 'linear', NaN);
valid_mask = stats.accepted_mask & isfinite(delta_grid) & delta_grid > 0;
domain_mask = tblR2.trusted_domain_mask(valid_mask, mean_bl.wall_distance_mm, ...
    cfg.structures.trusted_domain);

overlay_dir = fullfile(opts.sample_dir, 'overlays');
if opts.make_overlays && ~isfolder(overlay_dir); mkdir(overlay_dir); end

%% 3. 逐帧推导
frame_keys = fieldnames(manual.frames);
out_frames = struct();
n_box_total = 0; n_pos = 0; n_neg = 0; n_pending = 0;
rows = {};

for k = 1:numel(frame_keys)
    key = frame_keys{k};
    rec = manual.frames.(key);
    fid = sscanf(key, 'frame_%d');

    entry = struct('frame_id', fid, ...
        'image_file', sprintf('frames/frame_%04d.png', fid), ...
        'vlsm_boxes', {{}}, ...
        'annotation_status', rec.status, ...
        'annotator_notes', '');

    windows = normalize_windows(rec.x_windows);

    if strcmp(rec.status, 'pending')
        entry.annotator_notes = '未标注：不可计入真负样本';
        n_pending = n_pending + 1;
        out_frames.(key) = entry;
        continue;
    end
    if isempty(windows)
        entry.annotator_notes = '人工判定：无 VLSM';
        out_frames.(key) = entry;
        continue;
    end

    % 重构该帧并归一化
    u_norm = frame_fluctuation(denoise, stats, fid, mode_indices, domain_mask);

    boxes = {};
    for w = 1:size(windows, 1)
        box = derive_one_box(u_norm, x_mm, y_mm, delta_grid, ...
            windows(w, 1), windows(w, 2), opts.half_peak_fraction);
        if isempty(box); continue; end
        boxes{end+1} = box; %#ok<AGROW>
        n_box_total = n_box_total + 1;
        if box.sign > 0; n_pos = n_pos + 1; else; n_neg = n_neg + 1; end
        rows{end+1} = sprintf(['  %-12s x[%6.1f %6.1f] y[%5.2f %5.2f] ' ...
            'L=%5.1fmm L/d99=%4.2f %s peak=%5.2f'], key, ...
            box.x_min, box.x_max, box.y_min, box.y_max, box.length_mm, ...
            box.length_over_delta99, tern(box.sign > 0, 'HIGH', 'LOW '), ...
            box.peak_amplitude); %#ok<AGROW>
    end

    entry.vlsm_boxes = {boxes};
    entry.annotator_notes = sprintf('人工标 %d 个 VLSM，法向范围由半峰宽推导', ...
        numel(boxes));
    out_frames.(key) = entry;

    if opts.make_overlays
        save_overlay(overlay_dir, fid, x_mm, y_mm, u_norm, boxes, ...
            meta_in.energy_target, rank_r, cfg);
    end
end

%% 4. 汇总输出
fprintf('\n[推导结果] %d 个框（高速 %d / 低速 %d），pending %d 帧\n', ...
    n_box_total, n_pos, n_neg, n_pending);
for i = 1:numel(rows); fprintf('%s\n', rows{i}); end

annotations = struct();
annotations.metadata = meta_in;
annotations.metadata.y_extent_method = sprintf( ...
    'half-peak width of x-averaged u''/u_rms profile, fraction=%.2f', ...
    opts.half_peak_fraction);
annotations.metadata.x_windows_source = 'manual (user, 2026-08-29)';
annotations.metadata.derived_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
annotations.metadata.n_boxes = n_box_total;
annotations.metadata.n_pending_frames = n_pending;
annotations.frames = out_frames;

out_file = fullfile(opts.sample_dir, 'annotations.json');
fid_out = fopen(out_file, 'w', 'n', 'UTF-8');
fprintf(fid_out, '%s', jsonencode(annotations, 'PrettyPrint', true));
fclose(fid_out);
fprintf('\n[完成] 标注写入 %s\n', out_file);
if opts.make_overlays
    fprintf('       校核图 %s\n', overlay_dir);
end
end

% =========================================================================
function w = normalize_windows(raw)
%NORMALIZE_WINDOWS jsondecode 对 [[a,b]] 会给出 1x2 行向量，对 [[a,b],[c,d]]
% 给出 2x2 矩阵，对 [] 给出 0x0。统一成 Nx2。
if isempty(raw); w = zeros(0, 2); return; end
if isvector(raw) && numel(raw) == 2; w = reshape(raw, 1, 2); return; end
w = raw;
end

% =========================================================================
function u_norm = frame_fluctuation(denoise, stats, fid, mode_indices, domain_mask)
%FRAME_FLUCTUATION 重构单帧并归一化成 u'/u_rms，与 generate_annotation_samples
% 的口径逐行一致（含按 repeat 分段去均值）——两边不一致就等于标注和图看的不是
% 同一个场。
[U_pod, ~] = tblR2.pod_denoise_reconstruct_frame(denoise, fid, mode_indices);
if isfield(stats, 'repeat_means') && ~isempty(stats.repeat_means)
    rep = 1 + nnz(fid > stats.repeat_boundaries(:)');
    mean_U = squeeze(stats.repeat_means(1, rep, :, :));
else
    mean_U = squeeze(stats.Uavex);
end
u_norm = (U_pod - mean_U) ./ stats.u_rms;
u_norm(~domain_mask) = NaN;
end

% =========================================================================
function box = derive_one_box(u_norm, x_mm, y_mm, delta_grid, xa, xb, frac)
%DERIVE_ONE_BOX 在给定 x 窗口内定法向边界。
%
% 半峰宽而非阈值分割：先按 x 向平均剖面找主导符号与峰值行，再向两侧连续生长到
% 峰值的 frac 倍。连续性是硬要求——不连续地"凑"出一段会把两个分离的结构并成
% 一个框。

box = [];
cols = find(x_mm >= xa & x_mm <= xb);
if isempty(cols); return; end

block = u_norm(:, cols);
profile = mean(block, 2, 'omitnan');   % 逐行 x 向平均
if ~any(isfinite(profile)); return; end

[peak_abs, j_peak] = max(abs(profile));
if ~isfinite(peak_abs) || peak_abs <= 0; return; end
s = sign(profile(j_peak));             % +1 高速条纹 / -1 低速条纹

signed = s * profile;                  % 主导符号方向上的幅值
thr = frac * peak_abs;

% 从峰值行向下、向上连续生长
j_lo = j_peak;
while j_lo > 1 && isfinite(signed(j_lo-1)) && signed(j_lo-1) >= thr
    j_lo = j_lo - 1;
end
j_hi = j_peak;
while j_hi < numel(signed) && isfinite(signed(j_hi+1)) && signed(j_hi+1) >= thr
    j_hi = j_hi + 1;
end

y_lo = y_mm(j_lo);
y_hi = y_mm(j_hi);

% x 边界吸附到实际网格列，报回吸附后的值——避免标注写着 1mm 而网格最小是
% 0.258mm 这种对不上的坐标
x_lo = x_mm(cols(1));
x_hi = x_mm(cols(end));
len = x_hi - x_lo;

% 框内 delta99 取中位数（delta99 沿 x 从 14.9 涨到 37.6mm，用单点会偏）
d_block = delta_grid(j_lo:j_hi, cols);
d99 = median(d_block(isfinite(d_block)));

% 框内主导符号侧的实际幅值统计
core = block(j_lo:j_hi, :);
core_signed = s * core;
core_signed = core_signed(isfinite(core_signed));

box = struct( ...
    'x_min', round(x_lo, 3), 'x_max', round(x_hi, 3), ...
    'y_min', round(y_lo, 3), 'y_max', round(y_hi, 3), ...
    'length_mm', round(len, 3), ...
    'height_mm', round(y_hi - y_lo, 3), ...
    'center_x', round(0.5*(x_lo + x_hi), 3), ...
    'center_y', round(0.5*(y_lo + y_hi), 3), ...
    'sign', s, ...
    'type', tern(s > 0, 'high_speed', 'low_speed'), ...
    'peak_amplitude', round(peak_abs, 4), ...
    'mean_amplitude', round(mean(core_signed), 4), ...
    'delta99_mm', round(d99, 3), ...
    'length_over_delta99', round(len / d99, 3), ...
    'height_over_delta99', round((y_hi - y_lo) / d99, 3), ...
    'meets_vlsm_criterion', (len / d99) >= 3, ...
    'x_window_requested', [xa, xb], ...
    'notes', sprintf('%s条纹，x 窗口人工标定，y 由半峰宽(%.0f%%)推导', ...
        tern(s > 0, '高速', '低速'), frac*100));
end

% =========================================================================
function save_overlay(overlay_dir, fid, x_mm, y_mm, u_norm, boxes, e_target, rank_r, cfg)
%SAVE_OVERLAY 输出叠框校核图。人工必须能一眼看出框有没有套住结构。
fig = figure('Visible', 'off', 'Position', [100 100 1200 400]);
ax = axes(fig);
contourf(ax, x_mm, y_mm, u_norm, 60, 'LineStyle', 'none');
axis(ax, 'tight'); set(ax, 'YDir', 'normal');
finite_vals = u_norm(isfinite(u_norm));
clim_val = quantile(abs(finite_vals), 0.995);
clim(ax, [-clim_val, clim_val]);
colormap(ax, tblR2.viz.resolve_case_colormap('balance', 256));
colorbar(ax); hold(ax, 'on');

for i = 1:numel(boxes)
    b = boxes{i};
    rectangle(ax, 'Position', [b.x_min, b.y_min, ...
        b.x_max - b.x_min, b.y_max - b.y_min], ...
        'EdgeColor', 'k', 'LineWidth', 2, 'LineStyle', '-');
    text(ax, b.center_x, b.y_max, sprintf('%s L/\\delta=%.1f', ...
        tern(b.sign > 0, 'H', 'L'), b.length_over_delta99), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
        'FontWeight', 'bold', 'BackgroundColor', [1 1 1 0.7]);
end
hold(ax, 'off');

xlabel(ax, 'x (mm)'); ylabel(ax, '离壁距离 (mm)');
title(ax, sprintf('Frame %d | E=%g%% rank=%d | u''/u_{rms} + 人工标注框', ...
    fid, e_target*100, rank_r), 'Interpreter', 'tex');
tblR2.viz.apply_fov_aspect(ax, cfg);
saveas(fig, fullfile(overlay_dir, sprintf('frame_%04d.png', fid)));
close(fig);
end

% =========================================================================
function out = tern(cond, a, b)
if cond; out = a; else; out = b; end
end
