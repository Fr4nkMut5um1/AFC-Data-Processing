function [U, V] = pod_denoise_reconstruct_frame(denoise, frame_id, mode_indices)
%POD_DENOISE_RECONSTRUCT_FRAME 按需重构单帧 POD 去噪瞬时场。
%
% 与 +tblR2/pod_reconstruction.m 的分工：
%   - pod_reconstruction        : 面向绘图与残差诊断，返回 raw/残差/相对误差
%     等一整套字段，工作在窄 ROI 的采样网格上。
%   - pod_denoise_reconstruct_frame : 面向逐帧结构识别，只返回全网格 U/V，
%     不读原始数据、不算残差。设计成可在 12000 次循环里反复调用。
%
% 重构式：
%   snapshot = Phi_trunc(:, idx) * A_trunc(idx, k) + mean_snapshot
% 其中 mean_snapshot 是**全局集成均值**。返回的是物理速度场（含均值），
% 调用方仍需按自己的分支均值去均值后再做阈值判定。
%
% 输入
%   denoise      : pod_denoise_prepare 的输出。
%   frame_id     : 帧号（denoise.frame_ids 中的值，不是位置下标）。
%   mode_indices : 可选。默认用全部 1:denoise.rank。路径 B 的低阶诊断
%                  通过它传入 1:r_low 来取更低阶的子集。
%
% 输出
%   U, V : [J × I] double，掩膜外为 NaN。

if nargin < 3 || isempty(mode_indices)
    mode_indices = 1:denoise.rank;
end
mode_indices = double(mode_indices(:).');
if any(~isfinite(mode_indices) | mode_indices < 1 | ...
        mode_indices > denoise.rank | mode_indices ~= fix(mode_indices))
    error('tblR2:pod_denoise_reconstruct_frame:InvalidModeIndices', ...
        'mode_indices 必须是 1 到 rank=%d 之间的整数。', denoise.rank);
end

% frame_id 是缓存里的绝对帧号，A_trunc 的列却按 frame_ids 的顺序排列，
% 必须查表转成列位置，不能直接拿 frame_id 当下标。
position = find(denoise.frame_ids == frame_id, 1, 'first');
if isempty(position)
    error('tblR2:pod_denoise_reconstruct_frame:FrameNotInBasis', ...
        '帧 %d 不在 POD 基底的帧集合内。', frame_id);
end

snapshot = denoise.Phi_trunc(:, mode_indices) * ...
    denoise.A_trunc(mode_indices, position) + denoise.mean_snapshot;

n_spatial = denoise.n_spatial;
J = denoise.grid_size(1);
I = denoise.grid_size(2);
linear_mask = denoise.spatial_mask(:);

U = nan(J, I);
V = nan(J, I);
U(linear_mask) = snapshot(1:n_spatial);
V(linear_mask) = snapshot(n_spatial + 1:end);
end
