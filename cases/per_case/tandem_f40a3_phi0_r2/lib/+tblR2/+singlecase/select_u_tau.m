function normalization = select_u_tau(cfg, LF)
%SELECT_U_TAU Resolve the explicit baseline/local normalization switch.

normalization = struct();
normalization.source = char(cfg.normalization.u_tau_source);
normalization.baseline_u_tau = cfg.normalization.baseline_u_tau;
normalization.local_loglaw_u_tau = LF.u_tau;
switch normalization.source
    case 'baseline_inline'
        normalization.u_tau = normalization.baseline_u_tau;
    case 'local_loglaw'
        normalization.u_tau = normalization.local_loglaw_u_tau;
    otherwise
        error('tblR2:singlecase:select_u_tau:UnknownSource', ...
            '未知的 u_tau 来源：%s', normalization.source);
end
if ~isfinite(normalization.u_tau) || normalization.u_tau <= 0
    error('tblR2:singlecase:select_u_tau:InvalidValue', ...
        '选定的 u_tau 必须是有限正数。');
end
normalization.relative_difference_pct = 100 * ...
    (normalization.local_loglaw_u_tau - normalization.baseline_u_tau) / ...
    normalization.baseline_u_tau;
end
