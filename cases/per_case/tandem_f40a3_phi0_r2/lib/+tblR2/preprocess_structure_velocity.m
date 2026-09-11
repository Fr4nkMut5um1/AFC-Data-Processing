function result = preprocess_structure_velocity( ...
        U, V, frame_valid_mask, analysis_domain_mask, options)
%PREPROCESS_STRUCTURE_VELOCITY Apply the Section-4 ordinary Gaussian step.
% LaVision has already performed vector-quality screening before export, so
% this function intentionally performs no additional UOD/anomaly detection.
% If enabled, it applies one ordinary 2-D Gaussian convolution to U and V;
% there is no mask-normalized support weighting and no FFT low-pass step.

if ~isequal(size(U), size(V), size(frame_valid_mask), ...
        size(analysis_domain_mask)) || ~islogical(frame_valid_mask) || ...
        ~islogical(analysis_domain_mask)
    error('tblR2:preprocess_structure_velocity:SizeMismatch', ...
        'U、V 以及两个逻辑掩膜必须是尺寸相同的二维数组。');
end
input_valid = frame_valid_mask & analysis_domain_mask & ...
    isfinite(U) & isfinite(V);
outlier_mask = false(size(U));
outlier = struct('outlier_mask', outlier_mask, ...
    'method', 'not applied; LaVision export already screened vectors', ...
    'reference_doi', '');
source_mask = input_valid;

if options.gaussian.enabled
    gaussian_options = options.gaussian;
    [U_processed, U_gaussian_mask, U_gaussian] = ...
        tblR2.simple_gaussian_filter2( ...
        U, source_mask, options.gaussian.sigma_cells, ...
        options.gaussian.radius_cells, gaussian_options);
    [V_processed, V_gaussian_mask, V_gaussian] = ...
        tblR2.simple_gaussian_filter2( ...
        V, source_mask, options.gaussian.sigma_cells, ...
        options.gaussian.radius_cells, gaussian_options);
    U_gaussian.output_mask = U_gaussian_mask;
    V_gaussian.output_mask = V_gaussian_mask;
    output_valid = input_valid & isfinite(U_processed) & isfinite(V_processed);
else
    U_processed = double(U);
    V_processed = double(V);
    output_valid = source_mask;
    U_processed(~output_valid) = NaN;
    V_processed(~output_valid) = NaN;
    U_gaussian = struct('output_mask', output_valid, ...
        'method', 'disabled');
    V_gaussian = U_gaussian;
end
U_processed(~output_valid) = NaN;
V_processed(~output_valid) = NaN;

result = struct();
result.U = U_processed;
result.V = V_processed;
result.input_valid_mask = input_valid;
result.source_valid_mask = source_mask;
result.output_valid_mask = output_valid;
result.outlier_mask = outlier_mask;
result.reconstructed_outlier_mask = outlier_mask & output_valid;
result.outlier = outlier;
result.gaussian_U = U_gaussian;
result.gaussian_V = V_gaussian;
result.options = options;
result.counts = struct( ...
    'input_valid', nnz(input_valid), ...
    'outliers', nnz(outlier_mask), ...
    'source_valid', nnz(source_mask), ...
    'output_valid', nnz(output_valid), ...
    'reconstructed_outliers', nnz(outlier_mask & output_valid));
result.method = 'ordinary 2-D Gaussian blur only; no UOD or mask normalization';
end
