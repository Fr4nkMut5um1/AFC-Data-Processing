function tests = test_r2_section4_local_inputs
%TEST_R2_SECTION4_LOCAL_INPUTS Explicit S4 inputs and unchanged formal gate.
% MATLAB: results = runtests('tests/test_r2_section4_local_inputs.m');
% No 12000-frame computation, DAT scan, POD or figure export is performed.
tests = functiontests(localfunctions);
end

function setupOnce(test_case)
project_root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(project_root, 'lib'), '-begin');
test_case.TestData.root = tempname;
mkdir(test_case.TestData.root);
U = zeros(48, 89, 640, 'single');
cache_file = fullfile(test_case.TestData.root, 'short_postproc.mat');
save(cache_file, 'U', '-v7.3');
test_case.TestData.cache_file = cache_file;
end

function teardownOnce(test_case)
rmdir(test_case.TestData.root, 's');
end

function testRequiresExplicitMeanBLInput(test_case)
verifyError(test_case, @() tblR2.section4_vlsm_analysis('unused.mat', struct()), ...
    'tblR2:section4_vlsm_analysis:MissingMeanBLInput');
end

function testMissingCacheReportsTheNeededInput(test_case)
cfg = struct('structures', struct(), 'output_dir', test_case.TestData.root);
verifyError(test_case, @() tblR2.section4_vlsm_analysis( ...
    fullfile(test_case.TestData.root, 'missing_postproc.mat'), cfg, ...
    fullfile(test_case.TestData.root, 'mean_bl.mat')), ...
    'tblR2:section4_vlsm_analysis:MissingCache');
end

function testShortFixtureStillFailsTheFormalSizeGate(test_case)
cfg = struct('structures', struct(), 'output_dir', test_case.TestData.root, ...
    'total_frames', 48);
% Even cfg.total_frames=48 cannot weaken the actual 12000x89x640 gate.
% This also confirms the formal gate precedes the new local-path audit.
verifyError(test_case, @() tblR2.section4_vlsm_analysis( ...
    test_case.TestData.cache_file, cfg, ...
    fullfile(test_case.TestData.root, 'mean_bl.mat')), ...
    'tblR2:section4_vlsm_analysis:CacheShape');
end
