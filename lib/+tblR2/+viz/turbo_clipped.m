function cmap = turbo_clipped(n, trim_low, trim_high)
%TURBO_CLIPPED Reference turbo map with dark-end trimming.

if nargin < 1 || isempty(n), n = 256; end
if nargin < 2 || isempty(trim_low), trim_low = 0.12; end
if nargin < 3 || isempty(trim_high), trim_high = 0.12; end
full_map = turbo(512);
keep_start = round(512 * trim_low);
keep_end = round(512 * (1 - trim_high));
trimmed = full_map(keep_start:keep_end, :);
xi = linspace(1, size(trimmed, 1), n);
cmap = interp1(1:size(trimmed, 1), trimmed, xi);
end
