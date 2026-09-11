function BL = integral_params(Uavex, X, Y, h, dy_mm, n_top)
% INTEGRAL_PARAMS 边界层积分参数（v5：Uinf局部化改为顶N点均值"做法B"）
% ========================================================================
% 【v5 变化（Uinf局部化"做法B"，与 loglaw_fit_chen.m 统一口径）】
%   真实数据验证发现 v4 的 Uinf=ux_y(end)（剖面顶点单点）在测量域末端 FOV 边缘
%   退化列上可能取到接近0的值，导致 theta 除以 U99^2 数值爆炸。改为顶N点均值
%   （tblR2.bl.local_uinf，N=n_top，通常取 cfg.U_inf_n_top，默认5），用38个真实
%   case实测评估确认：多数case几乎零影响，少数受控工况改善明显，H基本不受影响。
%
% 【v4 变化（TBL_logfit 一致性改造，除 Uinf 局部化外仍适用）】
%   与陈朗生 TBL_logfit.m 完全一致的公式，废弃 v3 的以下自创逻辑：
%     - δ99 线性插值           → chen: delta=(dH+round(dy/h))*h，dH=首个 u>U99
%     - Spalding 盲区填充+trapz → chen: 近壁 round(dy/h) 个线性虚拟点 + 求和式积分
%     - fzero 反演 u_tau       → 不需要（虚拟点是 0→u1 线性）
%     - rloess 平滑            → chen 无平滑，原样输出
%
% 【chen 公式（TBL_logfit.m:59-98，Uinf 一项已按上述 v5 改为顶N点均值）】
%   ux_y(ux_y==0)=[];  Uinf=local_uinf(ux_y,n_top);  U99=0.99*Uinf
%   dH=find(u>U99,1,'first');  delta=(dH+round(dy/h))*h
%   u_new=[linspace(0,u1,r+1)(2:end); ux_y]  （r=round(dy/h)，末虚拟点与实测
%                                             首点重复一次，按 chen 原样保留）
%   delta_star=sum((1-u_new(1:dH+r)/U99)*h)
%   theta=sum(u_new(1:dH+r).*(U99-u_new(1:dH+r))*h)/U99^2
%   H=delta_star/theta
%
% 【输入】
%   Uavex - 时间平均U速度场 (J×I) [m/s]
%   X, Y  - 坐标 (J×I) [mm]（Y 仅保留签名兼容，chen 算法用等间距 h 重构）
%   h     - 矢量间距 [mm]
%   dy_mm - 最近壁矢量距壁面的物理距离 [mm]（来自 loglaw 拟合 LF.dy_opt；
%           缺省 2*h，即 chen 脚本手动默认 dy=2h）
%   n_top - Uinf局部化取剖面顶N点均值（见 tblR2.bl.local_uinf）；缺省5，通常
%           调用方应显式传 cfg.U_inf_n_top
%
% 【输出】BL.delta99/delta_star/theta/H/Uinf_local/x [mm 系]，BL.dy_mm_used
% ========================================================================

if nargin < 5 || isempty(dy_mm)
    dy_mm = 2 * h;   % chen 脚本默认 dy=2*h
end
if nargin < 6 || isempty(n_top)
    n_top = 5;   % 与 cfg.U_inf_n_top 默认一致；调用方应显式传 cfg.U_inf_n_top
end

[~, I] = size(Uavex);
r = round(dy_mm / h);       % chen: round(dy/h)
if r < 1, r = 1; end

fprintf('边界层积分参数计算开始（v5 chen 算法 + Uinf顶%d点均值, dy=%.3f mm = %.2fh）...\n', n_top, dy_mm, dy_mm/h);

delta99    = nan(1, I);
delta_star = nan(1, I);
theta      = nan(1, I);
Uinf_local = nan(1, I);

for col = 1:I
    ux_y = Uavex(:, col);
    % chen: ux_y(ux_y==0)=[]；PIV 掩膜区另有 NaN，一并剔除
    ux_y(ux_y == 0 | isnan(ux_y)) = [];
    if numel(ux_y) < 5
        continue;
    end

    Uinf_loc = tblR2.bl.local_uinf(ux_y, n_top);   % v5: 顶N点均值（"做法B"，见 local_uinf.m）
    if Uinf_loc <= 0
        continue;
    end
    Uinf_local(col) = Uinf_loc;
    U99 = 0.99 * Uinf_loc;

    % δ99：chen dH = 首个 u>U99 的索引（u_flag==0 first）
    dH = find(ux_y > U99, 1, 'first');
    if isempty(dH)
        continue;   % 剖面未达 0.99·Uinf，该列不计
    end
    delta99(col) = (dH + r) * h;   % mm

    % 近壁线性虚拟点：0→u1 共 r+1 点去掉 0（末点=u1，与实测首点重复，chen 原样）
    u1 = ux_y(1);
    u_virt = linspace(0, u1, r + 1)';
    u_virt = u_virt(2:end);
    u_new = [u_virt; ux_y];

    iu = min(dH + r, numel(u_new));                                         % chen 积分上限 dH+r
    delta_star(col) = sum(1 - u_new(1:iu)/U99) * h;                         % mm
    theta(col)      = sum(u_new(1:iu) .* (U99 - u_new(1:iu))) * h / U99^2;  % mm
end

% 形状因子（chen: H=delta_star/theta，无过滤无平滑）
H = delta_star ./ theta;

BL.delta99    = delta99;
BL.delta_star = delta_star;
BL.theta      = theta;
BL.H          = H;
BL.Uinf_local = Uinf_local;
BL.x          = X(1, :);
BL.dy_mm_used = dy_mm;

fprintf('边界层积分参数计算完成（chen v5）！\n');
fprintf('  δ99 中值: %.2f mm\n', median(delta99, 'omitnan'));
fprintf('  δ* 中值: %.2f mm\n', median(delta_star, 'omitnan'));
fprintf('  θ 中值: %.2f mm\n', median(theta, 'omitnan'));
fprintf('  H 中值: %.3f\n', median(H, 'omitnan'));

end
