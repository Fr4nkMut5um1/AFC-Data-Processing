function [script_file, case_root, repo_root, library_root] = bootstrap_r2_case(script_file, library_root)
%BOOTSTRAP_R2_CASE Resolve the case, shared r2 library, and repository paths.
% Keep the case scripts focused on configuration and stage order.

if nargin < 1 || isempty(script_file)
    try
        script_file = matlab.desktop.editor.getActiveFilename;
    catch
        script_file = '';
    end
end
if isempty(script_file)
    error('r2:bootstrap:MissingScriptPath', 'Run the case script from a file.');
end
script_file = char(script_file);
case_root = fileparts(script_file);
repo_root = case_root;
while ~isfolder(fullfile(repo_root, 'third_party'))
    parent = fileparts(repo_root);
    if strcmp(parent, repo_root)
        error('r2:bootstrap:MissingRepositoryRoot', ...
            'Could not locate the repository root (third_party).');
    end
    repo_root = parent;
end

if nargin < 2 || isempty(library_root)
    library_root = fullfile(repo_root, 'lib');
end
library_root = char(library_root);
if ~isfolder(fullfile(library_root, '+tblR2')) || ...
        ~isfolder(fullfile(library_root, '+d23'))
    error('r2:bootstrap:MissingCoreLibrary', ...
        'Missing +tblR2 or +d23 library: %s', library_root);
end

addpath(repo_root, '-end');
addpath(library_root, '-begin');
addpath(case_root, '-begin');
end
