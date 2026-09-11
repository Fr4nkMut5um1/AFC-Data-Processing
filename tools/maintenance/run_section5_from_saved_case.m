function [result, output] = run_section5_from_saved_case(case_name, source, stage, options)
%RUN_SECTION5 Deliver one r2 case using its saved config and selected cache.
% run_section5_from_saved_case('tandem_baseline_r2', 'raw', 'compute')
% run_section5_from_saved_case('tandem_f40a3_phi0_r2', 'postproc', 'compute')
if nargin < 1; case_name = 'tandem_baseline_r2'; end
if nargin < 2; source = 'raw'; end
if nargin < 3; stage = 'compute'; end
if nargin < 4; options = struct(); end
case_name = validatestring(case_name, {'tandem_baseline_r2', 'tandem_f40a3_phi0_r2'});
repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(repo_root, 'lib'), '-begin');
case_root = fullfile(repo_root, 'cases', 'per_case', case_name);
cfg = tblR2.vlsmpod.load_case_config(case_root, case_name);
if ~isfield(cfg, 'transport'); cfg.transport = struct(); end
names = fieldnames(options);
for k = 1:numel(names); cfg.transport.(names{k}) = options.(names{k}); end
cfg.transport.source = source;
cfg.output_dir = fullfile(case_root, 'output');
paths = tblR2.build_paths(cfg.output_dir);
[result, output] = tblR2.section5_run(cfg, paths, stage, true);
end
