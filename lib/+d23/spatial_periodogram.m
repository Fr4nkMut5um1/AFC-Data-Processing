function spectrum = spatial_periodogram(signal, dx_m, zero_padding_factor)
%SPATIAL_PERIODOGRAM One-sided Hamming spatial PSD without local detrending.
signal = double(signal(:).');
if nargin < 3
    zero_padding_factor = 4;
end
if numel(signal) < 2 || any(~isfinite(signal)) || ...
        ~isscalar(dx_m) || ~isfinite(dx_m) || dx_m <= 0
    error('d23:spatial_periodogram:InvalidInput', ...
        'Signal must be finite with at least two samples and dx_m > 0.');
end
n = numel(signal);
nfft = 2 ^ nextpow2(zero_padding_factor * n);
window = hamming(n, 'periodic').';
transform = fft(signal .* window, nfft);
p2 = dx_m / sum(window .^ 2) * abs(transform) .^ 2;
j = nfft / 2 + 1;
p1 = p2(1:j);
if j > 2
    p1(2:j-1) = 2 * p1(2:j-1);
end
frequency_cpm = (0:(j-1)) / (nfft * dx_m);
spectrum = struct('frequency_cpm', frequency_cpm, ...
    'wavenumber_radpm', 2 * pi * frequency_cpm, ...
    'psd_per_cpm', p1, 'premultiplied', frequency_cpm .* p1, ...
    'n_samples', n, 'nfft', nfft, 'dx_m', dx_m, ...
    'df_cpm', 1 / (nfft * dx_m), ...
    'record_length_m', n * dx_m, ...
    'window_energy', sum(window .^ 2), ...
    'weighted_mean_square', sum((signal .* window) .^ 2) / sum(window .^ 2));
end
