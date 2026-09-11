function Cf = secant_cf(theta_start, theta_end, x_start, x_end)
%SECANT_CF ZPG two-point skin-friction coefficient from momentum thickness.
%   Cf = 2 * (theta_end - theta_start) / (x_end - x_start).
%   theta and x may both be expressed in mm because their units cancel.

inputs = {theta_start, theta_end, x_start, x_end};
for k = 1:numel(inputs)
    value = inputs{k};
    if ~isnumeric(value) || ~isreal(value) || any(~isfinite(value(:)))
        error('tblR2:wall:secant_cf:NonfiniteInput', ...
            '所有 theta 和 x 端点都必须是有限实数数值。');
    end
end

if ~(all(cellfun(@isscalar, inputs)) || ...
        isequal(size(theta_start), size(theta_end), size(x_start), size(x_end)))
    error('tblR2:wall:secant_cf:SizeMismatch', ...
        '输入必须全部是标量，或全部为尺寸相同的数组。');
end

if any(x_end(:) <= x_start(:))
    error('tblR2:wall:secant_cf:InvalidInterval', ...
        '每个 x_end 都必须严格大于对应的 x_start。');
end

Cf = 2 .* (theta_end - theta_start) ./ (x_end - x_start);
end
