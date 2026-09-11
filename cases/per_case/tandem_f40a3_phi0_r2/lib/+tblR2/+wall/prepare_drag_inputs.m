function input = prepare_drag_inputs(BL)
%PREPARE_DRAG_INPUTS 保留完整流向数组，并用掩膜忽略首尾失真站位。
% 本函数不删除任何列、不缩短数组，也不平移x坐标。原始字段完整保存在input中；
% 仅额外生成calculation字段，把需要忽略的位置写成NaN，供Section 4计算使用。
%
% BL数组开头可能先出现若干NaN，因此“图上第一个可见点”未必是数组索引1。
% 固定忽略两端的失真位置：
%   1. 数组开头所有不完整站位，以及第一个完整可绘制站位；
%   2. 最后一个完整可绘制站位，以及其后的所有不完整尾段。
% 当前两个真实case中，这一规则等价于屏蔽源索引1--3和636。屏蔽只发生在
% calculation字段中，原始字段仍完整保留，后续流向坐标不会因屏蔽而平移。

required = {'x', 'theta', 'delta_star', 'delta99', 'Uinf_local'};
if ~isstruct(BL) || ~isscalar(BL) || ~all(isfield(BL, required))
    error('tblR2:wall:prepare_drag_inputs:InvalidInput', ...
        'BL 必须包含 x、theta、delta_star、delta99 和 Uinf_local。');
end

sizes = cellfun(@(name) numel(BL.(name)), required);
if numel(BL.x) < 2 || any(sizes ~= sizes(1))
    error('tblR2:wall:prepare_drag_inputs:SizeMismatch', ...
        '所有必需的 BL 字段必须长度相同，且至少包含两个点。');
end

input.x = reshape(BL.x, 1, []);
input.theta = reshape(BL.theta, 1, []);
input.delta_star = reshape(BL.delta_star, 1, []);
input.delta99 = reshape(BL.delta99, 1, []);
input.Uinf_local = reshape(BL.Uinf_local, 1, []);
if any(~isfinite(input.x)) || any(diff(input.x) <= 0)
    error('tblR2:wall:prepare_drag_inputs:InvalidX', ...
        'BL.x 必须是有限且严格递增的向量。');
end

drawable = isfinite(input.theta) & isfinite(input.delta_star) & ...
    isfinite(input.delta99) & input.delta99 > 0 & ...
    isfinite(input.Uinf_local) & input.Uinf_local > 0;
first_drawable_index = find(drawable, 1, 'first');
last_drawable_index = find(drawable, 1, 'last');
if isempty(first_drawable_index) || isempty(last_drawable_index) || ...
        first_drawable_index >= last_drawable_index
    error('tblR2:wall:prepare_drag_inputs:NoDrawableStation', ...
        'BL 至少必须包含两个有序、有限且可绘制的流向站位。');
end

input.ignore_mask = false(size(input.x));
input.ignore_mask(1:first_drawable_index) = true;
input.ignore_mask(last_drawable_index:end) = true;
input.use_mask = ~input.ignore_mask;
input.source_indices = 1:numel(input.x);

% calculation保留与BL完全相同的长度；被忽略的位置只写为NaN，不物理删除。
input.calculation = struct();
input.calculation.theta = input.theta;
input.calculation.delta_star = input.delta_star;
input.calculation.delta99 = input.delta99;
input.calculation.Uinf_local = input.Uinf_local;
input.calculation.theta(input.ignore_mask) = NaN;
input.calculation.delta_star(input.ignore_mask) = NaN;
input.calculation.delta99(input.ignore_mask) = NaN;
input.calculation.Uinf_local(input.ignore_mask) = NaN;

input.preprocessing = struct( ...
    'rule', 'mask_leading_invalid_plus_first_drawable_and_last_drawable_plus_tail', ...
    'array_length_preserved', true, ...
    'coordinates_shifted', false, ...
    'ignored_source_indices', find(input.ignore_mask), ...
    'ignored_x_mm', input.x(input.ignore_mask), ...
    'first_drawable_source_index', first_drawable_index, ...
    'first_drawable_x_mm', input.x(first_drawable_index), ...
    'last_drawable_source_index', last_drawable_index, ...
    'last_drawable_x_mm', input.x(last_drawable_index));
end
