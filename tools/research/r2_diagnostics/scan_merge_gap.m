function r = scan_merge_gap(varargin)
%SCAN_MERGE_GAP 扫描 merge_gap_cells 对召回与长度保真度的影响。
%
% 为什么单独扫：alpha 扫描里出现了"阈值收紧反而召回上升"的反直觉现象，怀疑
% merge_gap_cells=40（跨 20.6mm 搭桥）把相邻的独立结构并成一个巨块，导致两个
% 标注框只能命中一个。Lhat/Lann 稳定在 1.3-1.5 也指向过度合并。
%
% 关注 Lhat/Lann：它应该趋近 1。远大于 1 表示检出的结构比人眼看到的长得多，
% 那是合并把不该连的连上了。

p = inputParser;
addParameter(p, 'gaps', [0 5 10 20 30 40], @isnumeric);
addParameter(p, 'alpha_seed_pairs', [0.66 0.75; 0.58 0.75; 0.58 0.85], @isnumeric);
addParameter(p, 'output_file', ...
    'tmp/annotation_samples/e60/param_scores_merge.mat', @ischar);
parse(p, varargin{:});
opts = p.Results;

warning('off', 'tblR2:vlsmpod:resolve_settings:StaleCalibration');

ps = {};
for i = 1:size(opts.alpha_seed_pairs, 1)
    a = opts.alpha_seed_pairs(i, 1);
    s = opts.alpha_seed_pairs(i, 2);
    for g = opts.gaps
        ps{end+1} = struct('label', sprintf('a%.2f/s%.2f g%02d', a, s, g), ...
            'alpha', a, 'seed_alpha', s, 'merge_gap_cells', g); %#ok<AGROW>
    end
end
fprintf('scanning %d combos (gap sweep)\n', numel(ps));

r = score_params_vs_annotation('param_sets', ps, 'output_file', opts.output_file);

fprintf('\n=== length fidelity vs gap ===\n');
fprintf('%-18s %8s %9s %10s\n', 'combo', 'recall', 'FP/frame', 'Lhat/Lann');
for i = 1:numel(r)
    fprintf('%-18s %7.1f%% %9.2f %10.2f\n', r(i).label, ...
        100*r(i).recall, r(i).fp_per_frame, r(i).mean_len_ratio);
end
end
