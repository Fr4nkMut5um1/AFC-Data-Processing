# 数据处理需求清单
# Data Processing Requirements

**日期 Date**: 2026-09-06  
**项目 Project**: 音圈膜执行器 VLSM 主动控制实验  
**实验矩阵 Experimental Matrix**: Single/Tandem/Parallel × f(20-80Hz) × A(0.3-3mm) × φ(0-180°)

---

## 一、数据源清单 Data Source Inventory

### 1.1 已完成工况 Completed Cases（截至 2026-09-06）

| 工况名称 Case Name | 构型 Config | 频率 f (Hz) | 振幅 A (mm) | 相位 φ (deg) | 数据状态 Data Status |
|-------------------|------------|------------|------------|-------------|------------------|
| `tandem_baseline_r2` | tandem | 0 | 0 | NA | ✅ Section 1-2 完成 |
| `tandem_baseline_r1` | tandem | 0 | 0 | NA | ✅ 全流程完成 |
| `tandem_f40a3_phi0_r1` | tandem | 40 | 3 | 0 | ✅ 全流程完成 |
| `parallel_baseline_r1` | parallel | 0 | 0 | NA | ✅ 全流程完成 |

### 1.2 待处理工况 Pending Cases（原始数据已采集，需跑 r2 流程）

**数据根目录 Data Root**: `J:\Export0731\TempData0731_LinZheng\`

#### A. Tandem 构型（串列）
基础路径 Base Path: `J:\Export0731\TempData0731_LinZheng\Tandem\`

**频率扫描 Frequency Sweep（A = 3 mm，φ = 0°）**:
- `Tandem_f20A3_Phi0_PIV` / `Tandem_f20A3_Phi0_PostProc` → f = 20 Hz
- `Tandem_f40A3_Phi0_PIV` / `Tandem_f40A3_Phi0_PostProc` → f = 40 Hz（已有 r1，需补 r2）
- `Tandem_f60A3_Phi0_PIV` / `Tandem_f60A3_Phi0_PostProc` → f = 60 Hz
- `Tandem_f80A3_Phi0_PIV` / `Tandem_f80A3_Phi0_PostProc` → f = 80 Hz（需确认数据完整性）

**振幅扫描 Amplitude Sweep（f = 40 Hz，φ = 0°）**:
- `Tandem_f40A0.3_Phi0_PIV` / `Tandem_f40A0.3_Phi0_PostProc` → A = 0.3 mm
- `Tandem_f40A1_Phi0_PIV` / `Tandem_f40A1_Phi0_PostProc` → A = 1.0 mm
- `Tandem_f40A3_Phi0_PIV` / `Tandem_f40A3_Phi0_PostProc` → A = 3.0 mm（已有）

**相位扫描 Phase Sweep（f = 40 Hz，A = 3 mm）**:
- `Tandem_f40A3_Phi0_PIV` / `Tandem_f40A3_Phi0_PostProc` → φ = 0°（已有）
- `Tandem_f40A3_Phi30_PIV` / `Tandem_f40A3_Phi30_PostProc` → φ = 30°
- `Tandem_f40A3_Phi45_PIV` / `Tandem_f40A3_Phi45_PostProc` → φ = 45°
- `Tandem_f40A3_Phi90_PIV` / `Tandem_f40A3_Phi90_PostProc` → φ = 90°
- `Tandem_f40A3_Phi180_PIV` / `Tandem_f40A3_Phi180_PostProc` → φ = 180°
- （可能还有 φ = -30°, -45°, -90° 等，需确认）

**额外频率-振幅组合**（如有）:
- `Tandem_f80A0.3_Phi0_*`
- `Tandem_f80A1_Phi0_*`
- （f80 case 无 A=3mm 数据，如用户所述）

#### B. Parallel 构型（并列）
基础路径 Base Path: `J:\Export0731\TempData0731_LinZheng\Parallel\`

**结构与 Tandem 平行**（需确认具体命名）:
- `Parallel_Baseline_PIV` / `Parallel_Baseline_PostProc` → baseline（已有 r1）
- `Parallel_f40A3_Phi0_*`
- `Parallel_f40A3_Phi{30,45,90,180}_*`
- `Parallel_f{20,60,80}A3_Phi0_*`
- `Parallel_f40A{0.3,1}_Phi0_*`

#### C. Single 构型（单执行器，如有）
基础路径 Base Path: `J:\Export0731\TempData0731_LinZheng\Single\`（需确认）

- `Single_f{20,40,60,80}A{0.3,1,3}_*`

---

## 二、数据处理阶段清单 Processing Stage Checklist

### 2.1 必须完成阶段 Mandatory Stages

**每个工况必须执行 Required for Each Case**:

| Section | 阶段名称 Stage Name | 输出产物 Output | 论文使用位置 Paper Usage |
|---------|-------------------|---------------|----------------------|
| 1 | 序列缓存 Sequence Cache | `01_sequence_cache.mat` | 全部下游计算基础 |
| 2 | 统计场 Mean Statistics | `02_mean_statistics.mat` | Fig.2（平均流场），Fig.6（Reynolds 应力） |
| 2 | 边界层与摩阻 BL & Friction | `02_mean_bl_friction.mat` | Table 1（Re_τ），Fig.10（Cf vs. φ） |
| 3 | 相位平均 Phase Average | `03_phase_triple_statistics.mat` | Fig.8（相位平均流场），Fig.11（三重分解） |
| 4 | 结构识别 Structure Analysis | `04_structures.mat` | Fig.3,9（VLSM catalog），Fig.5（count vs. f） |
| 6 | 时域谱 Temporal Spectra | `06_temporal_spectra.mat` | Fig.4（预乘 PSD） |
| 7 | POD 模态 POD Modes | `06_pod.mat` | Fig.14（能量重分布） |
| 7 | DMD 分析 DMD Analysis | `07_dmd.mat` | Fig.15（频率谱） |

**注意 Note**: Section 3（相位平均）仅对受控工况执行，baseline 跳过。

### 2.2 可选阶段 Optional Stages

| Section | 阶段名称 Stage Name | 是否必需 Required? | 说明 Notes |
|---------|-------------------|------------------|-----------|
| 5 | 输运分析 Transport | 否 No | 如需 quadrant analysis 补充则做 |
| 6 | 空间谱 Spatial Spectra | 是 Yes（仅代表工况） | 论文 Fig.4 需要 |
| 7 | SPOD | 否 No | 计算成本高，论文可不用 |
| 7 | LCS/FTLE | 否 No | 已确认不做 |
| 8 | 相关性 Correlations | 否 No | 除非需要 two-point correlation |
| 8 | 谐波分析 Harmonics | 否 No | 除非需要谐波幅值 vs. x |

---

## 三、批量处理策略 Batch Processing Strategy

### 3.1 分组处理优先级 Processing Priority Groups

**优先级 1（论文核心数据，2 周内完成）**:
1. **相位扫描 Phase Sweep（f=40Hz, A=3mm）**:
   - `tandem_f40a3_phi{0,30,45,90,180}_r2`（5 个工况）
   - 产出 Fig.8–11（相位效应）
2. **Tandem baseline r2 补全**:
   - 当前只跑了 Section 1-2，需补 Section 4,6,7

**优先级 2（参数优化数据，1 周）**:
3. **频率扫描 Frequency Sweep（A=3mm, φ=0°）**:
   - `tandem_f{20,60,80}a3_phi0_r2`（3 个新工况）
   - 产出 Fig.5（VLSM count vs. f），Fig.7（最优参数图）
4. **振幅扫描 Amplitude Sweep（f=40Hz, φ=0°）**:
   - `tandem_f40a{0.3,1}_phi0_r2`（2 个新工况）
   - 产出 Fig.6（Reynolds 应力 vs. A），Fig.7

**优先级 3（构型比较数据，1 周）**:
5. **Parallel 构型基准与相位扫描**:
   - `parallel_baseline_r2`（补全或复用 r1）
   - `parallel_f40a3_phi{0,45,90}_r2`（选取代表相位）
   - 产出 Fig.12–13（tandem vs. parallel）

**优先级 4（补充数据，视时间而定）**:
6. **Single 构型**（如需用于对比）
7. **其他频率-振幅组合**（如 f80A1）

### 3.2 自动化脚本设计 Automated Script Design

#### 脚本 1：批量创建 r2 case 脚本
**路径 Path**: `scripts/create_r2_cases_batch.m`

**功能 Function**:
- 输入：工况列表（CSV 或 MATLAB table）
- 自动从 `tandem_baseline_r2_case.m` 模板生成新脚本
- 修改字段：
  - `cfg.case_id`
  - `cfg.name`
  - `cfg.sources.raw.name` / `cfg.sources.postproc.name`
  - `cfg.output_dir`
  - `cfg.phase.f0_hz`（如非 40 Hz）
  - `cfg.phase.phi0_user_deg`（相位偏置）

**伪代码 Pseudocode**:
```matlab
% 定义工况表
cases_table = readtable('scripts/case_list_phase_sweep.csv');
% 列: case_id, config, f_hz, A_mm, phi_deg, raw_name, postproc_name

for i = 1:height(cases_table)
    row = cases_table(i, :);
    template_file = 'cases/per_case/tandem_baseline_r2/tandem_baseline_r2_case.m';
    new_dir = fullfile('cases', 'per_case', row.case_id);
    new_file = fullfile(new_dir, [row.case_id '_case.m']);
    
    % 复制模板
    if ~exist(new_dir, 'dir'), mkdir(new_dir); end
    copyfile(template_file, new_file);
    
    % 修改关键字段（用正则表达式替换）
    content = fileread(new_file);
    content = strrep(content, 'tandem_baseline_r2', row.case_id);
    content = regexprep(content, "cfg.case_id = '.*?';", ...
        sprintf("cfg.case_id = 'per_case/%s';", row.case_id));
    content = regexprep(content, "raw_source_name = '.*?';", ...
        sprintf("raw_source_name = '%s';", row.raw_name));
    content = regexprep(content, "postproc_source_name = '.*?';", ...
        sprintf("postproc_source_name = '%s';", row.postproc_name));
    % （需处理相位配置：baseline 保持 skip，受控工况改为 compute）
    
    % 写回
    fid = fopen(new_file, 'w'); fprintf(fid, '%s', content); fclose(fid);
    fprintf('Created: %s\n', new_file);
end
```

#### 脚本 2：批量执行 r2 流程
**路径 Path**: `scripts/run_r2_cases_batch.m`

**功能 Function**:
- 串行执行工况列表（避免并行导致 MATLAB 崩溃）
- 每个工况执行前检查是否已有缓存（`cfg.stages` 设为 `reuse`）
- 记录每个工况的运行时间与错误日志

**伪代码 Pseudocode**:
```matlab
cases_list = {
    'tandem_f40a3_phi0_r2';
    'tandem_f40a3_phi30_r2';
    'tandem_f40a3_phi45_r2';
    'tandem_f40a3_phi90_r2';
    'tandem_f40a3_phi180_r2';
};

log_file = 'batch_processing_log_20260906.txt';
flog = fopen(log_file, 'w');
fprintf(flog, 'Batch processing started: %s\n', datetime('now'));

for i = 1:length(cases_list)
    case_id = cases_list{i};
    script_path = fullfile('cases', 'per_case', case_id, [case_id '_case.m']);
    
    fprintf(flog, '\n[%d/%d] Running: %s\n', i, length(cases_list), case_id);
    tic;
    try
        run(script_path);
        elapsed = toc;
        fprintf(flog, '  ✓ Success in %.1f min\n', elapsed/60);
    catch ME
        elapsed = toc;
        fprintf(flog, '  ✗ Failed in %.1f min: %s\n', elapsed/60, ME.message);
    end
end

fprintf(flog, '\nBatch processing finished: %s\n', datetime('now'));
fclose(flog);
```

#### 脚本 3：汇总结果表格
**路径 Path**: `scripts/aggregate_results_summary.m`

**功能 Function**:
- 遍历所有已处理工况的 `output/mat/` 目录
- 提取关键指标：
  - Re_τ（from `02_mean_bl_friction.mat`）
  - VLSM count, mean Lx/δ（from `04_structures.mat`）
  - Cf mean over x∈[160,240]（from `02_mean_bl_friction.mat`）
  - POD cumulative energy first 10 modes（from `06_pod.mat`）
  - DMD dominant frequency（from `07_dmd.mat`）
- 生成 CSV 表格：`results/parameter_sweep_summary_20260906.csv`

**输出表格格式 Output Table Format**:
```csv
case_id,config,f_hz,A_mm,phi_deg,Re_tau,VLSM_count,mean_Lx_delta,Cf_mean,TKE_reduction_pct,POD_energy_10modes
tandem_baseline_r2,tandem,0,0,NA,2100,183,4.2,0.00245,0,0.72
tandem_f40a3_phi0_r2,tandem,40,3,0,2090,158,3.8,0.00238,6.5,0.68
tandem_f40a3_phi45_r2,tandem,40,3,45,2095,142,3.5,0.00232,8.2,0.65
...
```

---

## 四、数据验证检查点 Data Quality Checkpoints

### 4.1 必检项 Mandatory Checks（每个工况执行后）

| 检查项 Check Item | 验证方法 Validation Method | 通过标准 Pass Criteria |
|------------------|--------------------------|---------------------|
| 1. 帧数完整性 Frame Count | `sequence_cache.meta.total_frames == 12000` | 必须精确匹配 |
| 2. 有效率 Valid Fraction | `mean(mean(statistics.valid_mask)) > 0.70` | 全场有效率 >70% |
| 3. Re_τ 一致性 Re_tau Consistency | 与 baseline ± 5% | 同一实验批次不应大幅波动 |
| 4. VLSM 识别非空 Non-Empty VLSM | `length(structures.catalog) > 0` | 至少检测到若干结构 |
| 5. 相位箱数量 Phase Bins | `phase.n_bins == 24`（f₀=40Hz）| 必须匹配激励频率 |
| 6. POD 能量守恒 Energy Conservation | `sum(pod.energy_fraction) ≈ 1.0` | 相对误差 <1% |
| 7. DMD 频率范围 Frequency Range | `max(dmd.frequency_hz) < fs/2` | 不超过 Nyquist 频率 |

### 4.2 交叉验证 Cross-Validation

**工况间一致性检查 Inter-Case Consistency**:
- **Baseline 重复性**：tandem_baseline_r1 vs. r2，VLSM count 差异应 <10%
- **相位对称性**：如有 φ=30° 和 φ=-30°，Reynolds 应力应镜像对称
- **单调性**：Cf vs. A 应单调递减（或先减后增）

**物理合理性 Physical Plausibility**:
- u_rms/U∞ 应在 0.08–0.15 范围（典型 TBL）
- VLSM 平均尺度应 3δ < Lx < 10δ（文献范围）
- 相位相干应力 ⟨ũṽ⟩ 应远小于总应力 ⟨u′v′⟩（除非共振）

---

## 五、输出产物规范 Output Deliverables Specification

### 5.1 数值结果 Numerical Results

**每个工况必须产出 Required per Case**:
- `mat/01_sequence_cache.mat`（~4.5 GB × 2 sources）
- `mat/02_mean_statistics.mat`（~50 MB）
- `mat/02_mean_bl_friction.mat`（~5 MB）
- `mat/04_structures.mat`（~20 MB，包含 catalog）
- `mat/06_temporal_spectra.mat`（~10 MB）
- `mat/06_pod.mat`（~30 MB，20 modes）
- `mat/07_dmd.mat`（~15 MB）

**受控工况额外产出 Additional for Controlled Cases**:
- `mat/03_phase_triple_statistics.mat`（~100 MB，24 相位箱）

**汇总表格 Aggregate Tables**:
- `results/parameter_sweep_summary_20260906.csv`
- `results/phase_scan_detailed_metrics_20260906.csv`
- `results/configuration_comparison_20260906.csv`

### 5.2 图表产物 Figure Outputs

**立即可用图表 Ready-Made Figures**（PNG，300 dpi）:
- 每个工况自动生成：
  - 平均流场（⟨U⟩, u_rms, ⟨-u′v′⟩）
  - 瞬时 VLSM 快照（3 个代表帧）
  - 预乘 PSD
  - POD 前 4 阶模态

**论文定制图表 Paper-Quality Figures**（需单独绘制脚本）:
- `scripts/plot_phase_effects.m` → Fig.8–11
- `scripts/plot_parameter_optimization.m` → Fig.5–7
- `scripts/plot_configuration_comparison.m` → Fig.12–13
- `scripts/plot_modal_analysis.m` → Fig.14–15

---

## 六、计算资源估算 Computational Resource Estimation

### 6.1 单工况处理时间 Time per Case

**基于 tandem_baseline_r1 历史数据 Based on Past Experience**:

| Section | 阶段名称 Stage | CPU 时间 CPU Time | 备注 Notes |
|---------|--------------|-----------------|-----------|
| 1 | 序列缓存 Cache | 15 min | 读取 12000 帧 DAT |
| 2 | 统计场 Statistics | 30 min | 分块处理 |
| 2 | 边界层 BL | 10 min | Rodriguez-Lopez 拟合 |
| 3 | 相位平均 Phase | 40 min | 仅受控工况 |
| 4 | 结构识别 Structures | 60 min | 12000 帧逐帧聚类 |
| 6 | 时域谱 Temporal | 20 min | Welch PSD |
| 7 | POD | 45 min | 12000×(640×91) 矩阵 |
| 7 | DMD | 25 min | piDMD exact |
| **总计 Total** | | **~4 小时 hours**（受控）| baseline 减 40 min |

**批量处理总时间 Total Batch Time**:
- 优先级 1（5 个相位扫描）：5 × 4h = **20 小时**
- 优先级 2（5 个参数扫描）：5 × 3.3h = **16.5 小时**
- 优先级 3（3 个 parallel）：3 × 4h = **12 小时**
- **合计 Total**: ~48.5 小时（连续运行 2 天）

**建议分批执行 Recommended Batching**:
- 每批 5 个工况，每天运行 1 批（过夜）
- 避免长时间运行导致 MATLAB 内存泄漏

### 6.2 存储空间需求 Storage Requirements

**每个工况磁盘占用 Disk per Case**:
- 序列缓存：4.5 GB (raw) + 4.5 GB (postproc) = **9 GB**
- 其他 MAT 文件：~130 MB
- PNG 图表：~50 MB
- **单工况总计 Total**: ~9.2 GB

**批量处理总需求 Total Batch Storage**:
- 13 个新工况 × 9.2 GB = **~120 GB**
- 建议预留 **150 GB**（留 30% 余量）

---

## 七、风险与应对 Risks and Mitigation

### 7.1 已知风险 Known Risks

| 风险项 Risk | 影响 Impact | 缓解措施 Mitigation |
|-----------|-----------|------------------|
| 数据源缺失或损坏 Missing/corrupted data | 工况无法处理 | 执行前用脚本批量检查 B0001.dat–B6000.dat 完整性 |
| 内存溢出 Out-of-memory | MATLAB 崩溃 | 分块读取（chunk_frames=48），串行执行 |
| SPOD 帧数不足 Insufficient frames | 报错 | 已排除 SPOD（可选阶段） |
| 相位配置错误 Wrong phase config | baseline 被当作受控 | 模板脚本明确设 `cfg.case_type = 'baseline'/'control'` |
| 网格不匹配 Grid mismatch | 缓存拒绝复用 | 统一使用 [640 91] 网格 |

### 7.2 应急预案 Contingency Plan

**如某工况处理失败 If Case Fails**:
1. 检查诊断日志：`output/csv/01_diagnostic_messages.csv`
2. 如缓存损坏：删除 `output/mat/01_sequence_cache.mat`，设 `cfg.stages.cache='compute'` 重跑
3. 如数据源问题：联系实验人员确认原始 DAT 文件
4. 如计算错误：在 GitHub issue 或项目日志记录 stack trace

**最小可行数据集 Minimum Viable Dataset**（如时间紧张）:
- 必做：baseline + f40a3_phi{0,45,90} (4 个工况) → 勉强支撑相位效应结论
- 补充：f{20,60}a3_phi0 (2 个工况) → 频率优化
- 舍弃：振幅扫描、parallel 构型 → 后续补充

---

## 八、时间节点与里程碑 Timeline and Milestones

| 周次 Week | 日期范围 Date Range | 任务 Task | 交付物 Deliverable |
|----------|------------------|----------|------------------|
| Week 1 | 2026-09-06 – 09-12 | 批量创建 r2 脚本 + 执行优先级 1 | 5 个相位扫描工况完成 |
| Week 2 | 2026-09-13 – 09-19 | 执行优先级 2 + 汇总表格 | 参数扫描完成 + CSV 汇总 |
| Week 3 | 2026-09-20 – 09-26 | 执行优先级 3 + 论文图表脚本 | parallel 完成 + 核心图表 16 张 |
| Week 4 | 2026-09-27 – 10-03 | 数据验证 + 补充处理 | 数据质检报告 + 论文 Results 初稿 |

**关键里程碑 Key Milestones**:
- ✅ **M1** (2026-09-12): 相位扫描数据可用 → 开始写 Section 5
- ✅ **M2** (2026-09-19): 参数优化数据可用 → 开始写 Section 4
- ✅ **M3** (2026-09-26): 所有核心数据就绪 → 完成 Results 草稿
- ✅ **M4** (2026-10-03): 数据验证通过 → 提交内部审阅

---

## 九、附录：快速参考 Appendix: Quick Reference

### 9.1 数据处理命令速查 Command Cheatsheet

**单工况处理 Single Case**:
```matlab
% 从项目根目录执行
run(fullfile('cases', 'per_case', 'tandem_f40a3_phi45_r2', 'tandem_f40a3_phi45_r2_case.m'))
```

**批量处理 Batch Processing**:
```matlab
run('scripts/run_r2_cases_batch.m')
```

**汇总结果 Aggregate Results**:
```matlab
run('scripts/aggregate_results_summary.m')
% 输出: results/parameter_sweep_summary_20260906.csv
```

**检查工况状态 Check Case Status**:
```matlab
case_id = 'tandem_f40a3_phi45_r2';
output_dir = fullfile('cases', 'per_case', case_id, 'output', 'mat');
files = dir(fullfile(output_dir, '*.mat'));
fprintf('%s: %d MAT files found\n', case_id, length(files));
% 完整工况应有 7-8 个 MAT 文件
```

### 9.2 常见问题排查 Troubleshooting FAQ

**Q1: 提示 "Missing data source"**  
A: 检查 `cfg.sources.raw.name` 是否与 J: 盘实际目录一致，注意大小写。

**Q2: Section 4 运行极慢（>2 小时）**  
A: 检查 `cfg.structures.instantaneous.frame_range`，如设为 [1 12000] 会处理全部帧。建议用 `n_output_frames=3` 只保存代表帧。

**Q3: POD 报错 "Out of memory"**  
A: 降低 `cfg.pod.n_frames` 从 12000 到 6000，或减少 `spatial_stride`。

**Q4: 相位平均结果全是 NaN**  
A: baseline 不应执行 Section 3，确保 `cfg.stages.phase='skip'`。

**Q5: DMD 频率为负数**  
A: 正常现象（复特征值的虚部），取 `abs(dmd.frequency_hz)` 作图。

---

**文档版本 Document Version**: v1.0  
**创建日期 Created**: 2026-09-06  
**维护者 Maintainer**: Frank  
**审核者 Reviewer**: Kiro AI
