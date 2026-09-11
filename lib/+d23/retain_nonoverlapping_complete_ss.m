function catalog = retain_nonoverlapping_complete_ss(catalog, cfg)
%RETAIN_NONOVERLAPPING_COMPLETE_SS Retain deterministic non-overlapping SS.
% The input contains one frame/connectivity/sign group.  Edge-rejected rows
% remain in the catalog for audit but are never assigned an IsSS* flag.
if isempty(catalog)
    return;
end

if ~ismember('RejectedByStreamwiseEdge', catalog.Properties.VariableNames)
    catalog.RejectedByStreamwiseEdge = false(height(catalog), 1);
end
if ~ismember('SuppressedByBBoxOverlap', catalog.Properties.VariableNames)
    catalog.SuppressedByBBoxOverlap = false(height(catalog), 1);
end

% Edge exclusion is an independent rejection rule.  Clear every length-tier
% SS flag for an edge-rejected row, including rows that also touch the exact
% FOV boundary and are therefore censored.  Censoring remains an audit flag;
% it must not allow an excluded object back into the primary catalog.
edge_rejected = logical(catalog.RejectedByStreamwiseEdge);
catalog.IsSS3(edge_rejected) = false;
catalog.IsSS3p8(edge_rejected) = false;
catalog.IsSS4p5(edge_rejected) = false;

initial = catalog.IsSS3 & ~catalog.IsCensored;
% Reset all initially qualified rows before applying the deterministic
% non-overlap/limit selector; otherwise suppressed non-edge rows would retain
% their precomputed flags.
catalog.IsSS3(initial) = false;
catalog.IsSS3p8(initial) = false;
catalog.IsSS4p5(initial) = false;
catalog.SuppressedByBBoxOverlap(:) = false;

candidate = find(initial & ~edge_rejected);
if isempty(candidate)
    return;
end
key = [-catalog.Lx_over_delta(candidate), ...
    -double(catalog.PixelCount(candidate)), ...
    double(catalog.ComponentID(candidate))];
[~, order] = sortrows(key, [1 2 3]);
ordered = candidate(order);
limit = double(cfg.detection.max_complete_ss_per_sign);
keepers = zeros(0,1);

for i = 1:numel(ordered)
    row = ordered(i);
    if numel(keepers) >= limit
        continue;
    end
    if isempty(keepers)
        overlaps = false;
    else
        overlaps = any(boxes_share_pixel(catalog, row, keepers));
    end
    if overlaps
        catalog.SuppressedByBBoxOverlap(row) = true;
    else
        keepers(end+1,1) = row; %#ok<AGROW>
    end
end

catalog.IsSS3(keepers) = catalog.PassLength3(keepers) & ...
    catalog.PassWallLower(keepers) & catalog.PassWallUpper(keepers);
catalog.IsSS3p8(keepers) = catalog.PassLength3p8(keepers) & ...
    catalog.PassWallLower(keepers) & catalog.PassWallUpper(keepers);
catalog.IsSS4p5(keepers) = catalog.PassLength4p5(keepers) & ...
    catalog.PassWallLower(keepers) & catalog.PassWallUpper(keepers);
end

function overlap = boxes_share_pixel(catalog, row, keepers)
overlap = min(double(catalog.ColMax(row)), double(catalog.ColMax(keepers))) >= ...
    max(double(catalog.ColMin(row)), double(catalog.ColMin(keepers))) & ...
    min(double(catalog.RowMax(row)), double(catalog.RowMax(keepers))) >= ...
    max(double(catalog.RowMin(row)), double(catalog.RowMin(keepers)));
end
