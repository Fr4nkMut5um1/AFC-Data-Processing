function selection = select_gallery(ss_catalog, total_frames, connectivity)
%SELECT_GALLERY Deterministic 5-time-bin x 2-sign x 3-tier selection.
if nargin < 3 || isempty(connectivity)
    connectivity = 8;
end
if ~isscalar(connectivity) || ~ismember(double(connectivity), [4 8])
    error('d23:select_gallery:Connectivity', ...
        'connectivity must be the scalar value 4 or 8.');
end
candidates = ss_catalog(ss_catalog.Connectivity == connectivity & ...
    ss_catalog.IsSS3 & ~ss_catalog.IsCensored, :);
candidate_tier = ones(height(candidates), 1, 'uint8');
candidate_tier(candidates.Lx_over_delta > 3.8) = 2;
candidate_tier(candidates.Lx_over_delta > 4.5) = 3;
candidate_bin = min(5, max(1, ceil(5 * double(candidates.FrameOrdinal) / total_frames)));

n_slots = 30;
slot_id = uint8((1:n_slots).');
time_bin = zeros(n_slots, 1, 'uint8');
requested_sign = zeros(n_slots, 1, 'int8');
requested_tier = zeros(n_slots, 1, 'uint8');
selected = false(n_slots, 1);
fallback = false(n_slots, 1);
frame_ordinal = zeros(n_slots, 1, 'uint32');
frame_id = zeros(n_slots, 1, 'uint32');
actual_sign = zeros(n_slots, 1, 'int8');
actual_tier = zeros(n_slots, 1, 'uint8');
component_id = zeros(n_slots, 1, 'uint32');
lx = nan(n_slots, 1);
reason = strings(n_slots, 1);
used_objects = false(height(candidates), 1);
slot = 0;
for b = 1:5
    bin_center = (b - 0.5) * total_frames / 5;
    for sign_value = [1 -1]
        for tier = 1:3
            slot = slot + 1;
            time_bin(slot) = uint8(b);
            requested_sign(slot) = int8(sign_value);
            requested_tier(slot) = uint8(tier);
            unused = ~used_objects;
            exact = find(unused & candidate_bin == b & ...
                candidates.Sign == sign_value & candidate_tier == tier);
            if ~isempty(exact)
                key = [abs(double(candidates.FrameOrdinal(exact)) - bin_center), ...
                    -candidates.Lx_over_delta(exact), ...
                    double(candidates.FrameID(exact)), ...
                    double(candidates.ComponentID(exact))];
                [~, order] = sortrows(key, [1 2 3 4]);
                chosen = exact(order(1));
                reason(slot) = "exact_slot";
            else
                pool = find(unused);
                if isempty(pool)
                    reason(slot) = "no_unused_complete_ss_object";
                    continue;
                end
                key = [double(candidates.Sign(pool) ~= sign_value), ...
                    abs(double(candidate_tier(pool)) - tier), ...
                    abs(double(candidates.FrameOrdinal(pool)) - bin_center), ...
                    -candidates.Lx_over_delta(pool), ...
                    double(candidates.FrameID(pool)), ...
                    double(candidates.ComponentID(pool))];
                [~, order] = sortrows(key, 1:size(key,2));
                chosen = pool(order(1));
                fallback(slot) = true;
                reason(slot) = "fallback_remaining_complete_ss";
            end
            selected(slot) = true;
            frame_ordinal(slot) = candidates.FrameOrdinal(chosen);
            frame_id(slot) = candidates.FrameID(chosen);
            actual_sign(slot) = candidates.Sign(chosen);
            actual_tier(slot) = candidate_tier(chosen);
            component_id(slot) = candidates.ComponentID(chosen);
            lx(slot) = candidates.Lx_over_delta(chosen);
            used_objects(chosen) = true;
        end
    end
end
selection = table(slot_id, time_bin, requested_sign, requested_tier, ...
    selected, fallback, frame_ordinal, frame_id, actual_sign, actual_tier, ...
    component_id, lx, reason, 'VariableNames', {'SlotID','TimeBin', ...
    'RequestedSign','RequestedTier','Selected','Fallback','FrameOrdinal', ...
    'FrameID','ActualSign','ActualTier','ComponentID','Lx_over_delta', ...
    'SelectionReason'});
end
