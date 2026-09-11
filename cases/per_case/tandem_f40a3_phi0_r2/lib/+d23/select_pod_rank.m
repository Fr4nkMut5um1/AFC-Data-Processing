function [rank_value, positive_rank, lambda_tol] = select_pod_rank(eigenvalues, dof_count, pod_cfg)
%SELECT_POD_RANK Apply explicit fixed-N or energy-fraction rank selection.
lambda = double(eigenvalues(:));
if isempty(lambda)
    error('d23:select_pod_rank:EmptySpectrum', 'The POD spectrum is empty.');
end
lambda_scale = max(lambda(1), 1);
lambda_tol = max(100 * eps(lambda_scale) * max(dof_count, numel(lambda)), ...
    realmin('double'));
if any(lambda < -lambda_tol)
    error('d23:select_pod_rank:NegativeSpectrum', ...
        'The symmetric covariance has a materially negative eigenvalue.');
end
lambda(abs(lambda) <= lambda_tol) = 0;
positive_rank = nnz(lambda > 0);
if positive_rank == 0
    error('d23:select_pod_rank:ZeroEnergy', ...
        'All centered snapshots have zero numerical energy.');
end
kind = char(pod_cfg.rank.kind);
switch kind
    case 'fixed_n'
        rank_value = double(pod_cfg.rank.n);
        if ~isscalar(rank_value) || ~isfinite(rank_value) || ...
                rank_value < 1 || rank_value ~= fix(rank_value)
            error('d23:select_pod_rank:InvalidRank', ...
                'fixed_n rank must be a finite positive integer.');
        end
        if rank_value > positive_rank
            error('d23:select_pod_rank:RankTooLarge', ...
                'fixed_n exceeds the positive numerical rank.');
        end
    case 'energy_fraction'
        target = double(pod_cfg.rank.value);
        if ~isscalar(target) || ~isfinite(target) || target <= 0 || target > 1
            error('d23:select_pod_rank:InvalidEnergyFraction', ...
                'energy_fraction must be finite and lie in (0,1].');
        end
        cumulative = cumsum(lambda(1:positive_rank)) / ...
            sum(lambda(1:positive_rank));
        rank_value = find(cumulative >= target, 1, 'first');
    otherwise
        error('d23:select_pod_rank:InvalidKind', ...
            'POD rank.kind must be fixed_n or energy_fraction.');
end
end
