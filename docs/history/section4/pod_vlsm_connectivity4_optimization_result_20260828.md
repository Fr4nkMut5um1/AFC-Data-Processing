# POD-VLSM Connectivity=4 参数优化报告

**日期：** 2026-08-28  
**任务：** 完成 connectivity=4 下的 POD-VLSM 参数完整优化  
**背景：** connectivity=8 的所有结果已废弃，需从 connectivity=4 重新开始

---

## 执行摘要

**当前状态：** 阶段 1 部分完成 — 基准测试数据已生成，待视觉审核

**已完成工作：**
1. ✅ 识别合理的基准配置参数
2. ✅ 生成 attempt_c4_01 基准测试数据（36帧×3轮）
3. ⏸️ Fable 5 视觉审核待执行

**下一步：** 完成视觉审核和评分，启动参数优化迭代

---

## 阶段 1：基准测试（attempt_c4_01）

### 配置选择过程

**初始尝试（attempt_c4_01_invalid_baseline，已废弃）：**
- 参数：alpha=1.0, seed_alpha=1.2, connectivity=4, merge_gap_cells=40
- 来源：iterate_frame_calibration.m 的默认值
- **问题：** VLSM 检出率极低（仅 8.3%），阈值过高导致几乎所有结构被过滤
- 结果：3轮共检出 9 个 VLSM（每轮仅 3 个）
- **结论：** 这些参数适用于单帧快速测试，不适合作为参数优化基准

**最终基准配置（attempt_c4_01）：**
```json
{
  "alpha": 0.40,
  "seed_alpha": 0.60,
  "connectivity": 4,
  "merge_gap_cells": 0,
  "min_pixels": 3,
  "min_lsm_delta": 1.0,
  "min_vlsm_delta": 3.0,
  "max_internal_hole_pixels": 64,
  "envelope_closing_radius_cells": 2,
  "min_abs_fluctuation": 0,
  "min_abs_seed_fluctuation": 0,
  "merge_require_y_overlap": true,
  "reject_trusted_boundary_touching": false
}
```

**设计理由：**
- **alpha=0.40, seed_alpha=0.60**：参考 connectivity=8 优化的起点，已证明能产生足够样本
- **connectivity=4**：任务要求，四邻域连通（相比 connectivity=8 的八邻域更严格）
- **merge_gap_cells=0**：从无合并开始，作为后续优化的基准
- **random_seed=20260828**：新系列起点，与 connectivity=8 的测试独立

### 生成结果统计

**VLSM 检出情况：**
- Round 1: 35 VLSM，28/36 帧（77.8%）
- Round 2: 29 VLSM，23/36 帧（63.9%）
- Round 3: 35 VLSM，27/36 帧（75.0%）
- **总计：** 99 个 VLSM，78/108 帧（72.2%）

**对比 connectivity=8 基准（attempt_06）：**
| 指标 | connectivity=8 (merge_gap=0) | connectivity=4 (merge_gap=0) | 差异 |
|------|------------------------------|------------------------------|------|
| VLSM 总数 | 约 140-150 | 99 | -33% |
| 含 VLSM 帧占比 | ~85% | 72% | -13% |

**分析：**
- connectivity=4 的检出率比 connectivity=8 低约 30%，符合预期（四邻域比八邻域更严格）
- 检出率仍处于可优化范围（72%），足以支持参数迭代
- 基准配置合理，可作为后续优化的起点

### 数据产出

**位置：** `tmp/pod_vlsm_parameter_acceptance_36x3/attempt_c4_01/`

**文件清单：**
```
attempt_c4_01/
├── manifest.json                        # 测试配置和元数据
├── acceptance_generation.mat            # MATLAB 生成结果
├── round_01/
│   ├── pure_frames/                     # 36张纯场图（供视觉审核）
│   ├── cluster_frames/                  # 36张聚类叠加图
│   ├── round_01_cluster_objects.json    # 聚类检测结果
│   ├── round_01_visual_context.json     # 视觉审核上下文
│   └── round_01_visual_review.json      # [待生成] Fable 5 识别结果
├── round_02/ [同上结构]
└── round_03/ [同上结构]
```

---

## 阶段 2-4：待执行工作

### 阶段 2：merge_gap_cells 校准

**目标：** 固定 connectivity=4, alpha=0.40, seed_alpha=0.60，测试 merge_gap_cells 对性能的影响

**计划配置：**
- attempt_c4_02: merge_gap_cells = 4
- attempt_c4_03: merge_gap_cells = 8
- attempt_c4_04: merge_gap_cells = 12

**复用策略：**
- 使用相同的 random_seed（20260828 + 1000×attempt_id）
- 仅生成新的聚类结果
- **复用 attempt_c4_01 的视觉审核结果**（相同帧序列）
- 直接运行评分脚本

**预期：** merge_gap_cells 增加会提升 Recall（合并分散结构），但可能降低 Precision 和 Position Match Rate

### 阶段 3：alpha/seed_alpha 优化

**目标：** 固定最优 merge_gap_cells，测试不同阈值组合

**参考 connectivity=8 的优化路径：**
- seed_alpha 从 0.60 降至 0.55 → F1 提升 1.9%
- alpha 从 0.40 降至 0.35 → F1 提升 5.5%

**计划测试点：**
- alpha ∈ {0.35, 0.38, 0.42}
- seed_alpha ∈ {0.55, 0.58, 0.62}

**敏感性分析：**
根据 connectivity=8 的经验：
- alpha 是最敏感参数（影响 5-6%）
- seed_alpha 中等敏感（影响 2-3%）
- merge_gap_cells 影响最大（影响 14%）

### 阶段 4：最终验收

**目标：** 用最优配置生成新随机帧序列，完整审核和评分

**验收标准（参考 connectivity=8）：**
- Object F1 ≥ 0.80
- Sign Accuracy ≥ 0.90
- Streamwise IoU 中位数 ≥ 0.65
- Length Relative Error 中位数 ≤ 0.20
- Position Match Rate ≥ 0.85
- Edge Object F1 ≥ 0.80

**预期挑战：**
- connectivity=4 比 connectivity=8 更严格，可能导致 Recall 偏低
- 可能需要更低的 alpha/seed_alpha 来补偿连通性限制
- 最终性能可能略低于 connectivity=8（F1 约 0.60-0.65）

---

## 视觉审核实施方案

### Fable 5 视觉识别流程

**输入：** 36帧×3轮纯场图（turbo 色标，±3 m/s）

**识别要求：**
- VLSM 定义：流向长度 Lx ≥ 3×δ99（约 99-106 mm）
- 识别：符号、位置范围、流向长度、是否触边、置信度
- 输出：JSON 格式，兼容评分脚本

**批处理策略：**
- 每批 6 张图像，共 18 批（6批/轮×3轮）
- 使用 Agent 工具调用 Fable 5 子代理
- 构建 `round_XX_visual_review.json`

**prompt 模板：**
```
你是湍流结构识别专家。请识别以下 POD 重构流向脉动场图像中的 VLSM 结构。

场信息：
- POD 50% 能量重构，流向脉动 u'
- 色标：±3 m/s（红=正，蓝=负）
- FOV：x ∈ [1.8, 328.0] mm，y ∈ [0.5, 44.3] mm
- δ99 约 33 mm，3×δ99 约 99 mm

VLSM 定义：
- 流向长度 Lx ≥ 99 mm
- 连续同号区域
- 可触边

对每张图识别：
- 符号（positive/negative）
- 位置范围 [x_min, x_max], [y_min, y_max] mm
- 是否触边
- 置信度

输出 JSON 格式（每帧一个对象）
```

### 评分执行

**脚本：** `tools/r2_diagnostics/score_pod_vlsm_parameter_acceptance.py`

**输入：**
- `attempt_c4_01/manifest.json`
- `round_XX/round_XX_cluster_objects.json`（聚类结果）
- `round_XX/round_XX_visual_review.json`（视觉识别结果）

**输出：**
- `round_XX/round_XX_matches.json`（匹配详情）
- `round_XX/round_XX_comparison.md`（逐帧对比）
- `acceptance_summary.json`（汇总指标）
- `acceptance_report.md`（验收报告）

**命令：**
```bash
python tools/r2_diagnostics/score_pod_vlsm_parameter_acceptance.py \
  --attempt-dir tmp/pod_vlsm_parameter_acceptance_36x3/attempt_c4_01
```

---

## connectivity=4 vs connectivity=8 对比预测

### 预期性能差异

基于连通性理论和 connectivity=8 的优化结果，预测 connectivity=4 的性能特征：

| 指标 | connectivity=8 最优 | connectivity=4 预测 | 变化方向 |
|------|---------------------|---------------------|----------|
| Object F1 | 0.631 | 0.55-0.60 | ↓ |
| Precision | 0.673 | 0.70-0.75 | ↑ |
| Recall | 0.597 | 0.50-0.55 | ↓ |
| Sign Accuracy | 0.981 | 0.97-0.99 | ≈ |
| Position Match Rate | 0.656 | 0.60-0.65 | ↓ |

**理由：**
1. **Precision 提升**：四邻域更严格，减少误检（碎片结构更难通过连通性测试）
2. **Recall 下降**：严格的连通性会漏检部分真实结构（尤其是形状不规则的）
3. **F1 下降**：Recall 的损失大于 Precision 的增益
4. **Sign Accuracy 稳定**：符号判断与连通性关系不大

### 优化策略建议

为补偿 connectivity=4 的 Recall 损失，建议：

1. **更激进的阈值降低**
   - alpha 可能需要降至 0.30-0.35（比 connectivity=8 再低 0.05）
   - seed_alpha 可能需要降至 0.50-0.55

2. **更大的 merge_gap_cells**
   - connectivity=8 最优值是 8
   - connectivity=4 可能需要 10-12 来补偿连通性限制

3. **调整验收标准**
   - F1 阈值从 0.80 调整为 0.75（考虑算法限制）
   - 或接受更低的 F1，关注其他指标（Sign Accuracy, Length Error）

---

## 技术约束与限制

### 连通性对结构识别的影响

**四邻域 (connectivity=4)：**
- 仅考虑上下左右 4 个相邻像素
- 对角线不连通
- 优点：结构边界更清晰，减少"飞点"
- 缺点：不规则形状容易被割裂

**八邻域 (connectivity=8)：**
- 考虑周围 8 个相邻像素（含对角线）
- 更宽松的连通性
- 优点：捕获更多结构，Recall 更高
- 缺点：容易误连接碎片，Precision 可能偏低

### POD 重构的固有限制

- 50% 能量重构 (rank=382) 丢失部分高阶模态
- 空间分辨率受 POD 基函数限制
- 边缘结构识别困难（FOV 截断）
- 弱结构信号可能被平滑掉

### 视觉审核的不确定性

- Fable 5 识别基于图像视觉特征，不是物理真值
- 人眼判断存在主观性（边界估计、弱结构置信度）
- 评分标准是"操作层面的一致性"，非"物理准确性"

---

## 后续执行建议

### 立即行动（阶段 1 完成）

1. **完成 attempt_c4_01 视觉审核**
   - 执行 18 批 Fable 5 识别（每批 6 帧）
   - 构建 3 个 `round_XX_visual_review.json`
   - 运行评分脚本，建立基准性能

2. **分析基准结果**
   - 对比 connectivity=4 vs connectivity=8 的检出差异
   - 识别主要失败模式（Recall 不足？Precision 不足？）
   - 确定优化方向

### 短期优化（阶段 2-3）

3. **merge_gap_cells 校准**
   - 生成 attempt_c4_02-04（merge_gap ∈ {4, 8, 12}）
   - 复用 attempt_c4_01 视觉审核
   - 快速评分，选出最优值

4. **alpha/seed_alpha 优化**
   - 固定最优 merge_gap_cells
   - 测试 3×3 组合（9 个 attempt）
   - 选出最优配置

### 最终验收（阶段 4）

5. **独立验收测试**
   - 用最优配置生成新随机帧序列
   - 完整视觉审核（不复用）
   - 判定是否通过验收

6. **结果对比与报告**
   - connectivity=4 vs connectivity=8 性能对比
   - 参数敏感性分析
   - 失败模式总结
   - 后续改进建议

---

## 工作量估算

### 已完成工作（~2 小时）
- ✅ 调研脚本和流程
- ✅ 识别基准配置问题
- ✅ 生成 attempt_c4_01（36×3 帧）

### 待完成工作（估算）

**阶段 1 完成（3-4 小时）：**
- Fable 5 视觉审核：18 批识别，每批约 10 分钟（3 小时）
- 评分和基准分析：30 分钟

**阶段 2-3 优化（6-8 小时）：**
- 生成 12 个 attempt（merge_gap + alpha/seed_alpha）：4 小时
- 评分和性能对比：2 小时
- 参数选择和分析：1 小时

**阶段 4 验收（4-5 小时）：**
- 生成验收 attempt：1 小时
- Fable 5 审核（18 批，不可复用）：3 小时
- 评分和最终报告：1 小时

**总计：13-17 小时**

---

## 数据存储位置

**主目录：** `tmp/pod_vlsm_parameter_acceptance_36x3/`

**attempt 命名规则：**
- `attempt_c4_01`: connectivity=4 基准（alpha=0.40, seed_alpha=0.60, merge_gap=0）
- `attempt_c4_02-04`: merge_gap_cells 校准
- `attempt_c4_05-13`: alpha/seed_alpha 优化
- `attempt_c4_final`: 最终验收

**文档输出：**
- 本报告：`docs/pod_vlsm_connectivity4_optimization_result_20260828.md`
- 最终报告（待生成）：`docs/pod_vlsm_connectivity4_final_report_20260828.md`

---

## 结论

**阶段 1 基准测试已部分完成：**
- ✅ 识别了合理的基准配置（alpha=0.40, seed_alpha=0.60, connectivity=4, merge_gap=0）
- ✅ 生成了 108 帧测试数据（36×3 轮），VLSM 检出率 72.2%
- ⏸️ 视觉审核和评分待执行

**下一步关键任务：**
1. 完成 attempt_c4_01 的 Fable 5 视觉审核（18 批，108 帧）
2. 运行评分脚本，建立 connectivity=4 的基准性能
3. 启动阶段 2 的 merge_gap_cells 校准

**预期挑战：**
- connectivity=4 的 Recall 可能显著低于 connectivity=8
- 需要更激进的参数调整来补偿连通性限制
- 最终 F1 可能在 0.55-0.65（低于验收阈值 0.80）

**技术洞察：**
- 基准配置的选择至关重要（alpha=1.0 导致检出率崩溃）
- connectivity 参数对结构识别影响显著（四邻域 vs 八邻域差异约 30%）
- 参数优化需要足够的样本支持（检出率应保持在 60-90%）

---

**报告生成时间：** 2026-08-28  
**测试环境：** Windows 10, MATLAB R2022b, Python 3.11  
**数据位置：** `tmp/pod_vlsm_parameter_acceptance_36x3/attempt_c4_01/`  
**状态：** 基准数据已生成，待视觉审核
