function masks = quadrant_mask(U, V, hole_threshold, hole_scale)
%QUADRANT_MASK Q1-Q4 event masks shared by streaming and single-case analysis.
% Q1: U>0&V>0, Q2: U<0&V>0, Q3: U<0&V<0, Q4: U>0&V<0. The hole keeps
% abs(U*V) > hole_threshold*hole_scale (local u_rms*v_rms in the periodic
% flow; the pointwise mean |<u'v'>| in the single-case flow). An empty
% hole_scale fallback is only meaningful for hole_threshold=0, where it
% keeps all nonzero events; callers using H>0 must supply a scale.

if nargin < 4 || isempty(hole_scale)
    hole_scale = [];
end
valid = isfinite(U) & isfinite(V);
uv = U .* V;
if hole_threshold > 0
    if isempty(hole_scale)
        hole_scale = abs(uv);
    end
    strong = valid & abs(uv) > hole_threshold .* hole_scale;
elseif ~isempty(hole_scale)
    strong = valid & abs(uv) > 0;
else
    strong = valid;
end
masks = { ...
    U > 0 & V > 0 & strong, ...
    U < 0 & V > 0 & strong, ...
    U < 0 & V < 0 & strong, ...
    U > 0 & V < 0 & strong};
end
