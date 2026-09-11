function tests = test_r2_bootstrap_paths
%TEST_R2_BOOTSTRAP_PATHS Resolve both entries without reading experimental data.
tests = functiontests(localfunctions);
end

function testBothCasesFromRepositoryAndCaseDirectories(test_case)
repo_root = fileparts(fileparts(mfilename('fullpath')));
original_path = path;
original_cwd = pwd;
cleanup = onCleanup(@() restore_environment(original_path, original_cwd)); %#ok<NASGU>
addpath(fullfile(repo_root, 'cases', 'per_case'));
library_root = fullfile(repo_root, 'lib');
case_names = {'tandem_baseline_r2', 'tandem_f40a3_phi0_r2'};
for i = 1:numel(case_names)
    case_name = case_names{i};
    expected_case = fullfile(repo_root, 'cases', 'per_case', case_name);
    entry = fullfile(expected_case, [case_name '_case.m']);
    before = entry_identity(entry, repo_root);
    for working_dir = {repo_root, expected_case}
        cd(working_dir{1});
        [actual_file, actual_case, actual_repo, actual_library] = ...
            bootstrap_r2_case(entry);
        verifyEqual(test_case, actual_file, entry);
        verifyEqual(test_case, actual_case, expected_case);
        verifyEqual(test_case, actual_repo, repo_root);
        verifyEqual(test_case, actual_library, library_root);
        verifyEqual(test_case, pwd, working_dir{1});
        verifyEqual(test_case, which('tblR2.validate_config'), ...
            fullfile(library_root, '+tblR2', 'validate_config.m'));
        verifyEqual(test_case, which('d23.default_config'), ...
            fullfile(library_root, '+d23', 'default_config.m'));
        after = entry_identity(actual_file, actual_repo);
        verifyEqual(test_case, after, before);
        verifyEqual(test_case, after.case_id, ['per_case/' case_name]);
        verifyEqual(test_case, after.output_dir, fullfile(expected_case, 'output'));
        verifyEqual(test_case, after.script_file, entry);
        verifyEqual(test_case, after.n_frames, 6000);
        verifyEqual(test_case, after.total_frames, 12000);
        verifyEqual(test_case, d23.default_config(), d23.default_config(repo_root));
        [~, explicit_case, ~, explicit_library] = ...
            bootstrap_r2_case(entry, library_root);
        verifyEqual(test_case, explicit_case, expected_case);
        verifyEqual(test_case, explicit_library, library_root);
    end
end
end

function cfg = entry_identity(script_file, repo_root)
% Evaluate only identity/path assignments, never the case's stages or I/O.
source = fileread(script_file);
assert(contains(source, 'bootstrap_r2_case(script_file)'));
cfg = struct();
fields = {'case_id', 'script_file', 'output_dir', 'n_frames', 'total_frames'};
for i = 1:numel(fields)
    assignment = regexp(source, ...
        ['(?m)^cfg\.' fields{i} '\s*=\s*[^;]+;'], 'match', 'once');
    assert(~isempty(assignment), 'Missing identity field: %s', fields{i});
    eval(assignment);
end
end

function restore_environment(original_path, original_cwd)
cd(original_cwd);
path(original_path);
end
