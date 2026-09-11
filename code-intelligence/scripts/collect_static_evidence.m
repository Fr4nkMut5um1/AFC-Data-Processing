function output_dir = collect_static_evidence(case_root, output_parent)
%COLLECT_STATIC_EVIDENCE Read-only file analysis, one case per fresh MATLAB.
% Does NOT run the case script, startup files, tests, or scientific functions.
% File dependency edges are NOT function calls or execution order.
% Use MATLAB R2022b with JVM. Native execution is pending in this delivery.

case_root = char(java.io.File(char(case_root)).getCanonicalPath());
output_parent = char(java.io.File(char(output_parent)).getCanonicalPath());
if inside(output_parent, case_root)
    error('PIVCI:OutputInsideCase', 'Write evidence outside the scientific case.');
end
[~, case_name] = fileparts(case_root);
if ~isfolder(output_parent); mkdir(output_parent); end
[~, nonce] = fileparts(tempname);
output_dir = fullfile(output_parent, [case_name '_' datestr(now, 'yyyymmddTHHMMSS') '_' nonce]);
mkdir(output_dir);
try
    collect_case(case_root, case_name, output_dir);
catch ME
    failure = struct('status', 'FAILED_OR_PARTIAL', 'identifier', ME.identifier, ...
        'message', ME.message, 'report', getReport(ME, 'extended', 'hyperlinks', 'off'), ...
        'scientific_code_executed', false);
    % Includes preflight failures, before the first dependency API call.
    % Preserve any richer summary and native MAT already written.
    try
        write_json(fullfile(output_dir, 'failure.json'), failure);
        summary_file = fullfile(output_dir, 'execution_summary.json');
        if isfile(summary_file)
            summary = jsondecode(fileread(summary_file));
        else
            summary = struct('case_root', case_root, 'matlab_version', version);
        end
        summary.status = 'FAILED_OR_PARTIAL';
        summary.fatal = failure;
        write_json(summary_file, summary);
    catch save_error
        warning('PIVCI:FailureSave', 'Cannot save failure evidence: %s', save_error.message);
    end
    rethrow(ME);
end
end

function collect_case(case_root, case_name, output_dir)
entrypoint = fullfile(case_root, [case_name '_case.m']);
assert(isfile(entrypoint), 'PIVCI:MissingEntry', 'Missing entrypoint: %s', entrypoint);
assert(isfolder(fullfile(case_root, 'lib')), 'PIVCI:MissingLibrary', 'Missing case lib.');
original_path = path;
original_folder = pwd;
cleanup = onCleanup(@() restore_session(original_path, original_folder)); %#ok<NASGU>
% Reject existing project libraries instead of silently replacing their order.
for symbol = {'tblR2.validate_config', 'd23.default_config', 'piDMD', 'spod'}
    hits = which(symbol{1}, '-all');
    if ischar(hits); hits = cellstr(hits); end
    hits = hits(~cellfun('isempty', hits));
    for k = 1:numel(hits)
        assert(inside(hits{k}, case_root), 'PIVCI:ForeignPath', ...
            'Foreign %s: %s. Use a fresh MATLAB session.', symbol{1}, hits{k});
    end
end
[loaded, loaded_mex] = inmem('-completenames');
for k = 1:numel(loaded)
    p = strrep(loaded{k}, '\', '/');
    assert(~contains(p, '/+tblR2/') && ~contains(p, '/+d23/'), ...
        'PIVCI:LoadedCase', 'Case code is already loaded; start a fresh MATLAB.');
end
cd(case_root);
addpath(case_root, fullfile(case_root, 'lib'), '-begin');
if isfolder(fullfile(case_root, 'third_party', 'piDMD'))
    addpath(fullfile(case_root, 'third_party', 'piDMD'), '-begin');
end
% Do not recursively add the repository, another case, or optional SPOD.
resolved_tbl = which('tblR2.validate_config');
resolved_d23 = which('d23.default_config');
assert(~isempty(resolved_tbl) && inside(resolved_tbl, case_root), 'PIVCI:Resolution', 'Wrong tblR2.');
assert(~isempty(resolved_d23) && inside(resolved_d23, case_root), 'PIVCI:Resolution', 'Wrong d23.');
[~, run_id] = fileparts(output_dir);
meta = struct('schema_version', 'p1-draft-2', 'run_id', run_id, ...
    'status', 'RUNNING', 'case_name', case_name, 'case_root', case_root, ...
    'entrypoint', entrypoint, 'matlab_version', version, ...
    'matlab_release', version('-release'), 'computer', computer, ...
    'github_sha', getenv('GITHUB_SHA'), 'github_run_id', getenv('GITHUB_RUN_ID'), ...
    'created_utc', char(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd HH:mm:ss XXX')), ...
    'collector', mfilename('fullpath'), 'collector_sha256', sha256([mfilename('fullpath') '.m']), ...
    'scientific_code_executed', false, 'missing_dependencies_complete', false);
write_json(fullfile(output_dir, 'execution_summary.json'), meta);
installed_products = ver;
analysis_path = path;
inventory_before = inventory(case_root);
raw = struct('file', {}, 'recursive_files', {}, 'recursive_products', {}, ...
    'direct_files', {}, 'direct_products', {}, 'console', {}, 'error', {});
edges = struct('source', {}, 'target', {}, 'relation', {}, 'evidence', {});
external = struct('path', {}, 'boundary', {});
resolution = struct('symbol', {}, 'resolved', {}, 'purpose', {});
unresolved = struct('symbol', {}, 'status', {}, 'optional', {});
probes = {'csaps', 'fnder', 'bwconncomp', 'regionprops', 'pwelch', 'prctile', 'piDMD', 'spod'};
for k = 1:numel(probes)
    hits = which(probes{k}, '-all');
    if ischar(hits); hits = cellstr(hits); end
    hits = hits(~cellfun('isempty', hits));
    if isempty(hits)
        unresolved(end+1) = struct('symbol', probes{k}, 'status', 'NOT_RESOLVED_ON_ANALYSIS_PATH', ...
            'optional', strcmp(probes{k}, 'spod')); %#ok<AGROW>
    end
    resolution(end+1) = struct('symbol', probes{k}, 'resolved', {hits}, ...
        'purpose', 'path resolution only; not proof of use'); %#ok<AGROW>
end
queue = {entrypoint};
visited = {};
fatal = [];
try
    while ~isempty(queue)
        filename = queue{1}; queue(1) = [];
        if any(strcmp(visited, filename)); continue; end
        visited{end+1} = filename; %#ok<AGROW>
        item = struct('file', filename, 'recursive_files', {{}}, ...
            'recursive_products', [], 'direct_files', {{}}, 'direct_products', [], ...
            'console', '', 'error', []);
        try
            if strcmp(filename, entrypoint)
                item.console = evalc('[recursive_files, recursive_products] = matlab.codetools.requiredFilesAndProducts(filename);');
                item.recursive_files = recursive_files;
                item.recursive_products = recursive_products;
                % Also inspect resolved transitive files: do not assume top-only
                % traversal has identical coverage to the recursive analysis.
                for j = 1:numel(recursive_files)
                    [~, ~, ext] = fileparts(recursive_files{j});
                    if strcmpi(ext, '.m') && inside(recursive_files{j}, case_root)
                        queue{end+1} = recursive_files{j}; %#ok<AGROW>
                    end
                end
            end
            item.console = [item.console evalc('[direct_files, direct_products] = matlab.codetools.requiredFilesAndProducts(filename, ''toponly'');')];
            item.direct_files = direct_files;
            item.direct_products = direct_products;
            for j = 1:numel(direct_files)
                target = direct_files{j};
                if strcmp(target, filename); continue; end
                edges(end+1) = struct('source', portable(filename, case_root), ...
                    'target', portable(target, case_root), 'relation', 'direct_file_dependency', ...
                    'evidence', 'STATIC'); %#ok<AGROW>
                [~, ~, ext] = fileparts(target);
                if inside(target, case_root) && strcmpi(ext, '.m')
                    queue{end+1} = target; %#ok<AGROW>
                elseif ~inside(target, case_root)
                    boundary = 'outside_case';
                    if inside(target, matlabroot); boundary = 'matlab_installation'; end
                    external(end+1) = struct('path', target, 'boundary', boundary); %#ok<AGROW>
                end
            end
        catch ME
            item.error = struct('identifier', ME.identifier, 'message', ME.message, ...
                'report', getReport(ME, 'extended', 'hyperlinks', 'off'));
        end
        raw(end+1) = item; %#ok<AGROW>
    end
catch ME
    fatal = struct('identifier', ME.identifier, 'message', ME.message);
end
inventory_after = inventory(case_root);
meta.source_unchanged = isequal(inventory_before, inventory_after);
meta.analyzed_file_count = numel(raw);
meta.failed_file_count = sum(arrayfun(@(x) ~isempty(x.error), raw));
meta.status = 'COMPLETE_WITH_LIMITATIONS';
if ~isempty(fatal) || meta.failed_file_count > 0 || ~meta.source_unchanged
    meta.status = 'FAILED_OR_PARTIAL';
end
meta.fatal = fatal;
% Preserve native outputs even if later JSON normalization fails.
save(fullfile(output_dir, 'static_native.mat'), 'meta', 'raw', 'edges', ...
    'external', 'installed_products', 'analysis_path', 'original_path', ...
    'resolution', 'unresolved', 'loaded', 'loaded_mex', 'inventory_before', 'inventory_after', '-v7');
write_json(fullfile(output_dir, 'entrypoints.json'), struct( ...
    'status', 'SOURCE_SELECTED', 'evidence', 'INFERRED', 'file', portable(entrypoint, case_root), ...
    'note', 'Entrypoint role is source-reviewed, not established by dependency analysis.'));
write_json(fullfile(output_dir, 'static_dependencies.json'), struct( ...
    'status', meta.status, 'evidence', 'STATIC', 'edges', edges, ...
    'note', 'Unconditional file graph; not observed execution, call order or local-function graph.'));
write_json(fullfile(output_dir, 'toolboxes.json'), struct( ...
    'installed', installed_products, 'per_file_native', raw, ...
    'note', 'Keep Certain flags. Products absent from this installation may be omitted.'));
write_json(fullfile(output_dir, 'external_dependencies.json'), struct('files', external));
write_json(fullfile(output_dir, 'missing_dependencies.json'), struct( ...
    'status', 'NOT_EXHAUSTIVELY_ASSESSED', 'items', unresolved, 'resolution_probes', resolution, ...
    'note', 'Items are unresolved source-selected probes, not an exhaustive missing dependency set or proof of runtime need. RFAP omits off-path files. Optional SPOD is deliberately not added to this analysis path.'));
write_json(fullfile(output_dir, 'execution_summary.json'), meta);
assert(strcmp(meta.status, 'COMPLETE_WITH_LIMITATIONS'), ...
    'PIVCI:Incomplete', 'Analysis incomplete. Inspect evidence: %s', output_dir);
fprintf('Static evidence saved: %s\n', output_dir);
end

function yes = inside(filename, root)
filename = char(java.io.File(char(filename)).getCanonicalPath());
root = char(java.io.File(char(root)).getCanonicalPath());
if ispc; filename = lower(filename); root = lower(root); end
yes = strcmp(filename, root) || startsWith(filename, [root filesep]);
end

function value = portable(filename, root)
if inside(filename, root)
    filename = char(java.io.File(filename).getCanonicalPath());
    value = strrep(filename(numel(root)+2:end), '\', '/');
else
    value = filename;
end
end

function rows = inventory(root)
% Hash scientific source and small fixed resources, not experimental datasets.
files = [dir(fullfile(root, '**', '*.m')); dir(fullfile(root, '**', 'Cf_chart.txt')); ...
    dir(fullfile(root, '**', 'LICENSE'))];
rows = struct('path', {}, 'sha256', {});
for k = 1:numel(files)
    if files(k).isdir; continue; end
    p = fullfile(files(k).folder, files(k).name);
    rows(end+1) = struct('path', portable(p, root), 'sha256', sha256(p)); %#ok<AGROW>
end
if ~isempty(rows)
    [~, order] = sort({rows.path});
    rows = rows(order);
end
end

function digest = sha256(filename)
fid = fopen(filename, 'rb');
assert(fid >= 0, 'PIVCI:Read', 'Cannot open %s', filename);
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, Inf, '*uint8');
engine = java.security.MessageDigest.getInstance('SHA-256');
engine.update(bytes);
digest = lower(reshape(dec2hex(typecast(engine.digest(), 'uint8'), 2).', 1, []));
end

function write_json(filename, value)
fid = fopen(filename, 'w', 'n', 'UTF-8');
assert(fid >= 0, 'PIVCI:Write', 'Cannot write %s', filename);
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s\n', jsonencode(value, 'PrettyPrint', true));
end

function restore_session(old_path, old_folder)
cd(old_folder);
path(old_path);
end
