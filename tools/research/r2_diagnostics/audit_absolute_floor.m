function audit_absolute_floor(varargin)
%AUDIT_ABSOLUTE_FLOOR 量化 min_abs_fluctuation 绝对下限对标注结构的抑制作用。
%
% identify_structures.m 把两个判据做逻辑与：
%   |u'| >= alpha * u_rms        （归一化，随位置变）
%   |u'| >= min_abs_fluctuation  （绝对，m/s，全场同一个数）
% 外层 u_rms 小，绝对下限在那里等效于一个很大的 alpha。这个脚本报出两条判据各自
% 的通过率与联合通过率，看到底哪条在卡。

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

alpha = cfg.structures.alpha;
seed_alpha = cfg.structures.seed_alpha;
floor_abs = cfg.structures.min_abs_fluctuation;

ur = stats.u_rms(domain_mask);
ur = ur(isfinite(ur));
fprintf('=== u_rms scale over trusted domain (m/s) ===\n');
fprintf('  min=%.4f  p05=%.4f  median=%.4f  p95=%.4f  max=%.4f\n', ...
    min(ur), quantile(ur, .05), median(ur), quantile(ur, .95), max(ur));
fprintf('  absolute floor %.2f m/s equals %.2f x median(u_rms)\n', ...
    floor_abs, floor_abs / median(ur));
fprintf('  fraction of domain where alpha*u_rms >= floor : %.1f%%\n', ...
    100 * mean(alpha * ur >= floor_abs));
fprintf('  -> where that is false, the FLOOR is the binding gate, not alpha\n\n');

% u_rms 随离壁高度的分布：外层小，绝对下限在外层最狠
fprintf('=== u_rms vs wall distance (median per row) ===\n');
probe_y = [1 5 10 20 30 40 60 80 89];
for j = probe_y
    if j > numel(y_mm); continue; end
    row = stats.u_rms(j, :); row = row(domain_mask(j, :)); row = row(isfinite(row));
    if isempty(row); continue; end
    fprintf('  y=%5.2fmm  median u_rms=%.4f  alpha*u_rms=%.4f  floor/u_rms=%.2f\n', ...
        y_mm(j), median(row), alpha*median(row), floor_abs/median(row));
end
fprintf('\n');

fprintf('=== per-box gate pass rates ===\n');
fprintf('%-12s %5s %8s %8s %8s %8s %8s\n', 'frame', 'type', ...
    'med_urms', 'pass_a', 'pass_fl', 'pass_&', 'pass_sd');
fprintf('%s\n', repmat('-', 1, 66));

keys = fieldnames(ann.frames);
acc = zeros(0, 4);
for k = 1:numel(keys)
    rec = ann.frames.(keys{k});
    boxes = rec.vlsm_boxes;
    if isempty(boxes); continue; end
    if ~iscell(boxes); boxes = num2cell(boxes); end

    [U_pod, ~] = tblR2.pod_denoise_reconstruct_frame(denoise, rec.frame_id, mode_indices);
    if isfield(stats, 'repeat_means') && ~isempty(stats.repeat_means)
        rep = 1 + nnz(rec.frame_id > stats.repeat_boundaries(:)');
        mean_U = squeeze(stats.repeat_means(1, rep, :, :));
    else
        mean_U = squeeze(stats.Uavex);
    end
    u_abs = U_pod - mean_U;          % m/s
    u_abs(~domain_mask) = NaN;

    for b = 1:numel(boxes)
        bx = boxes{b};
        cols = find(x_mm >= bx.x_min - 1e-9 & x_mm <= bx.x_max + 1e-9);
        rowsel = find(y_mm >= bx.y_min - 1e-9 & y_mm <= bx.y_max + 1e-9);

        fl = bx.sign * u_abs(rowsel, cols);      % 主导符号方向的绝对幅值 m/s
        rms_blk = stats.u_rms(rowsel, cols);
        ok = isfinite(fl) & isfinite(rms_blk);
        fl = fl(ok); rms_blk = rms_blk(ok);
        if isempty(fl); continue; end

        pass_a  = mean(fl >= alpha * rms_blk);
        pass_fl = mean(fl >= floor_abs);
        pass_both = mean(fl >= alpha * rms_blk & fl >= floor_abs);
        pass_seed = mean(fl >= seed_alpha * rms_blk & fl >= floor_abs);
        acc(end+1, :) = [pass_a, pass_fl, pass_both, pass_seed]; %#ok<AGROW>

        fprintf('%-12s %5s %8.4f %7.1f%% %7.1f%% %7.1f%% %7.1f%%\n', ...
            keys{k}, tern(bx.sign > 0, 'HIGH', 'LOW'), median(rms_blk), ...
            100*pass_a, 100*pass_fl, 100*pass_both, 100*pass_seed);
    end
end

fprintf('%s\n', repmat('-', 1, 66));
fprintf('%-12s %5s %8s %7.1f%% %7.1f%% %7.1f%% %7.1f%%\n', 'MEAN', '', '', ...
    100*mean(acc(:,1)), 100*mean(acc(:,2)), 100*mean(acc(:,3)), 100*mean(acc(:,4)));
fprintf('\nn_boxes=%d   (pass_a = alpha gate only, pass_fl = floor only,\n', size(acc,1));
fprintf('             pass_& = both = what growth mask actually keeps,\n');
fprintf('             pass_sd = seed gate + floor = what can seed a component)\n');
fprintf('\nboxes with ZERO seed pixels: %d  <- these are undetectable at any\n', ...
    sum(acc(:,4) == 0));
fprintf('                                  merge/connectivity setting\n');
end

% =========================================================================
function out = tern(cond, a, b)
if cond; out = a; else; out = b; end
end
