function report = run_review_smoke_for_case(case_root, fixture_root, report_file)
%RUN_REVIEW_SMOKE_FOR_CASE Check one delivered case library against ORIGINAL expected.
% Explicit paths: case_root owns lib; fixture_root is original fixtures/baseline
% or fixtures/controlled from the preserved ZIP; report_file is a NEW JSON file.
% This is a layout-only adaptation. No record mode and no writes to fixtures.
assert(nargin==3, 'Provide case_root, original fixture_root and a new report_file.');
assert(~isfile(report_file), 'Choose a new report_file; old reports are never overwritten.');
addpath(fullfile(case_root,'lib'),'-begin');
tblR2.require_case_library(case_root, {'tblR2.mean_stats_cache', ...
    'tblR2.phase_stats_cache','tblR2.transport_analysis','d23.joint_pod_array'});
original_config=load(fullfile(fixture_root,'configuration_original.mat'),'cfg_original');
case_kind=original_config.cfg_original.case_type;
assert(ismember(case_kind,{'baseline','controlled'}),'Unsupported fixture case.');
case_name=regexp(original_config.cfg_original.case_id,'[^/]+$','match','once');
assert(isfile(fullfile(case_root,[case_name '_case.m'])), ...
    'The requested fixture must belong to the selected case library.');
mode='check';
report=struct('purpose','Small sample API/numerical check only', ...
    'phase_override','6 bins; minimum 2 samples/bin. Production remains 24 bins / 20 samples.', ...
    'matlab_version',version,'cases',struct());
for case_cell={case_kind}
    name=case_cell{1}; folder=fixture_root;
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
    stored=load(expected_file,'observed');
    compare_values(observed,stored.observed,name);
    report.cases.(name).comparison='PASS: same shape/mask; finite values rtol=1e-9, atol=1e-10';
    clear observed stats;
end
report.completed=true;
fid=fopen(report_file,'w','n','UTF-8');
assert(fid>=0,'Cannot create the requested new report file.');
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
