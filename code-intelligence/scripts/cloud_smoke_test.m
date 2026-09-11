function cloud_smoke_test(repoRoot, outputFile)
% Minimal MATLAB R2022b cloud environment smoke test.
if nargin < 1 || isempty(repoRoot), repoRoot = pwd; end
if nargin < 2 || isempty(outputFile)
    outputFile = fullfile(repoRoot, 'cloud_environment.json');
end
repoRoot = char(repoRoot);
if ~isfolder(repoRoot), error('cloud_smoke_test:MissingRepo', 'Repository root does not exist: %s', repoRoot); end
v = ver('MATLAB');
info = struct();
info.matlab_version = version;
info.matlab_release = v.Release;
info.os = computer;
info.architecture = computer('arch');
info.repository_root = repoRoot;
info.repository_commit = getenv('GITHUB_SHA');
info.execution_timestamp_utc = char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ssXXX'));
info.simple_command_result = 2 + 2;
products = ver;
info.installed_products = {products.Name};
info.required_products = {'MATLAB'};
info.matlab_ok = strcmp(info.simple_command_result, 4) && ~isempty(info.matlab_version);
text = jsonencode(info);
parent = fileparts(outputFile);
if ~isfolder(parent), mkdir(parent); end
fid = fopen(outputFile, 'w');
if fid < 0, error('cloud_smoke_test:OpenFailed', 'Cannot write %s', outputFile); end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', text);
fprintf('MATLAB version: %s\n', info.matlab_version);
fprintf('MATLAB release: %s\n', info.matlab_release);
fprintf('Runner architecture: %s\n', info.architecture);
fprintf('Smoke test result: %d\n', info.simple_command_result);
end
