function value = figures_global(cfg, name)
%FIGURES_GLOBAL 从按 Section 分组的图形参数中查找一个全局字段值。
% 查找顺序：cfg.figures.section<N>.<name>（N 升序，后写的覆盖先写的），
% 找不到时回退旧式平坦命名 cfg.figures.<name>；返回 [] 表示未配置。
% 用于 formats / export_dpi / robust_color_quantiles / fov_aspect_ratio /
% jobs / preview 这类不归属单一 Section 的全局导出参数。
value = [];
if ~isstruct(cfg) || ~isfield(cfg, 'figures') || ~isstruct(cfg.figures)
    return;
end
names = fieldnames(cfg.figures);
is_section = false(size(names));
for i = 1:numel(names)
    is_section(i) = ~isempty(regexp(names{i}, '^section\d+$', 'once'));
end
sec_names = names(is_section);
if ~isempty(sec_names)
    numbers = cellfun(@(s) str2double(regexp(s, '\d+', 'match', 'once')), ...
        sec_names);
    [~, order] = sort(numbers);
    sec_names = sec_names(order);
end
for i = 1:numel(sec_names)
    if isfield(cfg.figures.(sec_names{i}), name)
        value = cfg.figures.(sec_names{i}).(name);
    end
end
if isempty(value) && isfield(cfg.figures, name) && ...
        ~isempty(cfg.figures.(name))
    value = cfg.figures.(name);
end
end
