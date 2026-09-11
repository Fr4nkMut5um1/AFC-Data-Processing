function output = plot_products(results, cfg, paths, mode, selected_jobs)
%PLOT_PRODUCTS Figure dispatch for the compact r2 case.
% 所有具体绘制（纯 MATLAB 原生图形调用）集中在 plot_core_products.m；
% 本文件只做任务清单校验、逐 job 委托与错误收集。

if nargin < 4 || isempty(mode); mode = 'export'; end
mode = lower(char(mode));
if ~ismember(mode, {'export','preview'})
    error('tblR2:plot_products:InvalidMode', 'mode 必须是 export 或 preview。');
end

jobs = {'cache_raw','mean_turbulence','mean_profiles','loglaw','loglaw_diagnostic', ...
    'modern_clauser', ...
    'phase_triple','instantaneous_fields','instantaneous_vortex', ...
    'friction','structures','transport','temporal_spectra','spatial_spectra', ...
    'pod','dmd','lcs_ftle','spod','correlations','harmonics'};
aliases = {'modern_clauser_sensitivity','vlsm_gallery'};
if nargin < 5 || isempty(selected_jobs)
    selected_jobs = tblR2.figures_global(cfg, 'jobs');
    if isempty(selected_jobs)
        selected_jobs = jobs;
    end
end
selected_jobs = cellstr(selected_jobs);
unknown = setdiff(selected_jobs, [jobs aliases]);
if ~isempty(unknown)
    error('tblR2:plot_products:UnknownJob', '未知的图形任务：%s。', strjoin(unknown, ', '));
end

files = cell(0,1); figures = gobjects(0,1);
errors = repmat(struct('job','','identifier','','message',''),0,1);
disabled_jobs = cell(0,1); source_roles = struct('file',{},'source_role',{});
for ij = 1:numel(selected_jobs)
    job = selected_jobs{ij};
    if ismember(job, aliases)
        disabled_jobs{end+1,1} = job; %#ok<AGROW>
        continue;
    end
    try
        if strcmp(job, 'lcs_ftle')
            produced = lcs_ftle();
        else
            produced = delegate(job);
        end
        files = [files; produced(:)]; %#ok<AGROW>
    catch ME
        errors(end+1,1) = struct('job',job,'identifier',ME.identifier, ...
            'message',ME.message); %#ok<AGROW>
    end
end
output = struct('files',{files},'figures',figures,'errors',errors, ...
    'disabled_jobs',{disabled_jobs},'mode',mode,'jobs',{selected_jobs}, ...
    'source_roles',source_roles);

    function produced = delegate(job)
        out = tblR2.plot_core_products(job, results, cfg, paths, mode);
        if strcmp(mode,'preview')
            if ~isempty(out.figures); figures = [figures; out.figures(:)]; end %#ok<AGROW>
            produced = cell(0,1);
            return;
        end
        for k = 1:numel(out.files)
            source_roles(end+1,1) = struct('file',out.files{k}, ...
                'source_role',out.role); %#ok<AGROW>
        end
        produced = out.files;
    end

    function produced = lcs_ftle()
        produced = {};
        if ~isfield(results,'lcs') || isempty(results.lcs); return; end
        plot_indices = unique([1, ceil(numel(results.lcs.frame_ids) / 2), ...
            numel(results.lcs.frame_ids)]);
        if isfield(cfg, 'lcs') && isfield(cfg.lcs, 'plot_frame_indices') && ...
                ~isempty(cfg.lcs.plot_frame_indices)
            plot_indices = cfg.lcs.plot_frame_indices;
        end
        P = tblR2.plot_lcs_ftle(results.lcs, cfg, ...
            'frame_indices', plot_indices, ...
            'visible', strcmp(mode,'preview'));
        if strcmp(mode, 'preview')
            figures = [figures; P.figures(:)]; %#ok<AGROW>
            return;
        end
        for ii = 1:numel(P.figures)
            result_index = P.frame_indices(ii);
            stem = sprintf('08_lcs_ftle_%04d', results.lcs.frame_ids(result_index));
            produced = [produced; save_fig(P.figures(ii), stem)]; %#ok<AGROW>
        end
    end

    function produced = save_fig(f, stem)
        if strcmp(mode,'preview'); drawnow; figures(end+1,1)=f; produced = cell(0,1); return; end
        formats = {'png'};
        global_formats = tblR2.figures_global(cfg, 'formats');
        if ~isempty(global_formats); formats = cellstr(global_formats); end
        export_dpi = 200;
        global_dpi = tblR2.figures_global(cfg, 'export_dpi');
        if ~isempty(global_dpi) && isnumeric(global_dpi) && isscalar(global_dpi)
            export_dpi = global_dpi;
        end
        produced = cell(numel(formats),1);
        for jj = 1:numel(formats)
            ext = lower(strtrim(formats{jj})); if ~isfield(paths,ext); error('tblR2:plot_products:UnsupportedFigureFormat','没有为格式 %s 配置输出目录。',ext); end
            base = fullfile(paths.(ext),stem); tblR2.viz.export_publication_figure(f,base,{ext},export_dpi);
            produced{jj} = [base '.' ext]; source_roles(end+1,1) = struct('file',produced{jj},'source_role','postproc'); %#ok<AGROW>
        end
        close(f);
    end
end
