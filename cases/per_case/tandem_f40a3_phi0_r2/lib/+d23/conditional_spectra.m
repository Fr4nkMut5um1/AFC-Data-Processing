function result = conditional_spectra(pairs, ctx, stats, cfg, pod_file)
%CONDITIONAL_SPECTRA Paired SS/noSS u spectra on a common no-extrapolation grid.
if nargin < 5
    pod_file = '';
end
thresholds = double(cfg.detection.length_thresholds(:));
row_ids = [ctx.lower_spectrum_row ctx.upper_spectrum_row];
row_labels = ["lower_2p6sqrtRe" "upper_0p5Re"];
matched_pairs = pairs(pairs.Matched, :);
if isempty(matched_pairs)
    result = empty_result(thresholds);
    return;
end
widths = double(matched_pairs.SSColMax - matched_pairs.SSColMin + 1);
rho_min = 2 * (ctx.dx_mm / 1000) / (ctx.delta99_mm / 1000);
rho_max = max(widths) * ctx.dx_mm / ctx.delta99_mm;
lambda_grid = logspace(log10(rho_min), log10(rho_max), ...
    cfg.spectra.n_lambda).';
n_threshold = numel(thresholds);
n_rows = numel(row_ids);
n_grid = numel(lambda_grid);
sum_ss = zeros(n_threshold, n_rows, n_grid);
sum_noss = zeros(size(sum_ss));
count = zeros(size(sum_ss), 'uint32');
large_ss = zeros(n_threshold, n_rows);
large_noss = zeros(n_threshold, n_rows);
total_ss = zeros(n_threshold, n_rows);
total_noss = zeros(n_threshold, n_rows);
energy_count = zeros(n_threshold, n_rows, 'uint32');
dx_m = ctx.dx_mm / 1000;
delta_m = ctx.delta99_mm / 1000;
for i = 1:height(matched_pairs)
    pair = matched_pairs(i, :);
    fields = d23.fluctuation_chunk(ctx, stats, cfg, ...
        double(pair.FrameOrdinal), pod_file);
    up = squeeze(fields.up(1, :, :));
    ss_cols = double(pair.SSColMin):double(pair.SSColMax);
    no_cols = double(pair.NoSSColMin):double(pair.NoSSColMax);
    qualifies = double(pair.Lx_over_delta) > thresholds;
    for r = 1:n_rows
        z_ss = up(row_ids(r), ss_cols);
        z_no = up(row_ids(r), no_cols);
        if any(~isfinite(z_ss)) || any(~isfinite(z_no))
            continue;
        end
        s_ss = d23.spatial_periodogram(z_ss, dx_m, ...
            cfg.spectra.zero_padding_factor);
        s_no = d23.spatial_periodogram(z_no, dx_m, ...
            cfg.spectra.zero_padding_factor);
        f = s_ss.frequency_cpm;
        resolved = f > 0 & f >= (1 / s_ss.record_length_m);
        rho = 1 ./ (f(resolved) * delta_m);
        q_ss = s_ss.premultiplied(resolved);
        q_no = s_no.premultiplied(resolved);
        [rho, order] = sort(rho, 'ascend');
        q_ss = q_ss(order);
        q_no = q_no(order);
        interp_ss = interp1(log(rho), q_ss, log(lambda_grid), 'linear', NaN);
        interp_no = interp1(log(rho), q_no, log(lambda_grid), 'linear', NaN);
        finite_pair = isfinite(interp_ss) & isfinite(interp_no);
        large_mask = resolved & f <= 1 / (...
            cfg.spectra.large_scale_min_lambda_over_delta * delta_m);
        total_mask = resolved;
        e_large_ss = s_ss.df_cpm * sum(s_ss.psd_per_cpm(large_mask));
        e_large_no = s_no.df_cpm * sum(s_no.psd_per_cpm(large_mask));
        e_total_ss = s_ss.df_cpm * sum(s_ss.psd_per_cpm(total_mask));
        e_total_no = s_no.df_cpm * sum(s_no.psd_per_cpm(total_mask));
        for k = find(qualifies(:).')
            target_ss = squeeze(sum_ss(k, r, :));
            target_no = squeeze(sum_noss(k, r, :));
            target_count = squeeze(count(k, r, :));
            target_ss(finite_pair) = target_ss(finite_pair) + interp_ss(finite_pair);
            target_no(finite_pair) = target_no(finite_pair) + interp_no(finite_pair);
            target_count(finite_pair) = target_count(finite_pair) + 1;
            sum_ss(k, r, :) = target_ss;
            sum_noss(k, r, :) = target_no;
            count(k, r, :) = target_count;
            large_ss(k, r) = large_ss(k, r) + e_large_ss;
            large_noss(k, r) = large_noss(k, r) + e_large_no;
            total_ss(k, r) = total_ss(k, r) + e_total_ss;
            total_noss(k, r) = total_noss(k, r) + e_total_no;
            energy_count(k, r) = energy_count(k, r) + 1;
        end
    end
end
mean_ss = sum_ss ./ double(count);
mean_noss = sum_noss ./ double(count);
mean_ss(count == 0) = NaN;
mean_noss(count == 0) = NaN;

rows = cell(n_threshold * n_rows, 1);
energy_rows = cell(n_threshold * n_rows, 1);
slot = 0;
for k = 1:n_threshold
    for r = 1:n_rows
        slot = slot + 1;
        rows{slot} = table(repmat(thresholds(k), n_grid, 1), ...
            repmat(row_labels(r), n_grid, 1), ...
            repmat(ctx.wall_y_plus(row_ids(r)), n_grid, 1), lambda_grid, ...
            squeeze(mean_ss(k,r,:)), squeeze(mean_noss(k,r,:)), ...
            squeeze(count(k,r,:)), ...
            'VariableNames', {'LengthThreshold','RowLabel','WallY_plus', ...
            'LambdaX_over_delta','SSPremultiplied','NoSSPremultiplied', ...
            'EnsembleCount'});
        n_energy = double(energy_count(k,r));
        if n_energy > 0
            m_large_ss = large_ss(k,r) / n_energy;
            m_large_no = large_noss(k,r) / n_energy;
            m_total_ss = total_ss(k,r) / n_energy;
            m_total_no = total_noss(k,r) / n_energy;
        else
            m_large_ss = NaN; m_large_no = NaN;
            m_total_ss = NaN; m_total_no = NaN;
        end
        energy_rows{slot} = table(thresholds(k), row_labels(r), ...
            ctx.wall_y_plus(row_ids(r)), uint32(n_energy), ...
            m_large_ss, m_large_no, m_large_ss / m_large_no, ...
            m_total_ss, m_total_no, m_large_ss / m_total_ss, ...
            m_large_no / m_total_no, ...
            'VariableNames', {'LengthThreshold','RowLabel','WallY_plus', ...
            'PairCount','MeanLargeScaleEnergySS','MeanLargeScaleEnergyNoSS', ...
            'SS_to_NoSS_LargeScaleRatio','MeanResolvedEnergySS', ...
            'MeanResolvedEnergyNoSS','LargeScaleFractionSS', ...
            'LargeScaleFractionNoSS'});
    end
end
result = struct('lambda_grid', lambda_grid, ...
    'spectra_table', vertcat(rows{:}), ...
    'energy_table', vertcat(energy_rows{:}), ...
    'thresholds', thresholds, 'row_ids', row_ids, ...
    'row_labels', row_labels, ...
    'definition', ['One-sided spatial PSD of original u'', periodic Hamming, ' ...
    'fourfold zero padding, native-resolution masking, no extrapolation.']);
end

function result = empty_result(thresholds)
spectra_table = table(zeros(0,1), strings(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1,'uint32'), ...
    'VariableNames', {'LengthThreshold','RowLabel','WallY_plus', ...
    'LambdaX_over_delta','SSPremultiplied','NoSSPremultiplied','EnsembleCount'});
energy_table = table(zeros(0,1), strings(0,1), zeros(0,1), ...
    zeros(0,1,'uint32'), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    'VariableNames', {'LengthThreshold','RowLabel','WallY_plus','PairCount', ...
    'MeanLargeScaleEnergySS','MeanLargeScaleEnergyNoSS', ...
    'SS_to_NoSS_LargeScaleRatio','MeanResolvedEnergySS', ...
    'MeanResolvedEnergyNoSS','LargeScaleFractionSS','LargeScaleFractionNoSS'});
result = struct('lambda_grid', zeros(0,1), 'spectra_table', spectra_table, ...
    'energy_table', energy_table, 'thresholds', thresholds, ...
    'row_ids', zeros(1,0), 'row_labels', strings(1,0), ...
    'definition', 'No matched noSS pairs; spectra are empty.');
end
