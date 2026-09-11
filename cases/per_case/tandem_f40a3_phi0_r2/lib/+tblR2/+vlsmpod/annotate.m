function T = annotate(T, frame_id, branch, preprocessing)
%ANNOTATE 在 structures 表最前插入 FrameID/Branch/Preprocessing 三列。
%
% 原逻辑内嵌在 run_structure_pod_denoise.m 的主循环里，抽出来是因为三个新功能
% 扩展的合成数据测试也需要构造同样形状的表，抽出后可以共用同一份插列逻辑。

nrows = height(T);
T = addvars(T, repmat(frame_id, nrows, 1), repmat({branch}, nrows, 1), ...
    repmat({preprocessing}, nrows, 1), 'Before', 1, ...
    'NewVariableNames', {'FrameID', 'Branch', 'Preprocessing'});
end
