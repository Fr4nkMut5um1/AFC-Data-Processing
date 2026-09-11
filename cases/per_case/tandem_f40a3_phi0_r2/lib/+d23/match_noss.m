function pairs = match_noss(ss_catalog, ctx, cfg)
%MATCH_NOSS Find nearest same-frame, same-height, same-size noSS windows.
targets = ss_catalog(ss_catalog.Connectivity == 8 & ...
    ss_catalog.IsSS3 & ~ss_catalog.IsCensored, :);
if isempty(targets)
    pairs = d23.empty_pairs();
    return;
end
all_ss = ss_catalog(ss_catalog.Connectivity == 8 & ss_catalog.IsSS3, :);
n = height(targets);
pair_id = uint32((1:n).');
noss_min = zeros(n, 1, 'uint16');
noss_max = zeros(n, 1, 'uint16');
center_shift = nan(n, 1);
matched = false(n, 1);
reason = ones(n, 1, 'uint8');
candidate_count = zeros(n, 1, 'uint32');
nx = ctx.cache_size(3);
for i = 1:n
    target = targets(i, :);
    width = double(target.ColMax - target.ColMin + 1);
    starts = (1:(nx - width + 1)).';
    ends = starts + width - 1;
    same_frame = all_ss.FrameOrdinal == target.FrameOrdinal;
    obstacles = all_ss(same_frame, :);
    allowed = true(size(starts));
    for j = 1:height(obstacles)
        y_overlap = double(target.RowMin) <= double(obstacles.RowMax(j)) && ...
            double(target.RowMax) >= double(obstacles.RowMin(j));
        if y_overlap
            x_overlap = starts <= double(obstacles.ColMax(j)) & ...
                ends >= double(obstacles.ColMin(j));
            allowed = allowed & ~x_overlap;
        end
    end
    candidates = starts(allowed);
    if cfg.matching.require_full_valid_box && ~isempty(candidates)
        raw = d23.read_chunk(ctx.cache_file, double(target.FrameOrdinal));
        valid = squeeze(raw.valid(1, double(target.RowMin):double(target.RowMax), :));
        box_ok = false(size(candidates));
        for j = 1:numel(candidates)
            cols = candidates(j):(candidates(j) + width - 1);
            box_ok(j) = all(valid(:, cols), 'all');
        end
        candidates = candidates(box_ok);
    end
    candidate_count(i) = uint32(numel(candidates));
    if isempty(candidates)
        continue;
    end
    target_center = (double(target.ColMin) + double(target.ColMax)) / 2;
    candidate_centers = candidates + (width - 1) / 2;
    ranking = sortrows([abs(candidate_centers - target_center), candidates], [1 2]);
    chosen = ranking(1, 2);
    noss_min(i) = uint16(chosen);
    noss_max(i) = uint16(chosen + width - 1);
    center_shift(i) = (chosen + (width - 1) / 2) - target_center;
    matched(i) = true;
    reason(i) = uint8(0);
end
pairs = table(pair_id, targets.FrameOrdinal, targets.FrameID, targets.Sign, ...
    targets.ComponentID, targets.Lx_over_delta, targets.PassLength3, ...
    targets.PassLength3p8, targets.PassLength4p5, targets.ColMin, ...
    targets.ColMax, targets.RowMin, targets.RowMax, noss_min, noss_max, ...
    center_shift, center_shift * ctx.dx_mm, matched, reason, candidate_count, ...
    'VariableNames', d23.empty_pairs().Properties.VariableNames);
end
