function m = structure_geometry_metrics(id, analysis_mask)
%STRUCTURE_GEOMETRY_METRICS Fragmentation/merging diagnostics for one frame.
%   id : the FULL result struct from identify_structures run with the
%        production pipeline (size filter, hole fill, closing, aspect and
%        trusted-boundary rejection all active).
%   analysis_mask : the valid analysis domain for the frame.
%
%   The R2 table has no TouchesStreamwiseEdge column: R2 *rejects*
%   boundary-touching components outright and reports only a count, so the
%   merging diagnostic uses that count plus a geometric re-check of the
%   surviving components against the domain's streamwise extent.
%
%   Sweep trajectories diagnose the two failure modes:
%     fragmentation -> median/mean area falls, area tail thins, structure
%                      count rises, small-component share rises
%     merging       -> boundary-rejection count rises (a merged blob is far
%                      more likely to reach the FOV edge), aspect ratio
%                      blows up, LSM/VLSM counts fall as separate structures
%                      are absorbed into fewer, larger ones

structures = id.structures;

m = struct();
m.n_valid_pixels = nnz(analysis_mask);
m.n_structures   = height(structures);
m.rejected_boundary = id.rejected_trusted_boundary_count;
m.rejected_aspect   = id.rejected_aspect_ratio_count;

% Occupied area after the full pipeline, both signs.
occupied = (id.positive_mask | id.negative_mask) & analysis_mask;
m.occupancy = nnz(occupied) / max(nnz(analysis_mask), 1);

% Topology cleanup accounting: how much area the morphology actually added.
tc = id.topology_cleanup;
m.closed_pixels = tc.positive_closed_pixels + tc.negative_closed_pixels;
m.filled_pixels = tc.positive_filled_pixels + tc.negative_filled_pixels;
m.closed_patches = tc.positive_closed_patches + tc.negative_closed_patches;
m.filled_holes   = tc.positive_filled_holes + tc.negative_filled_holes;

if height(structures) == 0
    m.mean_area = NaN;      m.median_area = NaN;    m.p90_area = NaN;
    m.total_area = 0;
    m.mean_aspect_ratio = NaN;  m.median_aspect_ratio = NaN;
    m.p95_aspect_ratio = NaN;
    m.small_component_fraction = NaN;
    m.lsm_count = 0;        m.vlsm_count = 0;
    m.max_length_over_delta = NaN;
    m.structure_density = 0;
    m.tail_area_share = NaN;
    return;
end

areas   = structures.Area_mm2;
aspects = structures.AspectRatio;
lx_d    = structures.LengthX_over_delta;

m.mean_area   = mean(areas, 'omitnan');
m.median_area = median(areas, 'omitnan');
m.p90_area    = quantile(areas, 0.90);
m.total_area  = sum(areas, 'omitnan');

m.mean_aspect_ratio   = mean(aspects, 'omitnan');
m.median_aspect_ratio = median(aspects, 'omitnan');
m.p95_aspect_ratio    = quantile(aspects, 0.95);

% Fragmentation proxy: share of survivors sitting at the resolution floor.
m.small_component_fraction = nnz(structures.PixelCount <= 4) / height(structures);

% Tail share: fraction of total area held by the largest decile.  A thinning
% tail at fixed total area is the signature of a big structure being cut up.
sorted_areas = sort(areas(isfinite(areas)), 'descend');
n_tail = max(1, round(0.10 * numel(sorted_areas)));
if m.total_area > 0
    m.tail_area_share = sum(sorted_areas(1:n_tail)) / m.total_area;
else
    m.tail_area_share = NaN;
end

m.lsm_count  = nnz(structures.IsLSM);
m.vlsm_count = nnz(structures.IsVLSM);
m.max_length_over_delta = max(lx_d, [], 'omitnan');

m.structure_density = height(structures) / max(nnz(analysis_mask), 1);
end
