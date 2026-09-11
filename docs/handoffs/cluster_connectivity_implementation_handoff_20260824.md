# Handoff：+tblR2 聚类连通法改进 — 从调研落到正式实现

## Context（为什么要做这件事）

2026-08-24 完成了一轮"调研 + 诊断（不改正式逻辑）"任务，产出：

- `docs/cluster_connectivity_improvement_review.md` — 文献调研 + 诊断结论
- `docs/README_r2_structure_diagnostics.md` — 诊断工具说明
- `cases/per_case/tandem_baseline_r2/+tblR2/{load_sweep_frames,percolation_metrics,structure_geometry_metrics,percolation_sweep,sensitivity_sweep,bootstrap_stability,make_gaussian_spec,plot_percolation_diagnostics,plot_sensitivity_diagnostics}.m` — 诊断代码，9 个新文件
- `tools/run_r2_structure_diagnostics.m`、`tools/benchmark_single_frame_structure_identification.m`
- `cases/per_case/tandem_baseline_r2/output/mat/09d_percolation_sweep.mat`、`09d_sensitivity_sweep.mat`
- `docs/figures/09d_*.png` ×4

调研得到三个需要处理的发现，重要性从高到低：

1. **`cfg.structures.alpha=0.40` 没有落在逾渗转变区内**——补充宽扫描（α 到 3.0）显示，用真实生产平滑，最大簇占比谷值（转变标志）出现在 α≈0.85–1.0，比当前值高一倍以上；项目自己 2026-08-21 规划文档定的扫描范围 `0.25:0.05:0.65` 本身就扫不到转变。文献典型工作点 α≈1.4–2.2（Hwang & Sung 2018、Lozano-Durán 2012）。
2. **高斯预处理 `sigma` 存在实现缺陷，从未真正生效**——`simple_gaussian_filter2` 只读方向性字段（`sigma_x_cells`/`sigma_y_cells`/`radius_x_cells`/`radius_y_cells`），而 `structure_preprocessing()`（在 `structure_analysis_cache.m` 内）把这些字段预填为非空默认值 `0.8/1`，导致案例脚本设置的 `sigma_cells=1.5, radius_cells=4` 从未传导到卷积核。冲激响应实测确认：**实际生效是 σ=0.8/3×3 核，不是产物命名和 README 声称的 σ=1.5/9×9**。
3. **8 连通在当前阈值下运行在自身渗流临界点上**——实测占据率在 α=0.40 时约 0.39–0.43，卡在正方格点 8-连通渗流阈值 p_c≈0.4073 附近，而 4-连通阈值 p_c≈0.593 还很远。不是"8 连通更差"，而是当前阈值恰好选在 8 连通最敏感的工作点上。

**用户现在要开一个新会话，把这些发现落到"可行改进方案汇总"（`docs/cluster_connectivity_improvement_review.md` §5）里排第 1–5 优先级的项目上，从诊断走到正式实现。**

---

## 关键约束：新发现的合同冲突，必须先处理

`tests/test_r2_library_contract.m` 明确禁止把"标定/敏感性扫描类"模块放进 `+tblR2/`：

```matlab
excluded = {'conditional_structure_average', 'conditional_spatial_spectra', ...
    'benchmark_structure_tracking', 'threshold_calibration_scan'};
```

以及对 `structure_analysis_cache.m` 源码的 token 黑名单：`threshold_calibration`、`sensitivity_scan` 等。

**本轮新增的 9 个诊断文件目前没有触发这些字面检查（不同名字），但明显违反测试的精神**——它们就是"标定/敏感性扫描"模块，只是换了名字放进了同一个被保护的目录。当前测试仍能 PASS（已验证），是因为测试只按精确文件名匹配，不是因为这样做符合项目对"精简库"的既有约定。

**新会话必须先做的决定**（建议用 `/grill-me` 或 `AskUserQuestion` 跟用户对齐，不要自行假设）：

- 选项 A：把 9 个诊断文件移出 `+tblR2/`（例如移到 `tools/` 或新建 `cases/per_case/tandem_baseline_r2/+tblR2diag/`），保持 `+tblR2/` 的"精简库"定位不变；
- 选项 B：更新 `tests/test_r2_library_contract.m` 的 `excluded` 列表和 token 黑名单，明确把诊断工具排除在"禁止事项"之外（需要用户认可这是例外，而不是重新放开标定模块进正式库的口子）；
- 选项 C：诊断阶段的代码保留原地不动（毕竟已经产出了报告和数据），但**任何新的正式改进代码**（比如落实 §5 方案 1/2/4/5）一律不进 `+tblR2/`，走另外的路径。

这个决定会影响后续所有文件落点，必须在动手实现前敲定。

---

## 上一轮任务的方法论边界（供参考，新任务应重新走一遍 grill-me，不要直接照搬）

上一轮通过 `/grill-me` 逐条确认的边界（仅供背景参考，不代表新任务自动继承）：

- 痛点方向锁定为 **B（参数敏感性）+ C（预处理强度）**，**明确排除机器学习方案**（用户原话："机器学习的开销过大，目前难以负担"）。
- 检索域限定为**仅 PIV/湍流领域**；不限时间；含 arXiv、GitHub、MATLAB File Exchange。
- 扫描策略是"先粗后细"：Phase 1 逾渗主阈值（480 帧×9 α×2 连通性），Phase 2 正交/全网格预处理敏感性（120 帧×640 组合）。
- 诊断判据用复合判据：逾渗类（最大簇占比、稳定区宽度+bootstrap 重叠、结构数密度）+ 几何类（面积分布、长宽比、边界剔除率）。
- **诊断工具不改正式识别逻辑**——这是上一轮的核心边界，新任务性质变了（要落实改进），这条边界不再自动适用，需要用户重新确认新边界。

**新任务大概率需要重新走一遍类似的问答流程**，因为"落地实现"比"诊断"涉及更多决策：改哪个参数、改到什么程度、是否重算全部 12000 帧、是否影响下游产物、如何验证改进有效。

---

## 待实现的具体方案（来自调研报告 §5，按优先级）

| 优先级 | 方案 | 涉及文件 | 关键风险 |
|---|---|---|---|
| 1 | 修复 sigma 生效缺陷 | `+tblR2/simple_gaussian_filter2.m` 或 `structure_analysis_cache.m` 里的 `structure_preprocessing()` | 会改变全部 12000 帧的正式结构识别结果数值，`09_structure_analysis.mat` 及下游 Q2/Q4、条件平均、双工况比较全部要重算 |
| 2 | 用 α∈[0.5,2.5] 重新做 Phase 1 宽扫描，定位真转变区 | 复用已有诊断代码（若走选项 A/B，需先决定这些代码去哪） | 依赖优先级 1 先完成（sigma 修好后转变区位置还会再变一次） |
| 3 | 在转变区之后用 bootstrap 稳定区判据定位平台段、产出正式 alpha 推荐值 | 同上 | 需要用户对"推荐值"和"正式改 cfg"之间的关系表态——推荐完是否自动改 `tandem_baseline_r2_case.m` 里的 `cfg.structures.alpha` |
| 4 | 在新阈值下重新评估 4 vs 8 连通性 | 同上 | 纯诊断性质，风险较低 |
| 5 | seed_alpha 联合标定 | 同上 | 与优先级 2/3 耦合，建议合并成一次扫描 |
| 6（备选） | `imreconstruct` 替代自实现滞回逻辑 | `+tblR2/identify_structures.m` | 纯代码简化，数学等价性需先验证再替换 |
| 7（备选，范围更大） | POD 低阶重构去噪替代/补充高斯预处理 | 新增管线，超出"参数调优"范围 | 需要独立立项讨论，本次不建议直接纳入 |

**不建议的方向**（已在调研中排除，新会话不需要重新论证，除非用户主动提出）：机器学习、散度自由滤波（2D-2C 测量不满足零散度物理假设）、时域 Wiener 滤波（依赖未验证的"12000 帧是否时间分辨"前提）。

---

## 关键文件/路径速查

| 用途 | 路径 |
|---|---|
| 正式识别逻辑（本次调研未改动） | `cases/per_case/tandem_baseline_r2/+tblR2/identify_structures.m` |
| 预处理逻辑 + sigma 缺陷所在 | `cases/per_case/tandem_baseline_r2/+tblR2/preprocess_structure_velocity.m`、`simple_gaussian_filter2.m` |
| 缺陷根因（方向性字段预填非空默认值） | `structure_analysis_cache.m` 内的 `structure_preprocessing()` 函数 |
| 案例配置（`cfg.structures.*`） | `cases/per_case/tandem_baseline_r2/tandem_baseline_r2_case.m` 约第 144–182 行 |
| 库合同测试（本次发现的冲突点） | `tests/test_r2_library_contract.m` |
| 其他相关合同测试 | `tests/test_r2_baseline_control_contract.m`、`test_r2_cache_statistics_smoke.m`、`test_r2_compact_analysis_smoke.m`、`test_r2_offline_cache_reuse.m`、`test_r2_phase_smoke.m` |
| 本次调研报告 | `docs/cluster_connectivity_improvement_review.md`（全文，尤其 §0 执行摘要、§2 逾渗诊断数据、§4 sigma 缺陷、§5 方案汇总） |
| 诊断工具说明 | `docs/README_r2_structure_diagnostics.md` |
| 诊断产物（可复用，避免重跑） | `cases/per_case/tandem_baseline_r2/output/mat/09d_percolation_sweep.mat`、`09d_sensitivity_sweep.mat` |
| 单帧计时基准（89×640 网格实测） | 识别 0.060s/帧、高斯预处理 0.005s/帧（R2022b 实测，用于估算重算全量 12000 帧的成本） |
| 上一轮同类任务的边界记忆（POD/DMD/LCS，方法论可参考） | `C:\Users\Frank_7840HSw\.claude\projects\D--Users-Frank-7840HSw-Desktop-202605-------Current-Plate-Calculation/memory/pod-dmd-lcs-eval-scope-20260824.md` |
| r2 管线关键参数记忆 | `C:\Users\Frank_7840HSw\.claude\projects\D--Users-Frank-7840HSw-Desktop-202605-------Current-Plate-Calculation/memory/r2-modal-pipeline-facts.md`（fs=960Hz、12000 帧、`+tblR2` 同时被 `tandem_baseline_r2` 和 `tandem_f40a3_phi0_r2` 共用，改 `+tblR2` 会同时影响两个工况） |

---

## 重要背景事实（避免新会话重新踩坑）

1. **`+tblR2` 是被两个工况共用的库**：`tandem_f40a3_phi0_r2` 通过 `addpath` 引用 `tandem_baseline_r2` 的 `+tblR2`（`library_case_root = fullfile(fileparts(case_root), 'tandem_baseline_r2')`）。改 `identify_structures.m` 或 `preprocess_structure_velocity.m` 会同时影响两个工况的结果。
2. **MATLAB `+package` 目录本身不能加入 path，只能加其父目录**；`genpath` 会把 `+tblR2` 直接加入并报错，必须用普通 `addpath`。
3. **`run()` 会把 MATLAB 当前目录切到脚本所在文件夹**再执行——本次调研过程中因此踩过路径坑，写诊断脚本时如果用相对路径，务必在 `run()` 之前先捕获 `pwd`，或改用 `-batch` 内联字符串执行。
4. **MATLAB 标量索引的方向性陷阱**：`A(I)` 在 `A` 是向量时保持 `A` 自身方向，但 `A` 是标量时会退化成跟随 `I` 的形状——本次已在 `percolation_sweep.m`/`sensitivity_sweep.m` 里踩过并修复（用 `reshape(...,[],1)` 显式定向），任何新写的参数网格构造代码都要小心这一点。
5. **`09_structure_analysis.mat` 体积约 1.5 GB，序列缓存 `01_sequence_cache*.mat` 各约 4.5 GB**——任何要求"重算全部 12000 帧"的改动都有实质的时间和磁盘成本，新会话开工前应该先用现有单帧计时基准（§见上表）估算总耗时，别盲目跑。
6. **诊断阶段发现的转变区位置（α≈0.85–1.0）是在 sigma 缺陷仍然存在（σ=0.8）或用手动构造的"意图配置"（σ=1.5）两种条件下测的**，一旦正式修复 sigma 缺陷、改变生产管线的实际平滑强度，转变区位置需要重新扫一次，不能直接套用调研报告里的数字作为最终结论。

---

## 建议新会话的第一步

1. 用 `/grill-me` 或分步 `AskUserQuestion` 与用户对齐："本轮任务边界"（交付物形式、是否走 A/B/C 处理合同冲突、是否允许重算全部 12000 帧、改动后是否需要重新生成下游产物如 Q2/Q4/条件平均/双工况比较）。
2. 读 `docs/cluster_connectivity_improvement_review.md` 全文和 `docs/README_r2_structure_diagnostics.md`，确认理解调研结论。
3. 决定合同冲突的处理方式（选项 A/B/C），若选 A 或 B 需要先执行文件迁移/测试更新，再动手做正式改进。
4. 按敲定的优先级顺序实现，每一步验证：先跑 `tests/test_r2_library_contract.m` 等既有合同测试确认不破坏约定，再用真实数据小样本验证改动的实际效果（可参考上一轮 POD/DMD/LCS 任务里"1200 帧真实数据小缓存"的验证模式）。
