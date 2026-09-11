function block = read_cache_frames(cache, variable, frame_ids, J, I)
%READ_CACHE_FRAMES 从 MAT 缓存读取帧块，并恢复为 [帧数,J,I]。
% MATLAB 保存末尾 singleton 维度时会将三维数组压成二维；这里按已知网格
% 尺寸选择二维/三维索引，保证小网格测试与正式缓存使用同一读取合同。
frame_ids = double(frame_ids(:));
if ~(isscalar(J) && isscalar(I) && J >= 1 && I >= 1 && ...
        J == fix(J) && I == fix(I))
    error('tblR2:read_cache_frames:InvalidGridSize', ...
        '缓存网格尺寸 J/I 必须是正整数。');
end
switch variable
    case 'U'
        if I == 1
            raw = cache.U(frame_ids, 1:J);
        else
            raw = cache.U(frame_ids, 1:J, 1:I);
        end
    case 'V'
        if I == 1
            raw = cache.V(frame_ids, 1:J);
        else
            raw = cache.V(frame_ids, 1:J, 1:I);
        end
    case 'sampleValid'
        if I == 1
            raw = cache.sampleValid(frame_ids, 1:J);
        else
            raw = cache.sampleValid(frame_ids, 1:J, 1:I);
        end
    otherwise
        error('tblR2:read_cache_frames:InvalidVariable', ...
            '缓存变量名必须是 U、V 或 sampleValid。');
end
block = reshape(raw, [numel(frame_ids), J, I]);
end
