function result = run_pod_vlsm_parameter_optimization(varargin)
%RUN_POD_VLSM_PARAMETER_OPTIMIZATION
% 低阶 POD 重构场上的 VLSM 聚类联通法参数优化诊断。
%
% 每轮随机抽取 24 帧，使用 POD + signed-hysteresis connectivity 识别，
% 输出 contourf 审核图、聚类摘要和供 Codex 视觉审核填写的 JSON 模板。
% 视觉审核不是物理真值；它只作为操作性对照，不能替代实验标注。
%
% 重要边界：本工具只在 POD 分支使用 valid_mask（保留 FOV 边缘）。Gaussian
% 和既有 case 配置不被修改。POD 边缘结构同时关闭 trusted-boundary rejection。

parser = inputParser;
parser.addParameter('case_name', 'tandem_baseline_r2', @(x)ischar(x)||isstring(x));
parser.addParameter('energy_target', 0.50, @(x)isscalar(x)&&x>0&&x<=1);
parser.addParameter('n_frames_per_round', 24, @(x)isscalar(x)&&x==fix(x)&&x>=1);
parser.addParameter('max_rounds', 16, @(x)isscalar(x)&&x==fix(x)&&x>=1);
parser.addParameter('random_seed', 20260826, @(x)isscalar(x));
parser.addParameter('round_start', 1, @(x)isscalar(x)&&x==fix(x)&&x>=1);
parser.addParameter('initial_overrides', struct(), @isstruct);
parser.addParameter('review_dir', '', @(x)ischar(x)||isstring(x));
parser.addParameter('output_dir', '', @(x)ischar(x)||isstring(x));
% Fixed symmetric range for comparable POD fluctuation maps.  The previous
% per-frame robust range could leave high-amplitude values outside the outer
% contourf level and render them as white/unfilled regions.
parser.addParameter('colorbar_abs_limit', 3.0, ...
    @(x)isnumeric(x)&&isscalar(x)&&isfinite(x)&&x>0);
parser.parse(varargin{:});
opt = parser.Results;

script_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(fileparts(fileparts(script_dir)));
case_root = fullfile(repo_root, 'cases', 'per_case', char(opt.case_name));
addpath(fullfile(repo_root, 'lib'));
addpath(fullfile(repo_root, 'tools', 'research'));
cfg = tblR2.vlsmpod.load_case_config(case_root, char(opt.case_name));
paths = tblR2.build_paths(cfg.output_dir);
stats = tblR2.load_result(paths.statistics, cfg, 'statistics');
mean_bl = tblR2.load_result(paths.mean_bl, cfg, 'mean_bl');

basis_file = fullfile(repo_root, 'tmp', 'pod_energy_sweep', ...
    'pod_energy_sweep_basis.mat');
if ~isfile(basis_file)
    error('podVlsmOpt:MissingBasis', '找不到 POD 基底：%s', basis_file);
end
loaded = load(basis_file, 'denoise');
denoise = loaded.denoise;
cumulative = cumsum(denoise.eigenvalues) ./ sum(denoise.eigenvalues);
rank_r = find(cumulative >= opt.energy_target, 1, 'first');
if isempty(rank_r); rank_r = numel(cumulative); end
rank_r = min(rank_r, denoise.rank);

if isempty(opt.output_dir)
    out_root = fullfile(repo_root, 'tmp', 'pod_vlsm_parameter_optimization');
else
    out_root = char(opt.output_dir);
end
if ~isfolder(out_root); mkdir(out_root); end
if isempty(opt.review_dir); review_root = out_root; else; review_root = char(opt.review_dir); end

% “最基础/原始”局部副本：使用已验证的 r1 基础连通口径。
% 00_case_configuration.mat 可能含有旧的 1.77/1.97 bootstrap 标定值，不能把
% 该历史产物误当作本轮优化的起点；本地副本不回写 cfg。
settings = cfg.structures;
settings.alpha = 0.40;
settings.seed_alpha = 0.70;
settings.connectivity = 8;
settings = ensure_field(settings, 'min_pixels', 3);
settings = ensure_field(settings, 'min_lsm_delta', 1.0);
settings = ensure_field(settings, 'min_vlsm_delta', 3.0);
settings = ensure_field(settings, 'max_wall_normal_delta', Inf);
settings = ensure_field(settings, 'max_internal_hole_pixels', 64);
settings = ensure_field(settings, 'envelope_closing_radius_cells', 2);
settings = ensure_field(settings, 'max_aspect_ratio', Inf);
settings = ensure_field(settings, 'reject_trusted_boundary_touching', false);
settings = ensure_field(settings, 'min_abs_fluctuation', 0);
settings = ensure_field(settings, 'min_abs_seed_fluctuation', 0);
settings = ensure_field(settings, 'merge_gap_cells', 0);
settings = ensure_field(settings, 'merge_require_y_overlap', true);
% POD 专用边缘策略：保留 valid_mask 中的 FOV 边缘，并不拒绝触碰边界的结构。
settings = apply_struct(settings, opt.initial_overrides);
% 边缘策略是本工具的硬约束，不能被 initial_overrides 覆盖。
settings.trusted_domain = struct('streamwise_edge_columns', 0, ...
    'wall_normal_top_rows', 0);
settings.reject_trusted_boundary_touching = false;

all_frame_ids = double(denoise.frame_ids(:));
n_rounds = min(opt.max_rounds, 16);
rounds = repmat(empty_round(), n_rounds, 1);
stop_reason = 'max_rounds_reached';

for rr = 1:n_rounds
    round_id = opt.round_start + rr - 1;
    rng(double(opt.random_seed) + round_id - 1, 'twister');
    frame_ids = all_frame_ids(randperm(numel(all_frame_ids), ...
        min(opt.n_frames_per_round, numel(all_frame_ids))));
    frame_ids = sort(frame_ids(:));

    % 显式复用 POD 专用边缘策略；不修改 cfg 或其他分支。
    local = settings;
    resolved = tblR2.vlsmpod.resolve_settings(local, struct());
    ctx = tblR2.vlsmpod.prepare_context(cfg, stats, mean_bl, resolved);
    ctx.analysis_domain_mask = ctx.valid_mask; % POD 允许触碰 FOV 边缘
    source = struct('preprocessing', 'pod_denoise', 'denoise', denoise, ...
        'mode_indices', 1:rank_r);

    round_dir = fullfile(out_root, sprintf('round_%02d', round_id));
    frame_dir = fullfile(round_dir, 'frames');
    if ~isfolder(frame_dir); mkdir(frame_dir); end
    counts = zeros(numel(frame_ids), 3);
    catalogs = cell(numel(frame_ids), 1);
    for k = 1:numel(frame_ids)
        fid = frame_ids(k);
        field = tblR2.vlsmpod.frame_field(ctx, fid, source);
        identified = tblR2.vlsmpod.identify_frame(ctx, field, resolved);
        T = identified.structures;
        counts(k,:) = [height(T), sum(T.IsLSM), sum(T.IsVLSM)];
        catalogs{k} = annotate(T, fid);
        fig = figure('Visible','off','Color','w','Units','centimeters', ...
            'Position',[1 1 24 6.5]);
        ax = axes(fig);
        vals = field.u_fluct;
        clim = [-double(opt.colorbar_abs_limit), double(opt.colorbar_abs_limit)];
        levels = contour_levels_with_overflow(vals, double(opt.colorbar_abs_limit), 24);
        contourf(ax, ctx.X_mm, ctx.Y_wall_mm, vals, levels, ...
            'LineStyle','none');
        colormap(ax, blue_white_red(256)); caxis(ax, clim); hold(ax,'on');
        draw_boxes(ax,T);
        set(ax,'YDir','normal','FontSize',7,'Layer','top'); axis(ax,'tight');
        title(ax, sprintf('POD E=%.0f%% frame %d | struct=%d LSM=%d VLSM=%d', ...
            100*opt.energy_target, fid, counts(k,1), counts(k,2), counts(k,3)), ...
            'FontSize',8,'FontWeight','normal');
        xlabel(ax,'x (mm)'); ylabel(ax,'y_{wall} (mm)'); colorbar(ax);
        exportgraphics(fig, fullfile(frame_dir, sprintf('frame_%06d.png',fid)), ...
            'Resolution',160); close(fig);
    end

    summary = summarize_round(frame_ids, counts, vertcat_nonempty(catalogs));
    review_file = fullfile(review_root, sprintf('round_%02d_visual_review.json', round_id));
    review = read_review(review_file, frame_ids);
    update = choose_update(settings, summary, review, round_id);
    write_json(fullfile(round_dir, sprintf('round_%02d_parameter_update.json',round_id)), ...
        struct('round',round_id,'old_parameters',settings,'cluster_summary',summary, ...
        'visual_review',review,'updated_parameters',update.parameters, ...
        'reason',update.reason,'stop_decision',update.stop));
    write_json(fullfile(round_dir, sprintf('round_%02d_visual_review_template.json',round_id)), review);
    save(fullfile(round_dir, sprintf('round_%02d.mat',round_id)), ...
        'round_id','frame_ids','counts','summary','settings','resolved','rank_r','cumulative');
    rounds(rr).round = round_id; rounds(rr).frame_ids = frame_ids; ...
        rounds(rr).summary = summary; rounds(rr).settings = settings; ...
        rounds(rr).update = update;
    fprintf('Round %02d: struct/frame=%.2f, LSM/frame=%.2f, VLSM/frame=%.2f, VLSM frames=%d/%d\n', ...
        round_id, summary.mean_structures, summary.mean_lsm, summary.mean_vlsm, ...
        summary.frames_with_vlsm, summary.n_frames);
    settings = update.parameters;
    if update.stop
        stop_reason = update.reason; break;
    end
end

result = struct('case_name',char(opt.case_name),'energy_target',opt.energy_target, ...
    'rank',rank_r,'cumulative_energy',cumulative(rank_r), ...
    'edge_policy','include_fov_edges_for_pod', ...
    'colorbar_abs_limit_m_per_s',double(opt.colorbar_abs_limit), ...
    'include_fov_edges_for_pod',true,'rounds',rounds,'stop_reason',stop_reason, ...
    'output_dir',out_root,'literature_note', ...
    'POD低阶重构会优先保留大尺度能量，VLSM数量和长度分布仍依赖rank；2C-2D连通结果不是三维真值。');
save(fullfile(out_root,'pod_vlsm_parameter_optimization.mat'),'result','-v7.3');
end

function s = empty_round()
s = struct('round',NaN,'frame_ids',[],'summary',struct(),'settings',struct(),'update',struct());
end
function s = ensure_field(s,n,v); if ~isfield(s,n)||isempty(s.(n)); s.(n)=v; end; end
function s = apply_struct(s,o)
f=fieldnames(o); for i=1:numel(f); s.(f{i})=o.(f{i}); end
end
function T = annotate(T,fid)
if isempty(T); return; end
T = addvars(T,repmat(fid,height(T),1),'Before',1,'NewVariableNames','FrameID');
end
function T = vertcat_nonempty(c)
keep=~cellfun(@isempty,c); if any(keep); T=vertcat(c{keep}); else; T=table(); end
end
function s = summarize_round(frame_ids,counts,T)
s=struct('n_frames',numel(frame_ids),'mean_structures',mean(counts(:,1)), ...
    'mean_lsm',mean(counts(:,2)),'mean_vlsm',mean(counts(:,3)), ...
    'frames_with_vlsm',nnz(counts(:,3)>0),'total_structures',sum(counts(:,1)), ...
    'total_vlsm',sum(counts(:,3)),'length_median',NaN,'length_p90',NaN, ...
    'length_max',NaN,'edge_touching_structures',0);
if ~isempty(T)
    x=double(T.LengthX_over_delta); x=x(isfinite(x));
    if ~isempty(x); s.length_median=median(x); s.length_p90=prctile(x,90); s.length_max=max(x); end
    if ismember('TouchesTrustedBoundary',T.Properties.VariableNames)
        s.edge_touching_structures=nnz(T.TouchesTrustedBoundary);
    end
end
end
function review = read_review(file,frame_ids)
if isfile(file)
    review=jsondecode(fileread(file));
else
    review=struct('status','pending_codex_visual_review','round_frame_ids',frame_ids(:).', ...
        'frames',repmat(struct('frame_id',NaN,'gpt_has_vlsm',NaN, ...
        'gpt_vlsm_count',NaN,'gpt_edge_should_count',NaN,'confidence',NaN,'notes',''), ...
        numel(frame_ids),1),'summary',struct('gpt_vlsm_frames',NaN,'gpt_mean_vlsm',NaN, ...
        'agreement',NaN,'notes','请由 Codex 视觉审核填写；GPT 不是物理真值。'));
    for i=1:numel(frame_ids); review.frames(i).frame_id=frame_ids(i); end
end
end
function u = choose_update(old,summary,review,round_id)
u=struct('parameters',old,'reason','no_visual_review_yet','stop',false);
if isfield(review,'status') && strcmp(review.status,'complete') && isfield(review,'summary')
    g=review.summary;
    if isfield(g,'agreement') && isfinite(g.agreement) && g.agreement>=0.80
        u.reason=sprintf('Codex visual/cluster operational agreement %.3f >= 0.80',g.agreement); u.stop=true; return;
    end
    % 只做小步参数调整，避免一次同时改变多个机制。
    if isfield(g,'gpt_vlsm_frames') && isfinite(g.gpt_vlsm_frames) && ...
            g.gpt_vlsm_frames > summary.frames_with_vlsm
        u.parameters.alpha=max(0.40,old.alpha-0.15); u.parameters.seed_alpha=max(u.parameters.alpha,old.seed_alpha-0.10);
        u.reason='GPT 视觉认为 VLSM 漏检：降低滞回阈值。';
    elseif isfield(g,'gpt_vlsm_frames') && isfinite(g.gpt_vlsm_frames) && ...
            g.gpt_vlsm_frames < summary.frames_with_vlsm
        u.parameters.alpha=min(2.0,old.alpha+0.15); u.parameters.seed_alpha=min(2.2,old.seed_alpha+0.10);
        u.reason='聚类疑似过检：提高滞回阈值。';
    elseif old.connectivity==4
        u.parameters.connectivity=8; u.reason='视觉与聚类边界断裂差异：切换为 8 连通复核。';
    elseif old.merge_gap_cells==0
        u.parameters.merge_gap_cells=20; u.reason='视觉提示流向断裂：启用小间隙合并并要求法向重叠。';
    else
        u.reason='已完成一轮小步参数复核，保持参数。';
    end
end
if round_id>=16; u.stop=true; u.reason='达到最多 16 轮。'; end
end
function write_json(file,s)
fid=fopen(file,'w','n','UTF-8'); if fid<0; error('podVlsmOpt:WriteJSON','无法写入 %s',file); end
fwrite(fid,jsonencode(s),'char'); fclose(fid);
end
function draw_boxes(ax,T)
if isempty(T); return; end
for i=1:height(T)
    if T.IsVLSM(i); c=[0.9 0.05 0.05]; ls='-'; lw=1.8;
    elseif T.IsLSM(i); c=[0.1 0.35 0.95]; ls='--'; lw=1.0; else; continue; end
    rectangle(ax,'Position',[T.XMin_mm(i),T.YMin_mm(i),T.XMax_mm(i)-T.XMin_mm(i),T.YMax_mm(i)-T.YMin_mm(i)], ...
        'EdgeColor',c,'LineStyle',ls,'LineWidth',lw);
end
end
function cmap=blue_white_red(n)
h=floor(n/2); cmap=[[linspace(0,1,h)',linspace(0,1,h)',ones(h,1)]; ...
    [ones(h,1),linspace(1,0,h)',linspace(1,0,h)']];
end

function levels = contour_levels_with_overflow(values, clim_val, n_levels)
%CONTOUR_LEVELS_WITH_OVERFLOW Keep values outside caxis visibly saturated.
levels = linspace(-double(clim_val), double(clim_val), n_levels);
finite = double(values(isfinite(values)));
if ~isempty(finite)
    vmin = min(finite);
    vmax = max(finite);
    if vmin < levels(1); levels = [vmin levels]; end
    if vmax > levels(end); levels = [levels vmax]; end
end
levels = unique(levels, 'sorted');
if numel(levels) < 2
    levels = [-double(clim_val) double(clim_val)];
end
end
