function [y, u, cols_used] = extract_velocity_profile(Uavex, X, Y, h, mode, params)
% EXTRACT_VELOCITY_PROFILE 从时间平均速度场提取速度剖面
% ========================================================================
% 【功能】
%   从时间平均的U速度场Uavex中提取沿壁面法向（y方向）的速度剖面
%   支持三种提取模式：
%       'fixed'     - 单个流向位置（指定x_loc）
%       'multi_avg' - 多个流向位置平均（指定x_locs数组）
%       'range_avg' - 流向范围内所有点平均（指定x_range）
%
% 【输入参数】
%   Uavex  - 时间平均U速度场，矩阵 (J×I) [m/s]
%            J = 法向网格数（典型98），I = 流向网格数（典型640）
%   X      - X坐标矩阵 (J×I) [mm]
%   Y      - Y坐标矩阵 (J×I) [mm]
%   h      - 矢量间距 [mm]
%   mode   - 字符串，提取模式：
%            'fixed' | 'multi_avg' | 'range_avg'
%   params - 模式参数：
%            mode='fixed':     标量，单个流向位置 [mm]
%                              例如 165 表示x=165mm处
%            mode='multi_avg': 向量，多个流向位置 [mm]
%                              例如 [100, 165, 250] 在3个位置提取后平均
%            mode='range_avg': 双元素向量 [x_min, x_max] [mm]
%                              例如 [100, 200] 在该范围所有列平均
%
% 【输出】
%   y - 壁面法向坐标 [mm]，列向量
%   u - 对应的U速度 [m/s]，列向量
%       NaN和0值已被过滤
%
% 【使用示例】
%   % 方式1：固定位置
%   [y, u] = extract_velocity_profile(Uavex, X, Y, h, 'fixed', 165);
%
%   % 方式2：多位置平均（推荐用于log-law拟合）
%   [y, u] = extract_velocity_profile(Uavex, X, Y, h, 'multi_avg', [100,165,250]);
%
%   % 方式3：范围平均
%   [y, u] = extract_velocity_profile(Uavex, X, Y, h, 'range_avg', [100, 200]);
%
% 【关于模式选择】
%   - 'fixed':     单点剖面，受局部噪声影响，但反映实际流向变化
%   - 'multi_avg': 折中方案，几个代表性位置平均，降低噪声
%   - 'range_avg': 大量位置平均，统计稳定性最佳，但掩盖流向发展
%   实际应用中推荐先用 'multi_avg' 配合 [0.3L, 0.5L, 0.7L] 的位置
%
% 【注意事项】
%   - 函数假设流场沿流向接近平移不变（适用于平板边界层）
%   - 对于不同位置δ99差异>20%的情况，多位置平均可能引入偏差
% ========================================================================

[J, I] = size(Uavex);   % J=法向, I=流向

switch lower(mode)
    % --- 模式1：固定位置提取 ---
    case 'fixed'
        x_loc = params;     % 标量，目标x位置

        % 在X坐标中查找最接近的列
        x_vec = X(1, :);    % 取第一行作为X坐标向量（假设所有行X相同）
        [~, col_idx] = min(abs(x_vec - x_loc));

        y = Y(:, col_idx);
        u = Uavex(:, col_idx);
        cols_used = col_idx;

        fprintf('提取模式: 固定位置\n');
        fprintf('  目标位置: x = %.2f mm\n', x_loc);
        fprintf('  实际位置: x = %.2f mm (列 %d)\n', x_vec(col_idx), col_idx);

    % --- 模式2：多位置平均 ---
    case 'multi_avg'
        x_locs = params;            % 向量，多个目标位置
        n_locs = length(x_locs);

        % 找到每个目标位置对应的列索引
        x_vec = X(1, :);
        col_indices = zeros(1, n_locs);
        for i = 1:n_locs
            [~, col_indices(i)] = min(abs(x_vec - x_locs(i)));
        end

        % 在指定列范围内对U进行平均
        U_profiles = Uavex(:, col_indices);
        u = mean(U_profiles, 2);   % 沿列方向求均值
        y = Y(:, col_indices(1));  % 假设Y坐标相同，取第一列即可
        cols_used = col_indices;

        fprintf('提取模式: 多位置平均\n');
        fprintf('  位置数量: %d\n', n_locs);
        fprintf('  位置范围: x = [%.2f, %.2f] mm\n', ...
                x_vec(col_indices(1)), x_vec(col_indices(end)));

    % --- 模式3：范围平均 ---
    case 'range_avg'
        x_range = params;   % [x_min, x_max]
        x_min = x_range(1);
        x_max = x_range(2);

        % 找到范围内的所有列
        x_vec = X(1, :);
        col_mask = (x_vec >= x_min) & (x_vec <= x_max);
        col_indices = find(col_mask);

        if isempty(col_indices)
            error('tblR2:io:extract_velocity_profile:EmptyRange', ...
                '指定范围内没有数据点：x ∈ [%.2f, %.2f] mm。', x_min, x_max);
        end

        % 平均所有满足条件的列
        U_profiles = Uavex(:, col_indices);
        u = mean(U_profiles, 2);
        y = Y(:, col_indices(1));
        cols_used = col_indices;

        fprintf('提取模式: 范围平均\n');
        fprintf('  指定范围: x ∈ [%.2f, %.2f] mm\n', x_min, x_max);
        fprintf('  实际范围: x ∈ [%.2f, %.2f] mm\n', ...
                x_vec(col_indices(1)), x_vec(col_indices(end)));
        fprintf('  平均列数: %d\n', length(col_indices));

    otherwise
        error('tblR2:io:extract_velocity_profile:UnknownMode', ...
            '未知的提取模式：%s。可选模式为 fixed、multi_avg、range_avg。', mode);
end

% --- 过滤无效数据 ---
% 移除NaN值，确保后续log-law拟合等步骤数据干净
valid_mask = ~isnan(u) & ~isnan(y);
y = y(valid_mask);
u = u(valid_mask);

fprintf('  有效点数: %d\n', length(y));
end
