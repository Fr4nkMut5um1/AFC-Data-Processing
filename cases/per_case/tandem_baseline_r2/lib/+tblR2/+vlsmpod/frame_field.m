function field = frame_field(ctx, frame_id, source)
%FRAME_FIELD 取单帧的脉动场 u'/v' 与结构掩膜。
%
% 两条预处理路径，输出口径完全一致——这是「只换了预处理」这个论断成立的前提。
%   pod_denoise : Phi_trunc*A_trunc(:,k) 一次矩阵-向量乘。全网格全分辨率。
%   gaussian    : raw 瞬时 -> 9x9 高斯 -> 减分支均值，复刻主管线路径。
%
% 去均值口径与主管线保持一致：用**分支均值**（repeat-specific），而不是 POD 基底
% 里的全局集成均值。两者之差是 O(0.05 m/s) 的系统偏差，远小于 alpha*u_rms 阈值。
%
% 输入
%   ctx      : tblR2.vlsmpod.prepare_context 的输出
%   frame_id : 缓存里的绝对帧号
%   source   : 结构体
%              .preprocessing : 'pod_denoise' | 'gaussian'
%              .denoise       : pod_denoise_prepare 的输出（pod_denoise 时必需）
%              .mode_indices  : 可选。默认用全部 1:denoise.rank。取前 r 阶做
%                               低能量档重构时传 1:r。
%              .cache_file    : 序列缓存路径（gaussian 时必需）
%
% 输出 field 结构体
%   .u_fluct        [J x I] 流向脉动，掩膜外 NaN
%   .v_fluct        [J x I] 法向脉动，掩膜外 NaN（超结构分解用）
%   .mask           [J x I] logical 结构识别有效域
%   .frame_id       帧号

preprocessing = char(source.preprocessing);
switch preprocessing
    case 'pod_denoise'
        if ~isfield(source, 'denoise') || isempty(source.denoise)
            error('tblR2:vlsmpod:frame_field:MissingBasis', ...
                'pod_denoise 需要 source.denoise（pod_denoise_prepare 的输出）。');
        end
        mode_indices = [];
        if isfield(source, 'mode_indices'); mode_indices = source.mode_indices; end
        [proc_U, proc_V] = tblR2.pod_denoise_reconstruct_frame( ...
            source.denoise, frame_id, mode_indices);
        % POD 重构场在整个 spatial_mask 上都有值，逐帧无效矢量在建基底时已补 0，
        % 所以这里直接用分析域掩膜，不再按帧筛 sampleValid。
        source_valid = ctx.analysis_domain_mask;

    case 'gaussian'
        if ~isfield(source, 'cache_file') || isempty(source.cache_file)
            error('tblR2:vlsmpod:frame_field:MissingCacheFile', ...
                'gaussian 需要 source.cache_file（序列缓存路径）。');
        end
        raw_chunk = tblR2.read_cache_chunk(source.cache_file, frame_id, ...
            1:ctx.J, 1:ctx.I, 'raw', [], []);
        raw_U = squeeze(raw_chunk.U);
        raw_V = squeeze(raw_chunk.V);
        raw_valid = ctx.valid_mask & squeeze(raw_chunk.sampleValid);
        processed = tblR2.preprocess_structure_velocity(raw_U, raw_V, ...
            raw_valid, ctx.analysis_domain_mask, ctx.resolved.preprocess_spec);
        proc_U = processed.U;
        proc_V = processed.V;
        source_valid = processed.output_valid_mask;

    otherwise
        error('tblR2:vlsmpod:frame_field:InvalidPreprocessing', ...
            'preprocessing 必须是 pod_denoise 或 gaussian，当前为 %s。', ...
            preprocessing);
end

[mean_U, mean_V] = branch_mean(ctx.stats, frame_id, 1:ctx.J, 1:ctx.I);

mask = source_valid & isfinite(proc_U) & isfinite(proc_V) & ...
    isfinite(mean_U) & isfinite(mean_V);
u_fluct = proc_U - mean_U;
v_fluct = proc_V - mean_V;
u_fluct(~mask) = NaN;
v_fluct(~mask) = NaN;

field = struct();
field.u_fluct = u_fluct;
field.v_fluct = v_fluct;
field.mask = mask;
field.frame_id = frame_id;
field.preprocessing = preprocessing;
end

% =========================================================================
function [mean_U, mean_V] = branch_mean(stats, frame_id, row_ids, col_ids)
%BRANCH_MEAN 与 structure_analysis_cache 同口径的分支均值。
% 双 repeat 数据用各自 repeat 的均值；单 repeat 退回全局均值。用错会在 repeat
% 边界两侧引入伪脉动。

if isfield(stats, 'repeat_means') && ~isempty(stats.repeat_means) && ...
        isfield(stats, 'repeat_boundaries') && ~isempty(stats.repeat_boundaries)
    rep = 1 + sum(frame_id > double(stats.repeat_boundaries(:).'));
    mean_U = squeeze(stats.repeat_means(1, rep, row_ids, col_ids));
    mean_V = squeeze(stats.repeat_means(2, rep, row_ids, col_ids));
else
    mean_U = squeeze(stats.Uavex(row_ids, col_ids));
    mean_V = squeeze(stats.Vavex(row_ids, col_ids));
end
end
