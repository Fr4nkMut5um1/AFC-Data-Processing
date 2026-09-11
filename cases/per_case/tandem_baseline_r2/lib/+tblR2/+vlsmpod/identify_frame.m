function identified = identify_frame(ctx, field, resolved)
%IDENTIFY_FRAME 单帧 identify_structures + 可选流向合并，返回完整结果。
%
% 数值核心不动：tblR2.identify_structures / tblR2.vlsm.merge_streamwise_neighbors
% 都是字节不变的既有函数。本函数只负责把 frame_field 的输出接到它们的签名上——
% 这段接线原先在 run_structure_pod_denoise.m 的主循环里，现在收成一个可单测的
% 函数，供三个新功能扩展在其之上叠加。
%
% 输入
%   ctx      : tblR2.vlsmpod.prepare_context 的输出
%   field    : tblR2.vlsmpod.frame_field 的输出
%   resolved : tblR2.vlsmpod.resolve_settings 的输出
%
% 输出 identified 结构体（与 tblR2.identify_structures 的返回字段一致，
% 外加合并相关字段）
%   .structures        table，合并生效时是合并后的
%   .positive_labels    合并生效时为空（原始标签图对合并后的 ID 已不对应，
%                        避免误用；下游需要标签图时应在合并前调用）
%   .negative_labels    同上
%   .merge_applied      logical
%   .merge_log          合并生效时的日志；否则为空结构体
%   （其余字段照抄 tblR2.identify_structures 的输出：normalized_field、
%    analysis_mask、threshold_*_mask、growth_*_mask、seed_*_mask、
%    positive_mask、negative_mask、options、topology_cleanup、
%    rejected_aspect_ratio_count、rejected_trusted_boundary_count、
%    trusted_boundary_mask、method）

raw = tblR2.identify_structures(field.u_fluct, ctx.u_rms, ctx.X_mm, ...
    ctx.Y_wall_mm, ctx.delta_grid, field.mask, resolved.opts);

identified = raw;
identified.merge_applied = false;
identified.merge_log = struct();

if resolved.merge_enabled && height(raw.structures) > 0
    [merged_table, merge_log] = tblR2.vlsm.merge_streamwise_neighbors( ...
        raw.structures, raw.positive_labels, raw.negative_labels, ...
        ctx.X_mm, ctx.Y_wall_mm, ctx.delta_grid, ctx.dx_mm, ctx.dy_mm, ...
        field.u_fluct, resolved.merge_opts);
    identified.structures = merged_table;
    identified.merge_applied = true;
    identified.merge_log = merge_log;
    % 合并会重编 StructureID，原始标签图不再与合并后的行对应；置空防止误用。
    identified.positive_labels = [];
    identified.negative_labels = [];
end
end
