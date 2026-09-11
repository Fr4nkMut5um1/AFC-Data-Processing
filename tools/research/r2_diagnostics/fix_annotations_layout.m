function fix_annotations_layout(varargin)
%FIX_ANNOTATIONS_LAYOUT 把注释 JSON 的 vlsm_boxes 改写成扁平数组。
%
% 背景：derive_annotation_boxes.m 用 entry.vlsm_boxes = {boxes} 双嵌套。单元素
% cell 经 jsonencode 压成标量、多元素保持嵌套，于是 JSON 里出现 {"vlsm_boxes":
% [box]} 和 {"vlsm_boxes": [[box1,box2]]} 两种形态混存。本脚本把两者统一成
% [box1, box2, ...] 扁平数组。
%
% 调用
%   fix_annotations_layout()
%   fix_annotations_layout('sample_dir', 'tmp/annotation_samples/e60')

p = inputParser;
addParameter(p, 'sample_dir', 'tmp/annotation_samples/e60', @ischar);
parse(p, varargin{:});

ann_file = fullfile(p.Results.sample_dir, 'annotations.json');
ann = jsondecode(fileread(ann_file));
keys = fieldnames(ann.frames);
n_fixed = 0;
for k = 1:numel(keys)
    rec = ann.frames.(keys{k});
    if isempty(rec.vlsm_boxes); continue; end
    boxes = rec.vlsm_boxes;
    % 双层嵌套解开
    if iscell(boxes) && numel(boxes) == 1 && iscell(boxes{1})
        boxes = boxes{1};
    end
    % JSON 往返后单框可能已是 struct 而非 cell，统一成 cell
    if isstruct(boxes)
        boxes = num2cell(boxes);
    end
    rec.vlsm_boxes = boxes;      % cell，jsonencode 输出扁平数组
    ann.frames.(keys{k}) = rec;
    n_fixed = n_fixed + 1;
end

fid = fopen(ann_file, 'w', 'n', 'UTF-8');
fprintf(fid, '%s', jsonencode(ann, 'PrettyPrint', true));
fclose(fid);
fprintf('fixed %d frames, wrote %s\n', n_fixed, ann_file);
end
