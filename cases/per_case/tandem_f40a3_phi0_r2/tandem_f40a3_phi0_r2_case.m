%% 0. 本 case 路径与集中参数（重跑不清空已有结果）
% 串列 40 Hz 受控工况精简版 r2 主脚本。
% 主脚本直接展示 Section 0-9 的数据处理顺序，算法由 r2 核心库提供。
% baseline 与 controlled 使用同一套 +tblR2；差异只写在本文件的工况配置中。


script_file = mfilename('fullpath');
if isempty(script_file)
    try
        script_file = matlab.desktop.editor.getActiveFilename;
    catch
        script_file = '';
    end
end
[case_root, script_name] = fileparts(script_file);
if isempty(case_root) || ~strcmp(script_name, 'tandem_f40a3_phi0_r2_case')
    error('tblR2:caseScript:MissingScriptPath', '请从当前 case 主脚本文件运行 Section 0。');
end
case_root = char(java.io.File(case_root).getCanonicalPath());
script_file = fullfile(case_root, script_name);
library_root = fullfile(case_root, 'lib');
if ~isfolder(fullfile(library_root, '+tblR2'))
    error('tblR2:caseScript:MissingLocalLibrary', '缺少本 case 函数库：%s', library_root);
end
addpath(library_root, '-begin');
expected_guard = fullfile(library_root, '+tblR2', 'require_case_library.m');
resolved_guard = which('tblR2.require_case_library');
if ~strcmp(resolved_guard, expected_guard) && ~(ispc && strcmpi(resolved_guard, expected_guard))
    error('tblR2:caseScript:ForeignLibrary', ...
        '本 case 路径检查函数解析异常：%s；预期 %s。请移除旧 lib 路径后重跑。', ...
        resolved_guard, expected_guard);
end
tblR2.require_case_library(case_root, {'tblR2.require_case_library', ...
    'tblR2.validate_config','tblR2.build_paths','tblR2.workspace_results'});

% ==================== A. 工况身份 ====================
cfg = struct();
cfg.schema_version = 2;                                               % 配置合同版本，用于结果兼容性检查。
cfg.case_id = 'per_case/tandem_f40a3_phi0_r2';                        % 工况唯一标识，写入所有阶段元数据。
cfg.case_type = 'controlled';                                         % 工况类型：受控工况启用相位平均和三重分解。
cfg.name = '串列 40 Hz 受控工况精简版 r2';                            % 命令窗口和摘要中显示的工况名称。
cfg.script_file = script_file;                                        % 当前主脚本的绝对路径，便于追溯。
% 所有本工况 MAT、CSV、JSON、PNG、FIG 和日志文件的输出根目录.
cfg.output_dir = fullfile(case_root, 'output');

% ==================== B. 阶段运行策略（决定各 Section compute/reuse/skip）====================
cfg.stages = struct(); % 阶段运行策略容器；每个阶段可选 'compute'（计算）、'reuse'（复用缓存）或 'skip'（跳过）。
cfg.stages.cache       = 'reuse';       % Section 1：序列缓存。
cfg.stages.statistics  = 'reuse';       % Section 2：分块统计。
cfg.stages.mean_bl     = 'reuse';       % Section 2：复用当前 r2 平均边界层与摩阻结果。
cfg.stages.phase       = 'reuse';       % Section 3：复用已有相位结果，仅作为脚本上下文。
cfg.stages.structures  = 'compute';     % Section 4：瞬时结构识别。
cfg.stages.transport   = 'skip';        % Section 5：本次只重算 Section 4。
cfg.stages.temporal    = 'skip';        % Section 6：本次只重算 Section 4。
cfg.stages.spatial     = 'skip';        % Section 6：本次只重算 Section 4。
cfg.stages.pod         = 'skip';        % Section 7：本次只重算 Section 4。
cfg.stages.dmd         = 'skip';        % Section 7：本次只重算 Section 4。
cfg.stages.lcs         = 'skip';        % Section 7：LCS/FTLE（默认跳过）。
cfg.stages.spod        = 'skip';        % Section 7：本次只重算 Section 4。
cfg.stages.correlations = 'skip';       % Section 8：本次只重算 Section 4。
cfg.stages.harmonics   = 'skip';        % Section 8：本次只重算 Section 4。
cfg.stages.figures     = 'compute';        % Section 9：Section 4 图像独立导出。

% ==================== C. 全局物理量（所有 Section 共用）====================
cfg.wall_side = 'top'; % 壁面侧可选 'top' 或 'bottom'；决定壁面距离 y_wall 和法向坐标的正方向。
cfg.grid_size = [640 91]; % 网格尺寸 [Nx Ny]，分别为流向和法向测量点数；必须与序列缓存元数据一致。
cfg.fs = 960; % 采样频率 fs，单位 Hz；决定时间步长 dt=1/fs，必须为正数。
cfg.Uinf = 25; % 名义来流速度 U∞，单位 m/s；用于速度归一化和对流尺度，必须为正数。
cfg.nu = 1.48e-5; % 运动黏度 ν，单位 m²/s；用于 Reτ 和黏性尺度计算，必须为正数。
cfg.rho = 1.20; % 流体密度 ρ，单位 kg/m³；用于壁面剪切应力和摩阻计算，必须为正数。
cfg.D_mm = 30; % 参考特征尺度 D，单位 mm；用于几何尺度和无量纲化，必须为正数。
cfg.x_max = 328; % 分析域最大流向位置 x_max，单位 mm；应覆盖所选网格且大于分析起点。
cfg.min_valid_fraction = 0.70; % 网格点最小有效样本比例，范围 (0,1]；低于该比例的点从统计中排除。
cfg.rebuild_cache = strcmp(cfg.stages.cache, 'compute'); % 派生字段；重建只修改 stages.cache。

% ==================== D. Section 1 参数：序列缓存与数据源 ====================
cfg.frame_offset = 0; % 每个重复序列的起始帧偏移（非负整数）；0 表示从首帧开始读取。
cfg.n_frames = 6000; % 每个重复序列读取的帧数（正整数）；当前每个 repeat 为 6000 帧。
cfg.total_frames = 2 * cfg.n_frames; % 两次重复拼接后的总帧数（自动计算，不建议手动修改）。
cfg.formal_required_frames = 6000; % 正式运行要求每个重复序列达到的最少帧数（正整数）。
cfg.allow_debug_snapshot = false; % 短序列调试开关：true=允许少于正式帧数，false=执行完整数据安全闸门。
cfg.chunk_frames = 48; % 流式读写的帧分块大小（正整数）；当前 48 也用于 Section 4 的分块合同。
% 显式两个 repeat：保持原记录的 3rd → 2nd、各自 offset=0。
% 新建缓存时，DAT 放在本 case/input 下对应目录；不探测编号、不猜起帧。
% 旧缓存内的历史根路径不能自动改签；请先阅读 README 的旧结果迁移边界。
input_root = fullfile(case_root, 'input');
cfg.sources = struct();
cfg.sources.raw = struct();
cfg.sources.raw.roots = { ...
    fullfile(input_root, 'Tandem_f40A3_Phi+0_PIV_3rd'), ...
    fullfile(input_root, 'Tandem_f40A3_Phi+0_PIV_2nd')};
cfg.sources.raw.offsets = [0 0];
cfg.sources.raw.ids = {'Tandem_f40A3_Phi+0_PIV_3rd', 'Tandem_f40A3_Phi+0_PIV_2nd'};
cfg.sources.postproc = struct();
cfg.sources.postproc.roots = { ...
    fullfile(input_root, 'Tandem_f40A3_Phi+0_PostProc_3rd'), ...
    fullfile(input_root, 'Tandem_f40A3_Phi+0_PostProc_2nd')};
cfg.sources.postproc.offsets = [0 0];
cfg.sources.postproc.ids = {'Tandem_f40A3_Phi+0_PostProc_3rd', 'Tandem_f40A3_Phi+0_PostProc_2nd'};
cfg.data_root = cfg.sources.raw.roots{1}; % 派生身份，不单独调整。

% ==================== E. Section 2 参数：统计、剖面、Clauser 拟合、摩阻 ====================
% E1. 统计数据源与帧范围
cfg.statistics_source = 'raw'; % 统计输入源可选 'raw' 或 'postproc'；分别表示原始 PIV 与后处理速度场。
cfg.statistics_frame_mode = 'all'; % 统计帧范围可选 'first_half'、'second_half' 或 'all'；对应前6000、后6000或全部12000帧。

% E2. 代表性速度剖面提取
cfg.profile = struct(); % 速度剖面配置容器；mode 可选 'fixed'、'multi_avg' 或 'range_avg'，决定剖面的空间取样方式。
cfg.profile.mode = 'range_avg'; % 剖面提取模式可选 'fixed'、'multi_avg' 或 'range_avg'；当前按 x 区间平均。
cfg.profile.params = [80 180]; % 剖面模式参数；range_avg 时为 [x_min x_max]，单位 mm，表示沿程平均区间。
cfg.profile.U_inf_n_top = 5; % 估计外缘速度 Ue 使用的顶部法向网格点数（正整数）。

% E3. 传统 Clauser 对数律拟合（Option A，等效于 TBL_logfit.m）
cfg.loglaw = struct(); % 传统对数律拟合配置；mode 可选 'auto'、'semi'、'manual' 或 'manual_utau'。
cfg.loglaw.mode = 'auto'; % 传统对数律拟合模式可选 'auto'、'semi'、'manual' 或 'manual_utau'。
cfg.loglaw.skip_nearwall = 0; % 对数律拟合跳过的近壁网格点数（非负整数）；0 表示不额外跳过。
cfg.loglaw.rmse_yplus_range = [80 250];   % 用于 RMSE 评估的 y+ 区间。
cfg.loglaw.params = struct(); % 传统对数律物理参数容器，包含 κ、B、近壁起始位置和 Cf 参考曲线编号。
cfg.loglaw.params.kappa = 0.40; % von Kármán 常数 κ（无量纲正数），控制对数律斜率。
cfg.loglaw.params.B = 5.0; % 对数律截距 B（无量纲），表征内层速度剖面的偏移。
cfg.loglaw.params.dy_h = 1.3;            % 第一保留点距壁面的倍数（相对于网格间距h），实际距离=dy_h*h（mm）。
cfg.loglaw.params.Cfnum = 12; % Cf 参考曲线编号（正整数）；auto 模式可自动扫描可用编号。
cfg.loglaw.applicability = struct(); % 对数律适用性筛选容器；下列阈值约束 y+、y/δ、方法差异及拟合区覆盖度。
cfg.loglaw.applicability.min_y_plus = 30; % 传统对数律适用区的最小 y+（无量纲），低于此值不视为对数层。
cfg.loglaw.applicability.max_y_over_delta = 0.15; % 传统对数律适用区的最大 y/δ（无量纲），用于避免进入边界层外层。
cfg.loglaw.applicability.relative_target_tolerance = 0.10; % 目标量相对容差（0.10=10%）。
cfg.loglaw.applicability.max_method_difference = 0.15; % 不同拟合方法允许的最大相对差异（0.15=15%）。
cfg.loglaw.applicability.min_contiguous_points = 5; % 适用区至少包含的连续法向网格点数（正整数）。
cfg.loglaw.applicability.min_log10_span = 1.0; % log10(y+) 的最小覆盖跨度（1 表示至少一个 decade）。

% E4. 现代 Clauser 拟合（Option B，Rodriguez-Lopez 复合剖面法）
cfg.modern_clauser = struct(); % 现代 Clauser（Option B）配置容器；当前实现采用 Rodriguez--Lopez 复合边界层剖面。
cfg.modern_clauser.enabled = true; % 是否启用现代 Clauser Option B：true=启用，false=关闭。
cfg.modern_clauser.method = 'rodriguez_lopez_2015_constrained_bump1'; % 拟合方法标识；当前唯一支持 Rodriguez--Lopez 2015 约束复合剖面。
cfg.modern_clauser.kappa = 0.384; % Option B 的 von Kármán 常数 κ（无量纲正数）。
cfg.modern_clauser.B = 4.17; % Option B 的对数律截距 B（无量纲）。
cfg.modern_clauser.dy_h = 1.0; % Option B 首个保留法向点距壁面的网格间距倍数 dy/h（非负数）。
cfg.modern_clauser.skip_nearwall = 1; % 拟合时跳过的近壁网格点数（非负整数）。
cfg.modern_clauser.U_inf_n_top = 5; % 估计外缘速度 Ue 使用的顶部网格点数（正整数）。
cfg.modern_clauser.enable_bump = true; % 是否加入 Coles/Chauhan 尾迹 bump 修正：true/false。
cfg.modern_clauser.inner_step_yplus = 0.01; % 内层剖面在 y+ 方向的积分/搜索步长（正数）。
cfg.modern_clauser.pi_initial = 0.20; % 尾迹强度参数 Π 的优化初值，必须落在 pi_bounds 内。
cfg.modern_clauser.pi_bounds = [0 2]; % Π 的允许范围 [下限 上限]，下限必须非负。
cfg.modern_clauser.u_tau_scale_bounds = [0.5 1.8]; % 摩擦速度 uτ 相对初值的缩放范围 [下限 上限]。
cfg.modern_clauser.delta_scale_bounds = [0.5 2.0]; % 边界层厚度 δ 相对初值的缩放范围 [下限 上限]。
cfg.modern_clauser.minimum_points = 10; % 拟合所需的最少有效剖面点数（正整数）。
cfg.modern_clauser.max_iterations = 400; % 非线性优化器最大迭代次数（正整数）。
cfg.modern_clauser.max_function_evaluations = 1600; % 目标函数最大评估次数（正整数）。
cfg.modern_clauser.tolerance = 1e-7; % 优化收敛容差（有限正数，无量纲）。

% E5. u_tau 无量纲化来源
cfg.normalization = struct(); % 无量纲化配置容器；u_tau_source 决定速度/壁面单位的摩擦速度来源。
cfg.normalization.u_tau_source = 'local_loglaw'; % uτ 来源可选 'local_loglaw'（局部对数律）或 'baseline_inline'（指定基准值），决定壁面单位归一化。
cfg.normalization.baseline_u_tau = 0.95; % 备用基准摩擦速度 uτ，单位 m/s；仅在 u_tau_source='baseline_inline' 时生效。

% E6. 壁面摩阻与压力梯度
cfg.friction = struct(); % 壁面摩阻、动量积分和压力梯度配置容器；参数控制 θ 平滑、Cf 计算及质量评估。
cfg.friction.enable_pressure_gradient = 0; % 压力梯度修正开关：0=零压力梯度（ZPG），1=采用含压力梯度的 full 方程。
cfg.friction.secant_theta_source = 'p_smooth'; % 系统割线法 θ 来源：'raw'（原始动量厚度）或 'p_smooth'（按 p 平滑后的 θ）。
cfg.friction.thickness_smoothing_gap_mode = 'separate_segments'; % 跨无效/污染缺口的平滑方式：'separate_segments'（分段）或 'bridge_contamination'（跨缺口连接）。
cfg.friction.local_momentum_theta_source = 'shared_thickness_p_smooth'; % 局部动量厚度 θ 来源：'shared_thickness_p_smooth'（共享平滑）或 'independent_downstream_p_smooth'（下游独立平滑）。
cfg.friction.rbf_epsilon_scale = 1.2; % RBF 平滑核尺度 ε 相对于网格尺度的倍率；必须为正数。
cfg.friction.hole_thresholds = [0 1 2]; % 四象限 hole-size 阈值 H 列表（有限非负数）；事件条件按 H×局部 u_rms×v_rms 缩放。
cfg.friction.system_secant = struct(); % 系统割线法配置容器；用于跨上游参考区间与下游终点计算平均 Cf。
cfg.friction.system_secant.upstream_mode = 'range_mean'; % 系统割线法上游基准模式；当前支持 'range_mean'（区间平均）。
cfg.friction.system_secant.upstream_range = [80 90]; % 上游基准平均区间 [x_min x_max]，单位 mm；决定割线法的起点 θ。
cfg.friction.system_secant.x_end = [160 240 320]; % 系统割线法下游终点位置列表，单位 mm；每个终点独立给出区间平均 Cf。
cfg.friction.momentum = struct(); % 局部动量积分摩阻配置容器；包含平滑、方程和一致性检查参数。
cfg.friction.momentum.enabled = true; % 动量积分摩阻计算开关：true=启用，false=关闭。
cfg.friction.momentum.Ue_pre_smooth_p = 1e-7; % 外缘速度 Ue 的预平滑参数 p，取 [0,1]；数值越大表示更强的平滑/正则约束。
cfg.friction.momentum.pre_smooth_p = 1e-7; % 动量厚度 θ 的预平滑参数 p，取 []（显式关闭）或 [0,1]；用于稳定沿程导数。
cfg.friction.momentum.consistency_warn_pct = 10; % 动量法一致性报警阈值，单位 %；差异超过该值时提示诊断。
cfg.friction.quality = struct(); % 摩阻质量评估配置容器；用于扫描 p 参数并限定沿程评估区间。
cfg.friction.quality.p_grid = 1 - 10.^(0:-0.5:-5); % 质量评估扫描的 p 参数网格；每个 p 为有限非负值，控制平滑强度。
cfg.friction.quality.tolerance_pct = 10; % 摩阻质量评估允许的相对差异阈值，单位 %。
cfg.friction.quality.x_min = 80; % 摩阻质量评估起始流向位置，单位 mm。
cfg.friction.quality.x_max = 328; % 摩阻质量评估终止流向位置，单位 mm。

% ==================== F. Section 3 参数：相位平均与三重分解 ====================
cfg.phase = struct('enabled', true); % 相位分析开关：controlled 工况要求 true；false 表示不做相位平均/三重分解。
cfg.phase.f0_hz = 40; % 外部激励基频，单位 Hz；controlled 工况用于把帧映射到机械相位。
cfg.phase.n_bins = 24; % 一个激励周期的相位分箱数（正整数）；当前 24 箱对应 960/40 Hz。
cfg.phase.phi0_user_deg = []; % 用户指定机械零相位，单位 deg；[] 表示未标定并采用程序默认相位。
cfg.phase.minimum_samples_per_bin = 20; % 每个相位箱所需的最少有效样本数（正整数），不足时该箱不用于统计。

% -------------------- Section 3 预览图绘制区域配置（用户可改） --------------------
% 剖面图沿流向平均的区域。coherent 分量在激励器附近最强，x 范围过大会将其稀释。
% 默认取整个 FOV 下游段，用户可收紧到激励器影响区（如 [80 180]）以突出 coherent。
cfg.phase_preview = struct(); % Section 3 预览配置容器；控制相位剖面/云图的绘制范围、抽样和数据源。
cfg.phase_preview.profile_x_range_mm = [80 320];   % 三重分解剖面图的流向平均范围 [x_min x_max] (mm)。
cfg.phase_preview.contour_x_range_mm = [80 320];   % 相位云图的绘制区域 x 范围 [x_min x_max] (mm)。
%                   说明：x<80mm 处激励器薄膜周期性进入流场产生错误矢量，故默认截掉；
%                   用户可按需改回完整 FOV，后期对重点 case 用动态 mask 处理错误矢量。
cfg.phase_preview.smooth_points = 5; % 仅显示平滑；原 5 点 movmean，不改统计数据。
cfg.phase_preview.marker_stride = 1; % 相位剖面 marker 间隔（正整数）；1 表示每个测量点都绘制 marker。

% ---- Section 3 数据源配置 ----
% 相位平均分为两类输出：剖面图（三重分解 Reynolds 应力剖面）和云图（相位速度场）。
% 剖面图基于统计量，受 cfg.statistics_source 控制；云图为可视化用途，可独立指定数据源。
% profile_source 旧字段没有消费者，已移除可调入口；保留原相位来源与公式。
cfg.phase_preview.contour_source = 'postproc';     % 相位云图数据源：'raw' 或 'postproc'（默认 postproc，展示效果更好）。

% ==================== G. Section 4 参数：瞬时结构识别 ====================
cfg.instantaneous = struct(); % Section 4 代表性瞬时帧配置容器；用于选择结构识别结果中的展示帧。
cfg.instantaneous.n_output_frames = 3; % 代表性瞬时帧数量，必须为正整数；帧将在指定闭区间内均匀选取。
cfg.instantaneous.frame_ids = [1 cfg.total_frames]; % 代表帧选择的闭区间边界 [首帧 末帧]；必须为缓存内的 1-based 整数。

cfg.structures = struct(); % 结构识别总配置容器；Section 4 使用其中的 POD-E50、连通域和图像参数。
% Section 4 采用已验收的 POD-E50 + Deshpande-style 严格连通判据。
cfg.structures.section4 = struct(); % Section 4 参数唯一入口。
cfg.structures.section4.source_mode = 'pod_e50'; % Section 4 输入模式：'pod_e50' 或 'postproc_direct'；当前采用 POD 累计能量 50%。
cfg.structures.section4.connectivities = [8 4]; % Section 4 独立统计的连通性列表；8/4 两种邻域分别计数。
cfg.structures.section4.primary_connectivity = 8; % Section 4 主连通性，必须为 4 或 8；当前选 8。
% Detection statistics retain both connectivities; individual field figures
% are exported only for this explicitly selected connectivity.
cfg.structures.section4.figure_connectivity = 8; % 单对象流场图使用的连通性，必须为 4 或 8 且包含在 connectivities 中。
cfg.structures.section4.length_thresholds = [3 3.8 4.5]; % Section 4 的三档严格长度门槛 Lx/δ>3、>3.8、>4.5（无量纲）。
cfg.structures.section4.max_complete_ss_per_sign = Inf; % Section 4 每帧每符号完整 VLSM 数量上限；正整数限额或 Inf。
% S4 实际固定使用 balance(257)；旧 plot_colormap=ocean 不生效，移除该入口。
cfg.structures.section4.plot_normalization = 'u_over_Uinf'; % Section 4 图像归一化：'u_over_Uinf'（除以来流速度）或 'u_over_urms_y'（除以局部 u_rms）。
cfg.structures.section4.make_figures = true; % 是否导出 Section 4 VLSM 图像：true=生成 PNG/FIG，false=仅计算目录。
cfg.structures.section4.write_catalog_csv = true; % 是否写出结构目录 CSV：true=写出，false=不写出。
cfg.structures.section4.max_figure_objects = Inf; % 单次运行允许导出的最大结构图对象数；正整数限额或 Inf。
cfg.structures.section4.resume_run_dir = ''; % 断点续跑目录；空字符串表示不指定，使用新建/自动发现的运行目录。
cfg.structures.section4.frame_ordinals = []; % 指定要处理的 1-based 帧序号；空数组表示按默认全量/代表帧设置。
cfg.structures.section4.reuse_existing_run = true; % 是否复用已有 Section 4 运行：true=按合同复用，false=强制新建结果。
% 用户指定固定空间排除矩形：enabled=true/false；x_start_mm、x_end_mm 与 wall_y_height_mm 均以 mm 表示，区域为 [x_start,x_end]×[0,y_height]。
cfg.structures.section4.spatial_exclusion = struct( ...
    'enabled', true, 'x_start_mm', 0, 'x_end_mm', 80, ...
    'wall_y_height_mm', 4);
% Optional Section-4 censoring of boxes that lie within the streamwise FOV rim.
% Keep disabled by default so existing canonical results are not changed implicitly.
% 流向左右边缘排除：enabled=true/false；buffer_cells 为非负整数，表示距左右 FOV 边缘的缓冲列数。
cfg.structures.section4.streamwise_edge_exclusion = struct( ...
    'enabled', false, 'buffer_cells', 3);
cfg.structures.section4.reference_x_mm = [100 220]; % d23 参考边界层厚度取值区间，mm。
cfg.structures.section4.chunk_frames = 48; % 原 d23 分批次序，不跟随 S2 chunk_frames。
cfg.structures.section4.amplitude_multiplier = 1.0; % 严格幅值门槛乘数。
cfg.structures.section4.pod = struct(); % Section 4 POD 配置容器；只在 source_mode='pod_e50' 时参与识别预处理。
cfg.structures.section4.pod.spatial_block_dof = 512; % 原 POD 空间分块。
cfg.structures.section4.pod.time_tile_frames = 128; % 原 POD 时间分块。
cfg.structures.section4.pod.min_valid_fraction = 1.0; % POD 空间自由度的最小有效样本比例，范围 (0,1]；1 表示要求全时段有效。
cfg.structures.section4.pod.rank = struct('kind','energy_fraction','value',0.50); % POD 阶数选择规则；kind 可选 'fixed_n' 或 'energy_fraction'，当前保留累计能量 50%。
cfg.structures.alpha = 1.0; % 旧版兼容阈值 α（无量纲，通常为正）；当前 d23 Section 4 不使用，仅保留接口。
cfg.structures.seed_alpha = 1.0; % 旧版种子区域阈值 α（无量纲，通常为正）；当前 Section 4 不使用。
cfg.structures.min_pixels = 1; % 旧版连通结构最小像素数（正整数）；当前 d23 仅保留兼容字段。
cfg.structures.connectivity = 8; % 旧版默认连通性（4 或 8 邻域）；当前 Section 4 使用 section4.connectivities。
cfg.structures.min_lsm_delta = 1.0; % 旧版 LSM 长度下限 Lx/δ（无量纲）；当前 Section 4 不使用。
cfg.structures.min_vlsm_delta = 3.0; % 旧版 VLSM 长度下限 Lx/δ（无量纲）；当前 Section 4 不使用。
cfg.structures.catalog_frame_stride = 1; % 旧版结构目录抽帧步长（正整数）；当前 Section 4 默认逐帧处理。
% 旧版预处理兼容字段：enabled=true/false，name 当前为 'none'；Gaussian 的 sigma_cells 以网格单元计，当前均关闭。
cfg.structures.preprocessing = struct('enabled',false,'name','none', ...
    'gaussian',struct('enabled',false,'sigma_cells',[]));

% ==================== H. Section 5 参数：四象限与平面输运 ====================
cfg.transport = struct(); % Section 5 输运配置容器；包含差分/统计时的边缘可靠性缓冲。
cfg.transport.source = 'raw'; % Section 5: raw or postproc, including all dependent moments.
cfg.transport.stress_fraction_floor = 1e-6; % 应力份额分母保护：max(eps, floor*u_rms*v_rms)；不改变概率分母或 H 严格大于。
cfg.transport.frame_mode = 'all'; % all, first_half or second_half, applied to all Section 5 moments.
cfg.transport.profile_x_range_mm = [80 320]; % Within-case streamwise averaging range (mm).
cfg.transport.edge_buffer_cells = [2 16]; % 输运分析边缘缓冲 [法向行数 流向列数]；均为非负整数，用于避开不可靠边界差分。

% ==================== I. Section 6 参数：时域谱与空间谱 ====================
cfg.temporal = struct(); % Section 6 时域谱配置容器；控制 Welch/FFT 的时间窗口、频带和有效样本率。
cfg.temporal.x_interval_mm = [3 327]; % 时域谱分析流向区间 [x_min x_max]，单位 mm。
cfg.temporal.nfft = 512; % 时间 FFT 点数 NFFT，正整数且不超过处理帧数；决定频率分辨率。
cfg.temporal.overlap_fraction = 0.50; % Welch 分段重叠比例，范围 [0,1)；越大则相邻窗口共享样本越多。
cfg.temporal.frequency_band_hz = [2 430]; % 保留频率范围 [f_min f_max]，单位 Hz；上限应低于 Nyquist 频率 fs/2。
cfg.temporal.min_valid_fraction = 0.90; % 时域谱网格点最小有效样本比例，范围 (0,1]。
cfg.temporal.Uc = struct(); % 对流速度 Uc 配置容器；用于把频率换算为流向波长。
cfg.temporal.Uc.method = 'profile_fraction'; % Uc 估计方法；当前唯一支持 'profile_fraction'。
cfg.temporal.Uc.fraction = 0.80; % Uc 相对外缘速度 Ue 的比例（正数；0.80 表示 Uc=0.8Ue）。
cfg.temporal.Uc.nearwall_n = 0; % 估计 Uc 时跳过的近壁网格行数（非负整数；0 表示不按行跳过）。
cfg.temporal.Uc.nearwall_plus = 10.8; % 估计 Uc 时的近壁 y+ 参数（非负数），用于限定近壁排除范围。
cfg.spatial = struct(); % Section 6 空间谱配置容器；控制 x 窗口、提取 y+ 层和边界行跳过。
cfg.spatial.windows_mm = [3 327]; % 空间谱流向窗口 [x_min x_max]，单位 mm；也可设置为多行区间矩阵。
cfg.spatial.selected_y_plus = [100 200 400 800]; % 空间谱提取的法向位置 y+ 列表（无量纲）。
cfg.spatial.min_valid_fraction = 0.90; % 空间谱网格点最小有效样本比例，范围 (0,1]。
cfg.spatial.skip_nearwall_rows = 2; % 空间谱跳过的近壁网格行数（非负整数）。
cfg.spatial.skip_fov_top_rows = 3; % 空间谱跳过的视场顶部网格行数（非负整数）。

% ==================== J. Section 7 参数：POD、DMD、SPOD、LCS ====================
cfg.pod = struct(); % Section 7 POD 配置容器；DMD/SPOD 默认从该配置继承公共模态参数。
cfg.pod.n_modes = 20; % POD 保留模态数（正整数）；决定低阶重构的自由度。
cfg.pod.frame_stride = 1; % POD 时间抽帧步长（正整数）；1 表示使用每一帧。
cfg.pod.spatial_stride = [2 2]; % POD 空间下采样步长 [法向 流向]（两个正整数）。
cfg.pod.x_range_mm = [80 328]; % POD 分析流向范围 [x_min x_max]，单位 mm。
cfg.pod.max_y_over_delta = 1.5; % POD 最大归一化法向位置 y/δ（正数）。
cfg.pod.oversampling = 8; % 随机化 POD 过采样数（正整数）；提高随机子空间捕获能量的稳定性。
cfg.pod.random_seed = 1729; % POD 随机数种子（整数）；固定后可复现实验结果。
cfg.pod.max_frames = cfg.total_frames;    % POD 最多读入的帧数。
cfg.pod.reconstruction = struct(); % POD 重构配置容器；控制重构帧、模态数、均值和原场保留。
cfg.pod.reconstruction.enabled = true; % 是否执行 POD 重构：true=执行，false=跳过。
cfg.pod.reconstruction.frame_positions = []; % 指定重构帧位置（1-based）；空数组表示采用默认帧集合。
cfg.pod.reconstruction.n_modes = 20; % POD 重构使用的模态数（正整数）；不应超过已计算模态数。
cfg.pod.reconstruction.add_mean = true; % 重构场是否加回时间平均场：true=含均值，false=仅脉动部分。
cfg.pod.reconstruction.include_raw = true; % 是否同时保留直接输入场供对比：true=保留，false=不保留。
cfg.dmd = cfg.pod; % DMD 初始继承 POD 公共参数；随后可单独覆盖 DMD 的空间抽样和随机种子。
cfg.dmd.spatial_stride = [2 4]; % DMD 空间下采样步长 [法向 流向]（正整数）。
cfg.dmd.random_seed = 2718; % DMD 随机数种子（整数）；用于保证随机化步骤可复现。
cfg.spod = cfg.dmd; % SPOD 初始继承 DMD/POD 公共参数；随后覆盖频谱专用设置。
cfg.spod.toolbox_dir = ''; % 启用SPOD时填 fullfile(case_root,'third_party','SPOD')；须自行提供合法副本。
cfg.spod.nfft = 512; % SPOD 分块 FFT 点数（正整数）。
cfg.spod.overlap_fraction = 0.50; % SPOD 分块重叠比例，范围 [0,1)。
cfg.spod.selected_frequencies_hz = []; % SPOD 指定频率列表，单位 Hz；空数组表示不预先限定频率。
cfg.spod.spatial_block_dof = 256; % SPOD 空间分块自由度（正整数）；控制分块矩阵规模和内存占用。
cfg.lcs = struct(); % LCS/FTLE 配置容器；控制粒子积分方向、时间范围和种子区域。
cfg.lcs.direction = 'backward'; % LCS 积分方向：'backward'（向过去积分）或 'forward'（向未来积分）。
cfg.lcs.integration_steps = 10; % 每条轨迹的积分步数（正整数）。
cfg.lcs.frame_start = 11; % LCS 起始帧号（正整数）。
cfg.lcs.frame_end = []; % LCS 终止帧号（正整数）；空数组表示由程序按数据范围自动确定。
cfg.lcs.frame_stride = 1; % LCS 时间抽帧步长（正整数）。
cfg.lcs.seed_region = []; % LCS 种子区域 [x_min x_max y_min y_max]（物理坐标）；空数组使用默认区域。
cfg.lcs.seed_size = [41 41]; % LCS 种子网格尺寸 [法向 流向]（正整数，单位为网格点）。
cfg.lcs.velocity_to_grid_scale = 1000; % 速度从 m/s 转换到 mm/s/网格坐标的倍率（有限正数）。
cfg.lcs.plot_frame_indices = []; % LCS 绘图帧号列表；空数组表示采用程序默认帧。
cfg.lcs.branch = 'raw'; % LCS 数据分支：'raw'、'total' 或 'random'；对应不同速度场来源。
cfg.lcs.source_role = 'postproc'; % LCS 源数据角色；通常为 'postproc'，需与 branch 的结果合同匹配。

% ==================== K. Section 8 参数：相关性与沿程发展 ====================
cfg.correlations = struct(); % Section 8 相关性分析配置容器；控制参考点、滞后范围和分析开关。
cfg.correlations.reference_points_mm = [120 1; 200 1; 280 1]; % 相关性参考点 [x y]，单位 mm；每行定义一个空间参考位置。
cfg.correlations.max_time_lag_s = 0.10; % 最大时间滞后，单位 s；决定时间相关图的横轴范围。
cfg.correlations.max_streamwise_lag_mm = 120; % 最大流向滞后，单位 mm；决定沿程相关图的横轴范围。
cfg.correlations.selected_y_plus = [100 200 400 800]; % 相关性提取的法向位置 y+ 列表（无量纲）。
cfg.correlations.ridge_min_correlation = 0.20; % 相关脊线提取的最小相关系数，范围通常 [0,1]。
cfg.correlations.two_point = false; % 双点相关开关：true=启用，false=关闭。
cfg.correlations.space_time = false; % 时空相关开关：true=启用，false=关闭。
cfg.correlations.streamwise = false; % 沿流向相关开关：true=启用，false=关闭。
cfg.streamwise_development = struct(); % 沿程发展分析配置容器；记录边缘缓冲和下游演化统计设置。
cfg.streamwise_development.edge_buffer_columns = 20; % 沿程发展分析两侧排除的流向列数（非负整数）。

% ==================== L. Section 9 参数：图形导出与预览 ====================
cfg.figures = struct(); % Section 9 图形导出配置容器；控制格式、色阶、窗尺寸和任务列表。
cfg.figures.formats = {'png', 'fig'}; % 导出格式列表；当前使用 'png'（位图）和 'fig'（可编辑 MATLAB 图窗）。
cfg.figures.export_dpi = 200; % PNG 位图导出分辨率，单位 dpi；必须为正数。
cfg.figures.robust_color_quantiles = [0.005 0.995]; % 鲁棒色阶分位点 [下分位 上分位]，取值在 [0,1] 且需递增。
cfg.figures.contour_levels = struct(); % 等值线级数配置；default/各覆盖项必须为不小于 2 的整数。
cfg.figures.contour_levels.default = 60; % 默认等值线级数（整数且不小于 2）；数值越大云图分级越细。
cfg.figures.colormaps = struct(); % 各图产品颜色图配置；名称必须来自项目支持的本地色图列表。
cfg.figures.colormaps.default = 'turbo'; % 未单独指定物理量时的默认色图；可选 turbo、ocean、coolwarm、balance、parula、gray 等项目支持名称。
cfg.figures.colormaps.mean_u = 'turbo'; % 平均流向速度 U 颜色图；可选项目色图，如 'turbo'、'ocean'、'balance' 等。
cfg.figures.colormaps.mean_v = 'balance'; % 平均法向速度 V 颜色图；通常用对称 'balance' 表示正负号。
cfg.figures.colormaps.u_rms = 'turbo'; % 流向脉动 RMS 颜色图；表示脉动强度（速度单位 m/s）。
cfg.figures.colormaps.v_rms = 'turbo'; % 法向脉动 RMS 颜色图；表示法向脉动强度（速度单位 m/s）。
cfg.figures.colormaps.negative_uv = 'balance'; % 负 Reynolds 应力/uv 产品颜色图；用对称色图区分正负值。
cfg.figures.colormaps.tke = 'turbo'; % 湍动能 TKE 颜色图；TKE 为非负量，通常使用顺序色图。
cfg.figures.window_size = struct(); % 图窗尺寸配置容器；每个条目为正的 [宽 高]，单位像素。
cfg.figures.window_size.default = [1450 760]; % 默认图窗尺寸 [宽 高]，单位像素。
cfg.figures.window_size.mean_turbulence = [1450 760]; % 平均湍流图窗尺寸 [宽 高]，单位像素。
cfg.figures.window_size.mean_profiles = [1500 700]; % 平均剖面图窗尺寸 [宽 高]，单位像素。
cfg.figures.window_size.loglaw = [1250 560]; % 传统对数律图窗尺寸 [宽 高]，单位像素。
cfg.figures.window_size.loglaw_diagnostic = [1250 560]; % 对数律诊断图窗尺寸 [宽 高]，单位像素。
cfg.figures.window_size.modern_clauser = [1250 560]; % 现代 Clauser 图窗尺寸 [宽 高]，单位像素。
cfg.figures.window_size.modern_clauser_sensitivity = [1400 850]; % 现代 Clauser 敏感性图窗尺寸 [宽 高]，单位像素。
cfg.figures.window_size.friction = [1250 550]; % 摩阻图窗尺寸 [宽 高]，单位像素。
cfg.figures.color_limits = struct(); % 固定颜色轴配置容器；每项为空或有限递增 [下限 上限]。
cfg.figures.color_limits.mean_u = [0.30 1.03]; % 平均 U 色阶范围 [下限 上限]；通常为 U/Uinf 无量纲值。
cfg.figures.color_limits.mean_v = [-0.01 0.01]; % 平均 V 色阶范围 [下限 上限]，单位 m/s 或当前绘图归一化单位。
cfg.figures.color_limits.u_rms = [0.02 0.32]; % u_rms 色阶范围 [下限 上限]，单位 m/s 或当前归一化单位。
cfg.figures.color_limits.v_rms = [0.015 0.13]; % v_rms 色阶范围 [下限 上限]，单位 m/s 或当前归一化单位。
cfg.figures.color_limits.negative_uv = [-0.0016 0.0016]; % 负 uv 色阶范围 [下限 上限]，采用对称上下限表示正负相关。
cfg.figures.color_limits.tke = [0 0.06]; % TKE 色阶范围 [下限 上限]；TKE 为非负量，单位取决于输入速度归一化。
cfg.figures.fov_aspect_ratio = [1 1]; % 视场显示比例 [水平 垂直]；[1 1] 表示保持几何比例，不拉伸物理坐标。
cfg.figures.instantaneous = struct(); % 瞬时图配置容器；颜色轴覆盖项和动画设置位于其下。
cfg.figures.instantaneous.frame_range = [1 3]; % 通用瞬时图帧范围 [首帧 末帧]；Section 4 的代表帧实际由 cfg.instantaneous.frame_ids/n_output_frames 控制。
cfg.figures.instantaneous.frame_stride = 1; % 瞬时图抽帧步长（正整数）。
cfg.figures.instantaneous.animation = struct(); % 瞬时图动画配置容器；包括 enabled 和 fps。
cfg.figures.instantaneous.animation.enabled = false; % 是否导出瞬时场动画：true=导出，false=不导出。
cfg.figures.instantaneous.animation.fps = 5; % 动画播放/导出帧率，单位 frame/s；必须为正数。
cfg.figures.instantaneous.color_limits = struct(); % 瞬时图颜色轴覆盖配置；空结构表示沿用各物理量默认色阶。
cfg.figures.jobs = {'mean_turbulence', 'mean_profiles', 'loglaw', 'loglaw_diagnostic', 'modern_clauser', 'friction', 'structures', 'transport', 'temporal_spectra', 'spatial_spectra', 'pod', 'dmd', 'lcs_ftle', 'spod', 'phase_triple', 'correlations', 'harmonics'}; % 图形任务列表；可选合法 job 包括 mean_turbulence、mean_profiles、loglaw、modern_clauser、structures、spectra、pod、dmd、lcs_ftle、spod、phase_triple、correlations、harmonics 等。
cfg.preview = struct(); % 预览配置容器；enabled 控制交互式预览，独立于 Section 4 图像导出。
cfg.preview.enabled = false; % 交互式预览开关：true=生成 Section 2/3 预览，false=关闭；不影响 Section 4 独立图像导出。
% ==================== Section 0 轻量工作区准备 ====================
cfg = tblR2.validate_config(cfg); % 轻量配置检查，不访问数据目录。
paths = tblR2.build_paths(cfg.output_dir);
if ~exist('results', 'var'); results = []; end
results = tblR2.workspace_results('init', results, cfg);
started_utc = results.workspace.started_utc;
fprintf('\n%s\n输出目录：%s\n', cfg.name, paths.root);
disp(cfg.stages);
% 本节只定义参数、路径与结果归属；不扫描 DAT、不读速度缓存、不计算/绘图。

%% 1. raw / PostProc 序列缓存
if ~exist('cfg', 'var') || ~exist('paths', 'var') || ~exist('results', 'var') || ...
        ~isfield(cfg, 'case_id') || ~strcmp(cfg.case_id, 'per_case/tandem_f40a3_phi0_r2') || ...
        ~isfield(paths, 'root') || ~strcmp(paths.root, cfg.output_dir)
    error('tblR2:caseScript:RunSection0', '请先运行本 case 的 Section 0，再运行本节。');
end
tblR2.workspace_results('require', results, cfg, {}, '', mfilename('fullpath'));
tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.workspace_results'});
tblR2.require_case_library(fileparts(cfg.script_file), ...
    {'tblR2.prepare_sequence_cache','tblR2.validate_sequence_cache', ...
    'tblR2.validate_dual_source_grid','tblR2.write_case_card'});

results = tblR2.workspace_results('forget', results, cfg, {'cache', 'postproc_cache'});
% 这里仅使用 Section 0 的显式 sources；不从旧缓存/目录探测覆盖用户配置。
tblR2.write_case_card(cfg, paths);
if ~cfg.allow_debug_snapshot && cfg.n_frames < cfg.formal_required_frames  % 帧数不足且未开调试开关 → 不允许运行。
    % 这是安全闸门：正式模式要求完整序列，防止漏导出数据被当成有效结果。
    error('tblR2:caseScript:FormalFrameCount', ...
        '正式计算至少需要 %d 帧；当前为 %d 帧。', ...
        cfg.formal_required_frames, cfg.n_frames);
end                                                                     % 结束正式帧数检查。

% -------------------- 建立两套序列缓存（本节的"重活"） --------------------
% cache 是下游所有阶段的共同输入，因此不允许 skip；compute=强制重建，reuse=优先复用已有缓存。
if strcmp(cfg.stages.cache, 'skip')                                     % 缓存一旦缺失，下游要么报错要么算出无意义结果。
    error('tblR2:caseScript:CacheSkipped', ...
        '原始缓存是所有下游产品的必需输入，不能跳过。');
end                                                                     % 结束 cache=skip 检查。
cache_cfg = cfg;                                                        % 复制一份配置，避免缓存函数改动主配置。
% ① 建 raw 缓存：读两个重复序列的 DAT，按帧写入可随机访问的单精度 MAT（先写临时文件再改名，避免写一半坏文件）。
results.cache = tblR2.prepare_sequence_cache(cache_cfg, paths, 'raw');
paths.sequence_cache = results.cache.filename;                          % 记录实际生成/复用的缓存文件路径（仅当前 case 本地位置）。
% ② 建 postproc 缓存：S4 与可选谱/模态使用；S5 在自身入口独立选源。
results.postproc_cache = tblR2.prepare_sequence_cache(cache_cfg, paths, 'postproc');
paths.sequence_cache_postproc = results.postproc_cache.filename;        % 记录实际后处理缓存位置。
% ③ 双源网格一致性校验：raw 与 postproc 必须共享同一坐标网格、壁面裁剪和帧布局，否则下游会"错位"计算。
tblR2.validate_dual_source_grid(paths.sequence_cache, ...
    paths.sequence_cache_postproc);
results = tblR2.workspace_results('record', results, cfg, ...
    {'cache','postproc_cache'}, cfg.stages.cache);

%% 2. 原统计、平均边界层与摩阻
if ~exist('cfg', 'var') || ~exist('paths', 'var') || ~exist('results', 'var') || ...
        ~isfield(cfg, 'case_id') || ~strcmp(cfg.case_id, 'per_case/tandem_f40a3_phi0_r2') || ...
        ~isfield(paths, 'root') || ~strcmp(paths.root, cfg.output_dir)
    error('tblR2:caseScript:RunSection0', '请先运行本 case 的 Section 0，再运行本节。');
end
tblR2.workspace_results('require', results, cfg, {}, '', mfilename('fullpath'));
tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.workspace_results'});
if strcmp(cfg.stages.statistics, 'compute')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.mean_stats_cache','tblR2.save_result'});
elseif strcmp(cfg.stages.statistics, 'reuse')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.load_result'});
end
if strcmp(cfg.stages.mean_bl, 'compute')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.mean_bl_friction','tblR2.save_result'});
elseif strcmp(cfg.stages.mean_bl, 'reuse')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.load_result'});
end

statistics_cache = paths.sequence_cache;
if strcmpi(cfg.statistics_source, 'postproc'); statistics_cache = paths.sequence_cache_postproc; end
statistics_inputs = struct('cache', statistics_cache);
mean_bl_inputs = struct('statistics', paths.statistics);
if ~strcmp(cfg.stages.statistics, 'skip') || ~strcmp(cfg.stages.mean_bl, 'skip')
    tblR2.require_case_library(fileparts(cfg.script_file), ...
        {'tblR2.result_inputs','tblR2.result_parameters','tblR2.sequence_cache_identity', ...
        'tblR2.validate_sequence_cache','tblR2.contract_difference','d23.sha256_text'});
end
results = tblR2.workspace_results('forget', results, cfg, {'statistics', 'mean_bl'});
if strcmp(cfg.stages.statistics, 'compute')
    if strcmpi(cfg.statistics_source, 'postproc')
        tblR2.workspace_results('require', results, cfg, {'postproc_cache'});
    else
        tblR2.workspace_results('require', results, cfg, {'cache'});
    end
end
if strcmp(cfg.stages.statistics, 'skip')          % skip 表示本次不计算统计产品，并向下游暴露空值。
    results.statistics = [];                     % 显式置空，供依赖检查识别。
elseif strcmp(cfg.stages.statistics, 'reuse')     % reuse 表示读取同一配置合同下的已有统计结果。
    % 读取统计 MAT 文件，并校验工况标识、版本和阶段名称。
    results.statistics = tblR2.load_result( ...
        paths.statistics, cfg, 'statistics', statistics_inputs);
else                                                % 默认分支：从序列缓存重新计算统计量。
    % 选择统计数据源：raw（原始PIV）或 postproc（后处理速度场）
    statistics_cache = paths.sequence_cache;        % 默认使用 raw 缓存
    if isfield(cfg, 'statistics_source') && strcmpi(cfg.statistics_source, 'postproc')
        statistics_cache = paths.sequence_cache_postproc;
        fprintf('[statistics] 数据源：postproc 缓存。\n');
    else
        fprintf('[statistics] 数据源：raw 缓存（默认）。\n');
    end
    % 选择统计帧范围：first_half=前6000帧 | second_half=后6000帧 | all=全12000帧
    stats_frame_mode = 'all';
    if isfield(cfg, 'statistics_frame_mode') && ~isempty(cfg.statistics_frame_mode)
        stats_frame_mode = cfg.statistics_frame_mode;
    end
    switch stats_frame_mode
        case 'first_half'
            stats_frame_range = [1, cfg.n_frames];
            fprintf('[statistics] 帧范围：前半段 1-%d（repeat 1）。\n', cfg.n_frames);
        case 'second_half'
            stats_frame_range = [cfg.n_frames + 1, cfg.total_frames];
            fprintf('[statistics] 帧范围：后半段 %d-%d（repeat 2）。\n', cfg.n_frames + 1, cfg.total_frames);
        otherwise
            stats_frame_range = [1, cfg.total_frames];
            fprintf('[statistics] 帧范围：全部 1-%d。\n', cfg.total_frames);
    end
    % 以块为单位计算均值、脉动量和有效样本掩膜，控制峰值内存。
    tblR2.result_inputs(cfg, 'statistics', statistics_inputs);
    results.statistics = tblR2.mean_stats_cache( ...
        statistics_cache, cfg.min_valid_fraction, ...
        cfg.chunk_frames, cfg.Uinf, stats_frame_range);
    % 保存统计结果，供后续运行直接 reuse。
    tblR2.save_result(paths.statistics, results.statistics, ...
        cfg, 'statistics', statistics_inputs);
end                                                 % 结束 statistics 阶段的三路模式分支。
results = tblR2.workspace_results('record', results, cfg, {'statistics'}, cfg.stages.statistics);
if ~strcmp(cfg.stages.mean_bl, 'skip')
    tblR2.workspace_results('require', results, cfg, {'statistics'});
end

if strcmp(cfg.stages.mean_bl, 'skip')             % skip 时不生成平均边界层和摩阻产品。
    results.mean_bl = [];                         % 显式置空，保持结果结构字段稳定。
elseif isempty(results.statistics)                % 没有统计输入时无法执行该阶段。
    % 依赖缺失要在入口处报告，避免在函数深处出现难以定位的错误。
    error('tblR2:caseScript:MissingStatistics', ...
        'mean_bl 阶段需要先完成 statistics 阶段。');
elseif strcmp(cfg.stages.mean_bl, 'reuse')         % reuse 时加载已有平均边界层结果。
    results.mean_bl = tblR2.load_result( ...
        paths.mean_bl, cfg, 'mean_bl', mean_bl_inputs);
else                                                % 默认从统计结果计算剖面、厚度和摩阻。
    tblR2.result_inputs(cfg, 'mean_bl', mean_bl_inputs);
    results.mean_bl = tblR2.mean_bl_friction(results.statistics, cfg); % 汇总边界层参数并计算 Cf。
    % 保存平均边界层结果，后续结构、输运和谱分析都直接读取该产品。
    tblR2.save_result(paths.mean_bl, results.mean_bl, cfg, 'mean_bl', mean_bl_inputs);
end                                                 % 结束 mean_bl 阶段的依赖和模式分支。
results = tblR2.workspace_results('record', results, cfg, {'mean_bl'}, cfg.stages.mean_bl);


% Section 2 完成后立即打开可见预览图；预览不保存文件，也不改变任何阶段结果。
if logical(cfg.preview.enabled)
    section2_preview_jobs = {'mean_turbulence', 'mean_profiles', ...
        'loglaw', 'loglaw_diagnostic', 'modern_clauser', 'friction'};   % Section 2 的核心图组预览任务。
    section2_preview = tblR2.plot_products( ...
        results, cfg, paths, 'preview', section2_preview_jobs);         % 直接复用精简图形层，图窗保持打开。
    if isempty(section2_preview.errors)
        fprintf('[Section 2预览] 已打开：%s。\n', ...
            strjoin(section2_preview_jobs, ', '));
    else
        for k = 1:numel(section2_preview.errors)
            item = section2_preview.errors(k);
            warning('tblR2:caseScript:Section2PreviewFailed', ...
                'Section 2 预览任务“%s”未完成：%s', ...
                item.job, item.message);
        end
    end
end

%% 3. 相位平均与三重分解
if ~exist('cfg', 'var') || ~exist('paths', 'var') || ~exist('results', 'var') || ...
        ~isfield(cfg, 'case_id') || ~strcmp(cfg.case_id, 'per_case/tandem_f40a3_phi0_r2') || ...
        ~isfield(paths, 'root') || ~strcmp(paths.root, cfg.output_dir)
    error('tblR2:caseScript:RunSection0', '请先运行本 case 的 Section 0，再运行本节。');
end
tblR2.workspace_results('require', results, cfg, {}, '', mfilename('fullpath'));
tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.workspace_results'});
if strcmp(cfg.stages.phase, 'compute')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.phase_stats_cache','tblR2.save_result'});
elseif strcmp(cfg.stages.phase, 'reuse')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.load_result'});
end

phase_inputs = struct('cache', paths.sequence_cache, 'statistics', paths.statistics);
if ~strcmp(cfg.stages.phase, 'skip')
    tblR2.require_case_library(fileparts(cfg.script_file), ...
        {'tblR2.result_inputs','tblR2.result_parameters','tblR2.sequence_cache_identity', ...
        'tblR2.validate_sequence_cache','tblR2.contract_difference','d23.sha256_text'});
end
results = tblR2.workspace_results('forget', results, cfg, {'phase'});
if strcmp(cfg.stages.phase, 'compute')
    tblR2.workspace_results('require', results, cfg, {'cache','statistics'});
end
% 本节对 baseline 也保留完整的阶段编排；baseline 仅通过 cfg.stages.phase='skip'
% 跳过执行，controlled 则将该模式改为 compute 或 reuse。
% compute：按 frame-clock 和 cfg.phase 逐块计算相位均值、相干分量与随机分量；
% reuse：读取 paths.phase 中已经保存的相位结果；skip：结果字段保持为空。
if strcmp(cfg.stages.phase, 'skip')                 % baseline 默认走此分支，不生成相位文件。
    results.phase = [];                             % 空值会让下游函数自动使用 total/no-phase 分支。
elseif strcmp(cfg.stages.phase, 'reuse')            % 复用已有相位结果，避免重复扫描 sequence cache。
    % 读取相位阶段产物，并校验其 case/stage/frame/grid/fs 合同。
    results.phase = tblR2.load_result(paths.phase, cfg, 'phase', phase_inputs);
else                                                 % compute：执行相位平均和三重分解。
    if isempty(results.statistics)                   % 相位均值需要 Section 2 的时间平均场。
        error('tblR2:caseScript:MissingPhaseInputs', ...
            'phase 阶段需要先完成 statistics 阶段。');
    end
    % 读取 raw sequence cache，按 cfg.chunk_frames 分块计算相位统计量。
    tblR2.result_inputs(cfg, 'phase', phase_inputs);
    results.phase = tblR2.phase_stats_cache( ...
        paths.sequence_cache, cfg, results.statistics);
    % 将相位统计结果保存为独立阶段产物，供下游 controlled 分支复用。
    tblR2.save_result(paths.phase, results.phase, cfg, 'phase', phase_inputs);
end                                                  % 结束 phase 阶段的 skip/reuse/compute 分支。
results = tblR2.workspace_results('record', results, cfg, {'phase'}, cfg.stages.phase);


% Section 3 完成后的即时预览：三重分解 Reynolds 应力剖面 + 相位平均速度云图。
% 绘制区域与剖面平均范围由 cfg.phase_preview 控制（见 Section 0）。
% 剖面图 x 范围默认取整个下游段，用户可收紧到激励器影响区以突出 coherent 分量。
if logical(cfg.preview.enabled) && ~isempty(results.phase) && ...
        isfield(results.phase, 'u_coherent')
    tblR2.workspace_results('require', results, cfg, {'statistics','mean_bl','phase'});
    fprintf('[Section 3预览] 开始生成三重分解诊断图…\n');

    % ---- 云图数据源独立处理 ----
    % 若云图指定使用 postproc 数据源，且与剖面图（继承自统计）数据源不同，则重新计算相位平均速度场。
    contour_source = 'raw';  % 默认继承 results.phase 的数据源
    if isfield(cfg.phase_preview, 'contour_source')
        contour_source = cfg.phase_preview.contour_source;
    end

    phase_contour = results.phase;  % 默认使用已计算的相位结果
    if strcmpi(contour_source, 'postproc') && ~strcmpi(cfg.statistics_source, 'postproc')
        fprintf('[Section 3预览] 云图数据源指定为 postproc，重新计算相位平均速度场用于可视化…\n');
        % 保留原 phase_stats_cache 完整调用；这里只将其 U_phase/V_phase 用于云图。
        tblR2.workspace_results('require', results, cfg, {'postproc_cache'});
        phase_contour = tblR2.phase_stats_cache( ...
            paths.sequence_cache_postproc, cfg, results.statistics);
        fprintf('[Section 3预览] postproc 相位平均速度场计算完成（仅用于云图绘制）。\n');
    end

    tblR2.require_case_library(fileparts(cfg.script_file), ...
        {'tblR2.plot_section3_preview','tblR2.plot_phase_averaged_maps', ...
        'tblR2.viz.resolve_case_colormap'});
    section3_preview = tblR2.plot_section3_preview(results, cfg, phase_contour);
    if ~isempty(section3_preview.errors)
        for k = 1:numel(section3_preview.errors)
            item = section3_preview.errors(k);
            warning('tblR2:caseScript:Section3PreviewFailed', '%s: %s', item.job, item.message);
        end
    else
    fprintf('[Section 3预览] 5张图已生成（3 Reynolds应力剖面 + 2 相位脉动云图）。\n');
    end
end

%% 4. PostProc + POD-E50 结构识别与专用图组
if ~exist('cfg', 'var') || ~exist('paths', 'var') || ~exist('results', 'var') || ...
        ~isfield(cfg, 'case_id') || ~strcmp(cfg.case_id, 'per_case/tandem_f40a3_phi0_r2') || ...
        ~isfield(paths, 'root') || ~strcmp(paths.root, cfg.output_dir)
    error('tblR2:caseScript:RunSection0', '请先运行本 case 的 Section 0，再运行本节。');
end
tblR2.workspace_results('require', results, cfg, {}, '', mfilename('fullpath'));
tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.workspace_results'});
if strcmp(cfg.stages.structures, 'compute')
    tblR2.require_case_library(fileparts(cfg.script_file), ...
        {'tblR2.section4_vlsm_analysis','tblR2.section4_vlsm_figures', ...
        'd23.default_config','d23.prepare_source','d23.build_pod_cache','d23.run_detection'});
elseif strcmp(cfg.stages.structures, 'reuse')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.load_result'});
end

if ~strcmp(cfg.stages.structures, 'skip')
    tblR2.require_case_library(fileparts(cfg.script_file), ...
        {'tblR2.select_section4_run','tblR2.section4_run_contract', ...
        'tblR2.result_parameters','tblR2.result_inputs','tblR2.load_result', ...
        'tblR2.save_result','tblR2.sequence_cache_identity', ...
        'tblR2.validate_sequence_cache','tblR2.contract_difference','d23.sha256_text'});
end
results = tblR2.workspace_results('forget', results, cfg, {'structures'});
% 真实输入是本 case 的 PostProc 缓存和已保存 mean_bl 文件；不需要工作区 phase/statistics。
% 已有工作区证据不能绕过：mean_bl 若已知过期，先明确更新对应文件。
% 独立 0→4 从保存的 mean_bl 检查生产参数和统计身份，无需 raw/DAT 在线。
if ~strcmp(cfg.stages.structures, 'skip') && ...
        isfield(results.workspace.records, 'mean_bl') && ~isempty(results.mean_bl)
    tblR2.workspace_results('require', results, cfg, {'mean_bl'});
end
if strcmp(cfg.stages.structures, 'skip')
    results.structures = [];
elseif strcmp(cfg.stages.structures, 'reuse')
    results.structures = tblR2.load_result(paths.structures, cfg, 'structures', ...
        struct('cache', paths.sequence_cache_postproc, 'mean_bl', paths.mean_bl));
else
    if ~isfile(paths.sequence_cache_postproc)
        error('tblR2:caseScript:MissingPostprocCache', ...
            'Section 4 缺少 PostProc 缓存：%s。请运行 Section 1 或放入已核实的本地缓存。', paths.sequence_cache_postproc);
    end
    if ~isfile(paths.mean_bl)
        error('tblR2:caseScript:MissingMeanBlFile', ...
            'Section 4 缺少 mean_bl 文件：%s。请运行 Section 2 mean_bl compute 或提供已核实文件。', paths.mean_bl);
    end
    results.structures = tblR2.section4_vlsm_analysis( ...
        paths.sequence_cache_postproc, cfg, paths.mean_bl, paths.structures);
end
results = tblR2.workspace_results('record', results, cfg, {'structures'}, cfg.stages.structures);

%% 5. 四象限分析与平面输运
if ~exist('cfg', 'var') || ~exist('paths', 'var') || ~exist('results', 'var') || ...
        ~isfield(cfg, 'case_id') || ~strcmp(cfg.case_id, 'per_case/tandem_f40a3_phi0_r2') || ...
        ~isfield(paths, 'root') || ~strcmp(paths.root, cfg.output_dir)
    error('tblR2:caseScript:RunSection0', '请先运行本 case 的 Section 0，再运行本节。');
end
tblR2.workspace_results('require', results, cfg, {}, '', mfilename('fullpath'));
tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.workspace_results'});
if ~strcmp(cfg.stages.transport, 'skip')
    tblR2.require_case_library(fileparts(cfg.script_file), ...
        {'tblR2.section5_run','tblR2.validate_sequence_cache','tblR2.transport_analysis','tblR2.transport_figures'});
end

results = tblR2.workspace_results('forget', results, cfg, {'transport'});
if strcmp(cfg.stages.transport, 'skip')
    results.transport = [];
else
    % Section 5 computes all required moments from its independently selected source.
    [results.transport, transport_output] = tblR2.section5_run( ...
        cfg, paths, cfg.stages.transport, true);
    paths.transport = fullfile(results.transport.output_dir, 'mat', '04_transport_quadrant.mat');
end
results = tblR2.workspace_results('record', results, cfg, {'transport'}, cfg.stages.transport);


%% 6. 时域谱与空间谱
if ~exist('cfg', 'var') || ~exist('paths', 'var') || ~exist('results', 'var') || ...
        ~isfield(cfg, 'case_id') || ~strcmp(cfg.case_id, 'per_case/tandem_f40a3_phi0_r2') || ...
        ~isfield(paths, 'root') || ~strcmp(paths.root, cfg.output_dir)
    error('tblR2:caseScript:RunSection0', '请先运行本 case 的 Section 0，再运行本节。');
end
tblR2.workspace_results('require', results, cfg, {}, '', mfilename('fullpath'));
tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.workspace_results'});
if strcmp(cfg.stages.temporal, 'compute')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.temporal_spectra_cache','tblR2.save_result'});
elseif strcmp(cfg.stages.temporal, 'reuse')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.load_result'});
end
if strcmp(cfg.stages.spatial, 'compute')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.spatial_spectra_cache','tblR2.save_result'});
elseif strcmp(cfg.stages.spatial, 'reuse')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.load_result'});
end

results = tblR2.workspace_results('forget', results, cfg, {'temporal', 'spatial'});
if strcmp(cfg.stages.temporal, 'compute') || ...
        strcmp(cfg.stages.spatial, 'compute')
    tblR2.workspace_results('require', results, cfg, {'statistics','mean_bl'});
end
analysis_cache = paths.sequence_cache_postproc; % 本节显式指定瞬时输入；不依赖先运行 Section 4。
if strcmp(cfg.stages.temporal, 'compute') || ...
        strcmp(cfg.stages.spatial, 'compute')
    if ~isfile(analysis_cache)
        error('tblR2:caseScript:MissingAnalysisCache', ...
            '本节缺少 PostProc 缓存：%s。请运行 Section 1 或提供已核实缓存。', analysis_cache);
    end
end
if strcmp(cfg.stages.temporal, 'skip')           % skip 时不计算时间频率谱。
    results.temporal = [];                        % 显式保留空字段，便于摘要列出 skipped。
elseif strcmp(cfg.stages.temporal, 'reuse')      % reuse 时读取已有时域谱 MAT 文件。
    results.temporal = tblR2.load_result( ...
        paths.temporal, cfg, 'temporal');
else                                                % 默认采用总样本序列计算 Welch/FFT 时域谱。
    % total 表示对两个重复序列拼接后的总体样本进行谱估计。
    results.temporal.total = tblR2.temporal_spectra_cache( ...
        analysis_cache, cfg, results.statistics, results.phase, ...
        results.mean_bl, 'total');
    % 写入时域谱结果，避免下次重复执行长时间 FFT。
    tblR2.save_result(paths.temporal, results.temporal, ...
        cfg, 'temporal');
end                                                 % 结束 temporal 阶段分支。
results = tblR2.workspace_results('record', results, cfg, {'temporal'}, cfg.stages.temporal);


if strcmp(cfg.stages.spatial, 'skip')             % skip 时不计算沿流向空间谱。
    results.spatial = [];                         % 保留字段，供总结果结构稳定访问。
elseif strcmp(cfg.stages.spatial, 'reuse')       % reuse 时读取已有空间谱结果。
    results.spatial = tblR2.load_result( ...
        paths.spatial, cfg, 'spatial');
else                                                % 默认对选定 y+ 剖面的流向序列执行空间 FFT。
    % total 表示使用合并重复序列的总体空间谱产品。
    results.spatial.total = tblR2.spatial_spectra_cache( ...
        analysis_cache, cfg, results.statistics, results.phase, ...
        results.mean_bl, 'total');
    % 保存空间谱结果和其有效样本诊断。
    tblR2.save_result(paths.spatial, results.spatial, ...
        cfg, 'spatial');
end                                                 % 结束 spatial 阶段分支。
results = tblR2.workspace_results('record', results, cfg, {'spatial'}, cfg.stages.spatial);


%% 7. 模态分析产品
if ~exist('cfg', 'var') || ~exist('paths', 'var') || ~exist('results', 'var') || ...
        ~isfield(cfg, 'case_id') || ~strcmp(cfg.case_id, 'per_case/tandem_f40a3_phi0_r2') || ...
        ~isfield(paths, 'root') || ~strcmp(paths.root, cfg.output_dir)
    error('tblR2:caseScript:RunSection0', '请先运行本 case 的 Section 0，再运行本节。');
end
tblR2.workspace_results('require', results, cfg, {}, '', mfilename('fullpath'));
tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.workspace_results'});
if strcmp(cfg.stages.pod, 'compute')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.pod_module','tblR2.save_result'});
elseif strcmp(cfg.stages.pod, 'reuse')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.load_result'});
end
if strcmp(cfg.stages.dmd, 'compute')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.dmd_module','tblR2.save_result'});
elseif strcmp(cfg.stages.dmd, 'reuse')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.load_result'});
end
if strcmp(cfg.stages.lcs, 'compute')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.lcs_ftle','tblR2.save_result'});
elseif strcmp(cfg.stages.lcs, 'reuse')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.load_result'});
end
if strcmp(cfg.stages.spod, 'compute')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.spod_cache','tblR2.save_result'});
elseif strcmp(cfg.stages.spod, 'reuse')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.load_result'});
end

results = tblR2.workspace_results('forget', results, cfg, {'pod', 'dmd', 'lcs', 'spod'});
if strcmp(cfg.stages.pod, 'compute') || ...
        strcmp(cfg.stages.dmd, 'compute') || ...
        strcmp(cfg.stages.lcs, 'compute') || ...
        strcmp(cfg.stages.spod, 'compute')
    tblR2.workspace_results('require', results, cfg, {'statistics','mean_bl'});
end
analysis_cache = paths.sequence_cache_postproc; % 本节显式指定瞬时输入；不依赖先运行 Section 4。
if strcmp(cfg.stages.pod, 'compute') || ...
        strcmp(cfg.stages.dmd, 'compute') || ...
        strcmp(cfg.stages.spod, 'compute')
    if ~isfile(analysis_cache)
        error('tblR2:caseScript:MissingAnalysisCache', ...
            '本节缺少 PostProc 缓存：%s。请运行 Section 1 或提供已核实缓存。', analysis_cache);
    end
end
if strcmp(cfg.stages.pod, 'skip')                % skip 时不执行 POD 随机化分解。
    results.pod = [];                             % 以空值表示没有 POD 产品。
elseif strcmp(cfg.stages.pod, 'reuse')           % reuse 时读取已有 POD 模态和能量结果。
    results.pod = tblR2.load_result(paths.pod, cfg, 'pod');
else                                                % 默认从瞬时缓存构造快照矩阵并计算 POD。
    % total 模式对合并后的全时段样本进行分解。
    results.pod.total = tblR2.pod_module(analysis_cache, cfg, ...
        results.statistics, results.phase, results.mean_bl, 'total');
    % 保存 POD 结果，包含模态、特征值和能量占比。
    tblR2.save_result(paths.pod, results.pod, cfg, 'pod');
end                                                 % 结束 POD 阶段分支。
results = tblR2.workspace_results('record', results, cfg, {'pod'}, cfg.stages.pod);

if strcmp(cfg.stages.dmd, 'skip')                % skip 时不执行 DMD 动力模态分析。
    results.dmd = [];                             % 以空值表示没有 DMD 产品。
elseif strcmp(cfg.stages.dmd, 'reuse')           % reuse 时读取已有 DMD 结果。
    results.dmd = tblR2.load_result(paths.dmd, cfg, 'dmd');
else                                                % 默认使用相邻快照构造 DMD 输入矩阵。
    % DMD 与 POD 使用同一总体样本，但采用 cfg.dmd 的空间抽样和随机种子。
    results.dmd.total = tblR2.dmd_module(analysis_cache, cfg, ...
        results.statistics, results.phase, results.mean_bl, 'total');
    % 保存 DMD 特征值、频率和空间模态。
    tblR2.save_result(paths.dmd, results.dmd, cfg, 'dmd');
end                                                 % 结束 DMD 阶段分支。
results = tblR2.workspace_results('record', results, cfg, {'dmd'}, cfg.stages.dmd);

if strcmp(cfg.stages.lcs, 'skip')                % skip 时不执行 Lagrangian LCS/FTLE。
    results.lcs = [];                             % 保留稳定字段，表示阶段未请求。
elseif strcmp(cfg.stages.lcs, 'reuse')           % reuse 时读取已有 FTLE 结果。
    results.lcs = tblR2.load_result(paths.lcs, cfg, 'lcs');
else                                                % 默认从后处理缓存执行规则网格 FTLE。
    lcs_branch = 'raw';
    if isfield(cfg.lcs, 'branch') && ~isempty(cfg.lcs.branch)
        lcs_branch = cfg.lcs.branch;
    end
    if strcmp(lcs_branch, 'random')
        tblR2.workspace_results('require', results, cfg, {'phase'});
    end
    lcs_cache = analysis_cache;
    if isfield(cfg.lcs, 'source_role') && strcmpi(cfg.lcs.source_role, 'raw')
        lcs_cache = paths.sequence_cache;
    elseif isfield(cfg.lcs, 'source_role') && ...
            ~strcmpi(cfg.lcs.source_role, 'postproc')
        error('tblR2:caseScript:InvalidLcsSourceRole', ...
            'cfg.lcs.source_role 必须是 raw 或 postproc。');
    end
    if ~isfile(lcs_cache)
        error('tblR2:caseScript:MissingLcsCache', ...
            'Section 7 LCS 缺少所选缓存：%s。请运行 Section 1 或提供已核实缓存。', lcs_cache);
    end
    results.lcs = tblR2.lcs_ftle(lcs_cache, cfg, ...
        results.statistics, results.mean_bl, lcs_branch, ...
        'phase_stats', results.phase);
    tblR2.save_result(paths.lcs, results.lcs, cfg, 'lcs');
end                                                 % 结束 lcs 阶段分支。
results = tblR2.workspace_results('record', results, cfg, {'lcs'}, cfg.stages.lcs);

if strcmp(cfg.stages.spod, 'skip')               % skip 时不执行频域 SPOD。
    results.spod = [];                             % 以空值表示没有 SPOD 产品。
elseif strcmp(cfg.stages.spod, 'reuse')          % reuse 时读取已有 SPOD 结果。
    results.spod = tblR2.load_result(paths.spod, cfg, 'spod');
else                                                % 默认按时间块计算频率分辨的空间模态。
    % SPOD 使用 cfg.spod 的 nfft、重叠比例和空间块自由度。
    results.spod.total = tblR2.spod_cache(analysis_cache, cfg, ...
        results.statistics, results.phase, results.mean_bl, 'total');
    % 保存 SPOD 模态、频率和能量谱，供图形阶段直接读取。
    tblR2.save_result(paths.spod, results.spod, cfg, 'spod');
end                                                 % 结束 SPOD 阶段分支。
results = tblR2.workspace_results('record', results, cfg, {'spod'}, cfg.stages.spod);


%% 8. 相关性与沿程发展
if ~exist('cfg', 'var') || ~exist('paths', 'var') || ~exist('results', 'var') || ...
        ~isfield(cfg, 'case_id') || ~strcmp(cfg.case_id, 'per_case/tandem_f40a3_phi0_r2') || ...
        ~isfield(paths, 'root') || ~strcmp(paths.root, cfg.output_dir)
    error('tblR2:caseScript:RunSection0', '请先运行本 case 的 Section 0，再运行本节。');
end
tblR2.workspace_results('require', results, cfg, {}, '', mfilename('fullpath'));
tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.workspace_results'});
if strcmp(cfg.stages.correlations, 'compute')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.correlation_analysis_cache','tblR2.save_result'});
elseif strcmp(cfg.stages.correlations, 'reuse')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.load_result'});
end
if strcmp(cfg.stages.harmonics, 'compute')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.streamwise_development_analysis','tblR2.save_result'});
elseif strcmp(cfg.stages.harmonics, 'reuse')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.load_result'});
end

results = tblR2.workspace_results('forget', results, cfg, {'correlations', 'harmonics'});
if strcmp(cfg.stages.correlations, 'compute') || ...
        strcmp(cfg.stages.harmonics, 'compute')
    tblR2.workspace_results('require', results, cfg, {'statistics','mean_bl'});
end
analysis_cache = paths.sequence_cache_postproc; % 本节显式指定瞬时输入；不依赖先运行 Section 4。
if strcmp(cfg.stages.correlations, 'compute')
    if ~isfile(analysis_cache)
        error('tblR2:caseScript:MissingAnalysisCache', ...
            '本节缺少 PostProc 缓存：%s。请运行 Section 1 或提供已核实缓存。', analysis_cache);
    end
end
if strcmp(cfg.stages.correlations, 'skip')        % skip 时不计算探针时间相关或空间相关。
    results.correlations = [];                    % 保留空字段，表示阶段已明确跳过。
elseif strcmp(cfg.stages.correlations, 'reuse')   % reuse 时读取已有相关性产品。
    results.correlations = tblR2.load_result( ...
        paths.correlations, cfg, 'correlations');
else                                                % 默认计算配置中启用的基础相关性产品。
    % 只有 cfg.correlations 中显式打开的扩展相关才会进入函数库计算。
    results.correlations.total = tblR2.correlation_analysis_cache( ...
        analysis_cache, cfg, results.statistics, results.phase, ...
        results.mean_bl, 'total');
    % 保存相关性矩阵、滞后坐标和质量诊断。
    tblR2.save_result(paths.correlations, results.correlations, ...
        cfg, 'correlations');
end                                                 % 结束 correlations 阶段分支。
results = tblR2.workspace_results('record', results, cfg, {'correlations'}, cfg.stages.correlations);

if strcmp(cfg.stages.harmonics, 'compute')
    if strcmp(cfg.case_type, 'controlled')
        tblR2.workspace_results('require', results, cfg, {'phase'});
    end
    optional_inputs = {'structures','transport','temporal','spatial','pod','dmd','lcs','spod','correlations'};
    for input_index = 1:numel(optional_inputs)
        input_name = optional_inputs{input_index};
        if ~isempty(results.(input_name))
            tblR2.workspace_results('require', results, cfg, {input_name});
        end
    end
end
if strcmp(cfg.stages.harmonics, 'skip')           % skip 时不生成沿程发展/谐波汇总。
    results.harmonics = [];                        % 以空值表示阶段未运行。
elseif strcmp(cfg.stages.harmonics, 'reuse')      % reuse 时读取已有汇总结果。
    results.harmonics = tblR2.load_result( ...
        paths.harmonics, cfg, 'harmonics');
else                                                % 默认整合结构、输运、谱和相关性沿程指标。
    % 该函数只接收已经生成的结果结构，主脚本保持数据流清晰可见。
    results.harmonics = tblR2.streamwise_development_analysis( ...
        results, cfg);
    % 保存沿程发展和谐波汇总产品。
    tblR2.save_result(paths.harmonics, results.harmonics, ...
        cfg, 'harmonics');
end                                                 % 结束 harmonics 阶段分支。
results = tblR2.workspace_results('record', results, cfg, {'harmonics'}, cfg.stages.harmonics);


%% 9. 图形导出与机器可读摘要
if ~exist('cfg', 'var') || ~exist('paths', 'var') || ~exist('results', 'var') || ...
        ~isfield(cfg, 'case_id') || ~strcmp(cfg.case_id, 'per_case/tandem_f40a3_phi0_r2') || ...
        ~isfield(paths, 'root') || ~strcmp(paths.root, cfg.output_dir)
    error('tblR2:caseScript:RunSection0', '请先运行本 case 的 Section 0，再运行本节。');
end
tblR2.workspace_results('require', results, cfg, {}, '', mfilename('fullpath'));
tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.workspace_results'});
if strcmp(cfg.stages.figures, 'compute')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.plot_products','tblR2.save_result'});
elseif strcmp(cfg.stages.figures, 'reuse')
    tblR2.require_case_library(fileparts(cfg.script_file), {'tblR2.load_result'});
end

results = tblR2.workspace_results('forget', results, cfg, {'figures'});
if strcmp(cfg.stages.figures, 'compute')
    tblR2.workspace_results('require', results, cfg, {'statistics'});
    % Existing products may be drawn only while current; optional missing products
    % keep the original plot_products error/skip behavior and its explicit errors list.
    available_inputs = {'mean_bl','phase','structures','transport','temporal','spatial', ...
        'pod','dmd','lcs','spod','correlations','harmonics'};
    for input_index = 1:numel(available_inputs)
        input_name = available_inputs{input_index};
        if ~isempty(results.(input_name))
            tblR2.workspace_results('require', results, cfg, {input_name});
        end
    end
end
if strcmp(cfg.stages.figures, 'skip')             % skip 时不创建图形文件，但保留空清单。
    results.figures = [];                         % 摘要仍会记录 figures=skipped。
elseif strcmp(cfg.stages.figures, 'reuse')        % reuse 时读取已有图形清单，不重复导出。
    results.figures = tblR2.load_result( ...
        paths.figure_manifest, cfg, 'figures');
else                                                % 默认按 cfg.figures.jobs 导出核心科研图形。
    if isempty(results.statistics)                  % 基础统计缺失时无法生成平均场图形。
        % 允许用户改为 reuse 图形清单，但不允许无输入静默导出空图。
        error('tblR2:caseScript:MissingFigureInputs', ...
            '图形导出需要已完成的 statistics，或可复用的图形清单。');
    end                                             % 结束图形输入检查。
    % 图形函数根据任务清单逐项导出 PNG/FIG，并返回文件清单和错误记录。
    results.figures = tblR2.plot_products( ...
        results, cfg, paths, 'export', cfg.figures.jobs);
    % 保存图形清单，使后续摘要能够复用而不重新打开所有图窗。
    tblR2.save_result(paths.figure_manifest, results.figures, ...
        cfg, 'figures');
end                                                 % 结束 figures 阶段分支。
results = tblR2.workspace_results('record', results, cfg, {'figures'}, cfg.stages.figures);


% 固定摘要中的阶段顺序，使不同运行之间的产品清单可直接比较。
stage_names = {'cache','statistics','mean_bl','phase','structures', ...
    'transport','temporal','spatial','pod','dmd','lcs','spod', ...
    'correlations','harmonics','figures'};
% 预分配产品清单结构，避免循环中动态扩展数组。
products = repmat(struct('stage','','status','','file',''), ...
    numel(stage_names), 1);
for k = 1:numel(stage_names)                      % 逐阶段填充名称、状态和产物文件路径。
    stage = stage_names{k};                       % 取出当前阶段名称。
    products(k).stage = stage;                    % 写入摘要中的阶段字段。
    if isfield(results.workspace.records, stage) && ~isempty(results.(stage))
        try
            tblR2.workspace_results('require', results, cfg, {stage});
            if strcmp(stage, 'cache')
                tblR2.workspace_results('require', results, cfg, {'postproc_cache'});
            end
            products(k).status = 'completed';
        catch problem
            if startsWith(problem.identifier, 'tblR2:workspace:')
                products(k).status = 'stale';
            else
                rethrow(problem);
            end
        end
    elseif strcmp(cfg.stages.(stage), 'skip')
        products(k).status = 'skipped';
    else
        products(k).status = 'not_run';
    end
    products(k).file = stage_file(paths, stage);  % 关联该阶段对应的 MAT 或清单文件。
end                                                 % 结束产品清单构造。
% 记录完成时间，与本 case 工作区初始化时刻配对。
started_utc = results.workspace.started_utc;
finished_utc = char(datetime('now', 'TimeZone', 'UTC', ...
    'Format', 'yyyy-MM-dd''T''HH:mm:ssXXX'));
% 图形阶段允许单个任务受限；有错误记录时整体标记为“带限制完成”。
if ~isempty(results.figures) && isfield(results.figures, 'errors') && ...
        ~isempty(results.figures.errors)
    overall_status = 'completed_with_limits';       % 计算完成，但部分图形任务存在错误记录。
elseif any(ismember({products.status}, {'not_run','stale'}))
    overall_status = 'partial'; % Run Section 不等于其余已配置阶段已经运行。
else
    overall_status = 'completed';
end                                                 % 结束总体状态判断。
% 汇总工况身份、运行时间、输出根目录、阶段清单和全部结果引用。
report = struct('case_id', cfg.case_id, 'status', overall_status, ...
    'started_utc', started_utc, 'finished_utc', finished_utc, ...
    'output_root', paths.root, ...
    'products', products, 'results', results);
tblR2.write_summary(report, paths);                 % 写入 JSON/Markdown 摘要供机器和人工读取。
fprintf('本次分节状态：%s。输出根目录：%s\n', overall_status, paths.root);    % 在命令窗口给出最终产物位置。

% 将阶段名称映射到对应的 MAT 产物路径，供摘要和工况卡片使用。
function filename = stage_file(paths, stage)
switch stage                                         % 将阶段名转换为 paths 中的具体文件字段。
    case 'cache'; filename = paths.sequence_cache;   % 原始序列缓存文件。
    case 'statistics'; filename = paths.statistics;  % 分块统计结果文件。
    case 'mean_bl'; filename = paths.mean_bl;        % 平均边界层和摩阻结果文件。
    case 'phase'; filename = paths.phase;             % 相位平均和三重分解结果文件。
    case 'structures'; filename = paths.structures;  % 结构识别结果文件。
    case 'transport'; filename = paths.transport;    % 输运分析结果文件。
    case 'temporal'; filename = paths.temporal;      % 时域谱结果文件。
    case 'spatial'; filename = paths.spatial;        % 空间谱结果文件。
    case 'pod'; filename = paths.pod;                % POD 结果文件。
    case 'dmd'; filename = paths.dmd;                % DMD 结果文件。
    case 'lcs'; filename = paths.lcs;                % LCS/FTLE 结果文件。
    case 'spod'; filename = paths.spod;              % SPOD 结果文件。
    case 'correlations'; filename = paths.correlations; % 相关性结果文件。
    case 'harmonics'; filename = paths.harmonics;    % 沿程/谐波汇总文件。
    case 'figures'; filename = paths.figure_manifest; % 图形清单文件。
    otherwise; filename = '';                        % 未知阶段不关联任何产物。
end                                                     % 结束文件路径映射。
end                                                     % 结束 stage_file 本地函数。
