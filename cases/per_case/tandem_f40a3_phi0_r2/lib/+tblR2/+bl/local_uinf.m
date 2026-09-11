function Uinf = local_uinf(u_valid, n_top)
% LOCAL_UINF 剖面（已清洗0/NaN）顶N点均值，作局部势流速度Uinf估计（"做法B"）
% ========================================================================
% 【背景】
%   单点剖面顶点值（原做法：ux_y(end) / u_valid(end)）对PIV噪声/FOV边缘伪影
%   敏感：测量域末端退化列上可能取到接近0的值，导致下游除以Uinf^2的量
%   （如theta、delta_star）数值爆炸。用38个真实case实测评估确认：顶N点均值
%   对多数工况几乎零影响，对少数受控工况（强激励导致剖面顶部有起伏）改善明显，
%   且对N取3或5不敏感（结论无实质差异）。
%
%   本函数供 tblR2.bl.integral_params 与 tblR2.bl.loglaw_fit_chen 共用同一算法，
%   避免两处独立实现（原两处各自写 ux_y(end) / u_valid(end)，现已统一于此）。
%
% 【输入】
%   u_valid - 已剔除0/NaN的速度剖面（列或行向量），语义上按y从壁面到剖面顶排列
%   n_top   - 取顶N点均值，通常传 cfg.U_inf_n_top（默认5）；超过剖面点数时
%             自动clamp到剖面点数
%
% 【输出】
%   Uinf - 顶N点均值 [m/s]；u_valid为空时返回NaN
%
% 【实现说明】
%   用 maxk 取值（而非直接取末尾N点），不依赖调用方是否严格按y排序，更稳健。
% ========================================================================
    n = min(n_top, numel(u_valid));
    if n < 1
        Uinf = NaN;
        return;
    end
    Uinf = mean(maxk(u_valid, n));
end
