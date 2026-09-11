% TEST_R2_SECTION5_TRANSPORT Independent synthetic Section 5 contracts.
repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repo_root, 'lib'), '-begin');
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
[X, Y] = meshgrid([0 3], [0 1 4 9]);
J = size(Y, 1); I = size(Y, 2); N = 32;
cfg = struct('case_id', 'test/section5', 'case_type', 'controlled', ...
    'fs', 16, 'chunk_frames', 3, 'min_valid_fraction', 0.01, ...
    'phase', struct('f0_hz', 4, 'n_bins', 4, ...
    'minimum_samples_per_bin', 2, 'phi0_user_deg', []), ...
    'friction', struct('rbf_epsilon_scale', 1.2, 'hole_thresholds', [0 1 100]), ...
    'transport', struct('source', 'raw', 'frame_mode', 'all', ...
    'edge_buffer_cells', [0 0], 'stress_fraction_floor', 1e-6));
signal = repmat([-3 -1 1 3]', 4, 1);
noise = repelem([-0.5 0.5 -0.5 0.5]', 4);
u = [10 + signal + noise; 30 - signal + noise];
v = [2 - 2*signal - noise; 8 + 2*signal - noise];
U = reshape(u, N, 1, 1) + reshape(2*Y, 1, J, I);
V = repmat(reshape(v, N, 1, 1), 1, J, I);
sampleValid = true(size(U));
raw = write_cache(root, 'controlled', U, V, sampleValid, X, Y, 'raw');
[stats, phase] = tblR2.transport_statistics(raw, cfg);
assert_close(stats.Uavex, 20 + 2*Y, 1e-12, 'repeat-offset mean');
assert_close(stats.uu_rey, 5.25*ones(J,I), 1e-12, 'total uu');
assert_close(stats.vv_rey, 20.25*ones(J,I), 1e-12, 'total vv');
assert_close(stats.uv_rey, 10.25*ones(J,I), 1e-12, 'total stress');
assert_close(phase.coherent_global.uv_rey, 10*ones(J,I), 1e-12, 'coherent stress');
assert_close(phase.random_global.uv_rey, 0.25*ones(J,I), 1e-12, 'random stress');
assert_close(phase.U_phase, repmat(reshape(stats.Uavex,1,J,I),4,1,1), ...
    1e-12, 'pooled coherent signal cancels');
assert_close(phase.V_phase, 5*ones(4,J,I), 1e-12, 'pooled V cancels');
assert_close(phase.count, 8*ones(4,J,I), 0, 'phase counts');
result = tblR2.transport_analysis(raw, cfg);
assert_close(result.total.dUdy.finite_difference, 2000*ones(J,I), 1e-8, 'mm to m');
assert_close(result.total.production_primary_fd, 20500*ones(J,I), 1e-7, 'production');
assert_close(result.total.negative_uv, result.coherent.negative_uv + ...
    result.random.negative_uv, 1e-12, 'stress decomposition');
assert_close(result.total.production_primary_fd, ...
    result.coherent.production_primary_fd + result.random.production_primary_fd, ...
    1e-7, 'production decomposition');
for name = {'total_phase', 'coherent_phase', 'random_phase'}
    branch = result.(name{1});
    assert_close(branch.production_primary_fd, 2000*branch.negative_uv, ...
        1e-7, 'all phase terms use time-mean gradient');
end
check_quadrant(result.total.quadrant, stats.valid_count, stats.uv_rey);
check_quadrant(result.random_phase.quadrant, phase.count, phase.random_uv_phase);
assert_close(result.random_phase.quadrant.cycle_average.mean_negative_uv, ...
    phase.random_global.uv_rey, 1e-12, 'random cycle sample pooling');

% Reject one repeat/bin with one actual sample; its other repeat remains valid.
Us = U; Vs = V; valid = sampleValid;
valid([5 9 13], 2, 1) = false;
Us([5 9 13], 2, 1) = NaN;
valid(2, 1, 1) = false; Us(2, 1, 1) = 0; Vs(2, 1, 1) = 0;
Us(3, 1, 1) = NaN; Vs(4, 1, 1) = Inf;
valid(:, J, I) = false; Us(:, J, I) = NaN;
sparse = write_cache(root, 'sparse', Us, Vs, valid, X, Y, 'raw');
[ss, sp] = tblR2.transport_statistics(sparse, cfg);
assert(ss.raw_count_rep(1,1,2,1) == 1);
assert(ss.accepted_count_rep(1,1,2,1) == 0);
assert(sp.count(1,2,1) == 4 && ss.valid_count(2,1) == 28);
assert(isnan(sp.U_phase_rep(1,1,2,1)) && isfinite(sp.coherent_uv(1,2,1)));
for point = [1 1; 2 1]'
    j = point(1); i = point(2);
    expected = direct_point(Us(:,j,i), Vs(:,j,i), valid(:,j,i), 1:N, 2);
    assert_close(ss.valid_count(j,i), expected.count, 0, 'paired admitted count');
    assert_close(ss.Uavex(j,i), expected.mean_u, 1e-12, 'paired mean');
    assert_close(ss.uv_rey(j,i), expected.total, 1e-12, 'paired total');
    assert_close(sp.coherent_global.uv_rey(j,i), expected.coherent, 1e-12, 'sparse coherent');
    assert_close(sp.random_global.uv_rey(j,i), expected.random, 1e-12, 'sparse random');
end
qt = tblR2.quadrant_streaming(sparse,cfg,ss,sp,'total',[0 100]);
qr = tblR2.quadrant_streaming(sparse,cfg,ss,sp,'random',[0 100]);
check_quadrant(qt,ss.valid_count,ss.uv_rey);
check_quadrant(qr,sp.count,sp.random_uv_phase);
assert(isnan(ss.uv_rey(J,I)) && isnan(qt.mean_negative_uv(J,I)));
assert(all(isnan(qt.probability(:,:,J,I)), 'all'));
assert(all(isnan(qr.mean_negative_uv(:,J,I)), 'all'));

% Frame selection must also control repeat centering and quadrant observations.
for mode = {'first_half','second_half','range'}
    selected = cfg;
    if strcmp(mode{1}, 'range')
        selected.transport.frame_mode = 'first_half';
        selected.transport.frame_range = [9 24]; ids = 9:24;
    else
        selected.transport.frame_mode = mode{1};
        if strcmp(mode{1}, 'first_half'); ids = 1:16; else; ids = 17:32; end
    end
    [s,p] = tblR2.transport_statistics(raw,selected);
    q = tblR2.quadrant_streaming(raw,selected,s,p,'total',0);
    rq = tblR2.quadrant_streaming(raw,selected,s,p,'random',0);
    assert(isequal(s.frame_ids,ids') && isequal(q.frame_ids,ids') && isequal(rq.frame_ids,ids'));
    expected = direct_point(U(:,1,1),V(:,1,1),sampleValid(:,1,1),ids,2);
    assert_close(s.Uavex(1,1),expected.mean_u,1e-12,'selected mean');
    assert_close(s.uv_rey(1,1),expected.total,1e-12,'selected stress');
    check_quadrant(q,s.valid_count,s.uv_rey);
    check_quadrant(rq,p.count,p.random_uv_phase);
end

post = write_cache(root,'postproc',3*U,3*V,sampleValid,X,Y,'postproc');
assert_error(@() tblR2.transport_statistics(post,cfg), 'tblR2:transport_statistics:SourceMismatch');
pcfg = cfg; pcfg.transport.source = 'postproc';
assert_error(@() tblR2.transport_analysis(raw,pcfg), 'tblR2:transport_statistics:SourceMismatch');
pr = tblR2.transport_analysis(post,pcfg);
assert(strcmp(pr.source_role,'postproc'));
assert_close(pr.statistics.Uavex,3*stats.Uavex,1e-12,'postproc mean');
assert_close(pr.statistics.Vavex,3*stats.Vavex,1e-12,'postproc V mean');
for field = {'uu_rey','vv_rey','uv_rey'}
    assert_close(pr.statistics.(field{1}),9*stats.(field{1}),1e-11,'postproc moment');
end
assert_close(pr.statistics.u_rms,3*stats.u_rms,1e-12,'postproc rms');
for name = {'total','coherent','random'}
    assert_close(pr.(name{1}).negative_uv,9*result.(name{1}).negative_uv,1e-11,'source stress');
    assert_close(pr.(name{1}).production_primary_fd, ...
        27*result.(name{1}).production_primary_fd,1e-6,'source production');
end
assert_close(pr.total.quadrant.mean_negative_uv_contribution, ...
    9*result.total.quadrant.mean_negative_uv_contribution,1e-11,'source quadrant');
assert_close(pr.total.quadrant.probability,result.total.quadrant.probability,0,'scale event invariance');

% A true single repeat has no boundary and must still support random centering.
single_file = write_cache(root,'single_repeat',U(1:16,:,:),V(1:16,:,:), ...
    sampleValid(1:16,:,:),X,Y,'raw');
single_cache = matfile(single_file,'Writable',true);
single_meta = single_cache.cache_meta;
single_meta.repeat_boundaries = [];
single_cache.cache_meta = single_meta;
clear single_cache;
single_result = tblR2.transport_analysis(single_file,cfg);
assert_close(single_result.statistics.valid_count,16*ones(J,I),0,'single repeat count');
assert_close(single_result.total.negative_uv,10.25*ones(J,I),1e-12,'single repeat stress');
assert_close(single_result.random.negative_uv,0.25*ones(J,I),1e-12,'single repeat random');
assert(single_result.diagnostics.stress_closure.max_abs < 1e-12);
assert(single_result.diagnostics.random_quadrant_closure.max_abs < 1e-12);

% Wrapper persists each source separately and refuses stale parameter contracts.
wrapper_cfg = cfg;
wrapper_cfg.data_root = root;
wrapper_cfg.n_frames = 16;
wrapper_cfg.total_frames = N;
wrapper_cfg.grid_size = [I J];
wrapper_cfg.frame_offset = 0;
wrapper_cfg.wall_side = 'bottom';
wrapper_cfg.formal_required_frames = 6000;
wrapper_cfg.allow_debug_snapshot = true; % Explicitly synthetic; formal threshold unchanged.
wrapper_cfg.sources = struct('raw', struct('roots', {{fullfile(root,'raw_3rd'), fullfile(root,'raw_2nd')}}, ...
    'offsets', [0 0], 'ids', {{'3rd','2nd'}}), ...
    'postproc', struct('roots', {{fullfile(root,'post_3rd'), fullfile(root,'post_2nd')}}, ...
    'offsets', [0 0], 'ids', {{'3rd','2nd'}}));
% The numerical-core fixtures above intentionally use nonuniform Y and minimal
% metadata. The public section entry now requires the actual Section 1 cache
% contract. Use separate complete fixtures; keep core data and assertions intact.
wrapper_raw = write_entry_cache(root,'wrapper_raw',U,V,sampleValid,X,wrapper_cfg,'raw');
wrapper_post = write_entry_cache(root,'wrapper_post',3*U,3*V,sampleValid,X,wrapper_cfg,'postproc');
wrapper_cfg.transport.profile_x_range_mm = [0 3];
paths = tblR2.build_paths(fullfile(root,'wrapper'));
paths.sequence_cache = wrapper_raw;
paths.sequence_cache_postproc = wrapper_post;
[computed,output] = tblR2.section5_run(wrapper_cfg,paths,'compute',false);
[reused,reuse_output] = tblR2.section5_run(wrapper_cfg,paths,'reuse',false);
assert(isequaln(computed,reused),'reuse must return the persisted result unchanged');
assert(isempty(output.files) && isempty(output.figures) && isempty(reuse_output.files));
assert(strcmp(output.role,'raw'));
assert(strcmp(computed.output_dir,fullfile(paths.root,'section5','raw')));
stale_cfg = wrapper_cfg;
stale_cfg.friction.hole_thresholds = [0 2 100];
assert_error(@() tblR2.section5_run(stale_cfg,paths,'reuse',false), ...
    'tblR2:section5:StaleResult');
stale_cfg = wrapper_cfg;
stale_cfg.transport.frame_range = [1 16];
assert_error(@() tblR2.section5_run(stale_cfg,paths,'reuse',false), ...
    'tblR2:section5:StaleResult');
post_wrapper_cfg = wrapper_cfg;
post_wrapper_cfg.transport.source = 'postproc';
[post_computed,post_output] = tblR2.section5_run(post_wrapper_cfg,paths,'compute',false);
post_reused = tblR2.section5_run(post_wrapper_cfg,paths,'reuse',false);
assert(isequaln(post_computed,post_reused),'postproc reuse');
assert(strcmp(post_output.role,'postproc'));
assert(strcmp(post_computed.output_dir,fullfile(paths.root,'section5','postproc')));
assert(~strcmp(computed.output_dir,post_computed.output_dir));
assert_close(post_computed.total.negative_uv,9*computed.total.negative_uv,1e-11,'wrapper source selection');
raw_reused = tblR2.section5_run(wrapper_cfg,paths,'reuse',false);
assert(isequaln(raw_reused,computed),'postproc compute must preserve the raw result');

% Mixed quadrants test the sign of normalization for either sign of stress.
bcfg = cfg; bcfg.case_type = 'baseline';
bu = repmat([-2 -1 1 2]',8,1); bv = repmat([-1 3 -3 1]',8,1);
for sign_v = [-1 1]
    Ub = reshape(bu,N,1,1) + reshape(2*Y,1,J,I);
    Vb = repmat(reshape(sign_v*bv,N,1,1),1,J,I);
    file = write_cache(root,sprintf('baseline_%d',sign_v),Ub,Vb,sampleValid,X,Y,'raw');
    s = tblR2.transport_statistics(file,bcfg);
    q = tblR2.quadrant_streaming(file,bcfg,s,[],'total',[0 100]);
    assert_close(s.uv_rey,sign_v*0.5*ones(J,I),1e-12,'signed baseline stress');
    check_quadrant(q,s.valid_count,s.uv_rey);
    fractions = q.contribution_fraction_of_total_stress(1,:,:,:);
    assert(any(fractions(:)<0) && any(fractions(:)>1));
    assert_close(reshape(sum(fractions,2),J,I),ones(J,I),1e-12,'signed fractions sum');
    assert(all(q.probability(2,:,:,:) == 0,'all'));
    assert(all(isnan(q.mean_event_negative_uv(2,:,:,:)),'all'));
end
% At H=1 all products exactly equal rms(u)*rms(v), so no events qualify.
equal_u = repmat([-1 1]',16,1);
Ue = reshape(equal_u,N,1,1) + reshape(2*Y,1,J,I);
Ve = repmat(reshape(-equal_u,N,1,1),1,J,I);
file = write_cache(root,'threshold',Ue,Ve,sampleValid,X,Y,'raw');
s = tblR2.transport_statistics(file,bcfg);
q = tblR2.quadrant_streaming(file,bcfg,s,[],'total',[0 1]);
assert(all(q.event_count(2,:,:,:) == 0,'all'));
assert(all(q.mean_negative_uv_contribution(2,:,:,:) == 0,'all'));
assert(all(isnan(q.mean_event_negative_uv(2,:,:,:)),'all'));
assert_close(reshape(sum(q.probability(1,:,:,:),2),J,I),ones(J,I),0,'H0 event probability');

for reverse_y = [false true]
    for columns = [1 2]
        x = [0 3]; y = [0 1 4 9]';
        if reverse_y; y = flipud(y); x = fliplr(x); end
        [gx,gy] = meshgrid(x(1:columns),y);
        g = tblR2.gradient_y_sensitivity(7 + 2*gy + 0.5*gx,gx,gy,1.2);
        assert_close(g.finite_difference,2000*ones(size(gy)),1e-8,'nonuniform FD including singleton');
        assert_close(g.rbf_fd,2000*ones(size(gy)),1e-7,'nonuniform RBF including singleton');
    end
end
% A supported single-column cache must also render with optional figure defaults.
render_cfg = bcfg;
render_cfg.transport.profile_x_range_mm = [-1 1];
render_file = write_cache(root,'render_column',U(:,:,1),V(:,:,1), ...
    sampleValid(:,:,1),X(:,1),Y(:,1),'raw');
render_result = tblR2.transport_analysis(render_file,render_cfg);
render_paths = tblR2.build_paths(fullfile(root,'render_output'));
render_output = tblR2.transport_figures(render_result,render_cfg,render_paths,'export');
assert(all(cellfun(@isfile,render_output.files)));
assert(numel(dir(fullfile(render_paths.png,'*.png'))) == 6);
assert(numel(dir(fullfile(render_paths.fig,'*.fig'))) == 6);
fprintf('test_r2_section5_transport: PASS\n');

function file = write_cache(root,name,U,V,sampleValid,X,Y,source)
h_mm = 1;
% Deliberately inconsistent cache means must never enter Section 5 centering.
cache_meta = struct('repeat_boundaries',16,'source_role',source, ...
    'case_id','test/section5','repeat_means',nan(2,2,size(X,1),size(X,2)));
file = fullfile(root,[name '.mat']);
save(file,'U','V','sampleValid','X','Y','h_mm','cache_meta','-v7.3');
end

function file = write_entry_cache(root,name,U,V,sampleValid,X,cfg,source)
% Complete schema-4 entry fixture, without changing minimal numerical fixtures.
U = single(U); V = single(V);
J = size(X,1); I = size(X,2); N = size(U,1);
Y = repmat((1:J)',1,I);
h_mm = mean(diff(X(1,:)));
frame_ids = (1:N)'; source_grid_size = cfg.grid_size; j_wall_removed = 0;
spec = cfg.sources.(source);
cache_meta = struct('schema_version',4,'case_id',cfg.case_id, ...
    'data_root',spec.roots{1},'source_root',spec.roots{1},'source_role',source, ...
    'repeat_roots',{spec.roots},'repeat_ids',{spec.ids},'repeat_offsets',spec.offsets, ...
    'repeat_boundaries',cfg.n_frames,'repeat_means',nan(2,2,J,I), ...
    'grid_size',cfg.grid_size,'cached_size',[N J I],'n_frames',cfg.n_frames, ...
    'total_frames',N,'frame_offset',0,'source_first_file','B0001.dat', ...
    'source_last_file',sprintf('B%04d.dat',cfg.n_frames),'fs',cfg.fs, ...
    'precision','single','wall_side',cfg.wall_side, ...
    'y_mapping',struct('version',1,'method','first_retained_row_0_plus_h','h_y_mm',1));
file = fullfile(root,[name '.mat']);
save(file,'U','V','sampleValid','X','Y','h_mm','frame_ids','source_grid_size', ...
    'j_wall_removed','cache_meta','-v7.3');
end

function e = direct_point(u,v,valid,ids,minimum)
e = struct('count',0,'mean_u',0,'total',0,'coherent',0,'random',0);
for r = 1:2
    groups = cell(1,4); admitted = [];
    for b = 1:4
        chosen = ids(ids > (r-1)*16 & ids <= r*16 & mod(ids-1,4)+1 == b);
        chosen = chosen(valid(chosen) & isfinite(u(chosen)) & isfinite(v(chosen)));
        if numel(chosen) < minimum; chosen = []; end
        groups{b} = chosen; admitted = [admitted chosen]; %#ok<AGROW>
    end
    if isempty(admitted); continue; end
    mu = mean(u(admitted)); mv = mean(v(admitted));
    e.count = e.count + numel(admitted); e.mean_u = e.mean_u + sum(u(admitted));
    e.total = e.total - sum((u(admitted)-mu).*(v(admitted)-mv));
    for b = 1:4
        chosen = groups{b}; if isempty(chosen); continue; end
        pu = mean(u(chosen)); pv = mean(v(chosen));
        e.coherent = e.coherent - numel(chosen)*(pu-mu)*(pv-mv);
        e.random = e.random - sum((u(chosen)-pu).*(v(chosen)-pv));
    end
end
for name = {'mean_u','total','coherent','random'}
    e.(name{1}) = e.(name{1})/e.count;
end
end

function check_quadrant(q,count,stress)
assert_close(q.valid_count,count,0,'quadrant observed counts');
assert_close(q.mean_negative_uv,stress,1e-11,'quadrant reference stress');
values = q.mean_negative_uv_contribution;
index = repmat({':'},1,ndims(values)); index{1} = 1;
assert_close(reshape(sum(values(index{:}),2),size(stress)),stress,1e-11,'H0 quadrant closure');
assert(q.reference_stress_missing_mismatch_count == 0);
end

function assert_close(actual,expected,tolerance,label)
assert(isequal(size(actual),size(expected)),[label ': shape']);
assert(isequal(isnan(actual),isnan(expected)),[label ': missing support']);
keep = ~isnan(expected);
assert(all(isfinite(actual(keep))),[label ': finite observations']);
assert(all(abs(actual(keep)-expected(keep)) <= tolerance),label);
end

function assert_error(action,identifier)
try
    action();
catch exception
    assert(strcmp(exception.identifier,identifier),exception.message);
    return;
end
error('test:ExpectedError','Expected %s.',identifier);
end
