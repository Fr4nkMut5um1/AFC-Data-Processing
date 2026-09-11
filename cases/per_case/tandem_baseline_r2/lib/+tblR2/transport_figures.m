function output = transport_figures(T, cfg, paths, mode)
%TRANSPORT_FIGURES Single-case Section-5 maps and streamwise profiles.
% Counts in profile tables are finite spatial samples, not event counts.
if nargin < 4 || isempty(mode), mode = 'export'; end
mode = validatestring(mode, {'export','preview'});
output = struct('files',{cell(0,1)},'figures',gobjects(0,1), ...
    'role',T.source_role,'job','transport');
formats = tblR2.figures_global(cfg,'formats');
if isempty(formats), formats = {'png','fig'}; end
formats = cellstr(formats);
dpi = tblR2.figures_global(cfg,'export_dpi');
if isempty(dpi), dpi = 300; end
display_quantile = 0.995;
if isfield(cfg, 'figures') && isfield(cfg.figures, 'section5') && ...
        isfield(cfg.figures.section5, 'display_quantile')
    display_quantile = cfg.figures.section5.display_quantile;
end
validateattributes(display_quantile, {'numeric'}, {'scalar','finite','>',0,'<=',1});
anchors = tblR2.viz.reference_balance_colormap();
balance = interp1(linspace(0,1,size(anchors,1)), anchors, linspace(0,1,256));
X = double(T.grid.X); Y = double(T.grid.Y);
mask = logical(T.calculation_mask) & isfinite(X) & isfinite(Y);
[ny,nx] = size(mask);
xrange = [80 320];
if isfield(cfg,'transport') && isfield(cfg.transport,'profile_x_range_mm')
    xrange = double(cfg.transport.profile_x_range_mm);
end
validateattributes(xrange,{'numeric'},{'vector','numel',2,'finite','increasing'});
profile_mask = mask & X >= xrange(1) & X <= xrange(2);
if ~any(profile_mask(:))
    error('tblR2:transport_figures:EmptyProfileRange', ...
        'The requested profile range has no accepted grid points.');
end
y = mean(Y,2,'omitnan');
identity = '';
for key = {'experiment_id','case_id','case_name'}
    if isfield(cfg,key{1}) && ~isempty(cfg.(key{1}))
        identity = char(string(cfg.(key{1}))); break;
    end
end
if isempty(identity), identity = char(paths.root); end
identity = strrep(strrep(identity, 'per_case/', ''), '_', ' ');
heading = sprintf('%s | %s',identity,char(T.source_role));
profile_heading = sprintf('x = %g to %g mm',xrange);
controlled = isfield(T,'coherent') && ~isempty(T.coherent) && ...
    isfield(T,'random') && ~isempty(T.random);
branches = {'total'};
if controlled, branches = {'total','coherent','random'}; end
rows = cell(0,8); qrows = cell(0,10); prows = cell(0,9);
limitrows = cell(0,9);

map_figure('01_total_stress_production', ...
    {T.total.negative_uv,T.total.production_primary_fd}, ...
    {'Total Reynolds shear stress','Total main-shear production (FD)'}, ...
    {'-<u''v''> [m^2 s^{-2}]','P = -<u''v''> dU/dy [m^2 s^{-3}]'},false,false);
map_figure('02_gradient_diagnostic', ...
    {T.total.dUdy.finite_difference,T.total.dUdy.difference}, ...
    {'Mean shear: finite difference','Mean shear: RBF-FD minus finite difference'}, ...
    {'dU/dy [s^{-1}]','Difference [s^{-1}]'},false,false);
quadrant_maps(T.total.quadrant,'total','03','04');
quadrant_profiles(T.total.quadrant,'total','05_total_quadrant_H_profiles');

f = new_figure(1,2,'Stress and production profiles');
tl = f.Children(1);
for k = 1:2
    ax = nexttile(tl); hold(ax,'on');
    fields = {'negative_uv','production_primary_fd'};
    units = {'m2/s2','m2/s3'};
    labels = {'-<u''v''> [m^2 s^{-2}]','Main-shear P [m^2 s^{-3}]'};
    for c = 1:numel(branches)
        branch = branches{c}; [v,n] = average(T.(branch).(fields{k}));
        colors = [0.1 0.1 0.1; 0.75 0.15 0.12; 0.0 0.35 0.70];
        styles = {'-','-','--'};
        plot(ax,v,y,'LineWidth',1.5,'DisplayName',branch, ...
            'Color',colors(c,:),'LineStyle',styles{c});
        for j = 1:ny
            rows(end+1,:) = {branch,fields{k},y(j),v(j),n(j), ...
                units{k},xrange(1),xrange(2)}; %#ok<AGROW>
        end
    end
    xlabel(ax,labels{k}); ylabel(ax,'y [mm]'); grid(ax,'on');
    title(ax,profile_heading,'Interpreter','none');
    legend(ax,'Location','best','Interpreter','none');
end
finish(f,'06_stress_production_profiles');

if controlled
    map_figure('07_coherent_random_stress', ...
        {T.coherent.negative_uv,T.random.negative_uv}, ...
        {'Coherent stress','Random stress'}, ...
        {'-<u~v~> [m^2 s^{-2}]','-<u''''v''''> [m^2 s^{-2}]'},false,true);
    map_figure('08_coherent_random_production', ...
        {T.coherent.production_primary_fd,T.random.production_primary_fd}, ...
        {'Coherent main-shear production (FD)','Random main-shear production (FD)'}, ...
        {'P coherent [m^2 s^{-3}]','P random [m^2 s^{-3}]'},false,true);
    phi = double(T.phase_degrees(:)); nb = numel(phi);
    phase_stress = {T.total_phase.negative_uv, ...
        T.coherent_phase.negative_utilde_vtilde,T.random_phase.negative_uv};
    phase_names = {'total','coherent','random'};
    heat = cell(1,3);
    for c = 1:3
        heat{c} = phase_average(phase_stress{c},phase_names{c},'negative_uv','m2/s2');
    end
    phase_figure('09_phase_stress',heat, ...
        {'Total phase stress','Coherent phase stress','Random phase stress'}, ...
        '-<uv> component [m^2 s^{-2}]');
    production_heat = cell(1,3);
    for c = 2:3
        field = T.([phase_names{c} '_phase']).production_primary_fd;
        production_heat{c} = phase_average(field,phase_names{c},'production_primary_fd','m2/s3');
    end
    if isfield(T.total_phase,'production_primary_fd')
        production_heat{1} = phase_average(T.total_phase.production_primary_fd,'total', ...
            'production_primary_fd','m2/s3');
        phase_figure('14_phase_production',production_heat, ...
            {'Total phase main-shear production','Coherent phase main-shear production', ...
            'Random phase main-shear production'},'P component [m^2 s^{-3}]');
        phase_figure('15_coherent_phase_detail',{heat{2},production_heat{2}}, ...
            {'Coherent phase stress (own scale)','Coherent phase main-shear production (own scale)'}, ...
            {'-<u~v~> [m^2 s^{-2}]','P coherent [m^2 s^{-3}]'},false);
    end
    rq = T.random_phase.quadrant;
    if isfield(rq,'cycle_average')
        cycleq = rq.cycle_average;
    elseif isfield(T.random_phase,'cycle_average')
        cycleq = T.random_phase.cycle_average.quadrant;
    else
        cycleq = T.random.quadrant;
    end
    if ~isfield(cycleq,'hole_thresholds'), cycleq.hole_thresholds = rq.hole_thresholds; end
    quadrant_maps(cycleq,'random cycle average','10','11');
    quadrant_profiles(cycleq,'random_cycle','13_random_quadrant_H_profiles');
    [~,h] = min(abs(double(rq.hole_thresholds(:))-1));
    qheat = cell(1,2);
    for c = 1:2
        q = 2*c;
        A = reshape(rq.mean_negative_uv_contribution(h,q,:,:,:),nb,ny,nx);
        qheat{c} = phase_average(A,'random',sprintf('Q%d_H%g_contribution', ...
            q,rq.hole_thresholds(h)),'m2/s2');
    end
    phase_figure('12_random_Q2_Q4_phase',qheat, ...
        {sprintf('Random Q2 contribution, H = %g',rq.hole_thresholds(h)), ...
         sprintf('Random Q4 contribution, H = %g',rq.hole_thresholds(h))}, ...
        'Contribution [m^2 s^{-2}]');
end

if strcmp(mode,'export')
    write_rows(rows,{'component','quantity','y_mm','mean_value', ...
        'finite_spatial_count','unit','x_min_mm','x_max_mm'},'transport_profiles');
    write_rows(qrows,{'branch','H','quadrant','y_mm','probability', ...
        'contribution_m2_s2','probability_spatial_count','contribution_spatial_count', ...
        'x_min_mm','x_max_mm'},'quadrant_profiles');
    if controlled
        write_rows(prows,{'component','quantity','phase_degrees','y_mm','mean_value', ...
            'finite_spatial_count','unit','x_min_mm','x_max_mm'},'phase_profiles');
    end
    write_rows(limitrows,{'figure','panel','clim_min','clim_max', ...
        'finite_count','clipped_count','display_quantile','data_min','data_max'},'display_limits');
end

    function [v,n] = average(A)
        A = reshape(double(A),ny,nx);
        A(~profile_mask | ~isfinite(A)) = NaN;
        n = sum(isfinite(A),2); v = mean(A,2,'omitnan');
    end

    function f = new_figure(nr,nc,label)
        visible = 'off'; if strcmp(mode,'preview'), visible = 'on'; end
        f = figure('Visible',visible,'Color','w','Name',[heading ' | ' label], ...
            'Position',[60 60 1200 max(450,245*nr)]);
        tlnew = tiledlayout(f,nr,nc,'TileSpacing','compact','Padding','loose');
        title(tlnew,[heading ' | ' label],'Interpreter','none','FontSize',12);
    end

    function finish(f,stem)
        set(findall(f,'Type','axes'),'FontSize',11);
        if strcmp(mode,'preview')
            output.figures(end+1,1) = f;
        else
            guard = onCleanup(@() close(f));
            for z = 1:numel(formats)
                fmt = lower(char(formats{z}));
                if isfield(paths,fmt), folder = paths.(fmt);
                else, folder = fullfile(paths.root,fmt); end
                base = fullfile(folder,['transport_' stem]);
                tblR2.viz.export_publication_figure(f,base,{fmt},dpi);
                output.files{end+1,1} = [base '.' fmt];
            end
            clear guard;
        end
    end

    function lim = symmetric(arrays)
        peak = 0;
        for z = 1:numel(arrays)
            v = arrays{z}; v = v(isfinite(v));
            if ~isempty(v), peak = max(peak,quantile(abs(v),display_quantile)); end
        end
        if peak == 0, peak = 1; end
        lim = [-peak peak];
    end

    function map_figure(stem,arrays,labels,units,sequential,shared)
        for z = 1:numel(arrays)
            arrays{z} = reshape(double(arrays{z}),ny,nx);
            arrays{z}(~mask | ~isfinite(arrays{z})) = NaN;
        end
        f = new_figure(numel(arrays),1,'Transport fields'); tlmap = f.Children(1);
        common = symmetric(arrays);
        for z = 1:numel(arrays)
            ax = nexttile(tlmap); A = arrays{z};
            if nx == 1
                scatter(ax,X(:,1),Y(:,1),36,A(:,1),'filled');
            else
                surface(ax,X,Y,zeros(ny,nx),A,'EdgeColor','none', ...
                    'FaceColor','texturemap','FaceAlpha','texturemap', ...
                    'AlphaData',double(isfinite(A)),'AlphaDataMapping','none');
                view(ax,2); daspect(ax,[1 1 1]);
            end
            axis(ax,'tight');
            set(ax,'YDir','normal','Color',[0.94 0.94 0.94]);
            if sequential
                lim = [0 min(1,common(2))]; colormap(ax,parula(256));
            else
                if shared, lim = common; else, lim = symmetric({A}); end
                if strcmp(stem, '02_gradient_diagnostic') && z == 2
                    scale = max(abs(arrays{1}(:)), [], 'omitnan');
                    lim = [-1 1] * max(lim(2), 1e-10*max(scale,1));
                end
                colormap(ax,balance);
            end
            clim(ax,lim); cb = colorbar(ax); cb.Label.String = units{z};
            cb.FontSize = 11;
            title(ax,labels{z},'Interpreter','none','FontSize',11);
            xlabel(ax,'x [mm]'); ylabel(ax,'y [mm]');
            record_limit(stem,labels{z},A,lim);
        end
        finish(f,stem);
    end

    function quadrant_maps(Q,branch,pstem,cstem)
        [~,h] = min(abs(double(Q.hole_thresholds(:))-1));
        probs = cell(1,4); contrib = cell(1,4); labels = cell(1,4);
        for q = 1:4
            probs{q} = reshape(Q.probability(h,q,:,:),ny,nx);
            contrib{q} = reshape(Q.mean_negative_uv_contribution(h,q,:,:),ny,nx);
            labels{q} = sprintf('%s Q%d, H = %g',branch,q,Q.hole_thresholds(h));
        end
        safe = strrep(branch,' ','_');
        map_figure([pstem '_' safe '_quadrant_probability'],probs,labels, ...
            repmat({'Probability'},1,4),true,true);
        map_figure([cstem '_' safe '_quadrant_contribution'],contrib,labels, ...
            repmat({'-<u''v'' I_Q,H> [m^2 s^{-2}]'},1,4),false,true);
    end

    function quadrant_profiles(Q,branch,stem)
        hs = double(Q.hole_thresholds(:));
        chosen = zeros(1,3);
        for z = 1:3, [~,chosen(z)] = min(abs(hs-(z-1))); end
        chosen = unique(chosen,'stable');
        f = new_figure(2,2,[branch ' quadrant contributions | ' profile_heading]);
        tlq = f.Children(1);
        for q = 1:4
            ax = nexttile(tlq); hold(ax,'on');
            for h = 1:numel(hs)
                [p,np] = average(Q.probability(h,q,:,:));
                [v,nv] = average(Q.mean_negative_uv_contribution(h,q,:,:));
                for j = 1:ny
                    qrows(end+1,:) = {branch,hs(h),sprintf('Q%d',q),y(j), ...
                        p(j),v(j),np(j),nv(j),xrange(1),xrange(2)}; %#ok<AGROW>
                end
                if ismember(h,chosen)
                    plot(ax,v,y,'LineWidth',1.4,'DisplayName',sprintf('H = %g',hs(h)));
                end
            end
            xlabel(ax,'Contribution [m^2 s^{-2}]'); ylabel(ax,'y [mm]');
            title(ax,sprintf('Q%d',q)); grid(ax,'on');
            legend(ax,'Location','best');
        end
        finish(f,stem);
    end

    function P = phase_average(A,branch,quantity,unit)
        A = reshape(double(A),nb,ny,nx); P = nan(ny,nb);
        for b = 1:nb
            [v,n] = average(A(b,:,:)); P(:,b) = v;
            for j = 1:ny
                prows(end+1,:) = {branch,quantity,phi(b),y(j),v(j),n(j), ...
                    unit,xrange(1),xrange(2)}; %#ok<AGROW>
            end
        end
    end

    function phase_figure(stem,arrays,labels,unit,shared)
        if nargin < 5; shared = true; end
        f = new_figure(numel(arrays),1,profile_heading); tlphase = f.Children(1);
        lim = symmetric(arrays); [sortedphi,order] = sort(phi);
        for z = 1:numel(arrays)
            ax = nexttile(tlphase); A = arrays{z}(:,order);
            if ~shared; lim = symmetric({A}); end
            plot_phi = [sortedphi; sortedphi(1)+360];
            plot_data = [A A(:,1)];
            im = imagesc(ax,plot_phi,y,plot_data); im.AlphaData = isfinite(plot_data);
            xlim(ax,[sortedphi(1) sortedphi(1)+360]);
            xticks(ax,sortedphi(1)+(0:90:360));
            set(ax,'YDir','normal','Color',[0.94 0.94 0.94]);
            colormap(ax,balance); clim(ax,lim);
            cb = colorbar(ax); cb.Label.String = unit; cb.FontSize = 11;
            if iscell(unit); cb.Label.String = unit{z}; end
            xlabel(ax,'Phase [degrees]'); ylabel(ax,'y [mm]');
            title(ax,labels{z},'Interpreter','none','FontSize',11);
            record_limit(stem,labels{z},A,lim);
        end
        finish(f,stem);
    end

    function record_limit(stem,label,A,lim)
        valid = isfinite(A);
        limitrows(end+1,:) = {stem,label,lim(1),lim(2),sum(valid(:)), ...
            nnz(valid & (A<lim(1) | A>lim(2))),display_quantile, ...
            min(A(valid),[],'omitnan'),max(A(valid),[],'omitnan')};
    end

    function write_rows(data,names,stem)
        file = fullfile(paths.csv,[stem '.csv']);
        writetable(cell2table(data,'VariableNames',names),file);
        output.files{end+1,1} = file;
    end
end
