function manifest = dat_manifest(data_root, n_frames, frame_offset)
%DAT_MANIFEST Record the exact DAT-file metadata used by a statistics run.

if ~(ischar(data_root) || (isstring(data_root) && isscalar(data_root))) || ...
        ~isnumeric(n_frames) || ~isreal(n_frames) || ~isscalar(n_frames) || ...
        ~isfinite(n_frames) || n_frames < 1 || n_frames ~= fix(n_frames)
    error('tblR2:singlecase:dat_manifest:InvalidInput', ...
        '必须提供 data_root，且 n_frames 必须是正整数。');
end
if nargin < 3 || isempty(frame_offset)
    frame_offset = 0;
end
if ~(isnumeric(frame_offset) && isscalar(frame_offset) && ...
        isfinite(frame_offset) && frame_offset >= 0 && ...
        frame_offset == fix(frame_offset))
    error('tblR2:singlecase:dat_manifest:InvalidFrameOffset', ...
        'frame_offset 必须是非负整数标量。');
end
data_root = char(data_root);
listing = dir(fullfile(data_root, 'B*.dat'));
names = {listing.name};
manifest = repmat(struct('name', '', 'cache_index', NaN, ...
    'bytes', NaN, 'datenum', NaN), ...
    1, n_frames);

for iframe = 1:n_frames
    name = sprintf('B%04d.dat', iframe + frame_offset);
    match = find(strcmp(names, name));
    if numel(match) ~= 1
        error('tblR2:singlecase:dat_manifest:MissingFrame', ...
            '预期恰好存在一个输入帧文件：%s', fullfile(data_root, name));
    end
    manifest(iframe).name = name;
    manifest(iframe).cache_index = iframe;
    manifest(iframe).bytes = listing(match).bytes;
    manifest(iframe).datenum = listing(match).datenum;
end
end
