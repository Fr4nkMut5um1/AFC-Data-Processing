function y_ref = interp_cf_curve(Cf_query, x_query, chart)
% INTERP_CF_CURVE 在 Cf_chart 相邻曲线之间插值得到任意 Cf 对应的参考曲线
% ========================================================================
% 【功能】
%   给定实数 Cf_query（可以是 Cf_chart 里没有的精确值），
%   在两根相邻曲线之间做加权平均得到 y_ref(x_query)。
%
% 【步骤】
%   1) 找 Cfnum_low, Cfnum_high 使 Cf_low >= Cf_query >= Cf_high
%      （Cf 单调递减 → Cfnum 单调递增；low/high 指 Cf 值高低）
%   2) 权重 w = (Cf_query - Cf_high) / (Cf_low - Cf_high)
%      Cf_query 靠近 Cf_low → w=1；靠近 Cf_high → w=0
%   3) 对每个 x_query：
%        y_low  = interp1(curve_low.x,  curve_low.y,  x_query)
%        y_high = interp1(curve_high.x, curve_high.y, x_query)
%        y_ref  = w*y_low + (1-w)*y_high
%
% 【输入】
%   Cf_query - 标量，欲查询的 Cf 值（e.g. 3.4e-3）
%   x_query  - 1D 数组，欲查询的 x = y·U∞/ν
%   chart    - load_cf_chart() 返回的结构体
%
% 【输出】
%   y_ref    - 1D 数组，尺寸与 x_query 相同，参考 u/U∞
%
% 【边界】
%   Cf_query 越界（<Cf_min 或 >Cf_max）报错。
%   x_query 越界外推：interp1 默认 NaN，本函数会填 NaN 然后由残差函数
%   通过 mask 过滤掉。
% ========================================================================

    Cf_vals = chart.Cf_values;
    Cf_min = min(Cf_vals);
    Cf_max = max(Cf_vals);

    if Cf_query < Cf_min - eps || Cf_query > Cf_max + eps
        error('tblR2:bl:interp_cf_curve:OutOfRange', ...
            '查询的 Cf=%.4e 超出 Cf_chart 支持范围 [%.4e, %.4e]。', ...
            Cf_query, Cf_min, Cf_max);
    end

    % 找相邻两根曲线
    % Cf_values 从小到大排列（对1=Cf_min=2e-4=底部曲线；对25=Cf_max=5e-3=顶部）
    % 需要 Cf_low <= Cf_query <= Cf_high
    idx_low  = find(Cf_vals <= Cf_query, 1, 'last');   % 最靠近的较小 Cf
    idx_high = find(Cf_vals >= Cf_query, 1, 'first');  % 最靠近的较大 Cf

    if isempty(idx_low),  idx_low  = 1;                    end
    if isempty(idx_high), idx_high = length(Cf_vals);      end

    Cf_low  = Cf_vals(idx_low);
    Cf_high = Cf_vals(idx_high);

    if idx_low == idx_high
        % 恰好命中某根曲线
        w = 0.0;  % 全取 low（即 high，因为相同）
    else
        w = (Cf_query - Cf_low) / (Cf_high - Cf_low);  % w=0 靠近 low, w=1 靠近 high
    end

    % 对每个 x_query 做插值
    x_low = chart.x_cols{idx_low};
    y_low = chart.y_cols{idx_low};
    x_high = chart.x_cols{idx_high};
    y_high = chart.y_cols{idx_high};

    % 确保单调递增（陈朗生数据一般已排好，但保险起见）
    [x_low_s,  ord_l] = sort(x_low);   y_low_s  = y_low(ord_l);
    [x_high_s, ord_h] = sort(x_high);  y_high_s = y_high(ord_h);
    % 去重
    [x_low_s,  ord_l] = unique(x_low_s);   y_low_s  = y_low_s(ord_l);
    [x_high_s, ord_h] = unique(x_high_s);  y_high_s = y_high_s(ord_h);

    y_low_interp  = interp1(x_low_s,  y_low_s,  x_query, 'linear', NaN);
    y_high_interp = interp1(x_high_s, y_high_s, x_query, 'linear', NaN);

    y_ref = (1 - w) * y_low_interp + w * y_high_interp;
end
