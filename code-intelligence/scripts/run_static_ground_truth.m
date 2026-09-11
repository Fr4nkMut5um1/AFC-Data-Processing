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
for k = 1:numel(cases)
    caseRoot = fullfile(repoRoot,'cases','per_case',cases{k});
    caseOut = fullfile(outputRoot,cases{k});
    if ~isfolder(caseOut), mkdir(caseOut); end
    try
        out = collect_static_evidence(caseRoot, caseOut);
        status = 'COMPLETE_WITH_LIMITATIONS';
    catch ME
        out = caseOut;
        status = 'FAILED_OR_PARTIAL';
        fid=fopen(fullfile(caseOut,'runner_failure.txt'),'w');
        if fid>=0, fprintf(fid,'%s\n',getReport(ME,'extended','hyperlinks','off')); fclose(fid); end
    end
    summary.cases(k)=struct('name',cases{k},'status',status,'output_dir',out); %#ok<AGROW>
end
fid=fopen(fullfile(outputRoot,'static_run_summary.json'),'w');
if fid<0, error('PIVCI:Write','Cannot write static run summary.'); end
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(summary,'PrettyPrint',true));
end
