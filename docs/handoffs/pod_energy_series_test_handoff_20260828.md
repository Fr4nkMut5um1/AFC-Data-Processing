# POD 能量系列测试 + 逐能量参数寻优任务交接文档

**生成时间：** 2026-08-28  
**源对话主题：** POD-VLSM 参数优化（connectivity=4 完整优化）  
**目标：** 新对话执行 POD 能量系列测试，且**每个能量水平独立进行参数寻优**

**⚠️ 本文档要求新对话积极调用子 agent（限定 fable-5）与 workflows 进行并行作业。**

---

## 【工作目录】

```
D:\Users\Frank_7840HSw\Desktop\202605实验快反计算\Current_Plate_Calculation
```

**Git 分支：** 2026-08-22  
**工况：** tandem_baseline_r2  
**MATLAB：** R2022b，可执行文件 `D:/Academic/Software/MATLAB/R2022b/bin/matlab.exe`  
**工作树状态：** 非常脏，含大量用户已有修改和未跟踪文件。不要 reset/checkout/清理/提交/覆盖无关改动；用户没有要求 commit。

---

## 【核心任务】[verified]

**测试 7 个 POD 能量水平，且每个能量水平独立进行聚类参数寻优**

**能量序列：** 20%, 30%, 40%, 50%（基准）, 60%, 70%, 80%

**固定不变：**
- `connectivity = 4`（物理要求，文献 100% 支持，不得改动）
- `min_vlsm_delta = 3.0`（VLSM 操作性定义，不得放宽）
- `min_pixels = 3`、`min_lsm_delta = 1`、`max_internal_hole_pixels = 64`、`envelope_closing_radius_cells = 2`
- `min_abs_fluctuation = 0`、`min_abs_seed_fluctuation = 0`（必须显式钉住，防止旧缓存污染）
- `merge_require_y_overlap = true`
- `reject_trusted_boundary_touching = false`、`trusted_domain` 边缘缓冲全 0（POD 方案不做边缘排除）

**每个能量水平需寻优的参数：**
- `alpha`（生长阈值）
- `seed_alpha`（种子阈值）
- `merge_gap_cells`（流向断裂合并间隙）

**关键理由 [verified]：** 不同能量的 POD 重构场平滑度和脉动幅值分布不同——低能量场更平滑（可能需更低阈值），高能量场噪声更多（可能需更高阈值）。50% 下的最优参数（alpha=0.30, merge_gap=12）**不可直接迁移**到其他能量水平。

---

## 【已验证的背景】

### 1. connectivity=4 在 50% 能量下的完整寻优结果 [verified]

**9 次迭代（attempt_c4_01 至 c4_08，attempt_id=17-25）：**

| Attempt | alpha | seed_α | merge_gap | VLSM 总数 (108帧) | 相比基准 |
|---------|-------|--------|-----------|-------------------|---------|
| c4_01 基准 | 0.40 | 0.60 | 0 | 99 | - |
| c4_02 | 0.40 | 0.60 | 4 | 127 | +28.3% |
| c4_03 | 0.40 | 0.60 | 8 | 141 | +42.4% |
| c4_04 | 0.40 | 0.60 | 12 | 159 | +60.6% |
| c4_05 | 0.40 | 0.60 | 16 | 162 | +63.6%（边际递减）|
| c4_06 | 0.35 | 0.60 | 12 | 170 | +71.7% |
| c4_07 | 0.35 | 0.55 | 12 | 172 | +73.7% |
| **c4_08 最优** | **0.30** | **0.55** | **12** | **191** | **+93.9%** |

**50% 能量最优配置（作为各能量寻优的起点参考）：**
```json
{
  "connectivity": 4,
  "alpha": 0.30,
  "seed_alpha": 0.55,
  "merge_gap_cells": 12
}
```

**已验证的寻优方法论 [verified]：**
1. **先拓扑后阈值**：merge_gap 贡献最大（+60.6%），再调 alpha（+33%）
2. **单变量控制**：每次只改一个参数或一个明确配对
3. **收益递减识别**：merge_gap=12→16 仅 +1.9%，即停
4. **统计快速评估**：用 VLSM 数量/检出率筛选候选，无需每个候选做视觉审核

### 2. POD 当前状态 [verified]

- 50% 能量：rank=382，累计能量 0.500237469280837
- 数据：12000 帧 PIV（fs=960Hz，网格 640×91）
- POD 基：`tmp/pod_energy_sweep/pod_energy_sweep_basis.mat`（另见 cases 输出目录）
- **用户观点 [verified]**：本项目 POD 前几阶模态能量占比不高（不像文献那些前几阶就占很高的情况），因此低能量（20-40%）与高能量（60-80%）都值得测试，不能只信文献的 60-80% 建议。
- **新对话应自行调取 POD 模态-能量占比数据**（能量谱/累计能量曲线），在报告中呈现本项目的模态能量分布，作为解释结果的依据。

### 3. 文献调研结论 [verified]

- 文献 POD 能量中位数 ~80-85%，本项目 50% 处于下四分位数
- 支持低能量的证据：Lumley (2017) ~50% TKE；Elyasi & Ghaemi (2018) 42% TKE（PIV 分离边界层，最相关）
- connectivity=4：所有 DNS 湍流研究使用正交邻域（Hwang & Sung 2018、Lozano-Durán 2012）；渗流理论 p_c(4-conn)≈0.593
- 报告位置：`docs/pod_energy_selection_literature_review_20260828.md`、`docs/connectivity_and_gaussian_filter_research_20260828.md`

### 4. 评估口径 [verified]

- 结论只能表述为"2C-2D XOY 平面连通结构的操作性比较"，不得称为三维物理真值
- 本阶段以**聚类统计指标**（VLSM 数、检出率、尺寸分布）做参数寻优与能量对比，不做视觉审核
- 检出率 = 含 VLSM 帧数 / 总帧数；与对象级 Recall 不同，注意区分

---

## 【任务结构：7 能量 × 参数寻优】

### 总体流程

```
阶段 0：调取 POD 模态-能量占比数据（能量谱曲线）
阶段 1：生成 7 个能量的 POD 基（20%-80%）
阶段 2：每个能量独立参数寻优（7 组并行/串行）
   每组内：
   2a. 基准点（沿用 50% 最优参数作为起点）
   2b. merge_gap 扫描 {8, 12, 16}（必要时补 4 或 20）
   2c. alpha 扫描 {0.25, 0.30, 0.35}（必要时扩展）
   2d. seed_alpha 微调 {0.50, 0.55, 0.60}
阶段 3：跨能量对比分析
阶段 4：最终报告
```

### 每能量寻优预算 [inferred]

- 每个能量约 5-9 次迭代（参考 50% 用了 9 次，但已有方法论可加速）
- 总计约 **35-60 次 MATLAB 生成**
- 每次生成约 5-15 分钟（取决于 rank；高能量 rank 更大更慢）
- **总预计：15-30 小时 MATLAB 时间** —— 必须用 workflow/子 agent 并行组织，但注意 MATLAB 实例数限制（见下）

### 寻优起点建议 [inferred]

| 能量 | 场特征预期 | alpha 起点 | merge_gap 起点 |
|------|-----------|-----------|---------------|
| 20% | 极平滑，脉动幅值小 | 0.25-0.30 | 8-12 |
| 30% | 很平滑 | 0.25-0.30 | 8-12 |
| 40% | 平滑 | 0.30 | 12 |
| 50% | 基准 | **0.30（已验证最优）** | **12（已验证最优）** |
| 60% | 稍多噪声 | 0.30-0.35 | 10-12 |
| 70% | 更多噪声 | 0.35 | 8-12 |
| 80% | 噪声明显 | 0.35-0.40 | 8 |

这些只是起点假设 [inferred]，必须以实测为准，不得跳过扫描直接采信。

---

## 【必须遵守的执行约束】[verified]

1. **MATLAB 并发限制**：R2022b 尽量一次只运行一个批处理实例，避免内存争抢和结果互相污染。若要并行，先小规模试验确认两个实例可共存，否则保持串行；workflow 层面的"并行"应体现在子 agent 组织与分析上，MATLAB 调用需排队。
2. **不修改数值核心**：不改 `cases/per_case/tandem_baseline_r2/tandem_baseline_r2_case.m`、`+tblR2/identify_structures.m` 等上游数值核心；只改诊断/验收工具和 POD 局部参数副本。`resolve_settings` 是识别参数唯一口径。
3. **显式钉参数**：每次生成显式传入完整 `parameter_overrides`（含 connectivity=4、min_abs_fluctuation=0、min_abs_seed_fluctuation=0、merge_gap_cells），不从可能陈旧的 `cfg.structures` 继承。
4. **帧序列一致性**：所有能量、所有参数组合必须使用**同一批帧序列**（同一 random_seed 推导），否则不可比。生成工具的种子公式：
   ```
   round_seed = random_seed + 1000 * (attempt_id - 1) + (round_index - 1)
   ```
   50% 系列 c4 批次基准：attempt_id=17, random_seed=20260828 → Round1 种子 20276828。新系列若沿用同帧集，需按公式反推 random_seed；每个新 attempt_id 用 `random_seed = 20276828 - 1000*(attempt_id-1)` 使 Round1 种子恒为 20276828。**生成后必须程序化核对三轮 frame_ids 与 attempt_c4_01 完全一致**。
5. **attempt 目录管理**：不删除或覆盖旧 attempt；attempt_01-15 为 connectivity=8 旧系列（已废弃但保留审计），attempt_17-25 为 connectivity=4 的 50% 能量系列。新能量系列建议用清晰命名（如 attempt_id 从 26 起，并在目录/日志中注明能量水平），维护一个总的 attempt 索引表。
6. **绘图规范**（若生成流场图）：`contourf`、色标固定 ±3 m/s、保留 overflow-safe contour levels（levels 追加真实极值防止超量程留白）。不改成 pcolor/scatter。
7. **中文交流**：全程中文汇报，POD/VLSM/FOV/IoU 等术语保留英文。
8. **报告诚实性**：若某能量寻优后仍不理想，如实报告；不得为了"更好看"而放宽 min_vlsm_delta 或其他定义性参数。

---

## 【关键命令模板】

### 生成一个 attempt（示例：60% 能量需先确认 POD 基路径切换方式）

```bash
matlab -batch "cd('D:/Users/Frank_7840HSw/Desktop/202605实验快反计算/Current_Plate_Calculation'); addpath('tools/r2_diagnostics'); ov=struct('connectivity',4,'alpha',0.30,'seed_alpha',0.55,'merge_gap_cells',12); run_pod_vlsm_parameter_acceptance('attempt_id',26,'random_seed',20251828,'colorbar_abs_limit',3.0,'parameter_overrides',ov);"
```

**⚠️ [unverified] 重要**：`run_pod_vlsm_parameter_acceptance.m` 当前默认使用 50% POD 基（energy_target=0.5, rank=382）。新对话第一步必须阅读该脚本，确认：
1. 是否已有 `energy_target` 或 `pod_basis_file` 参数可指定其他能量
2. 若没有，需要为其添加能量/基文件参数（这是对诊断工具的允许修改）
3. 不同能量的 POD 基如何生成（查 `tmp/pod_energy_sweep/` 与 Section 7 POD 阶段代码）

### 汇总 VLSM 数量（从生成日志）

```bash
grep "cluster VLSM" tmp/pod_vlsm_parameter_acceptance_36x3/attempt_XX*_gen.log
```

### 静态检查

```bash
python tests/matlab_check.py tools/r2_diagnostics
git diff --check
```

---

## 【子 agent 与 workflow 组织建议】[verified 用户要求]

**用户明确要求：积极调用子 agent（限定 fable-5）与 workflows。**

### 推荐分工

1. **主会话（协调者）**：
   - 阅读脚本确认 POD 基切换接口（第一步，亲自做）
   - 维护 attempt 索引表和 MATLAB 执行队列
   - 汇总各能量寻优结果，做跨能量对比

2. **fable-5 子 agent（每能量一个，或每阶段一个）**：
   - 子 agent A：POD 基生成管理（7 个能量，串行 MATLAB）
   - 子 agent B-H：各能量的参数寻优（读日志、算统计、提出下一组参数、生成对比表）
   - 子 agent I：跨能量综合分析与报告撰写

3. **Workflow**：
   - 用于组织"寻优决策循环"：每轮收集 7 个能量的当前结果 → 并行让子 agent 分析 → 汇总决定下一轮参数
   - **注意**：上一会话中 workflow 的 agent() 带严格 JSON schema 曾全部失败（StructuredOutput 重试超限）；建议 schema 用宽松结构或纯文本返回后主流程解析

### 已知教训 [verified]

- Workflow + 严格 schema + 图像任务 → 18/18 批次失败；统计/文本任务 schema 可用但应从宽
- 子 agent 曾出现种子计算错误导致帧序列不一致 → 每次生成后必须核对 frame_ids
- MATLAB `save` 到不存在的目录会报错 → 让生成函数自建目录或预先 mkdir

---

## 【交付物要求】

### 每能量水平
1. 寻优迭代表（参数组合 × VLSM 数 × 检出率）
2. 该能量的最优参数配置
3. 该能量最优性能（VLSM 数、检出率、尺寸分布）

### 跨能量综合
1. **主对比表**：能量 × 最优参数 × 最优性能 × POD rank × 计算时间
2. **曲线图**（用 MATLAB 或 Python 生成并保存）：
   - 能量 vs 最优 VLSM 数
   - 能量 vs 最优检出率
   - 能量 vs 最优 alpha / merge_gap（参数漂移趋势）
   - 本项目 POD 模态-能量占比曲线（回应用户观点）
3. **最终报告**：`docs/pod_energy_series_optimization_result_YYYYMMDD.md`
   - 回答核心问题：本项目最优 POD 能量是多少？50% 是否偏低？
   - 参数随能量的漂移规律及物理解释
   - 与文献（中位数 80-85%）的差异及原因（结合本项目模态能量分布）

---

## 【上下文限制与验证要求】

**新对话必须先独立验证（不要盲信本文档）：**
1. `run_pod_vlsm_parameter_acceptance.m` 的 POD 基指定方式 [unverified]
2. 各能量 POD 基的生成入口与耗时 [unverified]
3. attempt 目录当前占用情况（attempt_17-25 已被 50% 系列使用）[verified 至 25]
4. 种子公式在当前脚本版本中是否仍然成立 [verified 于 50% 系列，新版本需复核]

**若工作区证据与本文档冲突，以工作区为准并明确说明冲突。**

---

## 【接管后第一步】

1. 阅读 `tools/r2_diagnostics/run_pod_vlsm_parameter_acceptance.m`，确认/添加 POD 能量切换接口
2. 调取并绘制本项目 POD 模态-能量占比曲线（回应用户"前几阶占比不高"的观点）
3. 生成 20% 能量的 POD 基做冒烟测试（最小 rank，最快）
4. 冒烟通过后，制定完整的 7 能量 × 寻优执行计划并开始执行
5. 全程用 fable-5 子 agent 分担各能量的寻优分析，用 workflow 组织决策循环

---

**交接完成。核心要求：7 个 POD 能量水平（20%-80%），connectivity=4 固定，每个能量独立寻优 alpha/seed_alpha/merge_gap_cells，积极使用 fable-5 子 agent 与 workflows。**
