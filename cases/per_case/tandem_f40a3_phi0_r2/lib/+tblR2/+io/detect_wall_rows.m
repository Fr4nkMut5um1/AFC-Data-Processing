function n_removed = detect_wall_rows( ...
    data_root, frame_start, frame_end, I, J, frame_offset, wall_side)
% DETECT_WALL_ROWS 检测 PIV 数据中壁面侧 mask 区连续无效行数
% ========================================================================
% 【功能】
%   PIV mask 区域（真实壁面及壁面以下）表现为整行速度恒为 0（U=0 & V=0）。
%   因为壁面平直，从 j=1（壁面侧）起连续无效的行数在所有 x、所有帧一致。
%   本函数对若干抽样帧读取原始 dat 文件，用速度恒零判据找 n_removed。
%
% 【判据】
%   抽样帧中 U==0 & V==0 从 j=1 起连续为真的整行数（"流场速度一直为 0"）。
%   n_removed = max 所有抽样帧。isValid 列不参与判定——无效行只以
%   流场速度是否一直为 0 识别，与 isValid 取值无关。
%
% 【抽样帧】
%   unique([1, 500, 1000, 1500, 2000, 2500, frame_end])，越界跳过
%
% 【输入】
%   data_root   - PostProc 文件夹路径
%   frame_start - 起始帧
%   frame_end   - 结束帧
%   I, J        - 网格尺寸（流向×法向）
%   frame_offset - 可选，非负整数；实际源文件号 = 帧号 + frame_offset
%   wall_side    - 可选，'bottom' 或 'top'（默认 'bottom'）。
%                  'bottom' 沿用历史约定：翻转后从数组底部（idx=1）找壁面
%                  侧连续无效行；'top' 不翻转，直接从数组顶部找壁面侧。
%
% 【输出】
%   n_removed - 从 j=1 起需要裁掉的行数（0 = 无需裁）
%
% 【备注】
%   下游 load_tecplot_dat / mean_stats_chunked 各自用 n_removed 裁自己的数组。
%   裁行后的 Y 坐标映射由 load_tecplot_dat 的 remap_y_to_wall 决定：
%   开启时第一保留行 y = 0 + h（h = y 方向矢量间距），逐行递增；
%   关闭时保持源 Y 数值不动（历史单 case 流程口径）。
% ========================================================================

    if nargin < 6 || isempty(frame_offset)
        frame_offset = 0;
    end
    if ~(isnumeric(frame_offset) && isscalar(frame_offset) && ...
            isfinite(frame_offset) && frame_offset >= 0 && ...
            frame_offset == fix(frame_offset))
        error('tblR2:io:detect_wall_rows:InvalidFrameOffset', ...
        'frame_offset 必须是非负整数标量。');
    end
    if nargin < 7 || isempty(wall_side)
        wall_side = 'bottom';
    end
    wall_side = lower(char(wall_side));
    if ~ismember(wall_side, {'bottom', 'top'})
        error('tblR2:io:detect_wall_rows:InvalidWallSide', ...
        'wall_side 必须是 ''bottom'' 或 ''top''。');
    end

    % 抽样帧列表（缓存内相对帧号，再换算成真实源文件号）
    relative_span = frame_end - frame_start;
    candidate = [1, 500, 1000, 1500, 2000, 2500, relative_span];
    relative_frames = unique(candidate(candidate >= 1 & ...
        candidate <= relative_span));
    sample_frames = frame_start + relative_frames - 1 + frame_offset;

    n_b_list = zeros(1, numel(sample_frames));

    for k = 1:numel(sample_frames)
        f = sample_frames(k);
        [~, ~, Ux, Uy, ~] = read_single_dat_local( ...
            data_root, f, I, J, 0);

        % 翻转到"壁面在 idx=1"方向（bottom 历史约定；top 保持原始行序）
        if strcmp(wall_side, 'bottom')
            Ux  = flip(Ux,  1);
            Uy  = flip(Uy,  1);
        end

        % 判据：整行 U==0 & V==0（流场速度一直为 0）的连续壁面侧行数
        vel_zero = (Ux == 0) & (Uy == 0);
        n_b_list(k) = find_first_valid_offset(~vel_zero);
    end

    n_removed = max(n_b_list);

    fprintf('Mask 检测（流场速度一直为 0 判据）：\n');
    fprintf('  抽样帧: [%s]\n', num2str(sample_frames));
    fprintf('  速度恒零(U=V=0)连续壁面侧行数 → n=%d\n', n_removed);
    fprintf('  最终 n_removed = %d\n', n_removed);

    if n_removed >= J - 10
        error('tblR2:io:detect_wall_rows:AbnormalMask', ...
            '掩膜检测异常：n_removed=%d 接近 J=%d，请人工检查数据。', ...
            n_removed, J);
    end
end


function n_offset = find_first_valid_offset(valid_mask)
% 找 valid_mask 从 j=1 起第一个 true 的行号 - 1
% 即"壁面侧连续 false 的行数"
    row_has_valid = any(valid_mask, 2);
    idx = find(row_has_valid, 1, 'first');
    if isempty(idx)
        n_offset = length(row_has_valid);
    else
        n_offset = idx - 1;
    end
end


function [X, Y, Vx, Vy, Isvalid] = read_single_dat_local( ...
    data_root, iframe, I, J, frame_offset)
    filename = fullfile(data_root, ...
        sprintf('B%04d.dat', iframe + frame_offset));
    if ~exist(filename, 'file')
        error('tblR2:io:detect_wall_rows:MissingFile', ...
            '输入文件不存在：%s。', filename);
    end
    fid = fopen(filename, 'r');
    if fid < 0
        error('tblR2:io:detect_wall_rows:OpenFailed', ...
            '无法打开输入文件：%s。', filename);
    end
    for i = 1:4, fgetl(fid); end
    data = cell2mat(textscan(fid, repmat('%f', 1, 5)));
    fclose(fid);
    X = reshape(data(:,1), I, J)';
    Y = reshape(data(:,2), I, J)';
    Vx = (reshape(data(:,3), I, J))';
    Vy = (reshape(data(:,4), I, J))';
    Isvalid = (reshape(data(:,5), I, J))';
end
