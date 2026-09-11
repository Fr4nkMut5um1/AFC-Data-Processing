function [smooth, diag] = smooth_streamwise_series(values, x, p, opts)
%SMOOTH_STREAMWISE_SERIES 按指定缺口策略对沿程标量作csaps平滑。
% separate_segments：污染区作为断点，上下游分别拟合，污染区保持NaN；
% bridge_contamination：只用污染区外数据拟合一条曲线，并在污染区内评估该曲线。
% 两种模式都绝不把污染区内原始数值作为拟合输入。

if nargin < 4 || ~isstruct(opts) || ~isscalar(opts) || ...
        ~all(isfield(opts, {'gap_mode', 'contamination_x'}))
    error('tblR2:wall:smooth_streamwise_series:InvalidOptions', ...
        'opts 必须定义 gap_mode 和 contamination_x。');
end
if ~isnumeric(values) || ~isreal(values) || ~isvector(values) || ...
        ~isnumeric(x) || ~isreal(x) || ~isvector(x) || ...
        ~isequal(size(values), size(x))
    error('tblR2:wall:smooth_streamwise_series:SizeMismatch', ...
        'values 和 x 必须是尺寸相同的实数数值向量。');
end
if numel(x) < 2 || any(~isfinite(x(:))) || any(diff(x(:)) <= 0)
    error('tblR2:wall:smooth_streamwise_series:InvalidX', ...
        'x 必须是有限且严格递增的向量。');
end
if isempty(p) || ~isnumeric(p) || ~isreal(p) || ~isscalar(p) || ...
        ~isfinite(p) || p < 0 || p > 1
    error('tblR2:wall:smooth_streamwise_series:InvalidP', ...
        'p 必须是 [0,1] 内的有限标量。');
end
gap_mode = lower(char(opts.gap_mode));
if ~ismember(gap_mode, {'separate_segments', 'bridge_contamination'})
    error('tblR2:wall:smooth_streamwise_series:InvalidGapMode', ...
        'gap_mode 必须是 ''separate_segments'' 或 ''bridge_contamination''。');
end
contamination_x = reshape(opts.contamination_x, 1, []);
if ~isempty(contamination_x) && (numel(contamination_x) ~= 2 || ...
        any(~isfinite(contamination_x)) || ...
        contamination_x(2) <= contamination_x(1))
    error('tblR2:wall:smooth_streamwise_series:InvalidContamination', ...
        ['contamination_x 必须为空（关闭），或为有限且递增的 [x_min x_max] 区间。']);
end

input_size = size(values);
value_row = values(:).';
x_row = x(:).';
if isempty(contamination_x)
    in_contamination = false(size(x_row));
else
    in_contamination = x_row >= contamination_x(1) & ...
        x_row < contamination_x(2);
end
fit_mask = isfinite(value_row) & ~in_contamination;
if isempty(contamination_x)
    upstream_fit_mask = false(size(fit_mask));
    downstream_fit_mask = false(size(fit_mask));
else
    upstream_fit_mask = fit_mask & x_row < contamination_x(1);
    downstream_fit_mask = fit_mask & x_row >= contamination_x(2);
end
smooth_row = NaN(size(value_row));
derivative_row = NaN(size(value_row));
fit_segments_index = zeros(0, 2);
fit_segments_x = zeros(0, 2);

switch gap_mode
    case 'separate_segments'
        [starts, ends] = contiguous_runs(fit_mask);
        long_enough = ends - starts + 1 >= 2;
        starts = starts(long_enough);
        ends = ends(long_enough);
        fit_segments_index = [starts(:), ends(:)];
        fit_segments_x = [x_row(starts).', x_row(ends).'];
        for run = 1:numel(starts)
            idx = starts(run):ends(run);
            [smooth_row(idx), derivative_row(idx)] = evaluate_spline( ...
                x_row(idx), value_row(idx), x_row(idx), p, run);
        end

    case 'bridge_contamination'
        if isempty(contamination_x)
            [starts, ends] = contiguous_runs(fit_mask);
            long_enough = ends - starts + 1 >= 2;
            starts = starts(long_enough);
            ends = ends(long_enough);
            fit_segments_index = [starts(:), ends(:)];
            fit_segments_x = [x_row(starts).', x_row(ends).'];
            for run = 1:numel(starts)
                idx = starts(run):ends(run);
                [smooth_row(idx), derivative_row(idx)] = evaluate_spline( ...
                    x_row(idx), value_row(idx), x_row(idx), p, run);
            end
        else
            % 跨污染区拟合必须同时拥有污染区上游和下游的有效样本。
            % 这样可以保证缺口内结果确实由两侧实验数据共同约束，
            % 而不是在缺少一侧数据时退化为单侧外推。
            if nnz(fit_mask) < 2 || ~any(upstream_fit_mask) || ...
                    ~any(downstream_fit_mask)
                error('tblR2:wall:smooth_streamwise_series:InsufficientData', ...
                    ['bridge_contamination 模式要求污染区间两侧都存在有限样本。']);
            end
            fit_idx = find(fit_mask);
            % 只在原本有数据的位置和指定污染区内输出；其他NaN位置不被擅自填补。
            evaluation_mask = isfinite(value_row) | in_contamination;
            eval_idx = find(evaluation_mask & ...
                x_row >= x_row(fit_idx(1)) & x_row <= x_row(fit_idx(end)));
            [smooth_row(eval_idx), derivative_row(eval_idx)] = evaluate_spline( ...
                x_row(fit_idx), value_row(fit_idx), x_row(eval_idx), p, 1);
            fit_segments_index = [fit_idx(1), fit_idx(end)];
            fit_segments_x = [x_row(fit_idx(1)), x_row(fit_idx(end))];
        end
end

smooth = reshape(smooth_row, input_size);
diag = struct();
diag.gap_mode = gap_mode;
diag.pre_smooth_p = p;
diag.contamination_x = contamination_x;
diag.fit_mask = reshape(fit_mask, input_size);
diag.upstream_fit_mask = reshape(upstream_fit_mask, input_size);
diag.downstream_fit_mask = reshape(downstream_fit_mask, input_size);
diag.fit_sample_count = nnz(fit_mask);
% derivative与values/x使用相同长度单位。theta和x都用mm时，dtheta/dx无量纲，
% 可直接用于ZPG关系Cf=2*dtheta/dx，且保证数值来源就是同一条csaps曲线。
diag.derivative = reshape(derivative_row, input_size);
diag.pollution_interpolation_mask = reshape( ...
    in_contamination & isfinite(smooth_row), input_size);
diag.fit_segments_index = fit_segments_index;
diag.fit_segments_x = fit_segments_x;
if isempty(contamination_x)
    diag.method = 'csaps using every finite sample; no artificial gap';
else
    diag.method = 'csaps using contamination-excluded samples';
end
end


function [result, derivative] = evaluate_spline( ...
        x_fit, y_fit, x_eval, p, segment_number)
try
    pp = csaps(x_fit, y_fit, p);
    dpp = fnder(pp, 1);
    result = reshape(fnval(pp, x_eval), 1, []);
    derivative = reshape(fnval(dpp, x_eval), 1, []);
catch ME
    error('tblR2:wall:smooth_streamwise_series:SplineFailure', ...
        '对连续段 %d 执行 csaps/fnder 失败（p=%.17g）：%s', ...
        segment_number, p, ME.message);
end
if any(~isfinite(result)) || any(~isfinite(derivative))
    error('tblR2:wall:smooth_streamwise_series:SplineFailure', ...
        'csaps/fnder 在连续段 %d 中返回了非有限值。', ...
        segment_number);
end
end


function [starts, ends] = contiguous_runs(mask)
edges = diff([false, mask, false]);
starts = find(edges == 1);
ends = find(edges == -1) - 1;
end
