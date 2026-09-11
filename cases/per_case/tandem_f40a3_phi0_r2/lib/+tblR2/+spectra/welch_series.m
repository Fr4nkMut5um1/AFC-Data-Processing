function [phi, frequency, diagnostics] = welch_series(series, window, ...
    noverlap, nfft, fs, min_valid_fraction)
%WELCH_SERIES Repair, detrend, and Welch-PSD a set of column signals.
% =========================================================================
% 【共享 helper 合同（Section 6 时域谱与参考谱共用）】
%   - 输入 series 为 n_frames x n_series 列信号；无效样本必须是 NaN
%     （调用方负责把 sampleValid=false 或非有限的样本写成 NaN）。
%   - 有效率 = 有效样本数 / n_frames；低于 min_valid_fraction 或有效样本
%     数不足 nfft 的整条序列被排除，其谱保持 NaN，绝不参与后续平均。
%   - 保留序列先 fillmissing(..., 'linear', 1, 'EndValues', 'nearest')
%     修复孤立坏点，再 detrend('linear') 去均值/趋势，最后 pwelch。
%   - 输出 phi 为 n_frequency x n_series，被排除序列对应列为 NaN；
%     diagnostics 记录逐列有效率、修复样本数和排除标记。
% =========================================================================

if nargin < 6 || isempty(min_valid_fraction)
    min_valid_fraction = 0;
end
[n_frames, n_series] = size(series);
finite = isfinite(series);
valid_fraction = sum(finite, 1) ./ n_frames;
valid_count = sum(finite, 1);
included = valid_fraction >= min_valid_fraction & valid_count >= nfft;
repaired_sample_count = sum(~finite, 1);

if any(included)
    work = series(:, included);
    if any(~isfinite(work), 'all')
        work = fillmissing(work, 'linear', 1, 'EndValues', 'nearest');
    end
    work = detrend(work, 'linear');
    [phi_included, frequency] = pwelch(work, window, noverlap, nfft, fs);
    phi = nan(size(phi_included, 1), n_series);
    phi(:, included) = phi_included;
else
    [~, frequency] = pwelch(zeros(n_frames, 1), window, noverlap, nfft, fs);
    phi = nan(numel(frequency), n_series);
end
diagnostics = struct('valid_fraction', valid_fraction, ...
    'repaired_sample_count', repaired_sample_count, ...
    'excluded_series', ~included);
end
