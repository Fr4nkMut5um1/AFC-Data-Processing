function m = percolation_metrics(positive_mask, negative_mask, ...
    analysis_mask, connectivity, n_retained)
%PERCOLATION_METRICS Scalar percolation/geometry metrics for one frame.
%   Computed from the SIGNED masks that identify_structures returns after
%   hysteresis and topology cleanup, i.e. the regions the method actually
%   claims are structures, before the min_pixels / aspect-ratio / boundary
%   filters remove fragments.  Percolation theory concerns every cluster,
%   so the size filter is deliberately not applied to the cluster census;
%   n_retained is carried alongside purely for reference.
%
%   Positive and negative signs are labeled separately, matching the
%   production pipeline: a high-speed and a low-speed region can touch but
%   are never one cluster.

occupied = (positive_mask | negative_mask) & analysis_mask;

n_valid    = nnz(analysis_mask);
n_occupied = nnz(occupied);

pos_sizes = component_sizes(positive_mask & analysis_mask, connectivity);
neg_sizes = component_sizes(negative_mask & analysis_mask, connectivity);
sizes     = [pos_sizes; neg_sizes];

m = struct();
m.n_valid_pixels    = n_valid;
m.n_occupied_pixels = n_occupied;
m.n_components      = numel(sizes);
m.n_positive        = numel(pos_sizes);
m.n_negative        = numel(neg_sizes);
m.n_retained        = n_retained;

% Occupancy: fraction of the trusted domain the threshold claims.
if n_valid > 0
    m.occupancy = n_occupied / n_valid;
else
    m.occupancy = NaN;
end

% Percolation order parameter: largest cluster as a share of all occupied
% area.  ->1 means one cluster has swallowed the field (under-segmentation);
% ->0 means the field is dust (over-segmentation).
if n_occupied > 0 && ~isempty(sizes)
    m.max_component_pixels = max(sizes);
    m.max_component_ratio  = max(sizes) / n_occupied;
    m.mean_component_size  = mean(sizes);
    m.median_component_size = median(sizes);
    % Second-moment cluster size, the standard percolation susceptibility
    % with the spanning cluster excluded.
    other = sizes(sizes < max(sizes));
    if isempty(other)
        m.susceptibility = 0;
    else
        m.susceptibility = sum(other .^ 2) / sum(other);
    end
    % Fragmentation index: share of clusters too small to survive the
    % resolution floor.  High values mean the threshold is mostly cutting
    % speckle, not structure.
    m.small_component_fraction = nnz(sizes < 3) / numel(sizes);
else
    m.max_component_pixels    = 0;
    m.max_component_ratio     = NaN;
    m.mean_component_size     = NaN;
    m.median_component_size   = NaN;
    m.susceptibility          = NaN;
    m.small_component_fraction = NaN;
end
end

function sizes = component_sizes(mask, connectivity)
sizes = zeros(0, 1);
if ~any(mask(:))
    return;
end
if exist('bwconncomp', 'file') == 2
    try
        cc = bwconncomp(mask, connectivity);
        sizes = cellfun(@numel, cc.PixelIdxList)';
        return;
    catch
        % Missing or unlicensed toolbox falls through to the local labeler.
    end
end
pixels = tblR2.vlsm.connected_components_2d(mask, connectivity);
sizes = cellfun(@numel, pixels)';
end
