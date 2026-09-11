function field = load_tecplot_dat( ...
    data_root, frame_range, grid_size, frame_offset, wall_side, ...
    force_j_wall_removed, remap_y_to_wall)
% LOAD_TECPLOT_DAT 加载Tecplot格式的PIV二维流场数据
% ========================================================================
% 【功能】
%   从指定文件夹批量读取由DaVis等PIV软件导出的Tecplot ASCII格式数据文件
%   （B*.dat），将瞬时速度场组装为统一的field结构体，自动完成：
%       1) 坐标网格规整（J×I, 行=y方向, 列=x方向）
%       2) 坐标翻转（壁面置于数组底部 idx=1）
%       3) V分量符号修正（与陈朗生原始约定一致）
%       4) 分块加载以控制内存占用
%
% 【输入参数】
%   data_root    - 字符串，PostProc文件夹的绝对路径
%                  示例：'D:\...\Export\0530_Single\Baseline\PostProc'
%   frame_range  - [start, end] 双元素整数向量，指定加载的帧范围
%                  或字符串 'all'（默认加载全部3000帧）
%                  示例：[1, 200] 加载前200帧
%   grid_size    - [I, J] 双元素整数向量
%                  I=流向网格数（典型640），J=法向网格数（典型98）
%   frame_offset - 可选，非负整数，跳过前 frame_offset 个 B####.dat 文件
%                  （默认 0）。实际读取文件为
%                  B{frame_offset+frame_start}.dat .. B{frame_offset+frame_end}.dat。
%   wall_side    - 可选，'bottom' 或 'top'（默认 'bottom'）。
%                  'bottom' 保持历史约定：原始文件按顶部->底部排列，
%                  加载后翻转使壁面位于数组 idx=1。
%                  'top' 用于壁面在原始文件顶部的数据：不翻转，V 取负，
%                  使正 V 仍指向离壁方向。
%   force_j_wall_removed - 可选，非负整数；非空时跳过自动检测、强制
%                  从壁面侧裁掉该行数（双源对齐用：PostProc 缓存强制
%                  使用 raw 的 j_wall_removed）。
%   remap_y_to_wall - 可选，logical（默认 false）。true 时在裁行后把 Y
%                  重映射为壁面起算的测量坐标：第一保留行 y = 0 + h
%                  （h = y 方向矢量间距，取自源 Y 相邻行差绝对值），
%                  之后逐行 +h，壁面位于 y=0、数组 idx=1（y 最小）。
%                  历史单 case 流程（false）保持源 Y 数值不动。
%
% 【输出】
%   field 结构体，包含以下字段：
%       field.X       - 2D矩阵 (J×I)，X坐标 [mm]
%       field.Y       - 2D矩阵 (J×I)，Y坐标 [mm]
%       field.U       - 3D矩阵 (nFrames×J×I)，U速度场 [m/s]
%       field.V       - 3D矩阵 (nFrames×J×I)，V速度场 [m/s]，已符号修正
%       field.isValid - 2D逻辑矩阵 (J×I)，标记有效PIV矢量点
%       field.h       - 标量，矢量间距 [mm]（自动从坐标提取）
%       field.nFrames - 标量，实际加载的帧数
%
% 【使用示例】
%   data_root = 'D:\...\PostProc';
%   field = load_tecplot_dat(data_root, [1, 100], [640, 98]);
%   % 提取第50帧的U分量
%   U_frame50 = squeeze(field.U(50, :, :));
%
% 【性能与内存】
%   - 自动估算可用内存，按30%可用内存计算分块大小
%   - 典型3000帧×640×98×8字节 ≈ 3GB内存
%   - 单帧读取速度约50-100 ms
%
% 【依赖】
%   - MATLAB R2018a+
%   - 无外部工具箱依赖
%
% 【注意事项】
%   - 文件命名必须严格为 B%04d.dat（如B0001.dat）
%   - Tecplot文件头部应有4行（TITLE, VARIABLES, ZONE, STRANDID）
%   - 数据应为5列：x, y, u, v, isValid
% ========================================================================

% --- 解析输入参数 ---
I = grid_size(1);  % 流向网格数
J = grid_size(2);  % 法向网格数
if nargin < 4 || isempty(frame_offset)
    frame_offset = 0;
end
if ~(isnumeric(frame_offset) && isscalar(frame_offset) && ...
        isfinite(frame_offset) && frame_offset >= 0 && ...
        frame_offset == fix(frame_offset))
    error('tblR2:io:load_tecplot_dat:InvalidFrameOffset', ...
        'frame_offset 必须是非负整数标量。');
end
if nargin < 5 || isempty(wall_side)
    wall_side = 'bottom';
end
wall_side = lower(char(wall_side));
if ~ismember(wall_side, {'bottom', 'top'})
    error('tblR2:io:load_tecplot_dat:InvalidWallSide', ...
        'wall_side 必须是 ''bottom'' 或 ''top''。');
end

if nargin < 6 || isempty(force_j_wall_removed)
    force_j_wall_removed = [];
end
if ~isempty(force_j_wall_removed) && ...
        ~(isnumeric(force_j_wall_removed) && isscalar(force_j_wall_removed) && ...
        isfinite(force_j_wall_removed) && force_j_wall_removed >= 0 && ...
        force_j_wall_removed == fix(force_j_wall_removed))
    error('tblR2:io:load_tecplot_dat:InvalidWallRemoved', ...
        'force_j_wall_removed 必须是非负整数标量或空值。');
end

if nargin < 7 || isempty(remap_y_to_wall)
    remap_y_to_wall = false;
end
if ~(islogical(remap_y_to_wall) && isscalar(remap_y_to_wall)) && ...
        ~(isnumeric(remap_y_to_wall) && isscalar(remap_y_to_wall) && ...
        isfinite(remap_y_to_wall) && ...
        (remap_y_to_wall == 0 || remap_y_to_wall == 1))
    error('tblR2:io:load_tecplot_dat:InvalidYRemap', ...
        'remap_y_to_wall 必须是逻辑标量。');
end
remap_y_to_wall = logical(remap_y_to_wall);

% 帧范围解析：支持 'all' 或 [start, end]
if ischar(frame_range) && strcmp(frame_range, 'all')
    frame_start = 1;
    frame_end = 3000;       % 默认全部3000帧
else
    frame_start = frame_range(1);
    frame_end = frame_range(2);
end
nFrames = frame_end - frame_start + 1;

% --- 自动计算分块大小（防止内存溢出）---
% 策略：使用30%可用内存作为单批数据的上限
[~, sys] = memory;
available_GB = sys.PhysicalMemory.Available / 1e9;
bytes_per_frame = I * J * 8 * 2;        % U,V各占8字节double
chunk_size = min(nFrames, floor(available_GB * 0.3 / (bytes_per_frame / 1e9)));
chunk_size = max(chunk_size, 10);       % 至少10帧/批

% --- 打印配置信息 ---
fprintf('数据加载配置：\n');
fprintf('  网格尺寸: %d × %d\n', I, J);
fprintf('  帧范围: %d - %d (共%d帧)\n', frame_start, frame_end, nFrames);
fprintf('  源文件: B%04d.dat - B%04d.dat\n', ...
    frame_start + frame_offset, frame_end + frame_offset);
fprintf('  分块大小: %d帧/批\n', chunk_size);

% --- 预分配存储数组 ---
U_all = zeros(nFrames, J, I);
V_all = zeros(nFrames, J, I);
sample_valid = false(nFrames, J, I);

% --- 先读第一帧获取坐标网格和矢量间距h ---
[X, Y, ~, ~, isValid, h] = read_single_dat( ...
    data_root, frame_start, I, J, frame_offset);

% --- 分块循环读取所有帧 ---
n_chunks = ceil(nFrames / chunk_size);
fprintf('开始分块读取数据...\n');

for ic = 1:n_chunks
    idx_start = (ic-1)*chunk_size + 1;
    idx_end = min(ic*chunk_size, nFrames);
    frame_idx_global = frame_start + idx_start - 1 : frame_start + idx_end - 1;

    fprintf('  批次 %d/%d: 帧 %d-%d（源文件 B%04d-B%04d）\n', ...
        ic, n_chunks, frame_idx_global(1), frame_idx_global(end), ...
        frame_idx_global(1) + frame_offset, ...
        frame_idx_global(end) + frame_offset);

    for i = 1:length(frame_idx_global)
        iframe = frame_idx_global(i);
        [~, ~, Ux, Uy, valid_frame, ~] = ...
            read_single_dat(data_root, iframe, I, J, frame_offset);
        % 与参考Comparison_Re30w_AoA2.m最终口径一致：翻转J索引后，
        % 正V指向离壁方向。这里不再预先对Uy加负号。
        U_all(idx_start + i - 1, :, :) = Ux;
        V_all(idx_start + i - 1, :, :) = Uy;
        sample_valid(idx_start + i - 1, :, :) = ...
            valid_frame ~= 0 & isfinite(Ux) & isfinite(Uy);
    end
end

% --- 坐标方向：使壁面在数组 idx=1 ---
% 原始DaVis数据中y从大到小排列（顶部→底部）。历史数据壁面在底部，
% 翻转后y从小到大（壁面→外区）；Export0731 数据壁面在顶部，保持原始
% 行序并把 V 取负，使两种方向下正V都指向离壁方向。
if strcmp(wall_side, 'bottom')
    field.X = flip(X, 1);
    field.Y = flip(Y, 1);
    field.U = flip(U_all, 2);                   % 沿J维度翻转
    field.V = flip(V_all, 2);                   % 正V：离壁方向
    field.sampleValid = flip(sample_valid, 2);  % 每帧、每点有效性
    field.isValid = flip(isValid, 1);
else
    field.X = X;
    field.Y = Y;
    field.U = U_all;
    field.V = -V_all;                               % 正V：离壁方向
    field.sampleValid = sample_valid;
    field.isValid = isValid;
end
field.h = h;
field.nFrames = nFrames;

fprintf('数据加载完成！矢量间距 h = %.6f mm\n', h);

% --- 检测并裁掉壁面侧无效（mask）行 ---
% PIV mask 区域（真实壁面以下）表现为 U=V=0 或 isValid=0。
% 壁面平直 → n_removed 沿 x 恒定。用共享工具函数检测。
% Y 坐标数值不动——真实壁面 y=0 在 field.Y(1,:) 更下方，
% 由 loglaw 的 dy 或画图约定（plot_dy_h）处理。
if isempty(force_j_wall_removed)
    n_removed = tblR2.io.detect_wall_rows( ...
        data_root, frame_start, frame_end, I, J, frame_offset, wall_side);
else
    n_removed = force_j_wall_removed;
    if n_removed >= J - 10
        error('tblR2:io:load_tecplot_dat:WallCropTooLarge', ...
            '指定的壁面裁剪 n_removed=%d 距离 J=%d 太近。', ...
            n_removed, J);
    end
    fprintf('load_tecplot_dat: forced wall crop n_removed = %d\n', n_removed);
end

if n_removed > 0
    field.X = field.X(n_removed+1:end, :);
    field.Y = field.Y(n_removed+1:end, :);
    field.U = field.U(:, n_removed+1:end, :);
    field.V = field.V(:, n_removed+1:end, :);
    field.sampleValid = field.sampleValid(:, n_removed+1:end, :);
    field.isValid = field.isValid(n_removed+1:end, :);
    fprintf('load_tecplot_dat: 裁后 J = %d，源最小 y = %.3f mm\n', ...
            size(field.Y, 1), field.Y(1, 1));
end

% --- 壁面起算坐标重映射：第一保留行 y = 0 + h，逐行 +h ---
% 周期流程开启（remap_y_to_wall=true）：源数据 y 数值与物理方向相反
% （y 最大值的一侧是壁面），裁掉壁面侧恒零无效行后，把 Y 重写为
% 壁面 y=0 起算的测量坐标——第一保留行 y = 0 + h（h 为 y 方向矢量间距），
% 之后每行 +h。壁面在数组 idx=1（y 最小），预览与云图不再需要反转 y 轴。
% 默认 false 保持历史单 case 流程口径：Y 数值不动，仅裁剪行。
field.y_remapped = false;
if remap_y_to_wall
    n_rows = size(field.Y, 1);
    h_y = median(abs(diff(field.Y(:, 1))), 'omitnan');
    if ~(isfinite(h_y) && h_y > 0)
        error('tblR2:io:load_tecplot_dat:InvalidYSpacing', ...
            ['无法将 Y 重映射为壁面距离：裁剪网格没有有限正的 y 间距 ' ...
             '（h_y = %.6g）。'], h_y);
    end
    field.Y = repmat(((1:n_rows)' .* h_y), 1, size(field.Y, 2));
    field.y_remapped = true;
    field.h_y_mm = h_y;
    fprintf(['load_tecplot_dat: Y 已重映射为壁面距离（第一保留行 ' ...
        'y = 0 + h = %.4f mm，步长 %.4f mm，共 %d 行）\n'], ...
        h_y, h_y, n_rows);
end

field.j_wall_removed = n_removed;
field.y_min_kept = field.Y(1, 1);

end


% =========================================================================
% 内部函数：读取单个dat文件
% =========================================================================
function [X, Y, Vx, Vy, Isvalid, h] = read_single_dat( ...
    data_root, iframe, I, J, frame_offset)
% READ_SINGLE_DAT 读取单个B%04d.dat文件
% 输入：
%   data_root - 文件夹路径
%   iframe    - 帧号
%   I, J      - 网格尺寸
% 输出：
%   X, Y      - 坐标矩阵 (J×I)
%   Vx, Vy    - 速度矩阵 (J×I)
%   Isvalid   - 有效性掩码 (J×I)
%   h         - 矢量间距 [mm]

% 构造完整文件路径，B%04d.dat格式（如B0001.dat）
filename = fullfile(data_root, sprintf('B%04d.dat', iframe + frame_offset));

if ~exist(filename, 'file')
    error('tblR2:io:load_tecplot_dat:MissingFile', ...
        '输入文件不存在：%s。', filename);
end

% --- 跳过Tecplot文件头（4行）后读取数据（5列：x, y, u, v, isValid）---
% 头部格式示例：
%   TITLE = "B0001"
%   VARIABLES = "x [mm]", "y [mm]", "Velocity u [m/s]", "Velocity v [m/s]", "isValid"
%   ZONE T="Frame 0", I=640, J=98, F=POINT
%   STRANDID=1, SOLUTIONTIME=0.40085523
% fileread 一次性整读整文件（减少逐帧 fopen/fgetl 的文件流与网络往返开销），
% 再由 textscan 从字符向量解析；HeaderLines 跳过 4 行头，CollectOutput 合并成 N×5。
chr = fileread(filename);
data = textscan(chr, '%f%f%f%f%f', ...
    'HeaderLines', 4, 'CollectOutput', 1);
data = data{1};

% --- 重塑为2D矩阵 (J×I) ---
% Tecplot POINT格式：x方向先变化，再y方向；reshape需要先(I, J)再转置
X_vec = data(:, 1);
Y_vec = data(:, 2);
Vx = (reshape(data(:, 3), I, J))';        % 转置使尺寸为J×I
Vy = (reshape(data(:, 4), I, J))';
Isvalid = (reshape(data(:, 5), I, J))';

% 坐标网格
X = reshape(X_vec, I, J)';
Y = reshape(Y_vec, I, J)';

% --- 自动计算矢量间距h ---
% 从第一行X坐标的相邻间距均值得到
dx = diff(X(1, :));
h = mean(dx(dx > 0));
end
