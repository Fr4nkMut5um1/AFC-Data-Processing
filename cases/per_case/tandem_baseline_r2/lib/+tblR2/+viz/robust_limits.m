function limits = robust_limits(values, mode, probability)
%ROBUST_LIMITS Quantile-based display limits without changing stored data.
% MODE: 'balanced' -> symmetric about zero; 'positive' -> [0,q_high];
%       'range' -> [q_low,q_high].

if nargin < 2 || isempty(mode)
    mode = 'range';
end
if nargin < 3 || isempty(probability)
    probability = [0.005 0.995];
end
finite_values = double(values(isfinite(values)));
if isempty(finite_values)
    limits = [0 1];
    return;
end
if ~(isnumeric(probability) && numel(probability) == 2 && ...
        all(isfinite(probability)) && probability(1) >= 0 && ...
        probability(2) <= 1 && probability(1) < probability(2))
    error('tblR2:viz:robust_limits:InvalidProbability', ...
        'probability 必须是 [0,1] 内的有序双元素向量。');
end
switch char(mode)
    case 'balanced'
        bound = quantile(abs(finite_values), probability(2));
        if ~(isfinite(bound) && bound > 0)
            bound = max(abs(finite_values));
        end
        limits = [-bound bound];
    case 'positive'
        upper = quantile(finite_values, probability(2));
        if ~(isfinite(upper) && upper > 0)
            upper = max(finite_values);
        end
        limits = [0 upper];
    case 'range'
        limits = quantile(finite_values, probability);
    otherwise
        error('tblR2:viz:robust_limits:InvalidMode', ...
            'mode 必须是 balanced、positive 或 range。');
end
if ~all(isfinite(limits)) || limits(1) == limits(2)
    centre = mean(finite_values);
    span = max(1, abs(centre)) .* sqrt(eps);
    limits = centre + [-span span];
end
end
