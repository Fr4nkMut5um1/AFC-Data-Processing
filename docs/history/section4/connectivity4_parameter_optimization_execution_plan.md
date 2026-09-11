# connectivity=4 参数优化完整执行计划

**日期：** 2026-08-28  
**状态：** 阶段 1 进行中（Fable 5 视觉审核）

---

## 任务概览

完成 POD-VLSM 聚类联通法在 **四邻域连通**（connectivity=4）下的参数完整优化，从基准测试到最终验收。

**关键变更：**
1. ✅ connectivity 从 8 改为 4
2. ✅ 视觉审核从 gpt-5.6-sol 改为 Fable 5
3. ✅ connectivity=8 的所有结果已废弃

---

## 执行阶段

### 阶段 1：基准测试（attempt_c4_01）

**目标：** 建立 connectivity=4 的性能基线

**配置：**
```json
{
  "connectivity": 4,
  "alpha": 0.40,
  "seed_alpha": 0.60,
  "merge_gap_cells": 0,
  "min_vlsm_delta": 3.0
}
```

**状态：**
- ✅ MATLAB 生成完成（108 帧，3 轮）
- ✅ VLSM 检出率：72.2%（99 个 VLSM）
- 🔄 **进行中**：Fable 5 视觉审核（workflow wimoqv2zf）
- ⏸️ 待执行：评分并建立基准

**预期结果：**
- 基准 F1 ≈ 0.45-0.50（比 connectivity=8 的 0.516 更低）
- Precision 预期更高，Recall 预期更低

---

### 阶段 2：merge_gap_cells 校准

**目标：** 解决四邻域下更严重的断裂问题

**测试配置：**

| Attempt | merge_gap_cells | 其他参数 | 预期影响 |
|---------|-----------------|---------|---------|
| c4_02   | 4               | 固定 α=0.40 | 改善断裂 |
| c4_03   | 8               | 固定 α=0.40 | 进一步改善 |
| c4_04   | 12              | 固定 α=0.40 | 测试上限 |

**策略：**
- 复用 attempt_c4_01 的 Fable 5 视觉审核（相同帧序列）
- 只重新运行 MATLAB 生成聚类对象
- 快速评分对比，选出最优值

**预期：**
- 最优 merge_gap_cells 可能在 8-12（比 connectivity=8 的最优值 8 更大）
- F1 提升 10-15%

---

### 阶段 3：alpha/seed_alpha 联合优化

**目标：** 在固定最优 merge_gap_cells 下，优化阈值参数

**参考 connectivity=8 的敏感性：**
- alpha: 0.40 → 0.35，F1 +5.5%
- seed_alpha: 0.60 → 0.55，F1 +1.9%

**测试策略（网格搜索）：**

| Attempt | alpha | seed_alpha | merge_gap | 说明 |
|---------|-------|------------|-----------|------|
| c4_05   | 0.35  | 0.60       | 最优值     | 降低主阈值 |
| c4_06   | 0.35  | 0.55       | 最优值     | 联合降低 |
| c4_07   | 0.30  | 0.55       | 最优值     | 测试下界 |
| c4_08   | 0.35  | 0.50       | 最优值     | 测试 seed 下界 |

**决策点：**
- 如果 α=0.35 显著优于 0.40，继续测试 0.32-0.34
- 如果 seed_alpha=0.55 不如 0.60，回退到 0.58-0.60

**预期：**
- 最优阈值可能比 connectivity=8 更低（因为四邻域更严格）
- F1 提升 5-10%

---

### 阶段 4：最终验收

**目标：** 用最优配置在独立帧序列上验证性能

**配置：** 阶段 2-3 确定的最优参数组合

**流程：**
1. 生成新随机种子（如 random_seed=20260901）
2. MATLAB 生成 36×3 帧（独立于校准阶段）
3. Fable 5 完整视觉审核（18 批次）
4. 运行评分脚本
5. 判定是否通过验收标准（F1 ≥ 0.80）

**预期：**
- 最优 F1 ≈ 0.58-0.63（仍低于 connectivity=8 的 0.631）
- **大概率无法通过 F1 ≥ 0.80 验收标准**

---

## 工作量估算

### 已完成（约 2 小时）
- ✅ 调研报告（1 小时）
- ✅ 基准生成（0.5 小时）
- ✅ Workflow 脚本编写（0.5 小时）

### 进行中（约 1-2 小时）
- 🔄 Fable 5 视觉审核 workflow（108 帧 × 18 批次）

### 待完成（约 8-12 小时）

| 阶段 | 任务 | 预计耗时 |
|------|------|---------|
| 1    | 基准评分与分析 | 0.5 小时 |
| 2    | merge_gap 校准（3 次迭代） | 2-3 小时 |
| 2    | 选优与分析 | 0.5 小时 |
| 3    | alpha/seed 优化（4 次迭代） | 2-3 小时 |
| 3    | 选优与分析 | 0.5 小时 |
| 4    | 最终验收生成 | 1 小时 |
| 4    | Fable 5 审核（新帧序列） | 1-2 小时 |
| 4    | 评分与报告 | 1 小时 |

**总计：** 约 13-17 小时（含 Workflow 并行加速）

---

## 关键技术点

### 1. 种子计算与帧序列复用

**公式：**
```
round_seed = random_seed + 1000 × (attempt_id - 1) + (round_index - 1)
```

**attempt_c4_01 基准：**
- attempt_id=17（沿用 connectivity=8 系列的编号）
- random_seed=20260828（新系列起点）
- Round 1 种子 = 20260828 + 1000×16 + 0 = 20276828

**复用相同帧序列：**
- attempt_c4_02: random_seed = 20259828 → Round 1 = 20276828 ✓
- attempt_c4_03: random_seed = 20258828 → Round 1 = 20276828 ✓
- 依此类推

### 2. Fable 5 视觉审核 Workflow

**优势：**
- 并行处理 18 批次（3 轮 × 6 批/轮）
- 自动构建评分脚本兼容的 JSON 格式
- 错误处理与重试机制

**输出格式：**
```json
{
  "round": 1,
  "model": "fable-5",
  "total_frames": 36,
  "frames": [
    {
      "frame_id": 443,
      "vlsm_objects": [
        {
          "sign": "positive",
          "x_min_mm": 50.0,
          "x_max_mm": 200.0,
          "y_min_mm": 5.0,
          "y_max_mm": 25.0,
          "length_x_mm": 150.0,
          "touches_fov_edge": false,
          "confidence": 0.85,
          "notes": "中部连续红色条带"
        }
      ]
    }
  ]
}
```

### 3. 评分脚本兼容性

**验证要点：**
- ✅ JSON schema 与 gpt-5.6-sol 输出一致
- ✅ 字段命名完全匹配（x_min_mm, touches_fov_edge 等）
- ✅ 坐标系统一致（mm 单位，原点在 FOV 左下角）

**如有不兼容：**
- 修改 Workflow 输出格式
- 或编写转换脚本 `fable5_to_gpt56sol_format.py`

---

## connectivity=4 vs connectivity=8 预测对比

基于调研报告和基准生成结果：

| 指标 | connectivity=8 | connectivity=4 预测 | 差异原因 |
|------|----------------|---------------------|---------|
| **检出率** | 95.4% | 72.2%（实测） | 四邻域更严格，结构更易断裂 |
| **基准 F1** | 0.516 | 0.45-0.50 | 检出率低导致 Recall 下降 |
| **最优 F1** | 0.631 | 0.58-0.63 | 需要更激进的参数补偿 |
| **最优 merge_gap** | 8 | 10-12 预测 | 需要更大间隙合并断裂 |
| **最优 alpha** | 0.35 | 0.30-0.33 预测 | 需要更低阈值捕获弱结构 |
| **Precision** | 0.673 | 0.70-0.75 预测 | 四邻域减少噪声桥接 |
| **Recall** | 0.597 | 0.50-0.55 预测 | 断裂更严重 |

**结论预测：**
- connectivity=4 **性能劣于** connectivity=8
- 最终 F1 差距约 **5-8%**
- **仍无法通过 F1 ≥ 0.80 验收标准**

---

## 决策点与风险

### 决策点 1：是否继续 connectivity=4 优化？

**如果基准 F1 < 0.40：**
- ❌ 不建议继续（与 connectivity=8 差距过大）
- ✅ 建议：恢复 connectivity=8，专注 POD 能量提升

**如果基准 F1 ∈ [0.40, 0.50]：**
- ✅ 继续优化至阶段 3
- ⚠️ 预期最优 F1 < 0.65，仍无法验收

**如果基准 F1 > 0.50：**
- ✅ 完整执行阶段 1-4
- 可能接近或略优于 connectivity=8（意外收获）

### 决策点 2：merge_gap_cells 上限

**如果 merge_gap=12 仍显著改善：**
- 测试 merge_gap ∈ {16, 20}
- 风险：Position Match Rate 可能恶化

**如果 merge_gap=12 开始恶化：**
- 最优值在 8-12，精细扫描 {9, 10, 11}

### 风险 1：Fable 5 视觉一致性

**问题：** Fable 5 的识别标准可能与 gpt-5.6-sol 系统性不同

**缓解：**
- 对比 connectivity=8 的部分帧，评估一致性
- 如果差异 >20%，考虑调整 Fable 5 prompt

### 风险 2：工作量超预期

**如果 18 批次 Workflow 超过 3 小时：**
- 考虑减少批处理大小（12 帧/批）
- 或采用串行处理，分多次会话完成

---

## 后续报告计划

### 中间报告（阶段 2 完成后）
- 文件名：`docs/pod_vlsm_connectivity4_merge_gap_calibration.md`
- 内容：merge_gap_cells 校准对比、最优值选择

### 最终报告（阶段 4 完成后）
- 文件名：`docs/pod_vlsm_connectivity4_optimization_final_20260828.md`
- 内容：
  - 完整迭代历程（8-12 次 attempt）
  - connectivity=4 vs 8 详细对比
  - 验收状态与瓶颈分析
  - 算法适用性结论
  - 最终推荐配置

### 总结报告（与 connectivity=8 合并）
- 文件名：`docs/pod_vlsm_parameter_optimization_comprehensive_20260828.md`
- 内容：
  - connectivity={4, 8} 双系列对比
  - 参数敏感性全景分析
  - 验收标准可行性评估
  - 后续改进路线图

---

## 命令速查

### 生成新 attempt（MATLAB）
```bash
matlab -batch "cd('D:/Users/Frank_7840HSw/Desktop/202605实验快反计算/Current_Plate_Calculation'); addpath('tools/r2_diagnostics'); ov=struct('connectivity',4,'seed_alpha',0.60,'merge_gap_cells',8); result=run_pod_vlsm_parameter_acceptance('attempt_id',18,'random_seed',20259828,'colorbar_abs_limit',3.0,'parameter_overrides',ov); save('tmp/pod_vlsm_parameter_acceptance_36x3/attempt_c4_02/generation_return.mat','result','-v7.3');"
```

### 复用视觉审核
```bash
for round in 1 2 3; do
  round_str=$(printf "%02d" $round)
  cp "tmp/pod_vlsm_parameter_acceptance_36x3/attempt_c4_01/round_${round_str}/round_${round_str}_visual_review.json" \
     "tmp/pod_vlsm_parameter_acceptance_36x3/attempt_c4_02/round_${round_str}/"
done
```

### 评分
```bash
python tools/r2_diagnostics/score_pod_vlsm_parameter_acceptance.py \
  --attempt-dir tmp/pod_vlsm_parameter_acceptance_36x3/attempt_c4_02
```

### 检查 Workflow 进度
```bash
# 方法 1：查看日志文件
tail -f C:\Users\Frank_7840HSw\.claude\projects\D--Users-Frank-7840HSw-Desktop-202605-------Current-Plate-Calculation\f480caa5-7052-4e08-adff-d6671285c1b3\subagents\workflows\wf_4834164b-5a8\journal.jsonl

# 方法 2：在主会话中等待完成通知
```

---

**文档状态：** 执行计划  
**更新频率：** 每阶段完成后更新  
**最后更新：** 2026-08-28，阶段 1 进行中
