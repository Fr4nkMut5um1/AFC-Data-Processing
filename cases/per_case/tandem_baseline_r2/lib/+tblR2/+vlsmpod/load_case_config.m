function cfg = load_case_config(case_root, case_name)
%LOAD_CASE_CONFIG 读取 case 脚本固化下来的 cfg，不重跑 case 脚本。
%
% 为什么不直接 run case 脚本：那会触发全流程重算（读 12000 帧 DAT、重建缓存、
% 重算统计），要几小时。case 文件把配置构造逻辑放在函数体内，外部取不到，所以
% 通过 00_case_configuration.mat 读回已固化的 cfg。
%
% 三个入口脚本原先各有一份逐字相同的副本，这里收成一处。

if nargin < 2 || isempty(case_name)
    [~, case_name] = fileparts(case_root);
end
config_file = fullfile(case_root, 'output', 'mat', '00_case_configuration.mat');
if ~isfile(config_file)
    error('tblR2:vlsmpod:load_case_config:MissingConfig', ...
        ['找不到工况配置：%s\n' ...
        '请先运行 %s_case.m 至少一次，让它写出 00_case_configuration.mat。'], ...
        config_file, case_name);
end
loaded = load(config_file);
% 三种可能的存盘布局：save_result 包了一层 data.cfg；早期版本直接存 cfg；
% 更早的版本把 cfg 本身当作 data 存。
if isfield(loaded, 'data') && isstruct(loaded.data) && isfield(loaded.data, 'cfg')
    cfg = loaded.data.cfg;
elseif isfield(loaded, 'cfg')
    cfg = loaded.cfg;
elseif isfield(loaded, 'data')
    cfg = loaded.data;
else
    error('tblR2:vlsmpod:load_case_config:InvalidConfig', ...
        '配置文件结构无法识别：%s', config_file);
end
end
