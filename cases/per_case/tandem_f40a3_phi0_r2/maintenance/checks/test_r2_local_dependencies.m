function tests = test_r2_local_dependencies
%TEST_R2_LOCAL_DEPENDENCIES MATLAB: runtests('maintenance/checks/test_r2_local_dependencies.m')
% Metadata/path tests only. Does not run a case, DAT I/O, DMD, SPOD, or POD.
tests = functiontests(localfunctions);
end

function testCoreLocalAndCompetingCase(testCase)
case_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
old_path = path;
other_case = tempname;
mkdir(fullfile(other_case, 'lib', '+tblR2'));
cleanup = onCleanup(@() restore(old_path, other_case)); %#ok<NASGU>
addpath(fullfile(case_root, 'lib'), '-begin');
tblR2.require_case_library(case_root, {'tblR2.mean_stats_cache'});
fid = fopen(fullfile(other_case, 'lib', '+tblR2', 'mean_stats_cache.m'), 'w');
fprintf(fid, 'function out = mean_stats_cache(varargin)\nout = [];\nend\n');
fclose(fid);
addpath(fullfile(other_case, 'lib'), '-end');
verifyError(testCase, @() tblR2.require_case_library(case_root, ...
    {'tblR2.mean_stats_cache'}), 'tblR2:require_case_library:ForeignDependency');
rmpath(fullfile(other_case, 'lib'));
tblR2.require_case_library(case_root, {'tblR2.mean_stats_cache'});
end

function testOnlyRequestedLocalThirdParty(testCase)
case_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
old_path = path;
other_case = tempname;
mkdir(other_case);
cleanup = onCleanup(@() restore(old_path, other_case)); %#ok<NASGU>
addpath(fullfile(case_root, 'lib'), '-begin');
% Explicit owning script identity for this path-only test (never executed).
cfg = struct('script_file', fullfile(case_root, 'test_owner.m'), ...
    'stages', struct('dmd', 'skip', 'spod', 'skip'));
info = tblR2.ensure_external_toolboxes(cfg);
verifyEqual(testCase, info, struct('piDMD', '', 'spod', ''));
info = tblR2.ensure_external_toolboxes(cfg, {'dmd'});
verifyEqual(testCase, info.piDMD, fullfile(case_root, 'third_party', 'piDMD', 'piDMD.m'));
% An accidental global SPOD installation cannot satisfy missing local config.
fid = fopen(fullfile(other_case, 'spod.m'), 'w');
fprintf(fid, 'function out = spod(varargin)\nout = [];\nend\n');
fclose(fid);
addpath(other_case, '-end');
verifyError(testCase, @() tblR2.ensure_external_toolboxes(cfg, {'spod'}), ...
    'tblR2:ensure_external_toolboxes:MissingSPOD');
cfg.spod.toolbox_dir = other_case;
verifyError(testCase, @() tblR2.ensure_external_toolboxes(cfg, {'spod'}), ...
    'tblR2:ensure_external_toolboxes:ExternalSPOD');
end

function restore(old_path, folder)
path(old_path);
if isfolder(folder); rmdir(folder, 's'); end
end
