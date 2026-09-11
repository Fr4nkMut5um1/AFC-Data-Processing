function contract = result_parameters(cfg, stage)
%RESULT_PARAMETERS Producer parameters for original S2/S3 algorithms, not transport.
if strcmp(stage, 'structures')
    % Saved adapted result includes instantaneous selections and export metadata.
    % Changing these may require republishing it, but select_section4_run can
    % reuse equivalent POD/detection products without a new computation.
    names = {'case_id','case_type','fs','n_frames','total_frames','grid_size', ...
        'Uinf','nu','D_mm','instantaneous','structures'};
    parameters = struct();
    for k = 1:numel(names); parameters.(names{k}) = cfg.(names{k}); end
    controls = {'resume_run_dir','reuse_existing_run','output_dir'};
    for k = 1:numel(controls)
        if isfield(parameters.structures.section4, controls{k})
            parameters.structures.section4 = rmfield(parameters.structures.section4, controls{k});
        end
    end
    parameters.sources.postproc = cfg.sources.postproc;
    parameters.figure_dpi = cfg.figures.export_dpi;
    files = {'section4_vlsm_analysis.m','section4_vlsm_figures.m','instantaneous_frame_ids.m'};
    listing = dir(fullfile(fileparts(fileparts(mfilename('fullpath'))), '+d23', '*.m'));
    for k = 1:numel(listing); files{end+1} = ['../+d23/' listing(k).name]; end
    implementation = struct('file', {}, 'sha256', {});
    for k = 1:numel(files)
        implementation(k) = struct('file', files{k}, 'sha256', d23.sha256_text( ...
            fileread(fullfile(fileparts(mfilename('fullpath')), files{k}))));
    end
    contract = struct('schema_version', 2, 'algorithm', 'original_d23_r2_adapter_v1', ...
        'parameters', parameters, 'implementation', implementation);
    return;
end
fields = {'case_id','case_type','fs','n_frames','total_frames','grid_size', ...
    'wall_side','frame_offset','min_valid_fraction','chunk_frames','Uinf', ...
    'statistics_source','statistics_frame_mode'};
parameters = struct();
for k = 1:numel(fields)
    if ~isfield(cfg, fields{k})
        error('tblR2:result:MissingParameter', 'cfg.%s missing for %s.', fields{k}, stage);
    end
    parameters.(fields{k}) = cfg.(fields{k});
end
parameters.sources.(cfg.statistics_source) = cfg.sources.(cfg.statistics_source);
algorithms = {'mean_stats_cache.m','read_cache_frames.m'};
version_name = 'original_repeat_mean_statistics_v1';
if strcmp(stage, 'mean_bl')
    fields = {'profile','loglaw','modern_clauser','normalization','friction','nu','rho','x_max'};
    for k = 1:numel(fields)
        if isfield(cfg, fields{k}); parameters.(fields{k}) = cfg.(fields{k}); end
    end
    algorithms = [algorithms, {'mean_bl_friction.m','wall_distance_grid.m','+bl/data/Cf_chart.txt'}];
    folders = {'+bl','+wall','+singlecase','+stats','+io'};
    for j = 1:numel(folders)
        listing = dir(fullfile(fileparts(mfilename('fullpath')), folders{j}, '*.m'));
        for k = 1:numel(listing)
            algorithms{end+1} = [folders{j} '/' listing(k).name]; %#ok<AGROW>
        end
    end
    version_name = 'original_mean_bl_friction_v1';
elseif strcmp(stage, 'phase')
    parameters.phase = cfg.phase;
    parameters.phase_cache_source = 'raw'; % Actual historical Section-3 main call.
    parameters.sources.raw = cfg.sources.raw;
    algorithms = [algorithms, {'phase_stats_cache.m','assign_phase.m'}];
    version_name = 'original_frame_clock_phase_and_denominators_v1';
elseif ~strcmp(stage, 'statistics')
    error('tblR2:result:Stage', 'Unsupported S2/S3 producer stage: %s', stage);
end
implementation = struct('file', {}, 'sha256', {});
for k = 1:numel(algorithms)
    source = fullfile(fileparts(mfilename('fullpath')), algorithms{k});
    implementation(k) = struct('file', algorithms{k}, ...
        'sha256', d23.sha256_text(fileread(source)));
end
contract = struct('schema_version', 2, 'algorithm', version_name, ...
    'parameters', parameters, 'implementation', implementation);
end
