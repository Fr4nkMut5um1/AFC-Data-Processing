function paths = build_paths(output_dir)
%BUILD_PATHS 为单个 r2 工况建立最小产物路径集合。
if ~(ischar(output_dir) || (isstring(output_dir) && isscalar(output_dir))) || ...
        isempty(strtrim(char(output_dir)))
    error('tblR2:build_paths:InvalidOutputDir', ...
        'output_dir 必须是非空文本路径。');
end
paths.root = char(output_dir);
for name = {'mat','csv','json','md','png','fig','eps','emf','pdf','gif','tif'}
    paths.(name{1}) = fullfile(paths.root, name{1});
    if ~isfolder(paths.(name{1})); mkdir(paths.(name{1})); end
end
paths.case_configuration = fullfile(paths.mat, '00_case_configuration.mat');
paths.case_card = fullfile(paths.md, '00_case_card.md');
paths.sequence_cache = fullfile(paths.mat, '01_sequence_cache.mat');
paths.sequence_cache_postproc = fullfile(paths.mat, '01_sequence_cache_postproc.mat');
paths.source_manifest = fullfile(paths.csv, '01_source_manifest.csv');
paths.source_manifest_postproc = fullfile(paths.csv, '01_source_manifest_postproc.csv');
paths.statistics = fullfile(paths.mat, '02_statistics.mat');
paths.mean_bl = fullfile(paths.mat, '02_mean_boundary_layer_friction.mat');
paths.phase = fullfile(paths.mat, '03_phase_triple_statistics.mat');
paths.structures = fullfile(paths.mat, '09_structure_analysis.mat');
paths.transport = fullfile(paths.mat, '04_transport_quadrant.mat');
paths.temporal = fullfile(paths.mat, '05_temporal_spectra.mat');
paths.spatial = fullfile(paths.mat, '05_spatial_spectra.mat');
paths.pod = fullfile(paths.mat, '06_pod_analysis.mat');
paths.dmd = fullfile(paths.mat, '07_dmd_analysis.mat');
paths.spod = fullfile(paths.mat, '08_spod_analysis.mat');
paths.lcs = fullfile(paths.mat, '08_lcs_ftle_analysis.mat');
paths.correlations = fullfile(paths.mat, '13_correlation_analysis.mat');
paths.harmonics = fullfile(paths.mat, '13_streamwise_harmonic_development.mat');
paths.figure_manifest = fullfile(paths.mat, '12_figure_export_manifest.mat');
paths.summary_json = fullfile(paths.json, '12_case_summary.json');
paths.summary_md = fullfile(paths.md, '12_case_summary.md');
end
