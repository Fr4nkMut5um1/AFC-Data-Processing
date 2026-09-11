function result = run_deshpande2023_baseline(cfg)
%RUN_DESHPANDE2023_BASELINE Isolated 12,000-frame SS experiment entry point.
experiment_root = fileparts(mfilename('fullpath'));
repo_root = fileparts(fileparts(fileparts(experiment_root)));
addpath(fullfile(repo_root, 'lib'));

defaults = d23.default_config(repo_root);
if nargin < 1 || isempty(cfg)
    cfg = defaults;
else
    cfg = d23.merge_config(defaults, cfg);
end
result = d23.run_experiment(cfg);
end
