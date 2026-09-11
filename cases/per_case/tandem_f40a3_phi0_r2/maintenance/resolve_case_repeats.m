function info = resolve_case_repeats(case_root, case_prefix, n_frames, offset_candidates)
%RESOLVE_CASE_REPEATS Probe the two most recent numbered repeats and per-repeat frame offsets.
%   INFO = TBL.PERIODIC.RESOLVE_CASE_REPEATS(CASE_ROOT, CASE_PREFIX, N_FRAMES)
%
%   CASE_ROOT         : parent directory holding the numbered repeat folders,
%                       e.g. J:\...\TempData0731_LinZheng\Tandem.
%   CASE_PREFIX       : case folder prefix without the repeat suffix, e.g.
%                       'Tandem_f40A3_Phi+0_PIV' (matches
%                       Tandem_f40A3_Phi+0_PIV_1st/_2nd/_3rd).
%   N_FRAMES          : frames read per repeat (6000).
%   OFFSET_CANDIDATES : 1-based starting frame numbers tried in order of
%                       preference (default [1 49]); the largest start frame
%                       satisfying start + n_frames - 1 <= file count is
%                       chosen per repeat (6000 files -> start 1, 6050 files
%                       -> start 49). If none fits, the repeat is rejected.
%
%   INFO fields:
%     repeat_ids  : cellstr, two selected suffixes in descending rank order,
%                   e.g. {'3rd','2nd'}.
%     roots       : cellstr, two selected folder paths (same order).
%     offsets     : 1x2 double, zero-based frame_offset per repeat as used by
%                   load_tecplot_dat / dat_manifest (start_frame - 1).
%     starts      : 1x2 double, 1-based starting frame per repeat.
%     file_counts : 1x2 double, B*.dat count per repeat folder.
%
%   "Take the largest two numbered repeats" follows the pipeline convention
%   that a case reads the two most recent experiments (Phi+0 -> 2nd+3rd,
%   Phi+30 -> 1st+2nd when only 1st/2nd exist).

if nargin < 4 || isempty(offset_candidates)
    offset_candidates = [1 49];
end
offset_candidates = double(offset_candidates(:)).';
if ~(ischar(case_root) || isstring(case_root)) || isempty(case_root)
    error('tblR2:resolve_case_repeats:BadRoot', ...
        'case_root 必须是非空文件夹路径。');
end
if ~(ischar(case_prefix) || isstring(case_prefix)) || isempty(case_prefix)
    error('tblR2:resolve_case_repeats:BadPrefix', ...
        'case_prefix 必须是非空的文件夹名称前缀。');
end
case_root = char(case_root);
case_prefix = char(case_prefix);
if ~isfolder(case_root)
    error('tblR2:resolve_case_repeats:MissingRoot', ...
        '工况根目录不存在：%s', case_root);
end

% --- numbered repeat folders matching <prefix>_1st/_2nd/_3rd --------------
pattern = ['^' regexptranslate('escape', case_prefix) '_([123])(?:st|nd|rd)$'];
entries = dir(case_root);
numbered = struct('folder', {}, 'rank', {});
for k = 1:numel(entries)
    if ~entries(k).isdir
        continue;
    end
    tk = regexp(entries(k).name, pattern, 'tokens', 'once');
    if ~isempty(tk)
        numbered(end + 1).folder = entries(k).name; %#ok<AGROW>
        numbered(end).rank = str2double(tk{1}); %#ok<AGROW>
    end
end
if numel(numbered) < 2
    error('tblR2:resolve_case_repeats:NotEnoughRepeats', ...
        ['在 %s 下至少需要两个匹配 %s_* 的编号 repeat 文件夹，' ...
         '但只找到 %d 个。'], case_root, case_prefix, numel(numbered));
end
[~, order] = sort([numbered.rank], 'descend');
numbered = numbered(order);
selected = numbered(1:2);

% --- per-repeat frame start from the candidate ladder ----------------------
repeat_ids = cell(1, 2);
roots = cell(1, 2);
starts = nan(1, 2);
offsets = nan(1, 2);
file_counts = nan(1, 2);
for r = 1:2
    folder = fullfile(case_root, selected(r).folder);
    dat_count = numel(dir(fullfile(folder, 'B*.dat')));
    fit = offset_candidates(offset_candidates + n_frames - 1 <= dat_count);
    if isempty(fit)
        error('tblR2:resolve_case_repeats:NoFittingOffset', ...
            ['repeat 文件夹 %s 包含 %d 个 B*.dat 文件；候选起始帧 %s 均无法提供 ' ...
             '%d 个连续帧。请检查源数据导出的完整性。'], folder, dat_count, ...
            mat2str(offset_candidates), n_frames);
    end
    repeat_ids{r} = selected(r).folder;
    roots{r} = folder;
    starts(r) = max(fit);
    offsets(r) = starts(r) - 1;
    file_counts(r) = dat_count;
end

info = struct();
info.repeat_ids = repeat_ids;
info.roots = roots;
info.starts = starts;
info.offsets = offsets;
info.file_counts = file_counts;
end
