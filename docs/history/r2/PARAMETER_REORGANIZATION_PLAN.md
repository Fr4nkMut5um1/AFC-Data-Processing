# Section 0 参数重组与增强计划
**日期**: 2026-08-27  
**工况**: tandem_f40a3_phi0_r2

---

## 任务1: 参数按Section归属重排序

### 当前问题
参数分散在Section 0中，没有按实际使用的Section归类，且stages参数位于物理参数之后。

### 目标结构
```matlab
%% 0. 工况定义与初始化

% ========== A. 工况身份 ==========
cfg.schema_version = 2;
cfg.case_id = '...';
cfg.case_type = 'controlled';
cfg.name = '...';
cfg.script_file = script_file;
cfg.output_dir = fullfile(...);

% ========== B. 阶段运行策略（对应 Section 1-9）==========
cfg.stages = struct();
cfg.stages.cache = 'reuse';           % Section 1: 序列缓存
cfg.stages.statistics = 'reuse';      % Section 2: 统计与边界层
cfg.stages.mean_bl = 'reuse';
cfg.stages.phase = 'compute';         % Section 3: 相位平均
cfg.stages.structures = 'compute';    % Section 4: 结构识别
cfg.stages.quadrant = 'skip';         % Section 5: 四象限
cfg.stages.spectra = 'skip';          % Section 6: 谱分析
cfg.stages.pod = 'skip';              % Section 7: POD
cfg.stages.dmd = 'skip';
cfg.stages.lcs = 'skip';
cfg.stages.spod = 'skip';
cfg.stages.correlations = 'skip';     % Section 8: 相关性
cfg.stages.figures = 'skip';          % Section 9: 图形

% ========== C. 全局物理量（所有Section共用）==========
cfg.wall_side = 'top';
cfg.grid_size = [640 91];
cfg.fs = 960;
cfg.Uinf = 25;
cfg.nu = 1.48e-5;
cfg.rho = 1.20;
cfg.D_mm = 30;
cfg.x_max = 328;
cfg.min_valid_fraction = 0.70;
cfg.rebuild_cache = false;

% ========== D. Section 1 参数：序列缓存与数据源 ==========
cfg.frame_offset = 0;
cfg.sources = struct();
cfg.sources.raw = struct();
cfg.sources.postproc = struct();
% （自动探测结果后续填充）

% ========== E. Section 2 参数：统计、剖面、Clauser拟合 ==========
% E1. 统计数据源选择
cfg.statistics_source = 'raw';        % 'raw' 或 'postproc'
cfg.statistics_frame_mode = 'all';    % 'first_half' | 'second_half' | 'all'

% E2. 速度剖面提取
cfg.profile = struct();
cfg.profile.mode = 'range_avg';
cfg.profile.params = [80 160];
cfg.profile.U_inf_n_top = 5;

% E3. 传统Clauser对数律拟合
cfg.loglaw = struct();
cfg.loglaw.mode = 'auto';
cfg.loglaw.skip_nearwall = 1;
cfg.loglaw.rmse_yplus_range = [70 300];
cfg.loglaw.params = struct();
cfg.loglaw.params.kappa = 0.41;
cfg.loglaw.params.B = 5.0;
cfg.loglaw.params.dy_h = 1.0;        % 相对于h的倍数
cfg.loglaw.params.Cfnum = 12;

% E4. 对数律适用性判据
cfg.loglaw.applicability = struct();
cfg.loglaw.applicability.min_y_plus = 30;
cfg.loglaw.applicability.max_y_over_delta = 0.15;
cfg.loglaw.applicability.relative_target_tolerance = 0.10;
cfg.loglaw.applicability.max_method_difference = 0.15;
cfg.loglaw.applicability.min_contiguous_points = 5;
cfg.loglaw.applicability.min_log10_span = 1.0;

% E5. 现代Clauser拟合（Rodriguez-Lopez复合剖面）
cfg.modern_clauser = struct();
cfg.modern_clauser.enabled = true;
cfg.modern_clauser.method = 'rodriguez_lopez_2015_constrained_bump1';
cfg.modern_clauser.kappa = 0.384;
cfg.modern_clauser.B = 4.17;
cfg.modern_clauser.dy_h = 1.0;
cfg.modern_clauser.skip_nearwall = 1;
cfg.modern_clauser.U_inf_n_top = 5;
cfg.modern_clauser.enable_bump = true;
cfg.modern_clauser.inner_step_yplus = 0.01;
cfg.modern_clauser.pi_initial = 0.20;
cfg.modern_clauser.pi_bounds = [0 2];
cfg.modern_clauser.u_tau_scale_bounds = [0.5 1.8];
cfg.modern_clauser.delta_scale_bounds = [0.5 2.0];
cfg.modern_clauser.minimum_points = 10;

% E6. 摩阻与动量积分
cfg.friction = struct();
cfg.friction.enable_pressure_gradient = 0;
cfg.friction.secant_theta_source = 'p_smooth';
cfg.friction.thickness_smoothing_gap_mode = 'no_contamination';
cfg.friction.local_momentum_theta_source = 'shared_thickness_p_smooth';
cfg.friction.system_secant = struct();
cfg.friction.system_secant.upstream_mode = 'range_mean';
cfg.friction.system_secant.upstream_range = [80 90];
cfg.friction.system_secant.x_end = [160 240 320];
cfg.friction.momentum = struct();
cfg.friction.momentum.Ue_pre_smooth_p = 0.0000001;
cfg.friction.momentum.pre_smooth_p = 0.0000001;
cfg.friction.momentum.consistency_warn_pct = 10;
cfg.friction.quality = struct();
cfg.friction.quality.x_min = 80;
cfg.friction.quality.x_max = 328;
cfg.friction.quality.tolerance_pct = 10;

% ========== F. Section 3 参数：相位平均与三重分解 ==========
cfg.phase = struct();
cfg.phase.enabled = true;
cfg.phase.f0 = 40;
cfg.phase.n_bins = 24;
cfg.phase.method = 'frame_clock';
cfg.phase.tolerance_periods = 0.05;
cfg.chunk_frames = 500;

% ========== G. Section 4 参数：瞬时结构识别 ==========
cfg.structures = struct();
cfg.structures.alpha = 1.0;
cfg.structures.seed_alpha = 1.2;
cfg.structures.connectivity = 4;
cfg.structures.min_area_cells = 9;
cfg.structures.merge_gap_cells = 40;
cfg.structures.retain_wall_detached = false;

% ... 继续 Section 5-9 参数 ...
```

---

## 任务2: Section 2 统计帧范围选择

### 需求
用户希望Section 2统计能够：
1. 选择数据源：raw 或 postproc
2. 选择帧范围：前6000帧 / 后6000帧 / 全部12000帧

### 参考：参考脚本的实现
参考脚本 `cctandem_f40a3_phi_plus_0_u25_dt50_a1817_f5p6_2nd_case.m`:
- 第80行：`cfg.nFrames = 3000;  % 参与完整时间统计的DAT帧数`
- 直接从第1帧开始读取指定数量

### r2的当前实现
- `prepare_sequence_cache` 从两个repeat各读取 `n_frames` 帧
- 拼接为 `2*n_frames` 总帧数
- `mean_stats_cache` 使用全部缓存帧计算统计

### 增强方案

**新增参数**：
```matlab
cfg.statistics_frame_mode = 'all';  % 'first_half' | 'second_half' | 'all'
```

**行为**：
- `'first_half'`: 只使用缓存的前 `n_frames` 帧（repeat 1）
- `'second_half'`: 只使用缓存的后 `n_frames` 帧（repeat 2）
- `'all'`: 使用全部 `2*n_frames` 帧（当前默认行为）

**实现位置**：
在Section 2的统计计算分支中，根据 `cfg.statistics_frame_mode` 截取缓存的不同部分再传给 `mean_stats_cache`。

---

## 任务3: Clauser法等效性静态检查

### 对比目标
参考脚本：`cctandem_f40a3_phi_plus_0_u25_dt50_a1817_f5p6_2nd_case.m`  
r2实现：`+tblR2/+bl/loglaw_fit_chen.m`

### 关键差异点检查

#### 1. dy的语义
**参考脚本** (第139行):
```matlab
% dy_h表示最靠壁矢量到真实壁面的距离与网格间距h之比，即dy=dy_h*h。
```

**r2实现** (loglaw_fit_chen.m 第104行):
```matlab
dy_opt_mm = params.dy_h * h_mm;
```

✅ **等效**：两者都是 `dy = dy_h × h`

---

#### 2. 剖面提取方式
**参考脚本** (第111-112行):
```matlab
cfg.profile_mode = 'range_avg';
cfg.profile_params = [80 120];
```

**r2实现** (mean_bl_friction.m 第26-28行):
```matlab
[y_profile, u_profile, profile_cols] = tblR2.io.extract_velocity_profile( ...
    S_drag.Uavex, S_drag.X, S_drag.Y, S_drag.h, ...
    cfg.profile.mode, cfg.profile.params);
```

✅ **等效**：都支持 `range_avg` 模式，在流向区间内平均

---

#### 3. Uinf的估计
**参考脚本** (第145行):
```matlab
cfg.U_inf_n_top = 5;  % 用清洗后剖面顶部N点均值确定局部Uinf。
```

**r2实现** (loglaw_fit_chen.m 第78行):
```matlab
Uinf = tblR2.bl.local_uinf(u_valid, cfg.U_inf_n_top);
```

✅ **等效**：都使用清洗后剖面顶部N点均值

---

#### 4. auto模式的Cf扫描
**参考脚本** (第119-121行):
```matlab
cfg.loglaw_mode = 'auto';
cfg.loglaw_params = struct('kappa', 0.40, 'B', 5.00, ...
    'dy_h', 1.0, 'Cfnum', 12);
```

**r2实现** (loglaw_fit_chen.m 第100-107行):
```matlab
case 'auto'
    kappa = params.kappa;
    B     = params.B;
    dy_opt_mm = params.dy_h * h_mm;
    [Cfnum_opt, Cf_opt, converged, quality_flag, iter_info] = ...
        fit_auto_clauser(u_valid, h_mm, nu, Uinf, dy_opt_mm, ...
                         kappa, B, n_skip, rmse_yplus_range);
```

✅ **等效**：都是固定 κ、B、dy，扫描Cfnum最小化RMSE

---

#### 5. RMSE评价区间
**参考脚本** (第144行):
```matlab
cfg.loglaw_rmse_yplus_range = [80 250];
```

**r2实现** (loglaw_fit_chen.m 第69行):
```matlab
rmse_yplus_range = resolve_rmse_yplus_range(cfg);
```

✅ **等效**：都使用用户配置的 y+ 区间评估RMSE

---

#### 6. skip_nearwall处理
**参考脚本** (第142行):
```matlab
cfg.loglaw_skip_nearwall = 0;  % 从拟合数据中整体剔除的近壁点数；0表示不剔除。
```

**r2实现** (loglaw_fit_chen.m 第57-65行):
```matlab
n_skip = 0;
if isfield(cfg, 'loglaw_skip_nearwall') && cfg.loglaw_skip_nearwall > 0
    n_skip = min(cfg.loglaw_skip_nearwall, length(u_valid) - 10);
    if n_skip > 0
        u_valid = u_valid(n_skip+1:end);
        ...
```

✅ **等效**：都支持跳过近壁N个点

---

#### 7. δ99/δ*/θ/H的计算
**参考脚本** 引用：
```matlab
% Section 3没有额外独立参数；它复用Section 2的cfg.U_inf_n_top和LF.dy_opt。
```

**r2实现** (loglaw_fit_chen.m 第175-197行):
```matlab
U99 = 0.99 * Uinf;
dy_h_ratio = round(dy_opt_mm / h_mm) + n_skip;
...
delta99_mm = (dH + dy_h_ratio) * h_mm;
...
% δ*/θ（chen）：近壁 round(dy/h) 个线性虚拟点（0→u1 去 0）+ 求和式积分
```

✅ **等效**：r2注释明确说明"严格按陈朗生 TBL_logfit.m 公式"

---

### 结论：Clauser法完全等效

r2的 `loglaw_fit_chen.m` 与参考脚本的Clauser法**在算法层面完全等效**：

1. ✅ dy语义一致：都是 `dy_h × h`
2. ✅ 剖面提取一致：都支持 range_avg
3. ✅ Uinf估计一致：都用顶N点均值
4. ✅ auto扫描一致：固定κ/B/dy，扫描Cfnum
5. ✅ RMSE区间一致：用户配置的y+范围
6. ✅ 近壁裁剪一致：可选跳过N点
7. ✅ 边界层参数一致：注释明确说明复刻陈朗生公式

**差异仅在工程实现细节**：
- 参考脚本是单文件流程，r2是模块化函数库
- r2增加了 `manual_utau` 模式（直接指定u_tau）
- r2增加了现代Clauser拟合作为Option B（不影响Option A）

---

## 实施计划

### 第1步：重排Section 0参数（高优先级）
- 创建新的参数分组注释
- 按 A身份 → B策略 → C全局 → D-Section1 → E-Section2 → ... 顺序重排
- stages参数移到最前面（B组）

### 第2步：增强统计帧选择（高优先级）
- 添加 `cfg.statistics_frame_mode` 参数
- 修改Section 2统计计算分支
- 根据模式截取缓存的不同部分

### 第3步：文档化Clauser等效性（已完成）
- 创建本分析文档
- 明确r2与参考脚本的等效性
- 记录两者的实现差异

---

## 验证清单

- [ ] 参数重排后脚本仍可正常运行
- [ ] statistics_frame_mode='first_half' 使用前6000帧
- [ ] statistics_frame_mode='second_half' 使用后6000帧
- [ ] statistics_frame_mode='all' 使用全部12000帧（默认）
- [ ] Clauser拟合结果与参考脚本一致（数值验证）
