function out = bootstrap_stability(per_frame, opts)
%BOOTSTRAP_STABILITY Bootstrap CI over frames and locate the stable plateau.
%   per_frame : [n_frames x n_sweep] metric, one row per frame
%   opts      : struct with fields
%                 n_boot          number of resamples (default 500)
%                 ci_level        central mass, e.g. 0.95 (default 0.95)
%                 max_rel_change  plateau tolerance on the median (default 0.10)
%                 min_run         minimum consecutive sweep points (default 3)
%                 rng_seed        integer seed so runs are reproducible
%
%   Frames are resampled with replacement as whole frames, which is the
%   correct unit: pixels within a frame are spatially correlated, so a
%   pixel-level bootstrap would badly understate the uncertainty.
%
%   The plateau rule requires BOTH, over a run of at least min_run points:
%     (a) consecutive bootstrap CIs overlap, and
%     (b) the relative change in the median stays within max_rel_change.
%   (a) alone is too permissive when the CI is wide; (b) alone ignores
%   sampling error.  A run satisfying only one is not reported as stable.

if nargin < 2 || isempty(opts)
    opts = struct();
end
opts = fill_default(opts, 'n_boot', 500);
opts = fill_default(opts, 'ci_level', 0.95);
opts = fill_default(opts, 'max_rel_change', 0.10);
opts = fill_default(opts, 'min_run', 3);
opts = fill_default(opts, 'rng_seed', 20260824);

[n_frames, n_sweep] = size(per_frame);
if n_frames < 2
    error('tblR2:bootstrap_stability:TooFewFrames', ...
        'Bootstrap 需要至少 2 帧，当前 %d 帧。', n_frames);
end

lo_q = (1 - opts.ci_level) / 2;
hi_q = 1 - lo_q;

% Reproducible stream, isolated so the caller's global rng is untouched.
stream = RandStream('mt19937ar', 'Seed', opts.rng_seed);

median_val = nan(1, n_sweep);
ci_lo      = nan(1, n_sweep);
ci_hi      = nan(1, n_sweep);
boot_med   = nan(opts.n_boot, n_sweep);

for b = 1:opts.n_boot
    pick = randi(stream, n_frames, [n_frames 1]);
    boot_med(b, :) = median(per_frame(pick, :), 1, 'omitnan');
end

for j = 1:n_sweep
    median_val(j) = median(per_frame(:, j), 'omitnan');
    col = boot_med(~isnan(boot_med(:, j)), j);
    if ~isempty(col)
        ci_lo(j) = quantile(col, lo_q);
        ci_hi(j) = quantile(col, hi_q);
    end
end

% Pairwise plateau tests between adjacent sweep points.
overlap    = false(1, max(n_sweep - 1, 0));
rel_change = nan(1, max(n_sweep - 1, 0));
for j = 1:n_sweep - 1
    overlap(j) = ci_lo(j) <= ci_hi(j + 1) && ci_lo(j + 1) <= ci_hi(j);
    denom = max(abs(median_val(j)), abs(median_val(j + 1)));
    if denom > 0
        rel_change(j) = abs(median_val(j + 1) - median_val(j)) / denom;
    elseif median_val(j) == median_val(j + 1)
        rel_change(j) = 0;
    end
end

link_ok = overlap & isfinite(rel_change) & rel_change <= opts.max_rel_change;

% Longest run of consecutive satisfied links; a run of k links spans k+1 points.
runs = find_runs(link_ok);
runs = runs(([runs.len] + 1) >= opts.min_run);

out = struct();
out.median      = median_val;
out.ci_lo       = ci_lo;
out.ci_hi       = ci_hi;
out.ci_level    = opts.ci_level;
out.n_boot      = opts.n_boot;
out.n_frames    = n_frames;
out.overlap     = overlap;
out.rel_change  = rel_change;
out.link_ok     = link_ok;
out.rng_seed    = opts.rng_seed;
out.max_rel_change = opts.max_rel_change;
out.min_run     = opts.min_run;

if isempty(runs)
    out.stable_found = false;
    out.stable_idx   = zeros(1, 0);
    out.plateau_runs = repmat(struct('first', 0, 'last', 0, 'len', 0), 0, 1);
    out.note = sprintf(['未找到稳定区：无连续 %d 个扫描点同时满足 ' ...
        'bootstrap 区间重叠与中位数相对变化 <= %.0f%%。' ...
        '建议扩展扫描范围或增加帧数。'], opts.min_run, 100 * opts.max_rel_change);
    return;
end

all_runs = repmat(struct('first', 0, 'last', 0, 'len', 0), numel(runs), 1);
for k = 1:numel(runs)
    all_runs(k).first = runs(k).first;          % first point index
    all_runs(k).last  = runs(k).last + 1;       % links -> points
    all_runs(k).len   = runs(k).len + 1;
end
[~, best] = max([all_runs.len]);

out.stable_found = true;
out.plateau_runs = all_runs;
out.stable_idx   = all_runs(best).first : all_runs(best).last;
out.note = '';
end

function s = fill_default(s, name, value)
if ~isfield(s, name) || isempty(s.(name))
    s.(name) = value;
end
end

function runs = find_runs(flags)
runs = repmat(struct('first', 0, 'last', 0, 'len', 0), 0, 1);
j = 1;
n = numel(flags);
while j <= n
    if ~flags(j)
        j = j + 1;
        continue;
    end
    k = j;
    while k < n && flags(k + 1)
        k = k + 1;
    end
    runs(end + 1, 1) = struct('first', j, 'last', k, 'len', k - j + 1); %#ok<AGROW>
    j = k + 1;
end
end
