function cfg = default_config(repo_root)
%DEFAULT_CONFIG Explicit configuration for the isolated Deshpande experiment.
if nargin < 1 || isempty(repo_root)
    here = fileparts(mfilename('fullpath'));
    repo_root = fileparts(fileparts(here));
end
case_root = fullfile(repo_root, 'cases', 'per_case', 'tandem_baseline_r2');
experiment_root = fullfile(repo_root, 'cases', 'experiments', ...
    'deshpande2023_baseline');

cfg = struct();
cfg.schema_version = 3;
cfg.experiment_id = 'deshpande2023_baseline';
cfg.case_id = 'per_case/tandem_baseline_r2';
cfg.repo_root = repo_root;

cfg.data = struct();
cfg.data.cache_file = fullfile(case_root, 'output', 'mat', ...
    '01_sequence_cache_postproc.mat');
cfg.data.utau_result_file = fullfile(case_root, 'output', 'mat', ...
    '02_mean_boundary_layer_friction.mat');
cfg.data.expected_cache_size = [12000 89 640];
cfg.data.reference_x_mm = [100 220];
cfg.data.nu_m2_s = 1.48e-5;

cfg.statistics = struct();
cfg.statistics.chunk_size = 48;
cfg.statistics.frame_ordinals = (1:12000).';
cfg.statistics.reuse_file = '';

cfg.detection = struct();
cfg.detection.connectivities = [8 4];
cfg.detection.primary_connectivity = 8;
cfg.detection.amplitude_multiplier = 1.0;
cfg.detection.length_thresholds = [3.0 3.8 4.5];
cfg.detection.max_complete_ss_per_sign = 1;
cfg.detection.selection_rule = ...
    'longest_then_pixel_count_then_component_id';
% The isolated d23 default preserves the historical one-object behavior.
% Section 4 explicitly opts into all non-overlapping objects.
cfg.detection.streamwise_edge_exclusion = struct('enabled', false, ...
    'buffer_cells', 3);

cfg.preprocessing = struct();
cfg.preprocessing.spatial_exclusion = struct('enabled', false, ...
    'x_start_mm', [], 'x_end_mm', [], 'wall_y_height_mm', []);
cfg.preprocessing.pod = struct('enabled', false, ...
    'min_valid_fraction', [], 'rank', struct(), ...
    'rms_source', 'reconstruction', ...
    'spatial_block_dof', 512, 'time_tile_frames', 128, ...
    'memory_safety_factor', 1.25, 'disk_safety_factor', 1.25);
cfg.preprocessing.gaussian = struct('enabled', false, ...
    'sigma_cells', [], 'filter_size', [], 'padding', 'replicate');

cfg.matching = struct();
cfg.matching.require_full_valid_box = false;

cfg.spectra = struct();
cfg.spectra.window = 'hamming_periodic';
cfg.spectra.zero_padding_factor = 4;
cfg.spectra.n_lambda = 160;
cfg.spectra.large_scale_min_lambda_over_delta = 3.0;

cfg.execution = struct();
cfg.execution.label = 'full';
cfg.execution.frame_ordinals = (1:12000).';
cfg.execution.progress_every_batches = 5;
cfg.execution.make_gallery = true;
cfg.execution.make_figures = true;

cfg.output = struct();
cfg.output.root = fullfile(experiment_root, 'output', 'runs');
cfg.output.resume_run_dir = '';
cfg.output.write_catalog_csv = true;
cfg.output.verify_catalog_csv = true;
cfg.output.figure_dpi = 180;
cfg.output.field_colormap = 'balance';
cfg.output.field_colormap_levels = 257;
cfg.output.field_clim = [-3 3];
cfg.output.field_physical_aspect = true;
end
