function [result, output] = run_section5_legacy_config(configuration_file, stage)
%RUN_SECTION5_LEGACY_CONFIG Explicit historical configuration entry; no path migration.
% configuration_file must contain cfg. Existing source identity remains unchanged.
if nargin < 2; stage = 'reuse'; end
loaded = load(configuration_file, 'cfg');
if ~isfield(loaded, 'cfg'); error('tblR2:legacy:MissingConfig', '文件缺少 cfg：%s', configuration_file); end
cfg = loaded.cfg;
case_root = fileparts(fileparts(mfilename('fullpath')));
if ~isfield(cfg, 'script_file') || ~strcmp(fileparts(cfg.script_file), case_root)
    error('tblR2:legacy:UnmigratedConfig', '旧 cfg 不属于本 case；须先独立核实并显式迁移路径，不自动改写。');
end
addpath(fullfile(case_root, 'lib'), '-begin');
tblR2.require_case_library(case_root, {'tblR2.section5_run','tblR2.build_paths'});
paths = tblR2.build_paths(cfg.output_dir);
[result, output] = tblR2.section5_run(cfg, paths, stage, true);
end
