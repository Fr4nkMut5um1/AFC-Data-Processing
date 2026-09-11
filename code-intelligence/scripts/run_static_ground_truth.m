function run_static_ground_truth(repoRoot, outputRoot)
%RUN_STATIC_GROUND_TRUTH Run read-only native dependency analysis for both r2 cases.
if nargin < 1 || isempty(repoRoot), repoRoot = pwd; end
if nargin < 2 || isempty(outputRoot), outputRoot = fullfile(repoRoot, 'cloud-static-evidence'); end
repoRoot = char(repoRoot); outputRoot = char(outputRoot);
if ~isfolder(outputRoot), mkdir(outputRoot); end
scriptDir = fullfile(repoRoot, 'code-intelligence', 'scripts');
addpath(scriptDir, '-begin');
cases = {'tandem_baseline_r2','tandem_f40a3_phi0_r2'};
summary = struct('schema_version','p1-native-static-1','matlab_version',version, ...
    'matlab_release',version('-release'),'repository_commit',getenv('GITHUB_SHA'), ...
    'cases',struct('name',{},'status',{},'output_dir',{}));
fprintf('Native static ground truth: MATLAB %s %s\n', version, version('-release'));
for k = 1:numel(cases)
    caseRoot = fullfile(repoRoot,'cases','per_case',cases{k});
    caseOut = fullfile(outputRoot,cases{k});
    if ~isfolder(caseOut), mkdir(caseOut); end
    try
        out = collect_static_evidence(caseRoot, caseOut);
        status = 'COMPLETE_WITH_LIMITATIONS';
        summaryFile = fullfile(out,'execution_summary.json');
        if isfile(summaryFile)
            detail = jsondecode(fileread(summaryFile));
            fprintf('CASE %s: status=%s analyzed_files=%d failed_files=%d source_unchanged=%d\n', ...
                cases{k}, detail.status, detail.analyzed_file_count, detail.failed_file_count, detail.source_unchanged);
        end
        productNames = required_product_names(fullfile(out,'static_native.mat'));
        fprintf('CASE %s native required products (%d):\n', cases{k}, numel(productNames));
        for j=1:numel(productNames), fprintf('  %s\n', productNames{j}); end
    catch ME
        out = caseOut;
        status = 'FAILED_OR_PARTIAL';
        fid=fopen(fullfile(caseOut,'runner_failure.txt'),'w');
        if fid>=0, fprintf(fid,'%s\n',getReport(ME,'extended','hyperlinks','off')); fclose(fid); end
        fprintf('CASE %s: status=%s error=%s\n', cases{k}, status, ME.message);
    end
    summary.cases(k)=struct('name',cases{k},'status',status,'output_dir',out); %#ok<AGROW>
end
products = ver;
fprintf('Installed MathWorks products (%d):\n', numel(products));
for k = 1:numel(products), fprintf('  %s\n', products(k).Name); end
fid=fopen(fullfile(outputRoot,'static_run_summary.json'),'w');
if fid<0, error('PIVCI:Write','Cannot write static run summary.'); end
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(summary,'PrettyPrint',true));
end

function names = required_product_names(matFile)
names = {};
if ~isfile(matFile), return; end
loaded = load(matFile,'raw');
if ~isfield(loaded,'raw'), return; end
raw = loaded.raw;
for i=1:numel(raw)
    p = raw(i).recursive_products;
    if isempty(p), continue; end
    if isstruct(p)
        for j=1:numel(p)
            if isfield(p,'Name'), n=char(p(j).Name); else, n=char(p(j)); end
            if ~any(strcmp(names,n)), names{end+1}=n; end %#ok<AGROW>
        end
    elseif iscell(p)
        for j=1:numel(p)
            n=char(p{j});
            if ~any(strcmp(names,n)), names{end+1}=n; end %#ok<AGROW>
        end
    end
end
names = sort(names);
end
