function result = catalog_branch_metrics(catalog, frame_ids, analysis_pixel_count, ...
    branch_name, rms_basis)
%CATALOG_BRANCH_METRICS Build comparable per-frame and length-CDF metrics.

frame_ids = double(frame_ids(:));
if ~(isscalar(analysis_pixel_count) && isfinite(analysis_pixel_count) && ...
        analysis_pixel_count >= 1)
    error('tblR2:catalog_branch_metrics:InvalidArea', ...
        'analysis_pixel_count 必须是正数。');
end
if isempty(catalog)
    catalog = table();
elseif ~istable(catalog)
    error('tblR2:catalog_branch_metrics:InvalidCatalog', ...
        'catalog 必须是 table。');
end

rows = cell(numel(frame_ids), 1);
for k = 1:numel(frame_ids)
    frame_id = frame_ids(k);
    if isempty(catalog) || ~ismember('FrameID', catalog.Properties.VariableNames)
        subset = table();
    else
        subset = catalog(catalog.FrameID == frame_id, :);
    end
    if isempty(subset)
        lengths = zeros(0, 1);
        pixels = zeros(0, 1);
        lsm_count = 0;
        vlsm_count = 0;
    else
        lengths = double(subset.LengthX_over_delta);
        pixels = double(subset.PixelCount);
        lsm_count = nnz(subset.IsLSM);
        vlsm_count = nnz(subset.IsVLSM);
    end
    rows{k} = table(frame_id, {branch_name}, {rms_basis}, height(subset), ...
        lsm_count, vlsm_count, sum(pixels, 'omitnan') / analysis_pixel_count, ...
        percentile(lengths, 0.50), percentile(lengths, 0.90), ...
        'VariableNames', {'FrameID','Branch','RMSBasis','StructureCount', ...
        'LSMCount','VLSMCount','OccupiedAreaFraction', ...
        'MedianLengthXOverDelta','P90LengthXOverDelta'});
end

result = struct();
result.catalog = catalog;
result.frame_metrics = vertcat(rows{:});
result.length_cdf = length_cdf(catalog);
end

function value = percentile(values, probability)
values = sort(values(isfinite(values)));
if isempty(values)
    value = NaN;
    return;
end
position = 1 + (numel(values) - 1) * probability;
lo = floor(position); hi = ceil(position);
if lo == hi
    value = values(lo);
else
    value = values(lo) + (position - lo) * (values(hi) - values(lo));
end
end

function cdf = length_cdf(catalog)
cdf = struct('x', zeros(0,1), 'F', zeros(0,1), 'n', 0);
if isempty(catalog) || height(catalog) == 0
    return;
end
values = sort(double(catalog.LengthX_over_delta));
values = values(isfinite(values));
cdf.x = values(:);
cdf.n = numel(values);
cdf.F = ((1:numel(values))' ./ max(numel(values), 1));
end
