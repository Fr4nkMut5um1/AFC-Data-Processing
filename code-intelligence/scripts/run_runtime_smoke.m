function output_dir = run_runtime_smoke(repo_root, output_dir)
%RUN_RUNTIME_SMOKE Run synthetic, bounded runtime checks in MATLAB R2022b.
% This is RUNTIME_SMOKE evidence only. It is not a representative PIV run:
% the repository contains no experimental DAT/MAT input for either case.
if nargin < 1 || isempty(repo_root), repo_root = pwd; end
if nargin < 2 || isempty(output_dir), output_dir = fullfile(repo_root, 'cloud-runtime-smoke-evidence'); end
repo_root = canonical_path(repo_root);
output_dir = canonical_path(output_dir);
if ~isfolder(repo_root), error('PIVCI:MissingRepo', 'Repository root does not exist: %s', repo_root); end
if ~isfolder(output_dir), mkdir(output_dir); end

% Keep test selection explicit and reviewable. Each test creates its own
% temporary synthetic data and does not touch a case input or output folder.
test_files = { ...
    fullfile(repo_root, 'tests', 'test_r2_cache_statistics_smoke.m'), ...
    fullfile(repo_root, 'tests', 'test_r2_phase_smoke.m'), ...
    fullfile(repo_root, 'tests', 'test_r2_compact_analysis_smoke.m')};
test_names = {'test_r2_cache_statistics_smoke', ...
    'test_r2_phase_smoke', 'test_r2_compact_analysis_smoke'};
for k = 1:numel(test_files)
    if ~isfile(test_files{k})
        error('PIVCI:MissingRuntimeSmokeTest', 'Missing test: %s', test_files{k});
    end
end

meta = struct();
meta.schema_version = 'p2-runtime-smoke-1';
meta.status = 'RUNNING';
meta.evidence_class = 'RUNTIME_SMOKE';
meta.scientific_code_executed = true;
meta.representative_piv_runtime = false;
meta.representative_data_present = false;
meta.note = ['Synthetic bounded tests exercise selected cache/statistics, phase, ', ...
    'structure, temporal and correlation paths. They do not run either case ', ...
    'entrypoint and do not establish experimental-data acceptance.'];
meta.repository_root = repo_root;
meta.repository_commit = getenv('GITHUB_SHA');
meta.github_run_id = getenv('GITHUB_RUN_ID');
meta.github_workflow = getenv('GITHUB_WORKFLOW');
meta.matlab_version = version;
meta.matlab_release = version('-release');
meta.computer = computer;
meta.architecture = computer('arch');
meta.started_utc = utc_now();
meta.test_count = numel(test_files);
meta.tests = test_names;
write_json(fullfile(output_dir, 'execution_summary.json'), meta);

results = repmat(empty_result(), 1, numel(test_files));
all_pass = true;
for k = 1:numel(test_files)
    result = empty_result();
    result.test_name = test_names{k};
    result.test_file = portable(test_files{k}, repo_root);
    result.started_utc = utc_now();
    profile clear;
    profile('-history');
    profile on;
    started = tic;
    try
        run(test_files{k});
        result.status = 'PASS';
    catch ME
        result.status = 'FAIL';
        result.error_identifier = ME.identifier;
        result.error_message = ME.message;
        result.error_report = getReport(ME, 'extended', 'hyperlinks', 'off');
        all_pass = false;
    end
    result.elapsed_seconds = toc(started);
    profile off;
    try
        profile_info = profile('info');
        result.profile_function_count = profile_function_count(profile_info);
        result.profile_functions = summarize_profile(profile_info, repo_root);
        save(fullfile(output_dir, [test_names{k} '_profile.mat']), 'profile_info', '-v7');
    catch ME
        result.profile_error = ME.message;
    end
    try
        [loaded, loaded_mex] = inmem('-completenames');
        result.loaded_repo_files = repo_files(loaded, repo_root);
        result.loaded_mex_files = repo_files(loaded_mex, repo_root);
    catch ME
        result.loaded_files_error = ME.message;
    end
    result.finished_utc = utc_now();
    results(k) = result;
    fprintf('RUNTIME_SMOKE test=%s status=%s profile_functions=%d loaded_repo_files=%d\n', ...
        result.test_name, result.status, result.profile_function_count, numel(result.loaded_repo_files));
end

meta.finished_utc = utc_now();
meta.status = ternary(all_pass, 'COMPLETE_WITH_LIMITATIONS', 'FAILED_OR_PARTIAL');
meta.passed_count = sum(strcmp({results.status}, 'PASS'));
meta.failed_count = sum(strcmp({results.status}, 'FAIL'));
write_json(fullfile(output_dir, 'runtime_calls.json'), struct( ...
    'status', meta.status, 'evidence', 'RUNTIME_SMOKE', 'tests', results, ...
    'note', 'Profile and loaded-file records are session observations for these synthetic tests; they are not a complete call graph.'));
write_json(fullfile(output_dir, 'loaded_files.json'), struct( ...
    'status', meta.status, 'evidence', 'RUNTIME_SMOKE', ...
    'tests', arrayfun(@(x) struct('test_name', x.test_name, 'loaded_repo_files', {x.loaded_repo_files}, ...
        'loaded_mex_files', {x.loaded_mex_files}), results)));
write_json(fullfile(output_dir, 'execution_summary.json'), meta);
if ~all_pass
    error('PIVCI:RuntimeSmokeFailed', 'One or more runtime smoke tests failed. Inspect %s.', output_dir);
end
output_dir = char(output_dir);
end

function s = empty_result()
s = struct('test_name', '', 'test_file', '', 'status', 'NOT_RUN', ...
    'started_utc', '', 'finished_utc', '', 'elapsed_seconds', 0, ...
    'error_identifier', '', 'error_message', '', 'error_report', '', ...
    'profile_error', '', 'loaded_files_error', '', 'profile_function_count', 0, ...
    'profile_functions', {{}}, 'loaded_repo_files', {{}}, 'loaded_mex_files', {{}});
end

function out = summarize_profile(info, repo_root)
out = {};
if ~isstruct(info) || ~isfield(info, 'FunctionTable'), return; end
ft = info.FunctionTable;
for k = 1:numel(ft)
    name = field_text(ft(k), 'FunctionName');
    complete = field_text(ft(k), 'CompleteName');
    if isempty(complete), complete = name; end
    if ~contains(strrep(complete, '\\', '/'), strrep(repo_root, '\\', '/'))
        continue;
    end
    item = struct('name', name, 'complete_name', complete, ...
        'num_calls', field_number(ft(k), 'NumCalls'), ...
        'total_time_seconds', field_number(ft(k), 'TotalTime'));
    out{end+1} = item; %#ok<AGROW>
end
end

function n = profile_function_count(info)
n = 0;
if isstruct(info) && isfield(info, 'FunctionTable'), n = numel(info.FunctionTable); end
end

function out = repo_files(items, repo_root)
out = {};
if ischar(items), items = cellstr(items); end
if isempty(items), return; end
for k = 1:numel(items)
    item = char(items{k});
    if contains(strrep(item, '\\', '/'), strrep(repo_root, '\\', '/'))
        out{end+1} = portable(item, repo_root); %#ok<AGROW>
    end
end
end

function value = field_text(s, name)
value = '';
if isfield(s, name)
    raw = s.(name);
    if ischar(raw), value = raw;
    elseif isstring(raw), value = char(raw);
    end
end
end

function value = field_number(s, name)
value = 0;
if isfield(s, name) && isnumeric(s.(name)) && isscalar(s.(name))
    value = double(s.(name));
end
end

function write_json(filename, value)
parent = fileparts(filename);
if ~isfolder(parent), mkdir(parent); end
fid = fopen(filename, 'w');
if fid < 0, error('PIVCI:EvidenceWrite', 'Cannot write %s', filename); end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s\n', jsonencode(value));
end

function p = canonical_path(p)
p = char(java.io.File(char(p)).getCanonicalPath());
end

function p = portable(filename, root)
filename = canonical_path(filename); root = canonical_path(root);
p = strrep(filename, '\\', '/');
r = strrep(root, '\\', '/');
if startsWith(p, [r '/']), p = p(numel(r) + 2:end); end
end

function t = utc_now()
t = char(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd HH:mm:ss XXX'));
end

function out = ternary(condition, yes, no)
if condition, out = yes; else, out = no; end
end
