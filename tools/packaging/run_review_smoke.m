function report = run_review_smoke(bundle_root, mode)
% Small real-cache check, not a replacement for full-data acceptance.
% From an extracted bundle: addpath('validation'); run_review_smoke;
% 'record' is used once by the exporter; reviewers should use default 'check'.
if nargin<1 || isempty(bundle_root); bundle_root=fileparts(fileparts(mfilename('fullpath'))); end
if nargin<2; mode='check'; end
assert(ismember(mode,{'check','record'}),'Mode must be check or record.');
addpath(fullfile(bundle_root,'project','lib'),'-begin');
report=struct('purpose','Small sample API/numerical check only', ...
    'phase_override','6 bins; minimum 2 samples/bin. Production remains 24 bins / 20 samples.', ...
    'matlab_version',version,'cases',struct());
for case_cell={'baseline','controlled'}
    name=case_cell{1}; folder=fullfile(bundle_root,'fixtures',name);
    config=load(fullfile(folder,'configuration_original.mat'),'cfg_original');
    cfg=config.cfg_original;
    cfg.total_frames=48; cfg.n_frames=24; cfg.chunk_frames=24;
    cfg.allow_debug_snapshot=true; cfg.formal_required_frames=24;
    cfg.phase.n_bins=6; cfg.phase.minimum_samples_per_bin=2;
    cfg.transport=struct('source','raw','frame_mode','all','edge_buffer_cells',[2 16]);
    expected_file=fullfile(folder,'smoke_expected.mat');
    observed=struct();
    stats=tblR2.mean_stats_cache(fullfile(folder,'raw.mat'),cfg.min_valid_fraction,cfg.chunk_frames,cfg.Uinf);
    fields={'Uavex','Vavex','uu_rey','vv_rey','uv_rey','u_rms','v_rms','valid_count','accepted_mask'};
    for i=1:numel(fields); observed.section2.(fields{i})=stats.(fields{i}); end
    if strcmp(name,'controlled')
        phase=tblR2.phase_stats_cache(fullfile(folder,'raw.mat'),cfg,stats);
        observed.section3=struct('U_phase',phase.U_phase,'V_phase',phase.V_phase, ...
            'coherent_uv',phase.coherent_uv,'random_global_uv',phase.random_global.uv_rey);
        clear phase;
    end
    for role_cell={'raw','postproc'}
        role=role_cell{1}; cfg.transport.source=role;
        transport=tblR2.transport_analysis(fullfile(folder,[role '.mat']),cfg);
        observed.section5.(role)=struct('stress',transport.total.uv_rey, ...
            'production',transport.total.production_primary_fd, ...
            'quadrant_contribution',transport.total.quadrant.mean_negative_uv_contribution, ...
            'quadrant_probability',transport.total.quadrant.probability);
        if strcmp(name,'controlled')
            observed.section5.(role).coherent=transport.coherent.negative_uv;
            observed.section5.(role).random=transport.random.negative_uv;
        end
        report.cases.(name).(role)=transport.diagnostics;
        clear transport;
    end
    % Section 4 numerical kernels. This is NOT the full section4_vlsm run.
    post=load(fullfile(folder,'postproc.mat'),'U','V','sampleValid','X','Y','h_mm');
    defaults=d23.default_config();
    pod_cfg=defaults.preprocessing.pod;
    pod_cfg.rank=struct('kind','energy_fraction','value',0.5);
    pod_cfg.min_valid_fraction=cfg.min_valid_fraction;
    pod=d23.joint_pod_array(post.U,post.V,post.sampleValid,pod_cfg);
    observed.section4_pod=struct('eigenvalues',pod.eigenvalues, ...
        'selected_rank',pod.selected_rank, ...
        'reconstruction_first',squeeze(pod.U_reconstructed(1,:,:)), ...
        'spatial_mask',pod.retained_spatial_mask);
    clear pod post;
    if strcmp(mode,'record')
        save(expected_file,'observed','-v7');
        report.cases.(name).comparison='Recorded BEFORE refactoring';
    else
        stored=load(expected_file,'observed');
        compare_values(observed,stored.observed,name);
        report.cases.(name).comparison='PASS: same shape/mask; finite values rtol=1e-9, atol=1e-10';
    end
    clear observed stats;
end
if strcmp(mode,'record'); suffix='record'; else; suffix='check'; end
report.completed=true;
fid=fopen(fullfile(bundle_root,'validation',['sample_' suffix '_report.json']),'w','n','UTF-8');
fprintf(fid,'%s',jsonencode(report,'PrettyPrint',true)); fclose(fid);
fprintf('SMALL_SAMPLE_%s_PASS\n',upper(mode));
end

function compare_values(a,b,label)
if isstruct(a)
    names=fieldnames(b); assert(isequal(sort(fieldnames(a)),sort(names)),['Fields: ' label]);
    for i=1:numel(names); compare_values(a.(names{i}),b.(names{i}),[label '.' names{i}]); end
else
    assert(isequal(size(a),size(b)),['Shape: ' label]);
    assert(isequal(isnan(a),isnan(b)) && isequal(isinf(a),isinf(b)),['Validity: ' label]);
    valid=isfinite(a)&isfinite(b);
    assert(all(abs(double(a(valid))-double(b(valid)))<=1e-10+1e-9*abs(double(b(valid)))),['Values: ' label]);
end
end
