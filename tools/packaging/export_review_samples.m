function export_review_samples(repo_root, bundle_root)
% One-off review package export. Reads original outputs; writes bundle only.
addpath(fullfile(repo_root, 'lib'), '-begin');
addpath(fullfile(bundle_root, 'validation'), '-begin');
case_names = {'tandem_baseline_r2','tandem_f40a3_phi0_r2'};
short_names = {'baseline','controlled'};
source_frame_ordinals = [1:24 6001:6024].';
for k = 1:2
    source_output = fullfile(repo_root,'cases','per_case',case_names{k},'output');
    target = fullfile(bundle_root,'fixtures',short_names{k});
    if ~isfolder(target); mkdir(target); end
    configuration = load(fullfile(source_output,'mat','00_case_configuration.mat'),'cfg');
    cfg_original = configuration.cfg;
    save(fullfile(target,'configuration_original.mat'),'cfg_original','-v7');
    fid = fopen(fullfile(target,'configuration_original.json'),'w','n','UTF-8');
    fprintf(fid,'%s',jsonencode(cfg_original,'PrettyPrint',true)); fclose(fid);
    for role_cell = {'raw','postproc'}
        role = role_cell{1};
        name = '01_sequence_cache.mat';
        if strcmp(role,'postproc'); name = '01_sequence_cache_postproc.mat'; end
        source_file = fullfile(source_output,'mat',name);
        cache = matfile(source_file);
        X = cache.X; Y = cache.Y; h_mm = cache.h_mm;
        source_grid_size = cache.source_grid_size;
        j_wall_removed = cache.j_wall_removed;
        U = cat(1,cache.U(1:24,:,:),cache.U(6001:6024,:,:));
        V = cat(1,cache.V(1:24,:,:),cache.V(6001:6024,:,:));
        sampleValid = cat(1,cache.sampleValid(1:24,:,:),cache.sampleValid(6001:6024,:,:));
        cache_meta = cache.cache_meta;
        cache_meta.original_total_frames = cache_meta.total_frames;
        cache_meta.original_created_utc = cache_meta.created_utc;
        cache_meta.total_frames = 48; cache_meta.n_frames = 24;
        cache_meta.cached_size = size(U); cache_meta.repeat_boundaries = 24;
        cache_meta.repeat_offsets = [0 24];
        cache_meta.data_root = 'review_fixture'; cache_meta.source_root = 'review_fixture';
        cache_meta.repeat_roots = {'repeat_1_sample','repeat_2_sample'};
        cache_meta.created_utc = '2026-09-10T00:00:00Z';
        cache_meta.fixture_note = ['Real cached samples, full spatial grid, original ordinals ' ...
            '1:24 and 6001:6024. Renumbered 1:48. Repeat means below are recomputed ' ...
            'using the existing Section 1 plain mean convention, NOT inherited full-run means.'];
        cache_meta.repeat_means = zeros(2,2,size(X,1),size(X,2));
        for rep = 1:2
            ix = (rep-1)*24+(1:24);
            cache_meta.repeat_means(1,rep,:,:) = reshape(mean(double(U(ix,:,:)),1),1,1,size(X,1),size(X,2));
            cache_meta.repeat_means(2,rep,:,:) = reshape(mean(double(V(ix,:,:)),1),1,1,size(X,1),size(X,2));
        end
        frame_ids = (1:48).';
        save(fullfile(target,[role '.mat']),'U','V','sampleValid','X','Y','h_mm', ...
            'source_grid_size','j_wall_removed','cache_meta','frame_ids','source_frame_ordinals','-v7.3');
        fprintf('EXPORTED %s %s [%s]\n',short_names{k},role,num2str(size(U)));
        clear cache U V sampleValid;
    end
    % Small full-run references are observations, NOT recomputation fixtures.
    reference = struct();
    loaded = load(fullfile(source_output,'mat','02_statistics.mat'));
    reference.section2_statistics = loaded;
    loaded = load(fullfile(source_output,'mat','02_mean_boundary_layer_friction.mat'));
    reference.section2_bl_meta = loaded.meta;
    fields = {'boundary_layer','clauser','delta99_reference_mm','drag','drag_statistics', ...
        'loglaw','masks','modern_clauser','normalization','profile','wall_distance_mm','y_plus'};
    for n = 1:numel(fields)
        if isfield(loaded.data,fields{n}); reference.section2_bl.(fields{n})=loaded.data.(fields{n}); end
    end
    if k == 2
        loaded = load(fullfile(source_output,'mat','03_phase_triple_statistics.mat'));
        d = loaded.data; reference.section3_meta = loaded.meta;
        cols = d.X(1,:)>=80 & d.X(1,:)<=320;
        reference.section3_profile_columns = find(cols);
        fields = {'U_phase','V_phase','u_coherent','v_coherent','coherent_uv','random_uu_phase','random_vv_phase','random_uv_phase'};
        for n = 1:numel(fields)
            if isfield(d,fields{n})
                value = d.(fields{n});
                reference.section3_xmean.(fields{n}) = mean(value(:,:,cols),3,'omitnan');
            end
        end
        reference.section3_random_global = d.random_global;
        reference.section3_assignment = d.assignment;
    end
    clear loaded d;
    save(fullfile(target,'full_run_reference.mat'),'reference','-v7');
    clear reference;
end
environment = struct('matlab_version',version,'release',version('-release'), ...
    'installed_products',ver,'computer',computer,'spod_resolved',which('spod'));
fid=fopen(fullfile(bundle_root,'validation','environment.json'),'w','n','UTF-8');
fprintf(fid,'%s',jsonencode(environment,'PrettyPrint',true)); fclose(fid);
fprintf('Recording current-code small-sample observations.\n');
run_review_smoke(bundle_root,'record');
fprintf('REVIEW_SAMPLE_EXPORT_COMPLETE\n');
end
