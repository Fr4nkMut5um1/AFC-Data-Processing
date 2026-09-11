function Cf = cfnum_to_cf(Cfnum)
% CFNUM_TO_CF 由 Cf_chart 曲线序号 Cfnum 换算摩擦系数 Cf
% ========================================================================
% 【映射语义（陈朗生 Cf_chart.txt 参考曲线族）】
%   Cfnum = 0  → 顶部曲线 Cf = CF_TOP  = 5e-3
%   Cfnum = 24 → 底部曲线 Cf = 2e-4
%   Cf = CF_TOP - CF_STEP * Cfnum，Cfnum 单调增 → Cf 单调减
%   Cfnum 允许为分数（如 10.3），对应两根整数曲线之间的插值 Cf
%
% 【输入】
%   Cfnum - 标量或数组，Cf_chart 曲线序号（0..24，可为分数）
%
% 【输出】
%   Cf    - 对应摩擦系数，与 Cfnum 同尺寸
%
% 【常量唯一来源】
%   CF_TOP/CF_STEP 在本文件与 cf_to_cfnum.m 各定义一次，是全项目
%   Cf↔Cfnum 换算的单一真值来源，替换原先散落 6 处的硬编码公式。
% ========================================================================
    CF_TOP  = 5e-3;  % Cfnum=0 顶部曲线 Cf
    CF_STEP = 2e-4;  % 相邻整数 Cfnum 的 Cf 步长
    Cf = CF_TOP - CF_STEP * Cfnum;
end
