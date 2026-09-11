%MEAN_BL_FRICTION Mean-flow, boundary-layer, Clauser, and MIE products.
% =========================================================================
% 【合同（Section 2 mean_bl 阶段，与 mat/02_mean_boundary_layer_friction.mat 一致）】
%   - 输入：results.statistics（Section 2 statistics 输出）与 cfg；
%   - 壁面坐标唯一入口 tblR2.wall_distance_grid：首保留行真实壁距
%     = cfg.loglaw.params.dy_h * h，逐行增加 h；
%   - u_tau 来源由 tblR2.singlecase.select_u_tau 按 cfg.normalization.u_tau_source
%     决定（local_loglaw / baseline_inline），本函数不自行选择；
%   - 三种 Cf 是不同物理量：log-law Cf（剖面拟合单值）、system secant Cf
%     （跨区间平均值）、local Cf(x)（沿流向分布）；pressure_gradient_sensitivity
%     是对照诊断，不是第三种 Cf 方法；
%   - 全部数值计算复用 tblR2.stats/tblR2.io/tblR2.bl/tblR2.wall 共享函数，
%     不在本函数内重写任何公式。
% =========================================================================
function result = mean_bl_friction(stats, cfg)

% Reuse the baseline_case wall-coordinate contract. load_tecplot_dat has
% already removed the contiguous zero/invalid rows below the wall, so the
% first retained row is assigned y=dy_h*h rather than its absolute DAT Y.
[wall_distance_mm, wall_coordinate] = tblR2.wall_distance_grid( ...
    stats.Y, stats.h, cfg.loglaw.params.dy_h);
stats_wall = stats;
stats_wall.Y = wall_distance_mm;
[S_visual, S_drag, masks] = tblR2.stats.prepare_case_views( ...
    stats_wall, cfg.x_max, []);
[y_profile, u_profile, profile_cols] = tblR2.io.extract_velocity_profile( ...
    S_drag.Uavex, S_drag.X, S_drag.Y, S_drag.h, ...
    cfg.profile.mode, cfg.profile.params);

log_cfg = struct();
log_cfg.loglaw_mode = cfg.loglaw.mode;
log_cfg.loglaw_params = cfg.loglaw.params;
log_cfg.loglaw_skip_nearwall = cfg.loglaw.skip_nearwall;
log_cfg.loglaw_rmse_yplus_range = cfg.loglaw.rmse_yplus_range;
log_cfg.U_inf_n_top = cfg.profile.U_inf_n_top;
log_cfg.profile_mode = cfg.profile.mode;
log_cfg.profile_params = cfg.profile.params;
LF = tblR2.bl.loglaw_fit_chen( ...
    u_profile, y_profile, cfg.nu, cfg.Uinf, S_drag.h, log_cfg);
if abs(LF.dy_opt - wall_coordinate.dy_mm) > ...
        100 * eps(max([1, abs(LF.dy_opt), abs(wall_coordinate.dy_mm)]))
    error('tblR2:mean_bl_friction:WallOffsetContractMismatch', ...
        ['loglaw 的 dy_opt 与壁面距离网格使用的 dy_h*h 不一致。' ...
         '请检查 cfg.loglaw.params.dy_h 和网格间距。']);
end

% Option A is the existing fixed-wall Clauser scan.  Option B is an
% independent, constrained Rodriguez-Lopez et al. composite-profile fit.
% It intentionally does not feed normalization or alter the option-A result.
modern_options = resolve_modern_clauser_options(cfg, LF);
if modern_options.enabled
    nominal_options = modern_options;
    modern_clauser = tblR2.bl.composite_profile_fit_rodriguez_lopez( ...
        u_profile, y_profile, cfg.nu, cfg.Uinf, S_drag.h, nominal_options, LF);
    modern_clauser.sensitivity = struct('enabled', false, ...
        'reason', 'The compact r2 library keeps only the nominal Option-B fit.');
else
    modern_clauser = disabled_modern_clauser(modern_options);
end

normalization = tblR2.singlecase.select_u_tau(cfg, LF);
u_tau = normalization.u_tau;

BL = tblR2.bl.integral_params(S_drag.Uavex, S_drag.X, S_drag.Y, ...
    S_drag.h, LF.dy_opt, cfg.profile.U_inf_n_top);
drag_input = tblR2.wall.prepare_drag_inputs(BL);
[secant_theta, secant_theta_diag] = tblR2.wall.select_secant_theta( ...
    drag_input.calculation.theta, drag_input.x, ...
    cfg.friction.secant_theta_source, cfg.friction.momentum.pre_smooth_p, ...
    cfg.friction.thickness_smoothing_gap_mode, []);
edge_velocity = tblR2.wall.prepare_edge_velocity( ...
    S_visual.Uavex, S_visual.X, cfg.profile.U_inf_n_top, ...
    cfg.friction.momentum.Ue_pre_smooth_p);

if cfg.friction.enable_pressure_gradient == 1
    primary_equation = 'full';
else
    primary_equation = 'zpg';
end
primary = run_equation(primary_equation, false);
zpg_matched = run_equation('zpg', true);
full_matched = run_equation('full', true);

drag = struct();
drag.primary = primary;
drag.loglaw = struct('u_tau', LF.u_tau, 'Cf', LF.Cf);
drag.modern_clauser = struct('u_tau', modern_clauser.u_tau, ...
    'Cf', modern_clauser.Cf, 'enabled', modern_clauser.enabled, ...
    'method', modern_clauser.method);
drag.edge_velocity = edge_velocity;
drag.secant_theta = secant_theta_diag;
drag.preprocessing = drag_input.preprocessing;
drag.normalization = normalization;
drag.pressure_gradient_sensitivity = struct( ...
    'zpg_same_smoothed_Ue', zpg_matched, ...
    'full_same_smoothed_Ue', full_matched, ...
    'local_Cf_difference', full_matched.local.Cf - zpg_matched.local.Cf, ...
    'definition', ['The zpg/full sensitivity pair uses the same smoothed Ue ' ...
                   'profile; the primary branch preserves the selected contract.']);

result = struct();
result.visual_statistics = S_visual;
result.drag_statistics = S_drag;
result.masks = masks;
result.profile = struct('y_mm', y_profile, 'u_mps', u_profile, ...
    'columns', profile_cols);
result.loglaw = LF;
result.modern_clauser = modern_clauser;
result.clauser = struct('option_a', LF, 'option_b', modern_clauser, ...
    'normalization_option', 'A');
result.normalization = normalization;
result.boundary_layer = BL;
result.drag = drag;
result.wall_distance_mm = wall_distance_mm;
result.wall_coordinate = wall_coordinate;
result.y_plus = wall_distance_mm .* 1e-3 .* u_tau ./ cfg.nu;
result.delta99_reference_mm = median(BL.delta99, 'omitnan');
result.definition = ['Option A is the legacy fixed-wall Clauser/log-law fit; ' ...
    'option B is the independent Rodriguez-Lopez composite-profile fit. ' ...
    'Both are stored without changing the selected normalization (option A). ' ...
    'Local momentum-integral Cf(x) and finite-interval endpoint Cf remain ' ...
    'distinct physical quantities.'];

    function branch = run_equation(equation, use_matched_Ue)
        secant_opts = cfg.friction.system_secant;
        secant_opts.equation = equation;
        secant_opts.contamination_x = [];
        if strcmp(equation, 'full')
            secant_opts.Ue = edge_velocity.smooth;
            secant_opts.delta_star = drag_input.calculation.delta_star;
        end
        [system_cf, system_diag] = tblR2.wall.system_secant_cf( ...
            secant_theta, drag_input.x, ...
            cfg.friction.system_secant.x_end, secant_opts);

        local_opts = cfg.friction.momentum;
        local_opts.equation = equation;
        local_opts.x_min = cfg.friction.quality.x_min;
        local_opts.x_max = min(cfg.x_max, cfg.friction.quality.x_max);
        local_opts.theta_source = cfg.friction.local_momentum_theta_source;
        local_opts.gap_mode = cfg.friction.thickness_smoothing_gap_mode;
        local_opts.contamination_x = [];
        if strcmp(equation, 'full') || use_matched_Ue
            local_Ue = edge_velocity.smooth;
            local_opts.Ue_derivative = edge_velocity.derivative;
            local_opts.Ue_pre_smooth_p = edge_velocity.p;
            local_opts.Ue_source_description = edge_velocity.source_description;
        else
            local_Ue = drag_input.calculation.Uinf_local;
        end
        [tau_w, local_diag] = tblR2.wall.shear_momentum( ...
            drag_input.calculation.theta, local_Ue, drag_input.x, ...
            cfg.rho, cfg.nu, drag_input.calculation.delta_star, local_opts);

        quality_opts = cfg.friction.quality;
        quality_opts.equation = equation;
        quality = tblR2.wall.momentum_calibration_quality( ...
            secant_theta, local_Ue, drag_input.calculation.delta_star, ...
            drag_input.x, local_diag.Cf_local, ...
            local_opts.pre_smooth_p, quality_opts);
        branch = struct();
        branch.equation = equation;
        branch.system = struct('Cf', system_cf, 'diag', system_diag, ...
            'theta_source', cfg.friction.secant_theta_source);
        branch.local = struct('x', drag_input.x, ...
            'Cf', local_diag.Cf_local, 'tau_w', tau_w, ...
            'diag', local_diag, 'quality', quality);
        branch.used_matched_smoothed_Ue = use_matched_Ue;
    end
end


function options = resolve_modern_clauser_options(cfg, option_a)
% Existing cases remain compatible until they explicitly opt in.  Section 2
% tandem cases set enabled=true and carry their own fixed dy_h.
options = struct('enabled', false, ...
    'method', 'rodriguez_lopez_2015_constrained_bump1', ...
    'dy_h', option_a.dy_h_opt);
if isfield(cfg, 'modern_clauser') && ~isempty(cfg.modern_clauser)
    supplied = cfg.modern_clauser;
    names = fieldnames(supplied);
    for i = 1:numel(names)
        options.(names{i}) = supplied.(names{i});
    end
end
end


function result = disabled_modern_clauser(options)
result = struct( ...
    'option', 'B', ...
    'enabled', false, ...
    'method', char(options.method), ...
    'reference', struct(), ...
    'identifiability', struct(), ...
    'converged', false, ...
    'exitflag', NaN, ...
    'u_tau', NaN, ...
    'Cf', NaN, ...
    'Re_tau', NaN, ...
    'Pi', NaN, ...
    'delta_mm', NaN, ...
    'sensitivity', struct('enabled', false, ...
    'selection_policy', 'Option B is disabled.'), ...
    'warning', 'Option B is disabled by cfg.modern_clauser.enabled.');
end
