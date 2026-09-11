function LF = loglaw_fit_chen(u_prof, y_mm, nu, Uinf, h_mm, cfg)
% LOGLAW_FIT_CHEN Clauser-method log-law fit (legacy filename retained).
% ========================================================================
% 【设计哲学】
%   Clauser模式以Cf为核心变量，u_tau = sqrt(Cf·Uinf²/2)；
%   Cf_chart.txt 提供 Cf↔Cfnum 映射（cfnum_to_cf）；
%   dy 是"最靠近壁面矢量距真实壁面"的物理距离。
%
%   【v5 改动】auto 模式从"Cf_chart 读图残差量化"改为"固定 dy 的 Clauser RMSE 法"：
%     - dy 固定 = cfg.loglaw_params.dy_h · h（所有 case 同一 dy，可比）
%     - 在 Cfnum ∈ [0,24] 步长 0.01 扫描，取 log-law RMSE（u+ vs 直线）最小的 Cfnum
%     - 不再有 dy/Cf 嵌套 fminbnd，不再有 bracket / *_cont 辅助字段
%
%   【v6 改动】RMSE评价范围由固定窗口改为用户可配置的y+区间：
%     - cfg.loglaw_rmse_yplus_range = [下限 上限]，默认建议[30 300]
%     - auto扫描中每个Cf候选用自身u_tau重新计算y+和区间成员
%     - 移除按“近壁点数”额外裁剪RMSE数据的旧参数
%
%   四档模式：
%     'auto'        - 固定 dy + Cfnum 扫描最小化 RMSE
%     'semi'        - 用户填 dy 和 Cfnum（inputdlg 由上层触发）
%     'manual'      - 用户填 kappa, B, dy, Cfnum
%     'manual_utau' - 用户填 kappa, B, dy, u_tau；完全跳过Cf寻优与Cfnum映射
%
% 【输入】
%   u_prof - 速度剖面 (m/s)，列向量
%   y_mm   - 剖面 y 坐标 (mm)，列向量（未加 dy 偏移的原始 PIV 位置）
%   nu     - 运动粘度 (m²/s)
%   Uinf   - 局部势流速度 (m/s)（仅作日志对照/回退；实际用顶N点均值口径，
%            见 cfg.U_inf_n_top / tblR2.bl.local_uinf）
%   h_mm   - 矢量间距 (mm)
%   cfg    - 结构体，需包含：
%              cfg.loglaw_mode ('auto'|'semi'|'manual'|'manual_utau')
%              Clauser模式参数：kappa, B, dy_h, Cfnum
%              manual_utau参数：kappa, B, dy_h, u_tau
%              cfg.loglaw_skip_nearwall       - 拟合截断近壁点数（默认0）
%              cfg.loglaw_rmse_yplus_range    - 计算RMSE的[y+下限,y+上限]
%              cfg.U_inf_n_top                - Uinf局部化顶N点均值（默认5）
%
% 【输出】
%   LF - 结构体，含 u_tau, Cf, Re_tau, delta99, delta_star, theta, H,
%        dy_opt, dy_h_opt, Cfnum_opt, Cf_opt, kappa, B, mode,
%        y_plus, u_plus, rmse_yplus_range, RMSE, R_squared,
%        converged, quality_flag
%          Cfnum_opt    - 最终 Cfnum；manual_utau中为NaN（未使用Cfnum）
%          quality_flag - ''=正常；'no_valid_residual'=auto 扫描 RMSE 全 NaN
% ========================================================================

    % --- 剔除 u==0 和 NaN（陈朗生第一步）---
    u_prof = u_prof(:);
    y_mm = y_mm(:);
    valid_pre = u_prof > 1e-6 & ~isnan(u_prof) & ~isnan(y_mm);
    u_valid = u_prof(valid_pre);

    % --- 剔除近壁点（拟合截断，可选，默认 0）---
    n_skip = 0;
    if isfield(cfg, 'loglaw_skip_nearwall') && cfg.loglaw_skip_nearwall > 0
        n_skip = min(cfg.loglaw_skip_nearwall, length(u_valid) - 10);
        if n_skip > 0
            u_valid = u_valid(n_skip+1:end);
            fprintf('    loglaw: 跳过近壁 %d 点，剩余 %d 点拟合\n', n_skip, length(u_valid));
        else
            n_skip = 0;
        end
    end

    % --- 用户指定的RMSE评价区间，单位为y+ ---
    % y+依赖候选u_tau，因此auto扫描时必须对每个Cfnum候选重新计算区间成员。
    rmse_yplus_range = resolve_rmse_yplus_range(cfg);

    if length(u_valid) < 10
        error('tblR2:bl:loglaw_fit_chen:InsufficientData', ...
            '对数律拟合的有效点数为 %d，小于所需的 10 个。', length(u_valid));
    end

    % --- Uinf（"做法B"口径）：清洗后剖面顶N点均值（v5，与 integral_params.m 统一）---
    Uinf_arg = Uinf;
    Uinf = tblR2.bl.local_uinf(u_valid, cfg.U_inf_n_top);
    if abs(Uinf - Uinf_arg) / max(abs(Uinf_arg), eps) > 0.05
        fprintf('    注意：顶N点均值 Uinf=%.4f 与传入 %.4f 相差 >5%%\n', Uinf, Uinf_arg);
    end

    % --- 模式分派 ---
    mode = cfg.loglaw_mode;
    params = cfg.loglaw_params;

    % 只有显式Cfnum输入模式需要预先读取Cf chart并检查映射边界。
    % auto模式在扫描函数中逐候选映射；manual_utau完全不触碰Cf chart。
    if any(strcmp(mode, {'semi', 'manual'}))
        chart = tblR2.bl.load_cf_chart();
        Cf_lb = min(chart.Cf_values);  % 2e-4
        Cf_ub = max(chart.Cf_values);  % 5e-3
    end

    quality_flag = '';
    converged = true;
    manual_u_tau = NaN;

    switch mode
        case 'auto'
            kappa = params.kappa;
            B     = params.B;
            % 固定 dy = dy_h · h（所有 case 同一 dy）
            dy_opt_mm = params.dy_h * h_mm;
            [Cfnum_opt, Cf_opt, converged, quality_flag, iter_info] = ...
                fit_auto_clauser(u_valid, h_mm, nu, Uinf, dy_opt_mm, ...
                                 kappa, B, n_skip, rmse_yplus_range);

        case 'semi'
            kappa = params.kappa;
            B     = params.B;
            dy_opt_mm = params.dy_h * h_mm;
            Cfnum_opt = params.Cfnum;
            Cf_opt = tblR2.bl.cfnum_to_cf(Cfnum_opt);
            if Cf_opt < Cf_lb || Cf_opt > Cf_ub
                error('tblR2:bl:loglaw_fit_chen:CfOutOfRange', ...
                      'semi 模式：Cfnum=%g 对应 Cf=%.4e 超出支持范围 [%.4e, %.4e]。', ...
                      Cfnum_opt, Cf_opt, Cf_lb, Cf_ub);
            end
            iter_info = struct('mode', 'semi_user_input');

        case 'manual'
            kappa = params.kappa;
            B     = params.B;
            dy_opt_mm = params.dy_h * h_mm;
            Cfnum_opt = params.Cfnum;
            Cf_opt = tblR2.bl.cfnum_to_cf(Cfnum_opt);
            if Cf_opt < Cf_lb || Cf_opt > Cf_ub
                error('tblR2:bl:loglaw_fit_chen:CfOutOfRange', ...
                    'manual 模式：Cfnum=%g 对应 Cf=%.4e 超出支持范围。', ...
                    Cfnum_opt, Cf_opt);
            end
            iter_info = struct('mode', 'manual_user_input');

        case 'manual_utau'
            required_fields = {'kappa', 'B', 'dy_h', 'u_tau'};
            for i_required = 1:numel(required_fields)
                if ~isfield(params, required_fields{i_required})
                    error('tblR2:bl:loglaw_fit_chen:MissingManualUtauParameter', ...
                        'manual_utau 模式需要 cfg.loglaw_params.%s。', ...
                        required_fields{i_required});
                end
            end
            validate_manual_utau_params(params);
            kappa = params.kappa;
            B = params.B;
            dy_opt_mm = params.dy_h * h_mm;
            manual_u_tau = params.u_tau;
            Cf_opt = 2 * (manual_u_tau / Uinf)^2;
            Cfnum_opt = NaN;
            iter_info = struct('mode', 'manual_utau_user_input', ...
                'u_tau_input', manual_u_tau, 'Cf_derived', Cf_opt);

        otherwise
            error('tblR2:bl:loglaw_fit_chen:UnknownMode', ...
                '未知的对数律模式：%s。', mode);
    end
    % 所有模式都记录实际使用的RMSE y+区间，便于缓存与结果审计。
    iter_info.rmse_yplus_range = rmse_yplus_range;

    % --- 计算派生物理量 ---
    % 注：auto 扫描 RMSE 全 NaN（quality_flag='no_valid_residual'）时 Cf_opt 为 NaN，
    % 以下派生量随之为 NaN，配合 converged=false 明确标记该 case 不可信。
    if strcmp(mode, 'manual_utau')
        u_tau = manual_u_tau;
    else
        u_tau = sqrt(Cf_opt * Uinf^2 / 2);
    end

    N = length(u_valid);
    % 剔除近壁 n_skip 点后，u_valid(1) 的物理 y = dy_opt + n_skip*h
    y_shifted_mm = ((1:N)' - 1 + n_skip) * h_mm + dy_opt_mm;
    y_shifted_m  = y_shifted_mm * 1e-3;

    % --- δ99 / δ* / θ / H：严格按陈朗生 TBL_logfit.m 公式 ---
    U99 = 0.99 * Uinf;
    dy_h_ratio = round(dy_opt_mm / h_mm) + n_skip;   % chen: round(dy/h)；skip 时补齐被剔近壁位
    if dy_h_ratio < 1, dy_h_ratio = 1; end
    dH = find(u_valid > U99, 1, 'first');
    if isempty(dH)
        dH = length(u_valid);
        warning('loglaw_fit_chen: 剖面未达 0.99·Uinf，δ99 取剖面顶端');
    end
    delta99_mm = (dH + dy_h_ratio) * h_mm;

    Re_tau = delta99_mm * 1e-3 * u_tau / nu;
    Cf_check = 2 * (u_tau / Uinf)^2;   % 应等于 Cf_opt

    % δ*/θ（chen）：近壁 round(dy/h) 个线性虚拟点（0→u1 去 0）+ 求和式积分
    u_first = u_valid(1);
    u_virt = linspace(0, u_first, dy_h_ratio + 1)';
    u_virt = u_virt(2:end);   % 排除 y=0（u=0）
    u_full = [u_virt; u_valid];
    idx_upper = min(dH + dy_h_ratio, length(u_full));
    delta_star_mm = sum((1 - u_full(1:idx_upper)/U99)) * h_mm;
    theta_mm      = sum(u_full(1:idx_upper) .* (U99 - u_full(1:idx_upper))) * h_mm / U99^2;
    H_shape = delta_star_mm / theta_mm;

    % --- 诊断量 + RMSE（使用用户指定y+区间，与auto优化目标同口径）---
    y_plus = y_shifted_m * u_tau / nu;
    u_plus = u_valid / u_tau;
    u_plus_theory = (1/kappa) * log(y_plus) + B;

    [RMSE, R_squared] = compute_loglaw_rmse(u_valid, y_shifted_m, u_tau, ...
                                            nu, kappa, B, rmse_yplus_range);

    % --- dy 合理性警告：固定 dy 下最优拟合仍偏大，提示该 case 可能不适合此 dy ---
    RMSE_WARN_THRESH = 0.5;   % 现有基线 RMSE ~0.4，超此值提示
    if strcmp(mode, 'auto') && converged && isfinite(RMSE) && RMSE > RMSE_WARN_THRESH
        fprintf(['    ⚠ dy 合理性：固定 dy=%.2fh 下最优 RMSE=%.3f > %.2f，' ...
                 '该 case 的 log-law 段可能不适合此 dy，建议人工核查\n'], ...
                dy_opt_mm / h_mm, RMSE, RMSE_WARN_THRESH);
    end

    % --- 打包 LF ---
    LF.mode        = mode;
    LF.u_tau       = u_tau;
    LF.Cf          = Cf_check;
    LF.Cf_opt      = Cf_opt;
    LF.Re_tau      = Re_tau;
    LF.delta99     = delta99_mm;
    LF.delta_star  = delta_star_mm;
    LF.theta       = theta_mm;
    LF.H           = H_shape;
    LF.dy_opt      = dy_opt_mm;
    LF.dy_h_opt    = dy_opt_mm / h_mm;
    LF.Cfnum_opt   = Cfnum_opt;      % 最终 Cfnum（两位小数）
    LF.quality_flag = quality_flag;  % ''=正常；'no_valid_residual'=auto 扫描 RMSE 全 NaN
    LF.kappa       = kappa;
    LF.B           = B;
    LF.y_plus      = y_plus;
    LF.u_plus      = u_plus;
    LF.u_plus_theory = u_plus_theory;
    LF.RMSE        = RMSE;
    LF.R_squared   = R_squared;
    LF.converged   = converged;
    LF.iter_info   = iter_info;
    LF.n_points    = length(u_valid);
    LF.n_skip      = n_skip;
    LF.rmse_yplus_range = rmse_yplus_range;
    % 为绘图保留输入
    LF.u_valid     = u_valid;
    LF.h_mm        = h_mm;
    LF.Uinf_used   = Uinf;
    LF.nu          = nu;
    % 保存剖面提取信息（用于图注）
    if isfield(cfg, 'profile_mode')
        LF.profile_mode = cfg.profile_mode;
    end
    if isfield(cfg, 'profile_params')
        LF.profile_params = cfg.profile_params;
    end

    % 日志
    if strcmp(mode, 'manual_utau')
        fprintf(['Clauser log-law option A [%s]: manual u_τ=%.4f m/s, derived Cf=%.5f, ' ...
                 'dy=%.2fh, RMSE=%.3f, δ99=%.2f mm, Re_τ=%.0f\n'], ...
                mode, u_tau, Cf_check, LF.dy_h_opt, RMSE, delta99_mm, Re_tau);
    else
        fprintf(['Clauser log-law option A [%s]: u_τ=%.4f m/s, Cf=%.5f, Cfnum=%.2f, ' ...
                 'dy=%.2fh, RMSE=%.3f, δ99=%.2f mm, Re_τ=%.0f\n'], ...
                mode, u_tau, Cf_check, LF.Cfnum_opt, LF.dy_h_opt, RMSE, ...
                delta99_mm, Re_tau);
    end
end


% =========================================================================
% RMSE 计算（log-law残差；评价区间由用户以y+指定）
% =========================================================================
function [RMSE, R_squared] = compute_loglaw_rmse(u_valid, y_shifted_m, u_tau, ...
                                                 nu, kappa, B, yplus_range)
% u+与log-law直线在用户给定y+闭区间内的均方根偏差。
% 每次调用都根据当前候选u_tau重新计算y+，因此auto扫描中不同Cf候选可能使用
% 不同的物理网格点。区间内有效点少于3个时返回NaN。

    y_plus = y_shifted_m * u_tau / nu;
    u_plus = u_valid / u_tau;
    u_plus_theory = (1/kappa) * log(y_plus) + B;

    in_win = isfinite(y_plus) & isfinite(u_plus) & isfinite(u_plus_theory) & ...
        (y_plus >= yplus_range(1)) & (y_plus <= yplus_range(2));
    idx = find(in_win);

    if numel(idx) >= 3
        res = u_plus(idx) - u_plus_theory(idx);
        RMSE = sqrt(mean(res.^2));
        SS_res = sum(res.^2);
        SS_tot = sum((u_plus(idx) - mean(u_plus(idx))).^2);
        if SS_tot > eps
            R_squared = 1 - SS_res / SS_tot;
        else
            R_squared = NaN;
        end
    else
        RMSE = NaN;
        R_squared = NaN;
    end
end


% =========================================================================
% Auto 模式：固定 dy，扫描 Cfnum 最小化 log-law RMSE（Clauser 法）
% =========================================================================
function [Cfnum_opt, Cf_opt, converged, quality_flag, iter_info] = ...
    fit_auto_clauser(u_valid, h_mm, nu, Uinf, dy_opt_mm, kappa, B, ...
                     n_skip, rmse_yplus_range)
% 固定 dy_opt_mm，在 Cfnum ∈ [0,24] 步长 0.01 扫描：
%   每个 Cfnum → Cf=cfnum_to_cf → u_tau=sqrt(Cf·U∞²/2) → compute_loglaw_rmse
%   取 RMSE 最小的 Cfnum（两位小数）。
%   全NaN防护：所有Cfnum的RMSE都NaN（剖面与用户指定y+区间不重叠）
%   → converged=false, quality_flag='no_valid_residual'，Cfnum/Cf 置 NaN。

    N = length(u_valid);
    % 固定 dy 下所有 Cfnum 共用同一 y 偏移
    y_shifted_m = (((1:N)' - 1 + n_skip) * h_mm + dy_opt_mm) * 1e-3;

    cfnum_grid = 0:0.01:24;                    % 2401 个候选
    rmse_grid = nan(size(cfnum_grid));
    for i = 1:numel(cfnum_grid)
        Cf = tblR2.bl.cfnum_to_cf(cfnum_grid(i));
        u_tau_i = sqrt(Cf * Uinf^2 / 2);
        rmse_grid(i) = compute_loglaw_rmse(u_valid, y_shifted_m, u_tau_i, ...
                                           nu, kappa, B, rmse_yplus_range);
    end

    quality_flag = '';
    if all(~isfinite(rmse_grid))
        warning(['loglaw_fit_chen: auto扫描所有Cfnum的RMSE全为NaN，' ...
                 '剖面与y+区间[%.3g, %.3g]不重叠或有效点少于3个，' ...
                 '标记converged=false'], ...
                rmse_yplus_range(1), rmse_yplus_range(2));
        converged = false;
        quality_flag = 'no_valid_residual';
        Cfnum_opt = NaN;
        Cf_opt    = NaN;
        iter_info = pack_info();
        return;
    end

    [~, i_best] = min(rmse_grid);                       % NaN 被 min 忽略
    Cfnum_opt = round(cfnum_grid(i_best) * 100) / 100;  % 两位小数
    Cf_opt    = tblR2.bl.cfnum_to_cf(Cfnum_opt);
    converged = true;
    iter_info = pack_info();

    function info = pack_info()
        info = struct(...
            'mode', 'auto_clauser', ...
            'dy_opt_mm', dy_opt_mm, ...
            'dy_h', dy_opt_mm / h_mm, ...
            'cfnum_grid', cfnum_grid, ...
            'rmse_grid', rmse_grid, ...
            'rmse_yplus_range', rmse_yplus_range);
    end
end


% =========================================================================
% 解析并校验用户指定的RMSE y+区间
% =========================================================================
function value = resolve_rmse_yplus_range(cfg)
% 独立调用loglaw_fit_chen时也执行防御性校验；主脚本还会在validate_config中
% 更早检查同一合同。下限必须>0，因为log-law理论项包含log(y+)。
    if isfield(cfg, 'loglaw_rmse_yplus_range')
        value = cfg.loglaw_rmse_yplus_range;
    else
        value = [30 300];
    end
    if ~isnumeric(value) || ~isreal(value) || numel(value) ~= 2 || ...
            any(~isfinite(value(:))) || value(1) <= 0 || value(2) <= value(1)
        error('tblR2:bl:loglaw_fit_chen:InvalidRmseYplusRange', ...
            ['cfg.loglaw_rmse_yplus_range 必须是有限的双元素向量 [下限 上限]，' ...
             '并满足 0 < 下限 < 上限。']);
    end
    value = reshape(value, 1, 2);
end


% =========================================================================
% 校验manual_utau模式的显式用户输入
% =========================================================================
function validate_manual_utau_params(params)
if ~isnumeric(params.kappa) || ~isreal(params.kappa) || ...
        ~isscalar(params.kappa) || ~isfinite(params.kappa) || params.kappa <= 0
    error('tblR2:bl:loglaw_fit_chen:InvalidManualUtauKappa', ...
        'manual_utau 模式的 kappa 必须是有限正数标量。');
end
if ~isnumeric(params.B) || ~isreal(params.B) || ...
        ~isscalar(params.B) || ~isfinite(params.B)
    error('tblR2:bl:loglaw_fit_chen:InvalidManualUtauB', ...
        'manual_utau 模式的 B 必须是有限标量。');
end
if ~isnumeric(params.dy_h) || ~isreal(params.dy_h) || ...
        ~isscalar(params.dy_h) || ~isfinite(params.dy_h) || params.dy_h < 0
    error('tblR2:bl:loglaw_fit_chen:InvalidManualUtauDy', ...
        'manual_utau 模式的 dy_h 必须是有限非负标量。');
end
if ~isnumeric(params.u_tau) || ~isreal(params.u_tau) || ...
        ~isscalar(params.u_tau) || ~isfinite(params.u_tau) || params.u_tau <= 0
    error('tblR2:bl:loglaw_fit_chen:InvalidManualUtau', ...
        'manual_utau 模式的 u_tau 必须是 m/s 单位下的有限正数标量。');
end
end
