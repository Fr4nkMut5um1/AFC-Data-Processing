function selection = elf_mode_selection(joint_modes, sequence, opts)
%ELF_MODE_SELECTION Entropy-line-fit POD mode selection for PIV denoising.
%
% Each joint u-v spatial mode is mapped to the common POD grid.  A separable
% orthonormal DCT-II is applied to U and V independently; the smaller Shannon
% spectral entropy is retained for that joint mode.  Entropies are sorted and
% a two-line breakpoint is selected by the maximum R^2/sigma score.  Modes on
% the low-entropy side are retained, so the selected original POD indices need
% not be consecutive.  The calculation is repeated with zero-filled internal
% holes as a mask-sensitivity check.

if nargin < 3 || isempty(opts)
    opts = struct();
end
opts = defaults(opts);
required = {'n_spatial','spatial_mask'};
if ~isstruct(sequence) || ~all(isfield(sequence, required))
    error('tblR2:elf_mode_selection:InvalidSequence', ...
        'sequence 缺少 n_spatial 或 spatial_mask。');
end
if size(joint_modes, 1) ~= 2 * sequence.n_spatial
    error('tblR2:elf_mode_selection:ModeSizeMismatch', ...
        'joint_modes 行数必须等于 2*sequence.n_spatial。');
end
n_modes = size(joint_modes, 2);
if n_modes < 1
    error('tblR2:elf_mode_selection:NoModes', ...
        '至少需要一个 POD 模态。');
end

mask = logical(sequence.spatial_mask);
[mask_rows, mask_cols] = find(mask);
if isempty(mask_rows)
    error('tblR2:elf_mode_selection:EmptyMask', 'POD 空间掩膜为空。');
end
row_box = min(mask_rows):max(mask_rows);
col_box = min(mask_cols):max(mask_cols);
mask_box = mask(row_box, col_box);
[Ty, Tx] = dct_operators(size(mask_box, 1), size(mask_box, 2));

entropy_nearest = inf(n_modes, 1);
entropy_zero = inf(n_modes, 1);
n_spatial = sequence.n_spatial;
for k = 1:n_modes
    u_mode = nan(size(mask));
    v_mode = nan(size(mask));
    u_mode(mask) = double(joint_modes(1:n_spatial, k));
    v_mode(mask) = double(joint_modes(n_spatial + 1:end, k));
    u_box = u_mode(row_box, col_box);
    v_box = v_mode(row_box, col_box);

    u_nearest = propagate_holes(u_box, mask_box);
    v_nearest = propagate_holes(v_box, mask_box);
    entropy_nearest(k) = min(spectral_entropy(Ty * u_nearest * Tx'), ...
        spectral_entropy(Ty * v_nearest * Tx'));

    u_zero = u_box; u_zero(~mask_box) = 0;
    v_zero = v_box; v_zero(~mask_box) = 0;
    entropy_zero(k) = min(spectral_entropy(Ty * u_zero * Tx'), ...
        spectral_entropy(Ty * v_zero * Tx'));
end

primary = breakpoint_fit(entropy_nearest, opts);
robustness = breakpoint_fit(entropy_zero, opts);
mode_indices = primary.mode_indices;
zero_indices = robustness.mode_indices;
union_count = numel(union(mode_indices, zero_indices));
if union_count == 0
    mask_jaccard = 0;
else
    mask_jaccard = numel(intersect(mode_indices, zero_indices)) / union_count;
end

reasons = strings(0, 1);
if ~primary.fit_valid
    reasons(end + 1) = "two-line fit unavailable";
elseif primary.ppr < opts.min_ppr
    reasons(end + 1) = sprintf("PPR %.4g < %.4g", ...
        primary.ppr, opts.min_ppr);
end
if ~robustness.fit_valid
    reasons(end + 1) = "zero-fill robustness fit unavailable";
elseif mask_jaccard < opts.min_mask_jaccard
    reasons(end + 1) = sprintf("mask Jaccard %.4g < %.4g", ...
        mask_jaccard, opts.min_mask_jaccard);
end

selection = struct();
selection.valid = isempty(reasons);
selection.failure_reasons = cellstr(reasons);
selection.mode_indices = mode_indices(:);
selection.n_modes = numel(mode_indices);
selection.entropy = entropy_nearest;
selection.entropy_zero_fill = entropy_zero;
selection.sorted_mode_indices = primary.sorted_mode_indices;
selection.sorted_entropy = primary.sorted_entropy;
selection.breakpoint_rank = primary.breakpoint_rank;
selection.entropy_cutoff = primary.entropy_cutoff;
selection.score = primary.score;
selection.ppr = primary.ppr;
selection.zero_fill_mode_indices = zero_indices(:);
selection.mask_jaccard = mask_jaccard;
selection.options = opts;
selection.mask_bbox_rows = row_box([1 end]);
selection.mask_bbox_columns = col_box([1 end]);
selection.definition = ['ELF-style POD truncation: orthonormal DCT-II spectral ' ...
    'Shannon entropy per U/V spatial mode, joint entropy=min(Hu,Hv), sorted ' ...
    'two-line R^2/sigma breakpoint, non-contiguous original mode retention. ' ...
    'Failure is closed when PPR or mask robustness is insufficient.'];
end

function opts = defaults(opts)
if ~isfield(opts, 'min_ppr') || isempty(opts.min_ppr); opts.min_ppr = 1.8; end
if ~isfield(opts, 'min_mask_jaccard') || isempty(opts.min_mask_jaccard)
    opts.min_mask_jaccard = 0.90;
end
if ~isfield(opts, 'min_segment_modes') || isempty(opts.min_segment_modes)
    opts.min_segment_modes = 3;
end
if ~(isscalar(opts.min_ppr) && isfinite(opts.min_ppr) && opts.min_ppr > 0)
    error('tblR2:elf_mode_selection:InvalidPPR', 'min_ppr 必须为有限正数。');
end
if ~(isscalar(opts.min_mask_jaccard) && isfinite(opts.min_mask_jaccard) && ...
        opts.min_mask_jaccard >= 0 && opts.min_mask_jaccard <= 1)
    error('tblR2:elf_mode_selection:InvalidJaccard', ...
        'min_mask_jaccard 必须位于 [0,1]。');
end
if ~(isscalar(opts.min_segment_modes) && isfinite(opts.min_segment_modes) && ...
        opts.min_segment_modes >= 2 && opts.min_segment_modes == fix(opts.min_segment_modes))
    error('tblR2:elf_mode_selection:InvalidSegmentLength', ...
        'min_segment_modes 必须是不小于 2 的整数。');
end
end

function [Ty, Tx] = dct_operators(n_rows, n_cols)
Ty = dct_matrix(n_rows);
Tx = dct_matrix(n_cols);
end

function T = dct_matrix(n)
k = (0:n-1)';
j = 0:n-1;
T = sqrt(2 / n) .* cos(pi .* k .* (2 .* j + 1) ./ (2 .* n));
T(1, :) = T(1, :) ./ sqrt(2);
end

function filled = propagate_holes(field, mask)
filled = double(field);
known = mask & isfinite(filled);
filled(~known) = 0;
missing = ~known;
kernel = [0 1 0; 1 0 1; 0 1 0];
while any(missing(:))
    neighbor_count = conv2(double(known), kernel, 'same');
    candidates = missing & neighbor_count > 0;
    if ~any(candidates(:))
        filled(missing) = 0;
        break;
    end
    neighbor_sum = conv2(filled, kernel, 'same');
    filled(candidates) = neighbor_sum(candidates) ./ neighbor_count(candidates);
    known(candidates) = true;
    missing(candidates) = false;
end
end

function value = spectral_entropy(coefficients)
energy = abs(double(coefficients(:))) .^ 2;
total = sum(energy);
if ~(isfinite(total) && total > 0)
    value = Inf;
    return;
end
p = energy ./ total;
p = p(p > 0 & isfinite(p));
value = -sum(p .* log2(p));
end

function fit = breakpoint_fit(entropy_values, opts)
finite_indices = find(isfinite(entropy_values));
[sorted_entropy, local_order] = sort(entropy_values(finite_indices), 'ascend');
sorted_indices = finite_indices(local_order);
n = numel(sorted_entropy);
minimum = opts.min_segment_modes;
fit = struct('fit_valid', false, 'mode_indices', zeros(0,1), ...
    'sorted_mode_indices', sorted_indices(:), 'sorted_entropy', sorted_entropy(:), ...
    'breakpoint_rank', NaN, 'entropy_cutoff', NaN, 'score', [], 'ppr', NaN);
if n < 2 * minimum
    return;
end

candidate = minimum:(n - minimum);
score = nan(size(candidate));
for i = 1:numel(candidate)
    split = candidate(i);
    x1 = (1:split)'; y1 = sorted_entropy(1:split);
    x2 = (split + 1:n)'; y2 = sorted_entropy(split + 1:end);
    p1 = polyfit(x1, y1, 1);
    p2 = polyfit(x2, y2, 1);
    residual = [y1 - polyval(p1, x1); y2 - polyval(p2, x2)];
    sse = sum(residual .^ 2);
    sst = sum((sorted_entropy - mean(sorted_entropy)) .^ 2);
    r_squared = max(0, 1 - sse / max(sst, eps));
    sigma = sqrt(sse / max(n - 4, 1));
    score(i) = r_squared / max(sigma, eps);
end
if ~any(isfinite(score))
    fit.score = score(:);
    return;
end

local_peak = false(size(score));
for i = 1:numel(score)
    left = -Inf; right = -Inf;
    if i > 1; left = score(i - 1); end
    if i < numel(score); right = score(i + 1); end
    local_peak(i) = isfinite(score(i)) && score(i) >= left && score(i) >= right;
end
peak_values = score(local_peak);
[best_score, best_peak_order] = max(peak_values);
peak_positions = find(local_peak);
best_position = peak_positions(best_peak_order);
other_peaks = peak_values;
other_peaks(best_peak_order) = [];
if isempty(other_peaks)
    ppr = Inf;
else
    ppr = best_score / max(max(other_peaks), eps);
end
split = candidate(best_position);

fit.fit_valid = true;
fit.mode_indices = sorted_indices(1:split);
fit.breakpoint_rank = split;
fit.entropy_cutoff = sorted_entropy(split);
fit.score = score(:);
fit.ppr = ppr;
end
