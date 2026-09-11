function r = scan_alpha_seed_grid(varargin)
%SCAN_ALPHA_SEED_GRID 在 alpha x seed_alpha 网格上扫描，报帕累托前沿。
%
% recall 和 FP/frame 是一对相互拉扯的指标，单看任一个都能被刷分：alpha 压到 0
% 能让 recall=100%，FP 也会爆。所以这里报帕累托前沿——没有任何其他组合能在两个
% 指标上同时不劣于它的那些点。

p = inputParser;
addParameter(p, 'alphas', [0.42 0.46 0.50 0.54 0.58], @isnumeric);
addParameter(p, 'seeds', [0.75 0.80 0.85 0.90 1.00], @isnumeric);
addParameter(p, 'output_file', ...
    'tmp/annotation_samples/e60/param_scores_fine.mat', @ischar);
addParameter(p, 'extra_overrides', struct(), @isstruct);
parse(p, varargin{:});
opts = p.Results;

warning('off', 'tblR2:vlsmpod:resolve_settings:StaleCalibration');

ps = {};
for a = opts.alphas
    for s = opts.seeds
        if s < a; continue; end   % identify_structures 要求 seed_alpha >= alpha
        e = opts.extra_overrides;
        e.alpha = a; e.seed_alpha = s;
        e.label = sprintf('a%.2f/s%.2f', a, s);
        ps{end+1} = e; %#ok<AGROW>
    end
end
fprintf('scanning %d combos\n', numel(ps));

r = score_params_vs_annotation('param_sets', ps, 'output_file', opts.output_file);

rec = [r.recall];
fp = [r.fp_per_frame];
fprintf('\n=== Pareto front (high recall, low FP) ===\n');
for i = 1:numel(r)
    dominated = any(rec > rec(i) & fp <= fp(i)) || any(rec >= rec(i) & fp < fp(i));
    if ~dominated
        fprintf('  %-14s recall=%5.1f%%  FP/frame=%.2f  Lhat/Lann=%.2f\n', ...
            r(i).label, 100*rec(i), fp(i), r(i).mean_len_ratio);
    end
end
end
