function chart = load_cf_chart()
% LOAD_CF_CHART 读取陈朗生 Cf_chart.txt 参考曲线族（公开包函数 tblR2.bl.load_cf_chart）
% ========================================================================
% 【功能】
%   Cf_chart.txt 位于 +tblR2/+bl/data/，格式 = 交替 (x, y) 列，
%   每对 (x_col, y_col) 对应一根参考曲线：
%     x = y·U∞/ν
%     y = u/U∞
%   Cfnum = 0, 1, 2, ...（从左到右）
%   Cf = tblR2.bl.cfnum_to_cf(Cfnum)（顶部 5e-3 → 底部 2e-4）
%
% 【处理】
%   - 删除所有元素都是 NaN 的列（对应 TBL_logfit.m:27-29）
%   - 用 persistent 缓存，避免重复读；缓存带文件 mtime 校验，
%     调试期修改 Cf_chart.txt 会自动重读（解决改文件不生效的坑）
%
% 【输出结构】
%   chart.x_cols     - cell array, x_cols{k} = 第 k 根曲线的 x 序列
%   chart.y_cols     - cell array, y_cols{k} = 第 k 根曲线的 y 序列
%   chart.Cf_values  - 每根曲线的 Cf 值（1×n_curves）
%   chart.Cfnum      - 每根曲线的 Cfnum 值（1×n_curves）
%   chart.n_curves   - 曲线数
%
% 【历史】
%   原位于旧 +tbl/+bl/private/，本次改为公开包函数，供 +bl 与 +viz 共用，
%   消除 plot_loglaw_chen.m 里的重复本地副本。
% ========================================================================

    persistent cached_chart cached_datenum

    % 定位 Cf_chart.txt：本函数现直接位于 +bl 下，data 在 ./data/Cf_chart.txt
    this_file = mfilename('fullpath');
    bl_dir = fileparts(this_file);            % .../+bl
    txt_path = fullfile(bl_dir, 'data', 'Cf_chart.txt');

    if ~exist(txt_path, 'file')
        error('tblR2:bl:load_cf_chart:MissingChart', ...
            '未找到 Cf_chart.txt：%s。\n请确认已从陈朗生目录复制。', txt_path);
    end

    % mtime 校验：文件被改动时缓存失效
    finfo = dir(txt_path);
    cur_datenum = finfo.datenum;
    if ~isempty(cached_chart) && ~isempty(cached_datenum) ...
            && cached_datenum == cur_datenum
        chart = cached_chart;
        return;
    end

    raw = importdata(txt_path);
    % importdata 对纯数字返回矩阵；有些行 NaN，直接用 importdata 的返回

    % 删除全为 NaN 的列（陈朗生原 TBL_logfit.m 做法）
    all_nan_cols = all(isnan(raw), 1);
    Cf_c = raw(:, ~all_nan_cols);

    % 拆成 (x, y) 对
    n_pairs = size(Cf_c, 2) / 2;
    if mod(size(Cf_c, 2), 2) ~= 0
        error('tblR2:bl:load_cf_chart:InvalidColumnCount', ...
            'Cf_chart.txt 的有效列数 %d 不是偶数，文件格式异常。', ...
            size(Cf_c, 2));
    end

    x_cols = cell(1, n_pairs);
    y_cols = cell(1, n_pairs);
    for k = 1:n_pairs
        xk = Cf_c(:, 2*k-1);
        yk = Cf_c(:, 2*k);
        % 剔除单点 NaN 保留数值
        valid = ~isnan(xk) & ~isnan(yk);
        x_cols{k} = xk(valid);
        y_cols{k} = yk(valid);
    end

    % Cf_chart.txt 的列排列：从左往右是 y 值从小到大（底部曲线 → 顶部曲线）
    % 但陈朗生 Cfnum 定义为"从上往下数，首根 Cf 线计数为 0"（TBL_logfit.m title:
    % Cf_up=0.005, Cf_bottom=0.0002）
    % 所以 Cfnum=0 对应最右边的对（顶部/高 Cf），Cfnum=24 对应最左边（底部/低 Cf）
    Cfnum = (n_pairs-1):-1:0;               % 对1 → Cfnum=24, 对25 → Cfnum=0
    Cf_values = tblR2.bl.cfnum_to_cf(Cfnum);  % Cfnum=0 → Cf=5e-3 (顶部), Cfnum=24 → Cf=2e-4 (底部)

    chart.x_cols    = x_cols;
    chart.y_cols    = y_cols;
    chart.Cf_values = Cf_values;
    chart.Cfnum     = Cfnum;
    chart.n_curves  = n_pairs;

    cached_chart   = chart;
    cached_datenum = cur_datenum;
end
