# POD-VLSM 参数寻优交接文档 - 建立正确评价体系

**交接时间**: 2026-08-29 01:50  
**当前状态**: 已完成基于聚类内部指标的初步寻优，但**缺乏 Ground Truth 对照**，需重建评价体系  
**下一阶段**: 建立人工标注流程，基于图像识别结果进行真实参数寻优

---

## 一、当前问题诊断

### 1.1 核心问题
**前期寻优使用了错误的评价标准**：
- ❌ 使用指标：VLSM 总数、检出率（聚类算法自身输出）
- ❌ 假设：VLSM 数量越多 = 越好
- ✅ 正确标准：**与人工图像识别结果对比**（Precision, Recall, F1, IoU）

### 1.2 为什么前期结果不可靠
1. **过检风险**：VLSM=225 可能包含大量误检（false positives）
2. **无质量验证**：未确认聚类框是否真实对应流场中的大尺度结构
3. **参数耦合未验证**：能量档-阈值的关系仅基于数量，未验证真实性

### 1.3 前期工作的有限价值
- ✓ 确认了 7 档能量的 POD 基已生成且可用
- ✓ 验证了参数扫描流程（连通性、阈值、merge_gap）可正常运行
- ✓ 建立了帧一致性验证机制
- ⚠ **所有定量结论（"60% 最优"、"α=0.25 最优"）仅作为初始探索，不能作为最终结论**

---

## 二、正确的评价流程

### 2.1 建立 Ground Truth
1. **随机采样 36 帧** — 从某一能量档（如 60%）的 POD 重构场中随机选择
2. **生成标准化脉动云图** — u'/u_rms 归一化，红白蓝对称色标
3. **人工标注 VLSM 边界框** — 用户在每张图上框出真实的 VLSM 结构
4. **记录标注数据** — 保存为 JSON 格式（边界框坐标、中心、长度）

### 2.2 评价指标
对于每个参数配置（能量档 + 连通性 + 阈值 + merge_gap）：
- **Precision**: 聚类框中有多少是真阳性（TP / (TP + FP)）
- **Recall**: 标注框中有多少被正确检出（TP / (TP + FN)）
- **F1-score**: Precision 和 Recall 的调和平均
- **IoU**: 边界框重叠度（Intersection over Union，阈值通常取 0.5）

### 2.3 寻优策略
1. **单能量档标注验证** — 先对一个能量档（如 60%）标注 36 帧，验证不同参数的 F1
2. **跨能量档对比** — 若单能量档最优参数确定，再对其他能量档标注验证泛化性
3. **迭代优化** — 基于 F1-score 调整参数，重新生成聚类结果，再次对比

---

## 三、已创建的工具与数据

### 3.1 标注生成工具
**文件**: `tools/r2_diagnostics/generate_annotation_samples.m`

**功能**: 
- 从指定能量档的 POD 基中随机选择 N 帧
- 生成标准化脉动云图 PNG
- 输出元数据和空标注模板 JSON

**调用示例**:
```matlab
generate_annotation_samples('energy_target', 0.60, ...
                            'output_dir', 'tmp/annotation_samples/e60', ...
                            'n_frames', 36, ...
                            'random_seed', 20260829)
```

**输出**:
- `output_dir/frames/frame_XXXX.png` — 36 张脉动云图
- `output_dir/metadata.json` — 采样元数据
- `output_dir/annotation_template.json` — 空标注模板

### 3.2 评价脚本
**文件**: `tools/r2_diagnostics/evaluate_clustering_vs_annotation.py`

**功能**:
- 加载人工标注 JSON（Ground Truth）
- 加载聚类结果 manifest.json（预测）
- 计算 TP/FP/FN、Precision/Recall/F1、逐帧 IoU
- 输出评价报告 JSON

**调用示例**:
```bash
python tools/r2_diagnostics/evaluate_clustering_vs_annotation.py \
    --annotation tmp/annotation_samples/e60/annotation_completed.json \
    --clustering tmp/pod_energy_series_opt/attempt_34/manifest.json \
    --output tmp/evaluation_results/e60_attempt34.json \
    --iou-threshold 0.5
```

### 3.3 现有数据资产
**POD 基**:
- `tmp/pod_energy_sweep/pod_energy_sweep_basis.mat` — 全部 2811 阶，覆盖 20-80% 能量

**前期 attempt 结果**（仅作参考，未经 GT 验证）:
- `tmp/pod_energy_series_opt/attempt_26-38/` — 13 次参数配置的聚类结果
- `tmp/pod_energy_series_opt/final_summary.json` — 所有 attempt 的 VLSM 统计

**能量谱数据**:
- `tmp/pod_energy_series_opt/energy_curve.json` — POD 特征值谱与累计能量

---

## 四、下一步执行计划

### Phase 1: 建立 Ground Truth（优先级最高）

#### Step 1: 生成标注样本
```matlab
% 在 MATLAB 中执行
cd('D:/Users/Frank_7840HSw/Desktop/202605实验快反计算/Current_Plate_Calculation')
addpath('tools/r2_diagnostics')
addpath('cases/per_case/tandem_baseline_r2')

% 先从 60% 能量开始（前期探索显示该档数据较丰富）
generate_annotation_samples('energy_target', 0.60, ...
                            'output_dir', 'tmp/annotation_samples/e60', ...
                            'n_frames', 36, ...
                            'random_seed', 20260829)
```

**输出**: `tmp/annotation_samples/e60/frames/` 中有 36 张 PNG

#### Step 2: 人工标注 VLSM 边界框
**流程**:
1. 逐张打开 PNG（按帧号顺序）
2. 用户目视识别真实的 VLSM（u'/u_rms 云图中的大尺度低速/高速条纹）
3. 为每个 VLSM 记录边界框坐标（x_min, x_max, y_min, y_max, mm 单位）
4. AI 辅助：用户描述"第 X 帧有 Y 个 VLSM，位置大致在..."，AI 推荐坐标
5. 用户确认或修正 AI 推荐的坐标
6. 填充到 `annotation_template.json`

**标注格式示例**（已在模板中定义）:
```json
{
  "frames": {
    "frame_1234": {
      "frame_id": 1234,
      "image_file": "frames/frame_1234.png",
      "vlsm_boxes": [
        {
          "x_min": 50.0,
          "x_max": 150.0,
          "y_min": 10.0,
          "y_max": 30.0,
          "length_mm": 100.0,
          "center_x": 100.0,
          "center_y": 20.0,
          "notes": "强低速条纹，清晰"
        }
      ],
      "annotation_status": "completed",
      "annotator_notes": "该帧有 2 个明显 VLSM"
    }
  }
}
```

**人机协作建议**:
- 用户每标注 6-12 帧，让 AI 分析一次，检查标注一致性
- AI 可用 CV 算法（如轮廓检测）辅助推荐候选框
- 最终决策权在用户，AI 仅辅助

#### Step 3: 标注完成后改名
```bash
mv tmp/annotation_samples/e60/annotation_template.json \
   tmp/annotation_samples/e60/annotation_completed.json
```

### Phase 2: 评价现有参数配置

#### Step 4: 对比前期"最优"配置与 GT
```bash
# 评价 60% α=0.25 (attempt_34)
python tools/r2_diagnostics/evaluate_clustering_vs_annotation.py \
    --annotation tmp/annotation_samples/e60/annotation_completed.json \
    --clustering tmp/pod_energy_series_opt/attempt_34/manifest.json \
    --output tmp/evaluation_results/e60_attempt34_eval.json

# 评价 60% 基线 α=0.30 (attempt_27)
python tools/r2_diagnostics/evaluate_clustering_vs_annotation.py \
    --annotation tmp/annotation_samples/e60/annotation_completed.json \
    --clustering tmp/pod_energy_series_opt/attempt_27/manifest.json \
    --output tmp/evaluation_results/e60_attempt27_eval.json

# 对比 F1-score，确定哪个更接近真实
```

**预期结果**:
- 若前期"最优"配置 F1 > 0.7，说明聚类内部指标与真实质量有一定相关性
- 若 F1 < 0.5，说明前期结论不可靠，需重新寻优

### Phase 3: 基于 GT 重新寻优

#### Step 5: 参数网格搜索
若 Step 4 显示前期配置不理想，则：
1. 固定能量档（如 60%），扫描参数组合：
   - alpha: {0.20, 0.25, 0.30, 0.35, 0.40}
   - merge_gap: {8, 12, 16}
   - connectivity: {4, 8}（前期已验证 4 更优，但需 GT 确认）
2. 每个组合生成一个 attempt，计算 F1-score
3. 选择 F1 最高的配置作为该能量档最优

#### Step 6: 跨能量档验证
对最优能量档的标注样本，测试不同能量档（40%, 50%, 70%）的表现：
- 若 60% F1 显著高于其他档，确认能量档选择
- 若多个能量档 F1 接近，选择计算成本更低的（rank 更小的）

---

## 五、关键注意事项

### 5.1 标注质量控制
- **一致性检查**: 每标注 12 帧，回顾前 3 帧，确保标准不漂移
- **边界框定义**: 明确 VLSM 边界的判断标准（如 u'/u_rms > 某阈值的连通区域）
- **模糊案例**: 对不确定的结构，标注为"uncertain"，评价时可选择跳过

### 5.2 评价指标选择
- **主指标**: F1-score（平衡 Precision 和 Recall）
- **辅助指标**: 平均 IoU（评价边界框质量）
- **阈值敏感性**: 测试不同 IoU 阈值（0.3, 0.5, 0.7）下的 F1 变化

### 5.3 计算资源管理
- 标注阶段无需 MATLAB，仅需图像查看器
- 每次评价需生成一个 attempt（约 5 分钟），参数网格搜索可并行（2 并发）
- 若需测试 15 个参数组合，预计 40-60 分钟

---

## 六、前期工作存档（仅供参考）

### 6.1 前期"最优"配置（未经 GT 验证）
```
能量档: 60%
POD rank: 859
connectivity: 4
alpha: 0.25
seed_alpha: 0.55
merge_gap: 12
VLSM 数: 225（108 帧）
检出率: 100%
```

**警告**: 该配置基于 VLSM 数量最大化，可能存在严重过检。

### 6.2 前期数据文件位置
- 完整报告: `docs/pod_energy_series_optimization_final_report_20260829.md`
- 统计汇总: `tmp/pod_energy_series_opt/final_summary.json`
- 能量曲线: `tmp/pod_energy_series_opt/final_energy_vlsm_curve.png`

### 6.3 前期工具脚本
- 汇总工具: `tools/r2_diagnostics/summarize_attempts.py`
- 能量谱提取: `tools/r2_diagnostics/pod_energy_spectrum.py`
- 曲线绘制: `tools/r2_diagnostics/plot_energy_vlsm_curve.py`

**这些工具仍可用于后续的统计汇总，但评价标准需改为基于 GT 的 F1。**

---

## 七、给下一个对话的提示词

```
任务：POD-VLSM 参数寻优 - 建立人工标注评价体系

背景：前一对话完成了基于聚类内部指标的初步寻优，但缺乏 Ground Truth 验证。
用户指出正确的评价标准是与图像识别结果对比（Precision/Recall/F1/IoU）。

当前状态：
1. POD 基已生成（20-80% 能量全覆盖）
2. 标注生成工具已就绪（generate_annotation_samples.m）
3. 评价脚本已就绪（evaluate_clustering_vs_annotation.py）
4. 前期 13 次 attempt 结果可作为对照组

下一步：
Phase 1 - 生成标注样本（60% 能量，36 帧）
Phase 2 - 人工标注 VLSM 边界框（人机协作）
Phase 3 - 评价前期配置的真实 F1
Phase 4 - 基于 GT 重新参数网格搜索

关键文件：
- 交接文档：docs/handoffs/pod_vlsm_annotation_based_optimization_handoff_20260829.md
- 标注工具：tools/r2_diagnostics/generate_annotation_samples.m
- 评价脚本：tools/r2_diagnostics/evaluate_clustering_vs_annotation.py
- POD 基：tmp/pod_energy_sweep/pod_energy_sweep_basis.mat

第一步行动：
执行 generate_annotation_samples.m，生成 36 张 60% 能量的脉动云图，
开始人工标注流程。
```

---

## 八、参考资料

### 8.1 项目文档
- 主 README: `README.md`
- VLSM 聚类方法说明: `docs/README_vlsm_cluster_method.md`
- POD 能量选择文献综述: `docs/pod_energy_selection_literature_review_20260828.md`

### 8.2 相关代码
- 结构识别主函数: `cases/per_case/tandem_baseline_r2/+tblR2/+vlsmpod/identify_frame.m`
- POD 去噪准备: `cases/per_case/tandem_baseline_r2/+tblR2/pod_denoise_prepare.m`
- POD 重构: `cases/per_case/tandem_baseline_r2/+tblR2/pod_denoise_reconstruct_frame.m`

### 8.3 评价指标参考
- **IoU**: Intersection over Union，目标检测标准指标
- **F1-score**: 2 × (Precision × Recall) / (Precision + Recall)
- **阈值**: IoU ≥ 0.5 通常认为匹配成功

---

**交接完成时间**: 2026-08-29 02:00  
**下一对话启动条件**: 用户确认理解当前状况，准备开始标注流程  
**紧急联系**: 若标注工具运行出错，检查 MATLAB 路径和 case 配置文件是否加载正确
