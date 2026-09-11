# 论文结构方案（中英双语）

## Paper Structure Proposal (Dual Language)

**日期 Date**: 2026-09-06  
**实验背景 Experimental Context**: 零质量通量音圈膜执行器（tandem/parallel），频率扫描 f=20-80 Hz，振幅扫描 A=0.3-3 mm，相位扫描 φ=0°-180°，Re_τ≈2100

---

## 1. Introduction（引言）

### 1.1 Turbulent boundary layers and drag reduction（湍流边界层与减阻）
- Wall turbulence as a major source of drag in aeronautical and marine applications  
  壁湍流是航空、航海中阻力的主要来源
- Economic and environmental motivation for drag reduction  
  减阻的经济与环境动机

### 1.2 Very-large-scale motions (VLSM) in wall turbulence（壁湍流中的超大尺度运动）
- Definition and characteristics: streamwise extent Lx > 3δ, dominant contribution to Reynolds stress  
  定义与特征：流向尺度 Lx > 3δ，对 Reynolds 应力的主导贡献
- Role in skin-friction generation (Kim & Adrian 1999, Hutchins & Marusic 2007)  
  在摩阻生成中的作用（Kim & Adrian 1999，Hutchins & Marusic 2007）

### 1.3 Active control of VLSM: state of the art（VLSM 主动控制：研究现状）
- Zero-net-mass-flux actuators (synthetic jets, dielectric barrier discharge)  
  零净质量通量执行器（合成射流、介质阻挡放电）
- Phase-dependent effectiveness (Toedtli et al. 2019 PRF: phase strongly affects drag reduction)  
  相位依赖性（Toedtli et al. 2019 PRF：相位强烈影响减阻效果）
- Receptivity framework (Duvvuri & McKeon 2015/2016, Jacobi & McKeon 2017)  
  感受性框架（Duvvuri & McKeon 2015/2016，Jacobi & McKeon 2017）

### 1.4 Knowledge gaps and research objectives（知识缺口与研究目标）
- **Gap 1**: Systematic parametric study (f, A, φ) targeting VLSM scale (St_δ ≲ 0.1) is lacking  
  **缺口 1**：缺乏针对 VLSM 尺度（St_δ ≲ 0.1）的系统参数研究（f, A, φ）
- **Gap 2**: Streamwise tandem vs. spanwise parallel configurations未被系统比较  
  **缺口 2**：流向串列与展向并列构型未被系统比较
- **Novelty**: Geometric deformation (zero-net-mass-flux) + VLSM-scale forcing (St_δ ≲ 0.1) + systematic phase sweep + dual configurations (tandem/parallel) at Re_τ > 2000  
  **新颖性**：几何变形（零净质量通量）+ VLSM 尺度激励（St_δ ≲ 0.1）+ 系统相位扫描 + 双构型（串列/并列）在 Re_τ > 2000

### 1.5 Paper organization（论文组织）
Brief outline of Sections 2–8  
第 2–8 节简要概述

---

## 2. Experimental Methods（实验方法）

### 2.1 Facility and flow conditions（实验设备与流动条件）
- Wind tunnel specifications  
  风洞技术参数
- Freestream velocity U∞ = 25 m/s, Reynolds number Re_τ ≈ 2100  
  自由流速度 U∞ = 25 m/s，Reynolds 数 Re_τ ≈ 2100
- Boundary layer thickness δ₉₉ ≈ 33 mm, viscous length scale ν/u_τ  
  边界层厚度 δ₉₉ ≈ 33 mm，黏性长度尺度 ν/u_τ

### 2.2 Actuator design and configurations（执行器设计与构型）
- Voice-coil membrane actuator (zero-net-mass-flux)  
  音圈膜执行器（零净质量通量）
- **Tandem**: streamwise arrangement, spacing Δx  
  **串列**：流向布置，间距 Δx
- **Parallel**: spanwise arrangement, spacing Δz  
  **并列**：展向布置，间距 Δz
- Actuation parameters: frequency f = 20–80 Hz, amplitude A = 0.3–3 mm, phase φ = 0°–180°  
  激励参数：频率 f = 20–80 Hz，振幅 A = 0.3–3 mm，相位 φ = 0°–180°

### 2.3 PIV measurement system（PIV 测量系统）
- Field of view (FOV): 248 mm × 47 mm (≈ 7.5δ × 1.4δ)  
  视场：248 mm × 47 mm（≈ 7.5δ × 1.4δ）
- Spatial resolution: 7.7 pixel/mm → Δx = 0.39 mm, Δy = 0.52 mm  
  空间分辨率：7.7 pixel/mm → Δx = 0.39 mm，Δy = 0.52 mm
- Wall-normal resolution in wall units: Δy⁺ ≈ 34 (first measurable point at y⁺ ≈ 34)  
  壁面法向分辨率（壁面单位）：Δy⁺ ≈ 34（第一个可测点在 y⁺ ≈ 34）
- Temporal resolution: fs = 960 Hz, Δt ≈ 1.04 ms  
  时间分辨率：fs = 960 Hz，Δt ≈ 1.04 ms
- **Measurement limitations**: buffer layer (y⁺ < 30) not resolved, no extrapolation performed  
  **测量限制**：缓冲层（y⁺ < 30）未分辨，不进行外推

### 2.4 Phase-locked data acquisition（相位锁定数据采集）
- Trigger signal synchronized with actuator motion  
  触发信号与执行器运动同步
- Phase bins: 24 bins per actuation cycle (f₀ = 40 Hz)  
  相位箱：每个激励周期 24 个箱（f₀ = 40 Hz）
- Data ensembles: 6000 frames per repeat, 2 repeats → 12000 total frames  
  数据集合：每个重复 6000 帧，2 次重复 → 总计 12000 帧

### 2.5 Data processing pipeline（数据处理流程）

#### 2.5.1 POD-based noise suppression（基于 POD 的去噪）
- Snapshot POD on raw PIV velocity fields  
  对原始 PIV 速度场进行快照 POD
- Energy threshold: E = 50% (rank ≈ 382 modes retained)  
  能量阈值：E = 50%（保留 ≈ 382 阶模态）
- Low-rank reconstruction suppresses measurement noise while preserving VLSM scales  
  低秩重构抑制测量噪声同时保留 VLSM 尺度

#### 2.5.2 Triple decomposition（三重分解）
For phase-locked cases:
对于相位锁定工况：

u(x, y, t) = ⟨u⟩(x, y) + ũ(x, y, φ) + u″(x, y, t)

- ⟨u⟩: time-averaged mean flow  
  ⟨u⟩：时间平均流动
- ũ: phase-coherent component (periodic at f₀)  
  ũ：相位相干分量（以 f₀ 为周期）
- u″: random turbulent fluctuation  
  u″：随机湍流脉动

#### 2.5.3 VLSM identification（VLSM 识别）
- Threshold: u′/u_rms > α_seed (α_seed for high-intensity cores), u′/u_rms > α_extend (α_extend for weak envelopes)  
  阈值：u′/u_rms > α_seed（高强度核心），u′/u_rms > α_extend（弱外包络）
- Hysteresis threshold: α_seed = 1.77, α_extend = 1.50  
  滞后阈值：α_seed = 1.77，α_extend = 1.50
- Connectivity analysis: 4-neighbor connectivity, separate positive/negative events  
  连通性分析：4 邻域连通，正/负事件分离
- Scale criterion: Lx/δ ≥ 3.0 (VLSM), 1.0 ≤ Lx/δ < 3.0 (LSM)  
  尺度判据：Lx/δ ≥ 3.0（VLSM），1.0 ≤ Lx/δ < 3.0（LSM）
- Gaussian smoothing: σ = 1.5 cells, radius = 4 cells (applied only to structure identification input, not to cached statistics)  
  高斯平滑：σ = 1.5 格，半径 = 4 格（仅用于结构识别输入，不覆盖统计缓存）

#### 2.5.4 Drag estimation（阻力估计）
- Local momentum integral method with pressure gradient correction  
  考虑压力梯度修正的局部动量积分法
- System secant method: averaged Cf over streamwise range x ∈ [160, 240] mm  
  系统割线法：沿程平均 Cf，范围 x ∈ [160, 240] mm
- Modern Clauser chart fitting (Rodriguez-Lopez et al. 2015 composite profile)  
  现代 Clauser 图拟合（Rodriguez-Lopez et al. 2015 复合剖面）

---

## 3. Baseline Flow Characteristics（基准流动特性）

### 3.1 Mean flow and turbulence statistics（平均流动与湍流统计）
- Mean velocity profile ⟨U⟩/U∞, turbulence intensities u_rms/U∞, v_rms/U∞  
  平均速度剖面 ⟨U⟩/U∞，湍流强度 u_rms/U∞，v_rms/U∞
- Reynolds stress distribution ⟨-u′v′⟩/U∞²  
  Reynolds 应力分布 ⟨-u′v′⟩/U∞²
- Boundary layer integral parameters: δ₉₉, θ, δ*, shape factor H  
  边界层积分参数：δ₉₉，θ，δ*，形状因子 H

### 3.2 VLSM population and scale distribution（VLSM 数量与尺度分布）
- Catalog of detected VLSM events: count, streamwise extent Lx/δ, wall-normal centroid ⟨y_c/δ⟩  
  检测到的 VLSM 事件目录：数量、流向尺度 Lx/δ、法向质心 ⟨y_c/δ⟩
- Histogram of Lx/δ (compare with Kim & Adrian 1999, Hutchins & Marusic 2007)  
  Lx/δ 直方图（与 Kim & Adrian 1999，Hutchins & Marusic 2007 比较）
- Instantaneous snapshots showing VLSM spatial structure  
  显示 VLSM 空间结构的瞬时快照

### 3.3 Spectral signatures（谱特征）
- **Temporal spectra**: premultiplied PSD f·Φ_uu vs. λ_x⁺ (inner scaling) and St_δ (outer scaling)  
  **时域谱**：预乘 PSD f·Φ_uu vs. λ_x⁺（内尺度）和 St_δ（外尺度）
- Peak frequency corresponding to VLSM: St_δ ≈ 0.08–0.15  
  VLSM 对应的峰值频率：St_δ ≈ 0.08–0.15
- **Spatial spectra**: one-dimensional FFT in streamwise direction, identify dominant wavelength  
  **空间谱**：流向一维 FFT，识别主导波长
- Justification for actuation frequency selection: f₀ = 40 Hz → St_δ ≈ 0.10 (within VLSM range)  
  激励频率选择的依据：f₀ = 40 Hz → St_δ ≈ 0.10（在 VLSM 范围内）

---

## 4. Parametric Effects: Frequency and Amplitude（参数效应：频率与振幅）

### 4.1 Single actuator frequency sweep (A = 3 mm fixed)（单执行器频率扫描，A = 3 mm 固定）
- Cases: f = 20, 40, 60, 80 Hz  
  工况：f = 20，40，60，80 Hz
- **VLSM count vs. frequency**  
  **VLSM 数量 vs. 频率**
  - Does VLSM population decrease at optimal frequency?  
    VLSM 数量是否在最优频率下降？
  - Optimal frequency determination from drag reduction  
    从减阻确定最优频率

### 4.2 Amplitude sweep (f = 40 Hz fixed)（振幅扫描，f = 40 Hz 固定）
- Cases: A = 0.3, 1.0, 3.0 mm  
  工况：A = 0.3，1.0，3.0 mm
- **Reynolds stress modulation**: ⟨-u′v′⟩/U∞² vs. y/δ for different A  
  **Reynolds 应力调制**：不同 A 下的 ⟨-u′v′⟩/U∞² vs. y/δ
- **Drag coefficient vs. amplitude**  
  **阻力系数 vs. 振幅**
  - Local Cf(x) along streamwise direction  
    沿流向的局部 Cf(x)
  - System-averaged Cf over x ∈ [160, 240] mm  
    x ∈ [160, 240] mm 范围的系统平均 Cf

### 4.3 Optimal forcing parameters（最优激励参数）
- Identify (f_opt, A_opt) for maximum drag reduction  
  识别最大减阻的（f_opt，A_opt）
- Non-dimensional parameter map: St_δ vs. A/δ, contour plot of ΔCf/Cf_baseline  
  无量纲参数图：St_δ vs. A/δ，ΔCf/Cf_baseline 等值线图
- Physical interpretation: resonance with natural VLSM frequency  
  物理解释：与 VLSM 自然频率共振

---

## 5. Phase-Dependent Response（相位依赖响应）

### 5.1 Phase-averaged flow fields (f = 40 Hz, A = 3 mm)（相位平均流场，f = 40 Hz，A = 3 mm）
- Cases: φ = 0°, 30°, 45°, 90°, 180°  
  工况：φ = 0°，30°，45°，90°，180°
- Phase-coherent velocity ũ(x, y, φ): contour plots at selected phases  
  相位相干速度 ũ(x, y, φ)：选定相位的等值线图
- Vorticity evolution within one actuation cycle  
  一个激励周期内的涡量演化

### 5.2 VLSM population vs. phase（VLSM 数量 vs. 相位）
- **Bar chart**: VLSM count for each φ with error bars (3 time windows)  
  **柱状图**：每个 φ 的 VLSM 数量，带误差棒（3 个时间窗口）
- **Boxplot**: Streamwise extent ⟨Lx/δ⟩ distribution  
  **箱线图**：流向尺度 ⟨Lx/δ⟩ 分布
- **Scatter plot**: Wall-normal centroid ⟨y_c/δ⟩ vs. φ  
  **散点图**：法向质心 ⟨y_c/δ⟩ vs. φ

### 5.3 Drag modulation and optimal phase（阻力调制与最优相位）
- **Line plot**: Cf vs. φ (averaged over x ∈ [160, 240] mm)  
  **折线图**：Cf vs. φ（x ∈ [160, 240] mm 平均）
- Identify φ_opt for minimum Cf  
  识别最小 Cf 的 φ_opt
- Correlation between VLSM count and drag: do fewer VLSM → lower Cf?  
  VLSM 数量与阻力的相关性：更少 VLSM → 更低 Cf？

### 5.4 Reynolds stress decomposition（Reynolds 应力分解）
- Total: ⟨-u′v′⟩_total = ⟨-ũṽ⟩_coherent + ⟨-u″v″⟩_random  
  总量：⟨-u′v′⟩_total = ⟨-ũṽ⟩_coherent + ⟨-u″v″⟩_random
- **Stacked area plot**: coherent vs. random contribution as function of y/δ for different φ  
  **堆叠面积图**：不同 φ 下相干 vs. 随机贡献随 y/δ 的变化
- Physical mechanism: does optimal phase suppress coherent stress production?  
  物理机制：最优相位是否抑制相干应力产生？

---

## 6. Configuration Comparison: Tandem vs. Parallel（构型比较：串列 vs. 并列）

### 6.1 Mean flow modification（平均流动修改）
- Side-by-side comparison of ⟨U⟩, u_rms, ⟨-u′v′⟩ for tandem vs. parallel at (f_opt, A_opt, φ_opt)  
  在（f_opt，A_opt，φ_opt）下串列 vs. 并列的 ⟨U⟩，u_rms，⟨-u′v′⟩ 并排比较

### 6.2 VLSM response: spanwise coherence vs. fragmentation（VLSM 响应：展向相干 vs. 破碎）
- **Tandem**: enhances streamwise modulation, preserves spanwise coherence  
  **串列**：增强流向调制，保持展向相干性
- **Parallel**: induces spanwise fragmentation, disrupts large-scale organization  
  **并列**：引起展向破碎，破坏大尺度组织
- Two-point correlation R_uu(Δz) at fixed x to quantify spanwise coherence  
  固定 x 处的两点相关 R_uu(Δz) 量化展向相干性

### 6.3 Drag reduction efficiency（减阻效率）
- **Bar chart**: ΔCf/Cf_baseline for tandem vs. parallel  
  **柱状图**：串列 vs. 并列的 ΔCf/Cf_baseline
- **Energy efficiency**: drag reduction per unit actuation power  
  **能量效率**：单位激励功率的减阻量
- Which configuration is more effective for VLSM suppression?  
  哪种构型更有效抑制 VLSM？

---

## 7. Modal Analysis and Physical Mechanism（模态分析与物理机制）

### 7.1 POD energy redistribution（POD 能量重分布）
- Cumulative energy vs. mode number for baseline, f40a3_phi0, f40a3_phi_opt  
  基准、f40a3_phi0、f40a3_phi_opt 的累积能量 vs. 模态数
- **Stacked bar chart**: energy fraction of first 10 modes  
  **堆叠柱状图**：前 10 阶模态的能量分数
- Interpretation: does actuation concentrate energy into fewer dominant modes?  
  解释：激励是否使能量集中到更少的主导模态？

### 7.2 DMD frequency response（DMD 频率响应）
- DMD eigenvalue spectrum: growth rate σ vs. frequency ω/(2π)  
  DMD 特征值谱：增长率 σ vs. 频率 ω/(2π)
- Identify dominant frequencies: does f₀ = 40 Hz excite or suppress key modes?  
  识别主导频率：f₀ = 40 Hz 是否激发或抑制关键模态？
- Mode shapes: spatial structure of DMD modes at f₀ and 2f₀  
  模态形状：f₀ 和 2f₀ 处 DMD 模态的空间结构

### 7.3 SPOD analysis (optional, if computational resources allow)（SPOD 分析，如资源允许）
- Spectral POD at f₀: extract phase-coherent structures  
  f₀ 处的谱 POD：提取相位相干结构
- Compare with phase-averaged flow fields ũ(x, y, φ)  
  与相位平均流场 ũ(x, y, φ) 比较

### 7.4 Physical mechanism discussion（物理机制讨论）
- **Receptivity**: how does boundary deformation couple with VLSM?  
  **感受性**：边界变形如何与 VLSM 耦合？
- **Phase-dependent amplification/suppression**: link optimal phase to destructive interference with natural VLSM dynamics  
  **相位依赖放大/抑制**：将最优相位与自然 VLSM 动力学的相消干涉联系
- **Comparison with literature**: Toedtli 2019 (phase matters), Jacobi & McKeon 2017 (input-output framework)  
  **与文献比较**：Toedtli 2019（相位重要），Jacobi & McKeon 2017（输入-输出框架）
- **Limitations**: no wall-resolved measurements (y⁺ < 30), cannot resolve buffer-layer streaks  
  **局限性**：无壁面分辨测量（y⁺ < 30），无法分辨缓冲层条纹

---

## 8. Conclusions（结论）

### 8.1 Summary of key findings（关键发现总结）
1. Optimal actuation parameters: f_opt, A_opt, φ_opt for maximum drag reduction  
   最优激励参数：最大减阻的 f_opt，A_opt，φ_opt
2. VLSM population reduction correlates with drag reduction  
   VLSM 数量减少与减阻相关
3. Phase dependence: φ_opt achieves destructive interference with natural VLSM  
   相位依赖性：φ_opt 实现与自然 VLSM 的相消干涉
4. Configuration comparison: parallel more effective for VLSM fragmentation  
   构型比较：并列对 VLSM 破碎更有效

### 8.2 Contributions to knowledge（对知识的贡献）
- First systematic parametric study (f, A, φ) targeting VLSM at Re_τ > 2000  
  首次针对 Re_τ > 2000 VLSM 的系统参数研究（f，A，φ）
- Dual-configuration comparison (tandem/parallel)  
  双构型比较（串列/并列）
- Design guidelines for VLSM-targeted drag reduction  
  针对 VLSM 的减阻设计指南

### 8.3 Outlook and future work（展望与未来工作）
- Higher Reynolds numbers (Re_τ > 5000)  
  更高 Reynolds 数（Re_τ > 5000）
- Closed-loop control based on real-time VLSM detection  
  基于实时 VLSM 检测的闭环控制
- Wall-resolved measurements (y⁺ < 1) to capture buffer-layer dynamics  
  壁面分辨测量（y⁺ < 1）以捕捉缓冲层动力学

---

## 核心图表清单 Core Figure List

| 图号 Fig. | 内容 Content | 位置 Section |
|-----------|-------------|-------------|
| 1 | Experimental setup & actuator configurations 实验装置与执行器构型 | 2.2 |
| 2 | Baseline mean flow & turbulence statistics 基准平均流动与湍流统计 | 3.1 |
| 3 | Baseline VLSM catalog & scale distribution 基准 VLSM 目录与尺度分布 | 3.2 |
| 4 | Premultiplied PSD & spatial spectra 预乘 PSD 与空间谱 | 3.3 |
| 5 | VLSM count & drag vs. frequency (A=3mm) VLSM 数量与阻力 vs. 频率（A=3mm） | 4.1 |
| 6 | Reynolds stress & drag vs. amplitude (f=40Hz) Reynolds 应力与阻力 vs. 振幅（f=40Hz） | 4.2 |
| 7 | Optimal parameter map: St_δ vs. A/δ 最优参数图：St_δ vs. A/δ | 4.3 |
| 8 | Phase-averaged flow fields (φ=0°/90°/180°) 相位平均流场（φ=0°/90°/180°） | 5.1 |
| 9 | VLSM response vs. phase (count, Lx, y_c) VLSM 响应 vs. 相位（数量，Lx，y_c） | 5.2 |
| 10 | Drag modulation vs. phase 阻力调制 vs. 相位 | 5.3 |
| 11 | Reynolds stress decomposition (coherent vs. random) Reynolds 应力分解（相干 vs. 随机） | 5.4 |
| 12 | Tandem vs. Parallel: mean flow & VLSM 串列 vs. 并列：平均流动与 VLSM | 6.1–6.2 |
| 13 | Drag reduction efficiency: tandem vs. parallel 减阻效率：串列 vs. 并列 | 6.3 |
| 14 | POD energy redistribution POD 能量重分布 | 7.1 |
| 15 | DMD frequency spectrum DMD 频率谱 | 7.2 |
| 16 | Physical mechanism schematic 物理机制示意图 | 7.4 |

**总计 Total**: 16 个主图 16 main figures

---

## 写作时间表 Writing Timeline（估算 Estimated）

| 阶段 Phase | 任务 Task | 周数 Weeks |
|-----------|----------|-----------|
| 1 | 数据处理与汇总 Data processing & aggregation | 2–3 |
| 2 | Methods 撰写 Methods writing | 1 |
| 3 | Results 撰写（Section 3–7）Results writing (Sec 3–7) | 3–4 |
| 4 | Introduction & Discussion 撰写 Intro & Discussion | 2 |
| 5 | 内部审阅与修订 Internal review & revision | 1–2 |
| 总计 Total | | **9–12 周 weeks** |

---

## 目标期刊 Target Journals

**首选 First choice**:
- *Journal of Fluid Mechanics* (JFM) — 机制研究权威 authoritative for mechanism studies
- *Physical Review Fluids* (PRF) — 参数研究友好 friendly to parametric studies

**备选 Alternatives**:
- *Experiments in Fluids* (EIF) — 实验方法强调 emphasis on experimental methods
- *Flow, Turbulence and Combustion* (FTC) — 工程应用导向 engineering-oriented

---

**文档版本 Document Version**: v1.0  
**创建日期 Created**: 2026-09-06  
**负责人 Owner**: Frank  
**审核人 Reviewer**: Kiro AI
