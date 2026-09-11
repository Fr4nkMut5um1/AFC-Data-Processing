# 执行计划（4 周详细路线图）
# Execution Plan (4-Week Detailed Roadmap)

**项目 Project**: 音圈膜执行器 VLSM 主动控制论文数据分析与写作  
**起止日期 Duration**: 2026-09-06（周五）至 2026-10-03（周四），共 4 周  
**负责人 Owner**: Frank  
**目标 Goal**: 完成全部数据处理、核心图表、Results 章节初稿

---

## 总体时间分配 Overall Time Allocation

| 阶段 Phase | 周次 Week | 工作重点 Focus | 交付物 Deliverable |
|-----------|----------|--------------|------------------|
| **Phase 1** | Week 1 (9/6–9/12) | 环境准备 + 相位扫描数据 | 5 个相位工况完成 |
| **Phase 2** | Week 2 (9/13–9/19) | 参数扫描 + 汇总表格 | 频率/振幅工况完成 + CSV 汇总 |
| **Phase 3** | Week 3 (9/20–9/26) | 构型比较 + 论文图表 | Parallel 完成 + 16 张核心图 |
| **Phase 4** | Week 4 (9/27–10/3) | 质检 + Results 初稿 | 数据验证报告 + Section 3-7 草稿 |

**弹性缓冲 Buffer**: 每周预留 0.5 天处理意外（数据问题、计算失败等）

---

## Week 1: 环境准备与相位扫描（9/6 周五 – 9/12 周四）

### Day 1 (9/6 Friday): 项目启动与环境检查

**上午 Morning (3h)**:
- [ ] 阅读本执行计划与数据处理需求文档
- [ ] 检查 MATLAB R2022b 环境：
  ```matlab
  ver  % 确认版本
  path  % 确认 +tbl, +tblR2 在路径
  which spod  % 确认 SPOD toolbox 可用
  ```
- [ ] 检查 J: 盘数据完整性（自动化脚本）：
  ```matlab
  % 运行 scripts/check_data_integrity.m（需新建）
  % 输出报告：results/data_integrity_report_20260906.txt
  ```
- [ ] 创建工况配置表：`scripts/case_list_phase_sweep.csv`
  ```csv
  case_id,config,f_hz,A_mm,phi_deg,raw_name,postproc_name
  tandem_f40a3_phi0_r2,tandem,40,3,0,Tandem_f40A3_Phi0_PIV,Tandem_f40A3_Phi0_PostProc
  tandem_f40a3_phi30_r2,tandem,40,3,30,Tandem_f40A3_Phi30_PIV,Tandem_f40A3_Phi30_PostProc
  tandem_f40a3_phi45_r2,tandem,40,3,45,Tandem_f40A3_Phi45_PIV,Tandem_f40A3_Phi45_PostProc
  tandem_f40a3_phi90_r2,tandem,40,3,90,Tandem_f40A3_Phi90_PIV,Tandem_f40A3_Phi90_PostProc
  tandem_f40a3_phi180_r2,tandem,40,3,180,Tandem_f40A3_Phi180_PIV,Tandem_f40A3_Phi180_PostProc
  ```

**下午 Afternoon (4h)**:
- [ ] 编写 `scripts/create_r2_cases_batch.m`（批量生成 case 脚本）
- [ ] 执行生成脚本，产出 5 个新 case 文件夹：
  ```
  cases/per_case/tandem_f40a3_phi30_r2/tandem_f40a3_phi30_r2_case.m
  cases/per_case/tandem_f40a3_phi45_r2/tandem_f40a3_phi45_r2_case.m
  cases/per_case/tandem_f40a3_phi90_r2/tandem_f40a3_phi90_r2_case.m
  cases/per_case/tandem_f40a3_phi180_r2/tandem_f40a3_phi180_r2_case.m
  ```
- [ ] 手动检查 1 个生成脚本的关键参数：
  - `cfg.case_id` 正确
  - `cfg.sources.*` 指向正确数据集
  - `cfg.phase.f0_hz = 40`
  - `cfg.phase.phi0_user_deg` 对应相位角
  - `cfg.stages.phase = 'compute'`（非 baseline）

**晚上 Evening (可选，2h)**:
- [ ] 试运行 `tandem_f40a3_phi0_r2`（phi0 已有 r1 参考，风险低）
- [ ] 如成功，提交 git commit：
  ```bash
  git add cases/per_case/tandem_f40a3_phi*_r2/
  git commit -m "feat: add phase sweep r2 case scripts (phi=0/30/45/90/180)"
  ```

**交付物 Deliverables**:
- ✅ 5 个 r2 case 脚本
- ✅ 数据完整性报告
- ✅ 工况配置表 CSV

---

### Day 2-3 (9/7 Sat – 9/8 Sun): 批量处理相位扫描（周末集中计算）

**Day 2 上午 (9/7 Morning, 2h)**:
- [ ] 编写 `scripts/run_r2_cases_batch.m`（批量执行框架）
- [ ] 启动第一批（phi0 + phi30）：
  ```matlab
  run('scripts/run_r2_cases_batch.m')
  % 预计 2 × 4h = 8h，过夜运行
  ```
- [ ] 设置计算机：关闭屏保、禁用休眠、保持 MATLAB 运行

**Day 2 下午 – Day 3 全天 (9/7 Afternoon – 9/8)**:
- [ ] 监控日志文件：`batch_processing_log_20260906.txt`
- [ ] 如第一批完成，启动第二批（phi45 + phi90 + phi180）
- [ ] 定期检查 Windows 任务管理器内存使用（如接近 80% 则手动中断重启）

**预期输出 Expected Output**:
- 每个工况产出：
  - `output/mat/01_sequence_cache.mat` (~9 GB)
  - `output/mat/02_mean_statistics.mat` (~50 MB)
  - `output/mat/02_mean_bl_friction.mat` (~5 MB)
  - `output/mat/03_phase_triple_statistics.mat` (~100 MB)
  - `output/mat/04_structures.mat` (~20 MB)
  - `output/mat/06_temporal_spectra.mat` (~10 MB)
  - `output/mat/06_pod.mat` (~30 MB)
  - `output/mat/07_dmd.mat` (~15 MB)

**风险应对 Risk Mitigation**:
- 如某工况失败，先完成其他 4 个，问题工况后续单独处理
- 如内存溢出，修改 `cfg.pod.n_frames` 从 12000 降至 6000

---

### Day 4-5 (9/9 Mon – 9/10 Tue): 数据验证与初步可视化

**Day 4 (9/9 Monday, 全天 7h)**:
- [ ] 运行验证脚本（需新建）：`scripts/validate_phase_sweep_results.m`
  - 检查项：帧数、Re_τ 一致性、VLSM 非空、相位箱数量
  - 输出报告：`results/phase_sweep_validation_report_20260909.txt`
- [ ] 快速预览关键指标：
  ```matlab
  % 手动逐工况检查
  cases = {'phi0', 'phi30', 'phi45', 'phi90', 'phi180'};
  for c = cases
      load(fullfile('cases', 'per_case', ['tandem_f40a3_' c{1} '_r2'], ...
          'output', 'mat', '04_structures.mat'));
      fprintf('%s: VLSM count = %d\n', c{1}, length(structures.catalog));
  end
  ```
- [ ] 绘制第一批探索性图表（临时，非论文质量）：
  - VLSM count vs. φ（柱状图）
  - Cf vs. φ（折线图）

**Day 5 (9/10 Tuesday, 全天 7h)**:
- [ ] 补全 `tandem_baseline_r2` 的 Section 4,6,7（当前只跑了 Section 1-2）
  - 修改 `cfg.stages.structures = 'compute'`
  - 修改 `cfg.stages.temporal = 'compute'`
  - 修改 `cfg.stages.pod = 'compute'`
  - 修改 `cfg.stages.dmd = 'compute'`
  - 运行脚本：~3.5 小时
- [ ] 与 `tandem_baseline_r1` 交叉验证（VLSM count 差异应 <10%）
- [ ] 如验证通过，提交 baseline r2 完整结果

**交付物 Deliverables**:
- ✅ 5 个相位工况完整 MAT 文件
- ✅ Baseline r2 补全
- ✅ 验证报告
- ✅ 初步探索图（不入论文）

---

### Day 6 (9/11 Wed): 汇总表格与周总结

**全天 (7h)**:
- [ ] 编写 `scripts/aggregate_results_summary.m`
- [ ] 生成第一版汇总表：`results/phase_sweep_summary_20260911.csv`
  - 列：case_id, phi_deg, Re_tau, VLSM_count, mean_Lx_delta, Cf_mean, TKE_reduction_pct
- [ ] 检查数据合理性：
  - Re_τ 是否在 2000–2200 范围
  - VLSM count 是否有相位依赖趋势（单调或非单调）
  - Cf 是否在 0.0020–0.0030 范围
- [ ] 编写 Week 1 进度报告（Markdown）：
  - 完成工况列表
  - 遇到的问题与解决方案
  - 关键发现（如有）
- [ ] 提交本周 git commit：
  ```bash
  git add results/phase_sweep_summary_20260911.csv
  git commit -m "data: phase sweep r2 results aggregation (Week 1)"
  ```

**Week 1 里程碑检查 Milestone Check**:
- ✅ M1: 相位扫描数据可用（5 个工况 + baseline）
- ✅ 可以开始写 Section 5（相位依赖响应）
- ❓ 是否发现最优相位？（如 φ_opt 对应最小 Cf）

---

## Week 2: 参数扫描与汇总表格（9/13 – 9/19）

### Day 7 (9/13 Fri): 频率扫描工况准备

**上午 Morning (3h)**:
- [ ] 创建频率扫描配置表：`scripts/case_list_frequency_sweep.csv`
  ```csv
  case_id,config,f_hz,A_mm,phi_deg,raw_name,postproc_name
  tandem_f20a3_phi0_r2,tandem,20,3,0,Tandem_f20A3_Phi0_PIV,Tandem_f20A3_Phi0_PostProc
  tandem_f40a3_phi0_r2,tandem,40,3,0,Tandem_f40A3_Phi0_PIV,Tandem_f40A3_Phi0_PostProc
  tandem_f60a3_phi0_r2,tandem,60,3,0,Tandem_f60A3_Phi0_PIV,Tandem_f60A3_Phi0_PostProc
  tandem_f80a3_phi0_r2,tandem,80,3,0,Tandem_f80A3_Phi0_PIV,Tandem_f80A3_Phi0_PostProc
  ```
- [ ] 批量生成 case 脚本（复用 Week 1 的生成脚本）
- [ ] **注意修改**：
  - f40 已在 Week 1 完成，可跳过
  - f80 需修改 `cfg.phase.f0_hz = 80`
  - f20 需修改 `cfg.phase.f0_hz = 20`
  - 每个激励周期的相位箱数：
    - f=20Hz → 960/20=48 帧/周期 → `cfg.phase.n_bins = 24`（保持不变，采样一半）
    - f=40Hz → 24 帧/周期 → `cfg.phase.n_bins = 24`（已用）
    - f=60Hz → 16 帧/周期 → `cfg.phase.n_bins = 16`
    - f=80Hz → 12 帧/周期 → `cfg.phase.n_bins = 12`

**下午 Afternoon (4h)**:
- [ ] 手动修改每个 case 的 `cfg.phase.n_bins`（自动化脚本未处理频率依赖参数）
- [ ] 启动频率扫描批处理（过夜运行）：
  - f20, f60, f80（f40 Week 1 已完成）
  - 预计 3 × 4h = 12h

**晚上 Evening (可选)**:
- [ ] 检查日志，确保计算正常启动

---

### Day 8 (9/14 Sat): 振幅扫描工况处理

**上午 Morning (2h)**:
- [ ] 检查频率扫描进度（如未完成则等待）
- [ ] 创建振幅扫描配置表：`scripts/case_list_amplitude_sweep.csv`
  ```csv
  case_id,config,f_hz,A_mm,phi_deg,raw_name,postproc_name
  tandem_f40a0.3_phi0_r2,tandem,40,0.3,0,Tandem_f40A0.3_Phi0_PIV,Tandem_f40A0.3_Phi0_PostProc
  tandem_f40a1_phi0_r2,tandem,40,1.0,0,Tandem_f40A1_Phi0_PIV,Tandem_f40A1_Phi0_PostProc
  tandem_f40a3_phi0_r2,tandem,40,3.0,0,Tandem_f40A3_Phi0_PIV,Tandem_f40A3_Phi0_PostProc
  ```
- [ ] 批量生成（A=3 已有，跳过）

**下午 Afternoon – 晚上 Evening (6h)**:
- [ ] 启动振幅扫描批处理：
  - A=0.3, A=1.0
  - 预计 2 × 4h = 8h（过夜）
- [ ] 如频率扫描已完成，开始数据验证

---

### Day 9-10 (9/15 Sun – 9/16 Mon): 参数扫描汇总与可视化

**Day 9 (9/15 Sunday, 全天 7h)**:
- [ ] 验证频率与振幅扫描结果
- [ ] 更新汇总表：合并 phase + frequency + amplitude 数据
  - 输出：`results/parameter_sweep_full_summary_20260915.csv`
- [ ] 绘制参数优化图（临时版）：
  - VLSM count vs. f (A=3mm, φ=0°)
  - Cf vs. f
  - VLSM count vs. A (f=40Hz, φ=0°)
  - Cf vs. A

**Day 10 (9/16 Monday, 全天 7h)**:
- [ ] 编写 `scripts/plot_parameter_optimization.m`（论文质量图表脚本）
- [ ] 生成 Fig.5–7：
  - **Fig.5**: VLSM count & drag vs. frequency（双 y 轴）
  - **Fig.6**: Reynolds stress profiles vs. amplitude（多条曲线叠加）
  - **Fig.7**: Optimal parameter map (St_δ vs. A/δ, contour of ΔCf%)
- [ ] 确定最优参数组合：
  - f_opt = ? Hz
  - A_opt = ? mm
  - ΔCf_max = ?%
- [ ] 记录在进度报告中

**交付物 Deliverables**:
- ✅ 频率扫描 3 个工况
- ✅ 振幅扫描 2 个工况
- ✅ 完整参数汇总表（~13 个工况）
- ✅ Fig.5–7（论文级）

---

### Day 11-12 (9/17 Tue – 9/18 Wed): 相位效应深度分析

**Day 11 (9/17 Tuesday, 全天 7h)**:
- [ ] 编写 `scripts/plot_phase_effects.m`
- [ ] 生成 Fig.8–11：
  - **Fig.8**: Phase-averaged flow fields（3×3 subplot，φ=0°/90°/180°，显示 ũ, ṽ, ω_z）
  - **Fig.9**: VLSM response vs. phase
    - (a) Bar chart: VLSM count vs. φ with error bars
    - (b) Boxplot: Lx/δ distribution
    - (c) Scatter: y_c/δ vs. φ
  - **Fig.10**: Cf vs. φ（折线图，标注 φ_opt）
  - **Fig.11**: Reynolds stress decomposition（堆叠面积图，coherent vs. random）
- [ ] 检查数据一致性：
  - 总应力 = 相干应力 + 随机应力（逐点验证）
  - 误差应 <1%

**Day 12 (9/18 Wednesday, 全天 7h)**:
- [ ] 计算相位依赖定量指标：
  - 每个 φ 的 TKE 变化率
  - 相干应力占比 ⟨ũṽ⟩ / ⟨u′v′⟩_total
  - 最优相位的减阻效率（相对 baseline）
- [ ] 更新汇总表，增加相位相关列
- [ ] 编写 Week 2 进度报告
- [ ] Git commit：
  ```bash
  git add results/parameter_sweep_full_summary_20260915.csv
  git add scripts/plot_phase_effects.m scripts/plot_parameter_optimization.m
  git commit -m "feat: complete parameter sweep & phase analysis (Week 2)"
  ```

**Week 2 里程碑检查 Milestone Check**:
- ✅ M2: 参数优化数据可用（frequency + amplitude）
- ✅ 论文 Fig.5–11 完成（8 张核心图）
- ✅ 可以开始写 Section 4–5

---

## Week 3: 构型比较与论文图表（9/20 – 9/26）

### Day 13 (9/20 Fri): Parallel 构型工况准备

**上午 Morning (3h)**:
- [ ] 确认 `parallel_baseline_r1` 是否需要重跑 r2
  - 如 r1 结果完整且参数一致，可直接复用
  - 如需 r2，复制 `tandem_baseline_r2` 模板并修改数据源
- [ ] 创建 parallel 相位扫描配置表：`scripts/case_list_parallel_phase.csv`
  ```csv
  case_id,config,f_hz,A_mm,phi_deg,raw_name,postproc_name
  parallel_baseline_r2,parallel,0,0,NA,Parallel_Baseline_PIV,Parallel_Baseline_PostProc
  parallel_f40a3_phi0_r2,parallel,40,3,0,Parallel_f40A3_Phi0_PIV,Parallel_f40A3_Phi0_PostProc
  parallel_f40a3_phi45_r2,parallel,40,3,45,Parallel_f40A3_Phi45_PIV,Parallel_f40A3_Phi45_PostProc
  parallel_f40a3_phi90_r2,parallel,40,3,90,Parallel_f40A3_Phi90_PIV,Parallel_f40A3_Phi90_PostProc
  ```
  **注意**：只选取代表相位（0°/45°/90°），节省时间

**下午 Afternoon (4h)**:
- [ ] 批量生成 parallel case 脚本
- [ ] **关键修改**：
  - 数据源路径从 `Tandem\` 改为 `Parallel\`
  - 如执行器间距不同，需修改 `cfg` 相关几何参数（待确认实验配置）
- [ ] 启动 parallel 批处理（过夜运行）
  - 预计 4 × 4h = 16h

---

### Day 14-15 (9/21 Sat – 9/22 Sun): 构型比较分析

**Day 14 (9/21 Saturday, 全天 7h)**:
- [ ] 监控 parallel 计算进度
- [ ] 编写 `scripts/compare_tandem_parallel.m`
- [ ] 提取对比指标：
  - 平均流场差异：Δ⟨U⟩, Δu_rms
  - VLSM 响应差异：Δ(VLSM count), Δ(Lx/δ)
  - 减阻效率：ΔCf_tandem vs. ΔCf_parallel
- [ ] 计算展向两点相关：
  ```matlab
  % 在固定 x=200mm 处
  R_uu = twopoint_correlation_spanwise(u_fluctuation, Delta_z);
  % Tandem 应保持高相关，Parallel 应快速衰减
  ```

**Day 15 (9/22 Sunday, 全天 7h)**:
- [ ] 生成 Fig.12–13：
  - **Fig.12**: Tandem vs. Parallel 并排比较
    - (a) Mean velocity contour ⟨U⟩
    - (b) Turbulence intensity u_rms
    - (c) VLSM instantaneous snapshot
    - (d) Two-point correlation R_uu(Δz)
  - **Fig.13**: Drag reduction efficiency
    - Bar chart: ΔCf/Cf_baseline for tandem vs. parallel at (f_opt, A_opt, φ_opt)
    - 如有功率数据，计算 drag reduction per watt
- [ ] 验证物理合理性：
  - Parallel 是否确实破碎 VLSM？（看 Lx/δ 分布是否左移）
  - 展向相关长度是否缩短？

**交付物 Deliverables**:
- ✅ Parallel 构型 4 个工况完成
- ✅ Fig.12–13（论文级）
- ✅ 构型比较定量表格

---

### Day 16-17 (9/23 Mon – 9/24 Tue): 模态分析图表

**Day 16 (9/23 Monday, 全天 7h)**:
- [ ] 编写 `scripts/plot_modal_analysis.m`
- [ ] 生成 Fig.14：POD 能量重分布
  - (a) Cumulative energy vs. mode number（多条曲线：baseline, f40a3_phi0, f40a3_phi_opt）
  - (b) Stacked bar chart: energy fraction of first 10 modes
  - (c) Spatial structure of mode 1-2（contour plot）
- [ ] 计算能量集中度指标：
  - 前 10 阶模态能量占比
  - 90% 能量所需模态数

**Day 17 (9/24 Tuesday, 全天 7h)**:
- [ ] 生成 Fig.15：DMD 频率谱
  - (a) Growth rate σ vs. frequency ω/(2π)（scatter plot，颜色编码 baseline/controlled）
  - (b) Mode shape at f₀=40Hz（streamlines + vorticity）
  - (c) Mode shape at 2f₀=80Hz（谐波）
- [ ] 验证 DMD 结果：
  - 主导频率是否与时域谱峰值一致？
  - f₀ 处的模态增长率是否变化？（受控 vs. baseline）
- [ ] 如 SPOD 已执行且有意义结果，补充 SPOD 图（可选）

**交付物 Deliverables**:
- ✅ Fig.14–15（论文级）
- ✅ 模态分析定量指标表格

---

### Day 18 (9/25 Wed): 物理机制示意图与补充分析

**全天 (7h)**:
- [ ] 绘制 Fig.16：Physical mechanism schematic（手绘 + PowerPoint/Inkscape）
  - 面板 (a)：Baseline VLSM structure（流线 + 等值线）
  - 面板 (b)：Actuation at optimal phase（边界变形 + 相位标注）
  - 面板 (c)：Destructive interference concept（波形叠加示意）
  - 面板 (d)：VLSM suppression result（变短、变弱）
- [ ] 补充分析（如论文需要）：
  - 四象限分析（Q2/Q4 事件占比 vs. φ）
  - 谱分析细节（空间谱 FFT 峰值波数）
- [ ] 整理所有论文图表，检查：
  - 字体一致（Arial 或 Times New Roman，10-12 pt）
  - 颜色对比度（colorblind-friendly）
  - 坐标轴标签完整（单位、物理量符号）
  - 图例清晰

**交付物 Deliverables**:
- ✅ Fig.16（物理机制示意图）
- ✅ 全部 16 张核心图完成
- ✅ 补充分析数据（如需）

---

### Day 19 (9/26 Thu): Week 3 总结与数据备份

**全天 (7h)**:
- [ ] 汇总所有图表到 `figures/paper_figures_20260926/` 目录
  - PNG 格式（300 dpi，用于审阅）
  - EPS 格式（矢量，用于最终投稿）
- [ ] 更新主汇总表，增加 parallel 数据：
  - `results/full_dataset_summary_20260926.csv`
- [ ] 编写 Week 3 进度报告：
  - 完成的分析模块
  - 关键物理发现（3-5 条要点）
  - 剩余问题（如有）
- [ ] 数据备份（双重）：
  - 本地备份：复制 `cases/per_case/*/output/` 到移动硬盘
  - 云备份：上传汇总表与图表到 OneDrive/Google Drive
- [ ] Git commit：
  ```bash
  git add figures/paper_figures_20260926/
  git add results/full_dataset_summary_20260926.csv
  git commit -m "feat: complete all 16 paper figures & configuration comparison (Week 3)"
  ```

**Week 3 里程碑检查 Milestone Check**:
- ✅ M3: 所有核心数据就绪（tandem + parallel，全参数组合）
- ✅ 16 张论文级图表完成
- ✅ 可以开始写完整 Results 章节

---

## Week 4: 质检与 Results 初稿（9/27 – 10/3）

### Day 20-21 (9/27 Fri – 9/28 Sat): 全面数据质检

**Day 20 (9/27 Friday, 全天 7h)**:
- [ ] 编写 `scripts/comprehensive_data_validation.m`
- [ ] 执行全数据集验证：
  - **必检项**（见数据处理需求文档 Section 4.1）：
    - 帧数完整性（12000 帧）
    - 有效率 >70%
    - Re_τ 一致性（± 5%）
    - VLSM 识别非空
    - 相位箱数量正确
    - POD 能量守恒
    - DMD 频率范围合理
  - **交叉验证**：
    - Baseline 重复性（r1 vs. r2）
    - 相位对称性（如有 ±30°）
    - 物理合理性（u_rms/U∞, Lx/δ 范围）
- [ ] 生成验证报告：`results/comprehensive_validation_report_20260927.txt`
  - 通过工况列表
  - 失败工况列表（如有）+ 失败原因
  - 可疑数据标记（如异常值）

**Day 21 (9/28 Saturday, 全天 7h)**:
- [ ] 处理验证中发现的问题：
  - 如某工况失败，单独重跑（设 `cfg.rebuild_cache=true`）
  - 如数据异常，检查原始 DAT 或处理参数
  - 如无法解决，标记为"exclude from analysis"并记录原因
- [ ] 更新最终汇总表（排除问题工况）：
  - `results/final_dataset_summary_20260928.csv`
- [ ] 统计全数据集指标：
  - 总工况数 / 成功数 / 失败数
  - Re_τ 均值 ± 标准差
  - VLSM count 范围
  - 最大减阻百分比

**交付物 Deliverables**:
- ✅ 全数据集验证报告
- ✅ 最终汇总表（质检后）
- ✅ 问题工况处理记录

---

### Day 22-23 (9/29 Sun – 9/30 Mon): Results 章节初稿（Section 3-5）

**Day 22 (9/29 Sunday, 全天 7h)**:
- [ ] 撰写 **Section 3: Baseline Flow Characteristics**（3-4 页）
  - 3.1 Mean flow and turbulence statistics
    - 参考 Fig.2，描述 ⟨U⟩, u_rms, ⟨-u′v′⟩ 剖面
    - 报告 Re_τ, δ₉₉, θ, H 等积分参数
  - 3.2 VLSM population and scale distribution
    - 参考 Fig.3，描述 VLSM catalog
    - 直方图分析：Lx/δ 分布峰值、质心位置
  - 3.3 Spectral signatures
    - 参考 Fig.4，描述预乘谱峰值频率
    - 说明 f₀=40Hz 选择的依据（St_δ ≈ 0.10）
- [ ] 写作要点：
  - 每段一个主题句
  - 数据先行（"Fig.X shows..."），解释后置
  - 与文献比较（Kim & Adrian 1999 等）

**Day 23 (9/30 Monday, 全天 7h)**:
- [ ] 撰写 **Section 4: Parametric Effects**（5-6 页）
  - 4.1 Single actuator frequency sweep
    - 参考 Fig.5，描述 VLSM count 和 Cf vs. f
    - 识别 f_opt（如 40 Hz）
  - 4.2 Amplitude sweep
    - 参考 Fig.6，描述 Reynolds 应力调制
    - 报告 ΔCf vs. A 的趋势
  - 4.3 Optimal forcing parameters
    - 参考 Fig.7，展示 St_δ vs. A/δ 参数图
    - 给出最优组合：(f_opt, A_opt) 及减阻百分比
- [ ] 撰写 **Section 5: Phase-Dependent Response**（6-7 页）
  - 5.1 Phase-averaged flow fields
    - 参考 Fig.8，描述 ũ(x, y, φ) 演化
    - 涡量场变化
  - 5.2 VLSM population vs. phase
    - 参考 Fig.9，分析 count, Lx, y_c 随 φ 的变化
  - 5.3 Drag modulation and optimal phase
    - 参考 Fig.10，识别 φ_opt
    - 讨论 VLSM 数量与 Cf 的相关性
  - 5.4 Reynolds stress decomposition
    - 参考 Fig.11，分析相干 vs. 随机贡献

**写作提示 Writing Tips**:
- 使用过去时态（"The results showed..."）
- 避免主观评价（"surprisingly", "interestingly" 慎用）
- 定量描述（"VLSM count decreased by 23% at φ=90°"）
- 每个小节末尾一句总结

**交付物 Deliverables**:
- ✅ Section 3-5 初稿（Word 或 LaTeX，~12-15 页）

---

### Day 24-25 (10/1 Tue – 10/2 Wed): Results 章节初稿（Section 6-7）

**Day 24 (10/1 Tuesday, 全天 7h)**:
- [ ] 撰写 **Section 6: Configuration Comparison**（4-5 页）
  - 6.1 Mean flow modification
    - 参考 Fig.12(a-b)，对比 tandem vs. parallel
  - 6.2 VLSM response
    - 参考 Fig.12(c-d)，讨论展向相干性
    - Parallel 是否更有效破碎 VLSM？
  - 6.3 Drag reduction efficiency
    - 参考 Fig.13，比较减阻百分比
    - 如有能耗数据，讨论能量效率
- [ ] 撰写 **Section 7: Modal Analysis**（5-6 页）
  - 7.1 POD energy redistribution
    - 参考 Fig.14，描述能量集中度变化
    - 激励是否使能量更集中？
  - 7.2 DMD frequency response
    - 参考 Fig.15，讨论主导频率
    - f₀ 处的模态增长率是否变化？
  - 7.3 SPOD analysis（如有）
  - 7.4 Physical mechanism discussion
    - 参考 Fig.16，总结物理图像
    - 感受性 + 相位干涉 + VLSM 抑制
    - 与文献对比（Toedtli 2019, Jacobi & McKeon 2017）
    - 明确局限性（y⁺>33, FOV 限制）

**Day 25 (10/2 Wednesday, 全天 7h)**:
- [ ] 通读 Section 3-7，检查：
  - 逻辑连贯性（段落间过渡）
  - 图表引用完整（每张图至少被引用一次）
  - 数据一致性（文字描述与表格/图表匹配）
  - 术语统一（VLSM vs. superstructure，统一用前者）
- [ ] 编写每个 Section 的小结段落（2-3 句）
- [ ] 生成 Results 初稿完整版：
  - `Draft/Results_v1.0_20261002.docx` 或 `.tex`
  - 字数估算：~25-30 页（双栏格式约 15-18 页）
- [ ] 内部自审（self-review）：
  - 打印 PDF，用红笔标记问题
  - 检查图表清晰度（放大到 150% 仍可读）

**交付物 Deliverables**:
- ✅ Section 6-7 初稿
- ✅ Results 完整初稿（Section 3-7）

---

### Day 26 (10/3 Thu): Week 4 总结与交付

**上午 Morning (3h)**:
- [ ] 生成完整数据处理报告：`results/data_processing_final_report_20261003.md`
  - 包含内容：
    - 处理工况列表（13+ 个）
    - 数据质检结果
    - 关键发现摘要（5-10 条要点）
    - 剩余问题与建议
- [ ] 整理全部交付物：
  ```
  deliverables_20261003/
  ├── figures/               # 16 张论文级图表（PNG + EPS）
  ├── results/               # CSV 汇总表
  ├── Draft/                 # Results 初稿
  └── reports/               # 质检报告、进度报告
  ```
- [ ] 压缩打包：`deliverables_20261003.zip`

**下午 Afternoon (4h)**:
- [ ] 撰写 4 周总结报告：`PROJECT_PROGRESS_Week1-4_Summary.md`
  - 完成的工作（数据处理 + 图表 + 写作）
  - 关键物理发现
  - 下一步计划（Methods 写作，Introduction/Discussion 待补）
  - 遇到的问题与解决方案
- [ ] 最终 git commit：
  ```bash
  git add Draft/Results_v1.0_20261002.docx
  git add results/final_dataset_summary_20260928.csv
  git add figures/paper_figures_20260926/
  git commit -m "milestone: complete 4-week data processing & Results draft"
  git tag v1.0-results-draft
  ```
- [ ] 与导师/合作者同步：
  - 发送 Results 初稿
  - 安排下周审阅会议
  - 讨论后续写作计划

**Week 4 里程碑检查 Milestone Check**:
- ✅ M4: 数据验证通过，Results 初稿完成
- ✅ 全部 16 张核心图可用
- ✅ 可以开始 Methods 与 Introduction 写作（Week 5+）

---

## 后续路线图（Week 5-12，8 周）

### Week 5-6: Methods 与 Introduction
- **Methods**（2 周）：
  - 实验装置图（CAD 或照片 + 标注）
  - PIV 系统详细参数
  - 数据处理流程图（flowchart）
  - 不确定度分析（如需）
- **Introduction**（与 Methods 并行）：
  - 基于已有 v2.3 novelty 框架
  - 补充最新文献（2026 年）
  - 明确研究目标与贡献

### Week 7-9: Discussion 与 Conclusions
- **Discussion**（3 周）：
  - 物理机制深入讨论
  - 与文献定量比较
  - 实际应用展望
  - 局限性与未来工作
- **Conclusions**（与 Discussion 末期）：
  - 关键发现总结（3-5 条）
  - 贡献声明
  - Outlook

### Week 10-11: 内部审阅与修订
- 合作者审阅
- 逐段修订
- 语言润色

### Week 12: 投稿准备
- 格式调整（JFM/PRF 模板）
- 补充材料（Supplementary）
- Cover letter
- 投稿

---

## 关键成功因素 Key Success Factors

### 1. 时间管理 Time Management
- **严格执行每日计划**，避免拖延
- **周末集中计算**，利用过夜运行
- **每周五总结**，及时调整计划

### 2. 质量控制 Quality Control
- **每个工况处理后立即验证**（不要累积到最后）
- **图表边做边审**（不要等全部完成再修改）
- **代码模块化**（避免重复劳动）

### 3. 风险应对 Risk Management
- **预留缓冲时间**（每周 0.5 天）
- **优先级清晰**（核心数据先做）
- **增量交付**（每周产出可用成果）

### 4. 沟通协作 Communication
- **每周进度报告**（即使独立工作）
- **及时记录问题**（git issue 或笔记）
- **关键决策文档化**（参数选择依据）

---

## 工具与资源 Tools and Resources

### 软件环境 Software
- MATLAB R2022b（主计算）
- Git（版本控制）
- LaTeX 或 Word（写作）
- PowerPoint/Inkscape（示意图）
- Python（可选，批量绘图）

### 硬件需求 Hardware
- 计算机内存 ≥ 32 GB
- 硬盘空间 ≥ 200 GB
- 稳定网络（数据拷贝）

### 参考文献管理 Reference Management
- Zotero 或 Mendeley
- BibTeX 文件：`references_v2.3_verified_final_20260901.bib`（已有）

### 在线资源 Online Resources
- JFM 投稿指南：https://www.cambridge.org/core/journals/journal-of-fluid-mechanics
- PRF 投稿指南：https://journals.aps.org/prfluids/authors
- Semantic Scholar（文献搜索）
- AI4Scholar MCP（文献管理）

---

## 应急联系方式 Emergency Contacts

**技术问题 Technical Issues**:
- MATLAB 崩溃：重启，检查内存，减小 `n_frames`
- 数据损坏：联系实验人员，检查 J: 盘备份
- 算法错误：查看 `diagnose_coherent.m`，GitHub issue

**人员支持 Personnel**:
- 导师/合作者：（周例会或邮件）
- 实验室同事：（数据问题咨询）
- Kiro AI：（代码调试、文献查询）

---

**文档版本 Document Version**: v1.0  
**创建日期 Created**: 2026-09-06  
**负责人 Owner**: Frank  
**审核者 Reviewer**: Kiro AI  
**下次更新 Next Review**: 2026-09-13（Week 1 结束后）
