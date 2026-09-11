function value = figures_family(cfg, family, key)
%FIGURES_FAMILY 从按 Section 分组的图形参数中查找一个字段值。
% 主脚本中图形参数按 cfg.figures.section<N>.<family>.<key> 组织（文件名/面板都可
% 按 Section 快速定位）。本函数按 section 编号升序查找 <family> 下是否存在 <key>；
% 返回 [](未配置)或首个命中的值。为兼容旧配置存档，找不到时回退查找
% cfg.figures.<family>.<key>（旧式平坦命名）。
% 用法示例：tblR2.figures_family(cfg, 'window_size', 'mean_turbulence');
if ~isstruct(cfg) || ~isfield(cfg, 'figures') || ~isstruct(cfg.figures)
    value = [];
    return;
end
sections = section_names(cfg.figures);
order = section_order(sections);
for i = 1:numel(order)
    block = cfg.figures.(sections{order(i)});
    if isstruct(block) && isfield(block, family) && ...
            isstruct(block.(family)) && ...
            isfield(block.(family), key) && ~isempty(block.(family).(key))
        value = block.(family).(key);
        return;
    end
end
if isfield(cfg.figures, family) && isstruct(cfg.figures.(family)) && ...
        isfield(cfg.figures.(family), key) && ...
        ~isempty(cfg.figures.(family).(key))
    value = cfg.figures.(family).(key);
    return;
end
value = [];
end

function names = section_names(figures_cfg)
names = fieldnames(figures_cfg);
keep = false(size(names));
for i = 1:numel(names)
    keep(i) = ~isempty(regexp(names{i}, '^section\d+$', 'once'));
end
names = names(keep);
end

function order = section_order(names)
order = 1:numel(names);
values = zeros(size(names));
for i = 1:numel(names)
    tokens = regexp(names{i}, '\d+', 'match');
    values(i) = str2double(tokens{1});
end
[~, order] = sort(values);
end
