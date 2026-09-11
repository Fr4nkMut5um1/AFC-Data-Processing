function audit_annotation_detectability(varargin)
%AUDIT_ANNOTATION_DETECTABILITY 检查人工标注框内的逐点幅值能否被现行 alpha 检出。
%
% 为什么需要：derive_annotation_boxes 报的 peak 是 x 向平均剖面的峰值，平均会
% 削峰，不能直接和逐点阈值 alpha 比。要判断"现行参数能不能检出这些结构"，必须
% 看框内逐点 |u'|/u_rms 的分布。
%
% 同时检查框是否贴可信域边界——cfg.structures.reject_trusted_boundary_touching
% 为真时，贴边的结构会被整体丢弃，那是与 alpha 无关的第二条淘汰路径。

p = inputParser;
addParameter(p, 'sample_dir', 'tmp/annotation_samples/e60', @ischar);
addParameter(p, 'case_name', 'tandem_baseline_r2', @ischar);
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
mode_indices = 1:rank_r;

x_mm = stats.X(1, :);
y_mm = mean_bl.wall_distance_mm(:, 1);
delta_grid = interp1(mean_bl.boundary_layer.x, ...
    mean_bl.boundary_layer.delta99, stats.X, 'linear', NaN);
valid_mask = stats.accepted_mask & isfinite(delta_grid) & delta_grid > 0;
domain_mask = tblR2.trusted_domain_mask(valid_mask, mean_bl.wall_distance_mm, ...
    cfg.structures.trusted_domain);

% 可信域每列的最低/最高有效行，用于判断贴边
first_row = zeros(1, numel(x_mm)); last_row = zeros(1, numel(x_mm));
for i = 1:numel(x_mm)
    r = find(domain_mask(:, i));
    if isempty(r); first_row(i) = NaN; last_row(i) = NaN;
    else; first_row(i) = r(1); last_row(i) = r(end); end
end

thresholds = [1.2, 1.0, 0.7, 0.5, 0.4];
fprintf('alpha now = %.2f, seed_alpha = %.2f, min_abs_fluctuation = %.2f\n', ...
    cfg.structures.alpha, cfg.structures.seed_alpha, ...
    cfg.structures.min_abs_fluctuation);
fprintf('reject_trusted_boundary_touching = %d, min_pixels = %d, conn = %d\n\n', ...
    cfg.structures.reject_trusted_boundary_touching, ...
    cfg.structures.min_pixels, cfg.structures.connectivity);

fprintf('%-12s %5s %6s %6s', 'frame', 'type', 'p90', 'max');
for t = thresholds; fprintf(' %7s', sprintf('f>%.1f', t)); end
fprintf('  %s\n', 'edge');
fprintf('%s\n', repmat('-', 1, 78));

keys = fieldnames(ann.frames);
agg = zeros(0, numel(thresholds));
for k = 1:numel(keys)
    rec = ann.frames.(keys{k});
    boxes = rec.vlsm_boxes;
    if isempty(boxes); continue; end
    if ~iscell(boxes); boxes = num2cell(boxes); end

    u_norm = frame_fluctuation(denoise, stats, rec.frame_id, mode_indices, domain_mask);

    for b = 1:numel(boxes)
        bx = boxes{b};
        cols = find(x_mm >= bx.x_min - 1e-9 & x_mm <= bx.x_max + 1e-9);
        rowsel = find(y_mm >= bx.y_min - 1e-9 & y_mm <= bx.y_max + 1e-9);
        core = bx.sign * u_norm(rowsel, cols);
        core = core(isfinite(core));
        if isempty(core); continue; end

        frac = zeros(1, numel(thresholds));
        for t = 1:numel(thresholds)
            frac(t) = mean(core >= thresholds(t));
        end
        agg(end+1, :) = frac; %#ok<AGROW>

        touch = '';
        if any(rowsel(1) <= first_row(cols)); touch = [touch 'bottom ']; end
        if any(rowsel(end) >= last_row(cols)); touch = [touch 'top ']; end
        if cols(1) <= 1 || cols(end) >= numel(x_mm); touch = [touch 'x-edge']; end
        if isempty(touch); touch = '-'; end

        fprintf('%-12s %5s %6.2f %6.2f', keys{k}, ...
            tern(bx.sign > 0, 'HIGH', 'LOW'), quantile(core, 0.90), max(core));
        for t = 1:numel(thresholds); fprintf(' %6.1f%%', 100*frac(t)); end
        fprintf('  %s\n', touch);
    end
end

fprintf('%s\n', repmat('-', 1, 78));
fprintf('%-12s %5s %6s %6s', 'MEAN', '', '', '');
for t = 1:numel(thresholds); fprintf(' %6.1f%%', 100*mean(agg(:, t))); end
fprintf('\n\nn_boxes = %d\n', size(agg, 1));
end

% =========================================================================
function u_norm = frame_fluctuation(denoise, stats, fid, mode_indices, domain_mask)
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
function out = tern(cond, a, b)
if cond; out = a; else; out = b; end
end
