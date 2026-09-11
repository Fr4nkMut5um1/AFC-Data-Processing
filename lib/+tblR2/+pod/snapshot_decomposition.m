function POD = snapshot_decomposition(X, n_modes)
%SNAPSHOT_DECOMPOSITION Reference snapshot POD used by the Re30w AoA2 script.
%
% X is a D-by-N matrix whose columns are joint [u;v] snapshots. The mean
% snapshot is removed, C = Xf'*Xf / size(Xf,1), eigenvectors are computed
% with eig, spatial modes are Phi = Xf*As normalized to unit norm, and the
% coefficients are Ac = Phi'*Xf. This mirrors Comparison_Re30w_AoA2.m.
%
% Note on output semantics: POD.energy_ratio is the CUMULATIVE share of
% fluctuation energy (cumsum(lambda)/total_energy), consistent with legacy
% plot conventions. The r2 POD wrapper adds per-mode/cumulative energy fields.
% ratio lambda/total_energy under energy_ratio and its cumulative sum under
% cumulative_energy_ratio; keep the two contracts distinct.

if nargin < 2 || isempty(n_modes)
    n_modes = min(size(X));
end
if ~(isnumeric(n_modes) && isscalar(n_modes) && n_modes == fix(n_modes) && ...
        n_modes >= 1)
    error('tblR2:pod:snapshot_decomposition:InvalidModeCount', ...
        'n_modes 必须是正整数。');
end
X = double(X);
[dof_count, n_frames] = size(X);
if dof_count < 1 || n_frames < 2
    error('tblR2:pod:snapshot_decomposition:InvalidSnapshotMatrix', ...
        'X 至少必须包含两个快照和一个自由度。');
end

mean_snapshot = mean(X, 2);
Xf = X - mean_snapshot;
C = (Xf' * Xf) / dof_count;
[vectors, values] = eig(C);
lambda_all = sort(real(diag(values)), 'descend');
[~, order] = sort(real(diag(values)), 'descend');
As = vectors(:, order);
Phi = Xf * As;
for p = 1:n_frames
    norm_p = norm(Phi(:, p));
    if norm_p > 0
        Phi(:, p) = Phi(:, p) / norm_p;
    end
end
Ac = Phi' * Xf;

n_modes_actual = min(n_modes, n_frames);
lambda = lambda_all(1:n_modes_actual);
total_energy = sum(lambda_all);
if ~isfinite(total_energy) || total_energy <= 0
    error('tblR2:pod:snapshot_decomposition:DegenerateEnergy', ...
        '快照脉动的总能量必须是有限正值。');
end

POD = struct();
POD.modes = Phi(:, 1:n_modes_actual);
POD.coefficients = Ac(1:n_modes_actual, :);
POD.lambda = lambda;
POD.lambda_all = lambda_all;
POD.energy_ratio = cumsum(lambda) / total_energy;
POD.total_energy = total_energy;
POD.mean_snapshot = mean_snapshot;
POD.n_modes = n_modes_actual;
POD.definition = ['Reference snapshot POD: C=Xf''*Xf/size(Xf,1), ' ...
    'Phi=Xf*eigvec normalized, Ac=Phi''*Xf.'];
end
