function diagnostic = loglaw_diagnostic_function(LF)
%LOGLAW_DIAGNOSTIC_FUNCTION 计算Chauhan等建议的log-law诊断函数。
% 令中间变量xi=ln(y^+)，再计算Xi=dU^+/dxi=y^+*dU^+/dy^+。
% 这里的xi只用于数值求导，绝不是PIV数据中的流向坐标x。
% 理想对数区内U^+=(1/kappa)ln(y^+)+B，因此Xi应在1/kappa附近形成平台。
% 为避免直接差分放大噪声，分别采用5点和7点窗口对U^+(xi)作局部二次拟合，
% 再取拟合多项式在窗口中心的导数。只有两条结果趋势接近时诊断才较可信。
% 本函数只用于Section 2调试图，不修改LF，也不写入任何数值缓存。

required = {'y_plus', 'u_plus', 'kappa', 'rmse_yplus_range'};
if ~isstruct(LF) || ~isscalar(LF) || ~all(isfield(LF, required))
    error('tblR2:bl:loglaw_diagnostic_function:InvalidInput', ...
        'LF 必须包含 y_plus、u_plus、kappa 和 rmse_yplus_range。');
end

y_plus = LF.y_plus(:);
u_plus = LF.u_plus(:);
if numel(y_plus) ~= numel(u_plus)
    error('tblR2:bl:loglaw_diagnostic_function:SizeMismatch', ...
        'LF.y_plus 和 LF.u_plus 的元素数量必须相同。');
end

valid = isfinite(y_plus) & isfinite(u_plus) & y_plus > 0;
y_plus = y_plus(valid);
u_plus = u_plus(valid);
[y_plus, order] = sort(y_plus);
u_plus = u_plus(order);
[y_plus, unique_idx] = unique(y_plus, 'stable');
u_plus = u_plus(unique_idx);
if numel(y_plus) < 7
    error('tblR2:bl:loglaw_diagnostic_function:InsufficientData', ...
        '至少需要七个有限、互不重复且为正的 y_plus 点。');
end

% log_y_plus是截图公式中的中间变量，不是流向坐标。窗口只能在中心点完整时使用，
% 因而首尾各保留NaN，不用不对称外推制造看似平滑的边界趋势。
log_y_plus = log(y_plus);
Xi_5 = local_quadratic_slope(log_y_plus, u_plus, 5);
Xi_7 = local_quadratic_slope(log_y_plus, u_plus, 7);
rmse_range = double(LF.rmse_yplus_range(:)');

diagnostic = struct();
diagnostic.y_plus = y_plus;
diagnostic.u_plus = u_plus;
diagnostic.log_y_plus = log_y_plus;
diagnostic.Xi_5 = Xi_5;
diagnostic.Xi_7 = Xi_7;
diagnostic.common_mask = isfinite(Xi_5) & isfinite(Xi_7);
diagnostic.abs_difference = abs(Xi_5 - Xi_7);
diagnostic.kappa = LF.kappa;
diagnostic.target = 1 / LF.kappa;
diagnostic.rmse_yplus_range = rmse_range;
diagnostic.rmse_mask = y_plus >= rmse_range(1) & y_plus <= rmse_range(2);
end


function slope = local_quadratic_slope(coordinate, values, window_points)
%LOCAL_QUADRATIC_SLOPE 用奇数点对称窗口拟合二次多项式并求中心导数。
half_width = (window_points - 1) / 2;
slope = NaN(size(values));
for center = 1+half_width:numel(values)-half_width
    idx = center-half_width:center+half_width;
    % 以中心坐标为零点可改善polyfit的数值条件；p(2)即中心处一阶导数。
    local_coordinate = coordinate(idx) - coordinate(center);
    coefficients = polyfit(local_coordinate, values(idx), 2);
    slope(center) = coefficients(2);
end
end
