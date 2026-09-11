function tests = test_r2_section4_vlsm_figures
%TEST_R2_SECTION4_VLSM_FIGURES Synthetic individual-export contracts.
tests = functiontests(localfunctions);
end

function setupOnce(test_case)
repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repo_root, 'lib'), '-begin');
test_case.TestData.repo_root = repo_root;
end

function testSelectedConnectivityAndHighestTierOnly(test_case)
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>

ny = 8; nx = 20; nt = 3;
U = zeros(nt, ny, nx);
U(1, 1:5, 2:9) = 1;
U(2, 1:5, 4:13) = -1;
U(3, 1:5, 6:17) = 1;
V = zeros(size(U));
sampleValid = true(size(U));
cache_file = fullfile(root, 'cache.mat');
save(cache_file, 'U', 'V', 'sampleValid', '-v7.3');

ctx = struct('cache_file', cache_file, 'cache_size', [nt ny nx], ...
    'x_mm', 0.5 + (0:nx-1), 'wall_y_mm', (0.5:1:(ny-0.5)).', ...
    'wall_distance_mm', repmat((0.5:1:(ny-0.5)).', 1, nx), ...
    'spatial_exclusion_mask', false(ny,nx), ...
    'spatial_exclusion', struct('enabled', false));
stats = struct('Ubar', zeros(ny,nx), 'Vbar', zeros(ny,nx));
detection_stats = struct('u_rms_y', ones(ny,1));

dcfg = d23.default_config(test_case.TestData.repo_root);
dcfg.experiment_id = 'synthetic_section4_figure_test';
dcfg.data.expected_cache_size = [nt ny nx];
dcfg.preprocessing.pod.enabled = false;
dcfg.preprocessing.gaussian.enabled = false;
dcfg.output.figure_dpi = 30;
dcfg.Uinf = 1;
dcfg.plot_normalization = 'u_over_Uinf';
dcfg.section4_figure_connectivity = 4;
dcfg.section4_max_figure_objects = Inf;

catalog8 = synthetic_catalog(8);
catalog4 = synthetic_catalog(4);

% Managed stale outputs must not survive a connectivity-specific export.
png_root = fullfile(root, 'figures', 'png');
fig_root = fullfile(root, 'figures', 'fig');
sheet_root = fullfile(root, 'figures', 'contact_sheets');
mkdir(png_root); mkdir(fig_root); mkdir(sheet_root);
touch(fullfile(png_root, 'frame_stale_conn_8.png'));
touch(fullfile(fig_root, 'frame_stale_conn_8.fig'));
touch(fullfile(sheet_root, 'contact_sheet_timebin_1.png'));

[manifest, files, contact_files] = tblR2.section4_vlsm_figures( ...
    catalog8, catalog4, ctx, stats, detection_stats, dcfg, '', root, table());

verifyEqual(test_case, height(manifest), 3);
verifyTrue(test_case, all(manifest.Generated));
verifyEqual(test_case, manifest.Connectivity, uint8([4;4;4]));
verifyEqual(test_case, manifest.LengthTier, uint8([1;2;3]));
verifyEqual(test_case, manifest.FrameOrdinal, uint32([1;2;3]));
verifyEqual(test_case, manifest.StructureID, uint32([11;12;13]));
verifyEqual(test_case, numel(files), 3);
verifyTrue(test_case, all(isfile(manifest.PNG)));
verifyTrue(test_case, all(isfile(manifest.FIG)));
verifyEmpty(test_case, dir(fullfile(png_root, '*conn_8*.png')));
verifyEmpty(test_case, dir(fullfile(fig_root, '*conn_8*.fig')));
verifyEqual(test_case, numel(dir(fullfile(png_root, 'frame_*.png'))), 3);
verifyEqual(test_case, numel(dir(fullfile(fig_root, 'frame_*.fig'))), 3);
verifyGreaterThan(test_case, numel(contact_files), 0);

% Cumulative catalog flags remain unchanged even though the >4.5 object is
% represented by only its highest, exclusive image tier.
verifyTrue(test_case, catalog4.PassLength3(3));
verifyTrue(test_case, catalog4.PassLength3p8(3));
verifyTrue(test_case, catalog4.PassLength4p5(3));
verifyEqual(test_case, nnz(manifest.FrameID == uint32(103)), 1);
verifyEqual(test_case, manifest.LengthTier(manifest.FrameID == uint32(103)), ...
    uint8(3));
end

function testCaseScriptsExposeFigureConnectivity(test_case)
files = {
    fullfile(test_case.TestData.repo_root, 'cases', 'per_case', ...
        'tandem_baseline_r2', 'tandem_baseline_r2_case.m')
    fullfile(test_case.TestData.repo_root, 'cases', 'per_case', ...
        'tandem_f40a3_phi0_r2', 'tandem_f40a3_phi0_r2_case.m')};
for i = 1:numel(files)
    source = fileread(files{i});
    verifyTrue(test_case, contains(source, ...
        'cfg.structures.section4.figure_connectivity = 8;'));
    verifyTrue(test_case, contains(source, ...
        'cfg.structures.section4.max_figure_objects = Inf;'));
end
end

function testGallerySelectionUsesRequestedConnectivity(test_case)
catalog8 = synthetic_catalog(8);
catalog4 = synthetic_catalog(4);
catalog8.IsSS3 = catalog8.IsVLSM;
catalog4.IsSS3 = catalog4.IsVLSM;
catalog8.Lx_over_delta = catalog8.LengthX_over_delta;
catalog4.Lx_over_delta = catalog4.LengthX_over_delta;
catalog8.ComponentID = catalog8.StructureID;
catalog4.ComponentID = catalog4.StructureID + uint32(100);
selection = d23.select_gallery([catalog8;catalog4], 3, 4);
selected = selection(selection.Selected,:);
verifyEqual(test_case, height(selected), 3);
verifyTrue(test_case, all(selected.ComponentID > uint32(100)));
verifyError(test_case, @() d23.select_gallery([catalog8;catalog4],3,6), ...
    'd23:select_gallery:Connectivity');
end

function T = synthetic_catalog(connectivity)
n = 3;
T = table(uint32((1:n).'), uint32((101:103).'), int8([1;-1;1]), ...
    repmat(uint8(connectivity),n,1), uint32((11:13).'), ...
    true(n,1), false(n,1), true(n,1), true(n,1), ...
    true(n,1), logical([false;true;true]), logical([false;false;true]), ...
    [3.4;4.0;4.8], [16;20;24], [1;3;5], [8;12;16], ...
    [0.5;0.5;0.5], [4.5;4.5;4.5], ...
    'VariableNames', {'FrameOrdinal','FrameID','Sign','Connectivity', ...
    'StructureID','IsVLSM','IsCensored','PassWallLower','PassWallUpper', ...
    'PassLength3','PassLength3p8','PassLength4p5', ...
    'LengthX_over_delta','PixelCount','XMin_mm','XMax_mm', ...
    'YMin_mm','YMax_mm'});
end

function touch(filename)
fid = fopen(filename, 'w');
assert(fid >= 0);
fclose(fid);
end
