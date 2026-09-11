function selection = select_energy_modes(lambda_all, targets)
%SELECT_ENERGY_MODES Select the smallest leading POD rank at energy targets.

if nargin < 2 || isempty(targets)
    targets = [0.80 0.90 0.95];
end
lambda = double(lambda_all(:));
targets = double(targets(:));
if isempty(lambda) || any(~isfinite(lambda))
    error('tblR2:select_energy_modes:InvalidEigenvalues', ...
        'lambda_all 必须是非空有限向量。');
end
if any(~isfinite(targets) | targets <= 0 | targets > 1)
    error('tblR2:select_energy_modes:InvalidTargets', ...
        '累计能量目标必须位于 (0,1]。');
end

% Small negative eigenvalues can appear from round-off in the snapshot
% covariance.  They do not represent physical fluctuation energy.
lambda = max(lambda, 0);
total_energy = sum(lambda);
if ~(isfinite(total_energy) && total_energy > 0)
    error('tblR2:select_energy_modes:DegenerateEnergy', ...
        'POD 总能量必须为有限正值。');
end
cumulative = cumsum(lambda) ./ total_energy;

n_modes = zeros(size(targets));
achieved = zeros(size(targets));
for k = 1:numel(targets)
    idx = find(cumulative >= targets(k), 1, 'first');
    if isempty(idx)
        idx = numel(lambda);
    end
    n_modes(k) = idx;
    achieved(k) = cumulative(idx);
end

selection = struct();
selection.targets = targets;
selection.n_modes = n_modes;
selection.achieved_energy = achieved;
selection.cumulative_energy = cumulative;
selection.total_energy = total_energy;
selection.definition = ['Smallest leading joint u-v POD rank whose cumulative ' ...
    'eigenvalue energy reaches each requested target.'];
end
