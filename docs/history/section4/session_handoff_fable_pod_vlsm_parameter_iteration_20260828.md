# Fable 接管提示词：POD-VLSM 聚类联通法参数迭代

你正在接管一个正在进行的 agent 会话。请从下方状态继续，不要从头重做已经验证的工作，也不要仅凭旧摘要重新推翻已经确定的口径。若本提示词与当前工作区文件或新近验证证据冲突，以当前工作区证据为准，并明确说明冲突。你是后续工作的主协调模型 Fable；涉及图像视觉识别时，必须继续调用指定的 `gpt-5.6-sol` 子代理，不能用 Fable 自身视觉结果替代用户规定的审核模型。

【工作目录】

- Windows 工作区：`D:\Users\Frank_7840HSw\Desktop\202605实验快反计算\Current_Plate_Calculation`
- Git 分支：`2026-08-22`
- MATLAB：R2022b，已验证可执行文件在 `D:/Academic/Software/MATLAB/R2022b/bin/matlab.exe`
- 当前工作树非常脏，并包含大量用户已有修改和未跟踪文件。不要 `reset`、`checkout`、清理、提交或覆盖无关改动；用户没有要求 commit。
- 【任务森林状态】当前未发现 `.agent-workbench/task-forest/exports/`，因此没有 task-forest 状态可继承。

【用户目标】

[verified] 针对 POD 低阶重构流场，继续迭代 VLSM 聚类联通法参数，使聚类结果与 Codex `gpt-5.6-sol` 对纯 POD 脉动流场图的视觉估计在以下对象级属性上大体一致：

1. VLSM 正负号；
2. 流向和法向位置；
3. 可见流向长度/尺寸；
4. 是否触及 FOV 边缘，以及触边结构的可见部分。

[verified] 最终验收必须是随机 36 帧 × 3 轮，每轮帧序列可以不同；三轮都保持高一致性才算通过。不能把“计数接近”当作一致，也不能把 GPT 视觉估计称为三维物理真值。

[verified] 参数迭代的全过程图像和描述必须保存在本地，包括纯 POD 流场图、聚类叠加图、`gpt-5.6-sol` 视觉对象结果、对象匹配、轮次评分、参数调整理由和最终报告，便于用户随时调出查看。

【必须遵守的要求】

- [verified] 全程使用中文与用户交流；POD、VLSM、FOV、GPT、IoU 等术语可保留英文。
- [verified] 所有瞬时脉动流场图必须使用 `contourf`，禁止改成 `pcolor`、`scatter` 或散点式渲染。
- [verified] POD 图的 colorbar 必须使用固定、可调的对称绝对范围，当前默认 `±3.0 m/s`；纯场图和聚类叠加图必须完全一致。
- [verified] 仅设置 `caxis([-3,3])` 不足以解决白色超量程区：MATLAB `contourf` 会把超出最外层 level 的数值留成未填充白色。当前最终代码已通过给 levels 追加实际有限极值的方式解决；必须保留此“overflow-safe contour levels”逻辑，让超量程值饱和为蓝/红端色，而不是重新变白。
- [verified] POD 方案不做边缘排除：`trusted_domain.streamwise_edge_columns=0`、`wall_normal_top_rows=0`、`reject_trusted_boundary_touching=false`；FOV 边缘结构按可见部分识别和评分。
- [verified] 图像审核强制使用 `gpt-5.6-sol` 子代理。Fable 负责组织计算、读写产物和参数决策，但不得用自身图像判断冒充规定模型。
- [verified] MATLAB R2022b 尽量一次只运行一个批处理实例，避免内存争抢和结果互相污染。
- [verified] 不修改 `cases/per_case/tandem_baseline_r2/tandem_baseline_r2_case.m`，不改 Gaussian/Raw 分支及上游数值核心；当前任务只改诊断/验收工具和 POD 局部参数副本。
- [verified] 结论只能表述为“2C-2D XOY 平面连通结构的操作性比较”，不能称为三维物理真值或人工真值。
- [verified] POD 条件固定为累计能量目标 50%，当前 rank=382，实际累计能量 `0.500237469280837`。除非用户另行要求，不要重新论证或改变这个 POD 选型。
- [verified] `min_vlsm_delta=3` 是当前操作性 VLSM 长度定义，不应为了提高分数而随意放宽；优先优化连通、生长、断裂合并与拓扑参数。
- [verified] 验收阈值在评分脚本中已经固定，除非用户明确授权，不要为了让结果“通过”而降低阈值。

【已确认的当前候选参数】

```text
alpha=0.40
seed_alpha=0.60
connectivity=8
min_pixels=3
min_lsm_delta=1
min_vlsm_delta=3
max_wall_normal_delta=Inf
max_internal_hole_pixels=64
envelope_closing_radius_cells=2
max_aspect_ratio=Inf
reject_trusted_boundary_touching=false
min_abs_fluctuation=0
min_abs_seed_fluctuation=0
merge_gap_cells=0
merge_require_y_overlap=true
trusted_domain.streamwise_edge_columns=0
trusted_domain.wall_normal_top_rows=0
```

[verified] 这些参数是局部 POD 验收副本，不应从可能陈旧的 `cfg.structures` 继承关键值。尤其要显式钉住 `min_abs_fluctuation=0`、`min_abs_seed_fluctuation=0` 和 `merge_gap_cells=0`，因为旧工况缓存曾含 `1`、`1`、`40`，造成过一次无效验收。

【对象级验收阈值】

评分脚本 `tools/r2_diagnostics/score_pod_vlsm_parameter_acceptance.py` 当前固定：

```text
object_f1 >= 0.80
sign_accuracy >= 0.90
streamwise_iou_median >= 0.65
length_relative_error_median <= 0.20
position_match_rate >= 0.85
edge_object_f1 >= 0.80
complete_36_frame_review == true
```

[verified] 三轮必须全部满足才返回 `accepted`；只要任一轮失败，就返回 `adjustment_required`。匹配不是按计数，而是对同号对象的流向区间 IoU、二维包围盒、长度误差、质心位置和边缘属性做最大权匹配。

【已完成】（工具文件与验证）

- `tools/r2_diagnostics/run_pod_vlsm_parameter_acceptance.m`
  - 生成三轮随机 36 帧；每帧输出 `pure_frames` 和 `cluster_frames`；保存聚类对象 JSON、视觉上下文 JSON、MAT、总 manifest。
  - 已新增 `colorbar_abs_limit`，默认 `3.0`。
  - 已把色标写入每帧 `clim_abs_m_per_s`、每轮 `colorbar_abs_limit_m_per_s` 和总 manifest。
  - 已新增 `contour_levels_with_overflow`：levels 以 `[-3,3]` 为主体，同时追加该帧真实有限最小值/最大值，`caxis` 仍保持 `[-3,3]`，因此超量程值会端色饱和而非留白。
  - 小问题：[verified] 当前 `colorbar_abs_limit` validator 尚未显式加 `isnumeric(x)`；正常数值调用无碍，但下一模型可做最小修补，避免字符 `'3'` 被转为 ASCII 51。
- `tools/r2_diagnostics/run_pod_vlsm_parameter_optimization.m`
  - 旧的 24 帧迭代入口。
  - 已同步新增固定可调 `colorbar_abs_limit=3.0`、overflow-safe levels，并在结果里记录 `colorbar_abs_limit_m_per_s`。
  - 该修改已静态检查，但尚未在修改后重新完整运行。
- `tools/r2_diagnostics/run_vlsm_gaussian_pod_comparison.m`
  - 已把旧的 `clim_sigma × median(u_rms)` 机制改为固定 `colorbar_abs_limit=3.0`，并加入 overflow-safe levels 和报告字段。
  - [unverified] 此修改只做过静态检查，尚未做 MATLAB 冒烟运行；它不是当前 POD 参数验收的首要阻塞，不要先为它分散精力。
- `tools/r2_diagnostics/run_pod_vlsm_codex_subagent_review.py`
  - 将每轮 36 张纯场图按 6 张一批，调用隔离的官方 `gpt-5.6-sol` 子代理。
  - 命令使用 `codex exec --ignore-user-config --ephemeral -m gpt-5.6-sol -s read-only`，并由 JSON schema 限定输出。
  - 已修复一个重要 CLI 参数顺序问题：位置 prompt 必须紧跟 `codex exec`，放在变长 `-i/--image` 参数之前；否则 `-i` 会吞掉 prompt，日志只会出现 `No prompt provided via stdin.`。不要回退此修复。
- `tools/r2_diagnostics/codex_vlsm_review_schema.json`
  - 强制模型声明为 `gpt-5.6-sol`，每帧输出正负、x/y 范围、长度、触边状态、置信度与说明。
- `tools/r2_diagnostics/score_pod_vlsm_parameter_acceptance.py`
  - 生成每轮 `round_XX_matches.json`、`round_XX_comparison.md`，以及总 `acceptance_summary.json`、`parameter_adjustment_recommendation.json`、`acceptance_report.md`。
- `tools/r2_diagnostics/run_pod_vlsm_visual_review.py`
  - 另一条视觉审核实现，当前最终批次实际使用的是 `run_pod_vlsm_codex_subagent_review.py`。

【静态验证状态】

- [verified] `python tests/matlab_check.py tools/r2_diagnostics` 通过，20 个 `.m` 文件无结构问题。
- [verified] 三个 Python 脚本通过 `python -m py_compile`。
- [verified] `git diff --check` 没有由本轮文件引入的空白错误；只出现工作区其他旧文件的 LF/CRLF 提示。
- [verified] MATLAB `checkcode` 可解析修改后的 acceptance/optimization 脚本；仅有 `caxis` 建议换 `clim` 和循环内 axes 的性能提示，不是运行错误。项目使用 R2022b，保留 `caxis` 可以兼容现有代码。

【迭代与验收历史】

1. `attempt_01`
   - [verified] 无效，不可作为验收依据。
   - 原因是错误继承了旧 `min_abs_fluctuation=1` 和 `merge_gap_cells=40` 等陈旧配置。
   - 保留产物用于审计，但不要继续引用其参数结论。

2. `attempt_02`
   - [verified] 首个使用完整固定候选参数的 36×3 批次，但仍采用过小/自适应旧色标。
   - 三轮聚类 VLSM 数：30、34、31。
   - 三轮对象 F1：`0.4571 / 0.4655 / 0.4561`。
   - 正负和匹配对象的长度/流向 IoU总体较好，主要失败是视觉对象明显多于聚类对象，召回和边缘 F1 很低。
   - 用户随后指出 colorbar 过小、超量程白色，故该视觉结果不能作为最终色标下的验收。

3. `attempt_03`
   - [verified] 候选参数仍为 `seed_alpha=0.60`，色标固定为 ±3。
   - 三轮 F1：`0.6087 / 0.6237 / 0.5647`；比 attempt_02 改善。
   - 但当时 levels 仍只覆盖 `[-3,3]`，尚未加入真实极值外层 level；真正超出 ±3 的区域仍可能因 `contourf` 机制留白。因此该批次不代表最终 overflow-safe 绘图。

4. `attempt_04`
   - [verified] `seed_alpha=0.55`，三轮使用另一组随机帧。
   - 三轮 F1：`0.5684 / 0.7111 / 0.5510`，仍未通过。
   - 因帧集不同，不能把单轮 0.711 简单归因于参数改善。

5. `attempt_05`
   - [verified] `seed_alpha=0.50`，通过种子校准复用 attempt_03 的三轮帧号。
   - 三轮 F1：`0.5532 / 0.6067 / 0.4783`，比 `seed_alpha=0.60` 的 attempt_03 更差。
   - 结论：不能继续机械降低 `seed_alpha`。当前评分脚本生成的自动建议在“召回低”时总会再降 0.05，这个规则过于简单，后续必须看具体漏检形态再决定。
   - 同一纯图由 GPT 重审时对象总数也会有轻微随机波动，所以参数隔离比较应尽量固定并复用同一批视觉标签。

6. `attempt_06` —— 当前精确断点
   - 目录：`tmp/pod_vlsm_parameter_acceptance_36x3/attempt_06`
   - [verified] 使用原候选 `alpha=0.40, seed_alpha=0.60`，固定 colorbar ±3，并首次真正采用 overflow-safe contour levels。
   - [verified] 通过随机种子校准与 attempt_03/attempt_05 使用完全相同的三轮帧号，便于隔离绘图和参数影响。
   - [verified] 每轮均有 36 张纯场图和 36 张聚类叠加图，共 108+108 张。
   - [verified] 聚类 VLSM 总数：Round 1=34、Round 2=35、Round 3=31。
   - [verified] 三轮 `gpt-5.6-sol` 视觉审核已经全部完成，均为 36/36 帧、0 failure：
     - Round 1：34/36 帧含视觉 VLSM，共 51 个对象，平均置信度 0.7897；
     - Round 2：35/36 帧含视觉 VLSM，共 64 个对象，平均置信度 0.8092；
     - Round 3：33/36 帧含视觉 VLSM，共 58 个对象，平均置信度 0.8136。
   - [verified] 每轮已有 `round_XX_visual_review.json` 和 `subagent_gpt56sol_audit.json`。
   - 【未完成 / 待验证】[verified] 当前还没有运行对象级评分，因此缺少：
     - `attempt_06/acceptance_summary.json`
     - `attempt_06/parameter_adjustment_recommendation.json`
     - `attempt_06/acceptance_report.md`
     - 各轮 `round_XX_matches.json` 和 `round_XX_comparison.md`
   - [verified] `manifest.json` 仍写 `awaiting_gpt_5_6_sol_visual_review`，这是生成阶段状态未被后续审核/评分自动回写，不代表审核没完成。评分完成后应以 `acceptance_summary.json` 为当前权威结论，并考虑补上 manifest 状态同步。

【下一步】（当前最优先）

不要重新生成 attempt_06，也不要重新做已经完成的 108 帧视觉审核。第一步直接运行对象级评分：

```bash
python tools/r2_diagnostics/score_pod_vlsm_parameter_acceptance.py \
  --attempt-dir tmp/pod_vlsm_parameter_acceptance_36x3/attempt_06
```

注意：若未通过，脚本按设计可能以退出码 3 结束，这不是脚本崩溃；要读取它生成的 JSON/Markdown。评分后重点查看：

```text
tmp/pod_vlsm_parameter_acceptance_36x3/attempt_06/acceptance_summary.json
tmp/pod_vlsm_parameter_acceptance_36x3/attempt_06/acceptance_report.md
tmp/pod_vlsm_parameter_acceptance_36x3/attempt_06/round_01/round_01_matches.json
tmp/pod_vlsm_parameter_acceptance_36x3/attempt_06/round_02/round_02_matches.json
tmp/pod_vlsm_parameter_acceptance_36x3/attempt_06/round_03/round_03_matches.json
```

【若 attempt_06 未通过：参数诊断原则】

[verified] 之前的主要失败模式是聚类召回低、边缘 F1 低，但不能只根据“视觉对象数更多”就继续降 `seed_alpha`；attempt_05 已经否证这种机械策略。

先从每个 unmatched vision object 和 unmatched cluster object 的具体图形形态分类：

1. 若视觉认为是一条同号长带，但聚类把它切成若干短的同号片段，且片段在 y 上有重叠：优先小步测试 `merge_gap_cells`，保持 `merge_require_y_overlap=true`。建议从很小的 `[2,4,6,8]` cells 开始，不要直接恢复旧的 20 或 40。
2. 若主体连续但阈值生长边界过短，导致 `LengthX_over_delta` 刚好达不到 3：小步测试 `alpha`（例如 0.35 与 0.40），同时保持 seed 参数不变，先隔离 growth threshold 的作用。
3. 若明显主体完全没有 seed：才考虑调整 `seed_alpha`；已有证据表明 0.55/0.50 不是稳定改善方向，因此不要默认继续降低。
4. 若同号结构主要被内部小孔或一两格断裂切开：测试 `envelope_closing_radius_cells`（如 2→3）或 `max_internal_hole_pixels`，每次只改一个机制。
5. 若主要失败集中在 FOV 边缘：先检查 cluster 的 `touches_fov_edge` 几何判定与 vision 的 2% FOV 容差是否语义一致，不要误用 `TouchesTrustedBoundary`；trusted boundary 缓冲为 0 时，这两个概念不等价。
6. 不要为了提高召回而修改 `min_vlsm_delta=3`；那会改变 VLSM 定义，而不是改进连通法。
7. 每次只改变一个主参数或一个明确配对机制，记录旧值、新值、假设、对象级结果和失败帧，避免多参数同时变化后无法解释。

【控制变量与视觉标签复用】

[inferred] 纯 POD 场只由 POD rank/energy 和帧号决定，不由聚类参数决定。因此在同一帧号、同一固定 ±3 overflow-safe 绘图下，调整聚类参数时纯场图不变，attempt_06 的 `gpt-5.6-sol` 视觉对象可作为固定参考标签复用。这样能避免同一模型重复审核时的随机波动污染参数比较。

推荐先做“校准阶段”和“最终验收阶段”分离：

- 校准阶段：固定 attempt_06 的 108 帧和视觉标签，只重算不同参数的 cluster objects 与对象评分；筛出候选，不必每个候选都重新花费 108 帧视觉审核。
- 最终验收阶段：参数确定后，再用新的独立随机 36×3 帧集生成纯图，并调用 `gpt-5.6-sol` 全量盲审；只有三轮都通过才验收。固定校准集通过不能代替用户要求的随机三轮最终验收。

当前 acceptance 脚本按以下公式生成轮次种子：

```text
round_seed = random_seed + 1000 * (attempt_id - 1) + round_index - 1
```

attempt_06 的有效 Round 1 基准种子为 `20262828`。若临时用 attempt_07 复用同一帧集，应设置：

```text
attempt_id=7
random_seed=20256828
```

这样 `20256828 + 1000*(7-1) = 20262828`。不过长期更稳妥的做法是给 `run_pod_vlsm_parameter_acceptance.m` 增加显式的 `frame_ids_by_round` 或固定帧文件参数，避免继续靠 seed 算术维持同帧；这是建议，不是已实现功能。

复用视觉标签前必须程序化核对三轮 `frame_ids` 完全相同，并确认 `energy_target`、rank、FOV、colorbar 和 overflow-safe 绘图实现未变。若纯图发生任何变化，则必须重新调用 `gpt-5.6-sol`。

【最终验收循环建议】

1. 对 attempt_06 评分，确定失败指标及对象级形态。
2. 在 attempt_06 固定帧/固定视觉标签上做小步单变量候选测试。
3. 对候选比较平均 F1、三轮最差 F1、边缘 F1、位置匹配率、精确率/召回率，不要只看均值；优先选择三轮稳定而非单轮峰值高的参数。
4. 若校准结果没有明确改善，停止盲目降低阈值，转向连接断裂/合并拓扑机制。
5. 选定候选后，用新随机种子创建新的独立 `attempt_XX`，三轮各 36 帧。
6. 用现有 `run_pod_vlsm_codex_subagent_review.py` 对每轮做 `gpt-5.6-sol` 审核。
7. 运行评分脚本。若三轮全 pass，保存报告并把参数称为“在当前 2C-2D XOY POD 操作性基准下通过”；若未通过，继续小步迭代。
8. 达到用户此前规定的最大 16 次参数循环仍未通过时，停止并报告最佳参数、稳定性区间、主要不可消除差异和全部本地产物，不得伪造通过。

【常用命令】

生成一个新 36×3 attempt（示例；一次只开一个 MATLAB）：

```bash
matlab -batch "cd('D:/Users/Frank_7840HSw/Desktop/202605实验快反计算/Current_Plate_Calculation'); addpath('D:/Users/Frank_7840HSw/Desktop/202605实验快反计算/Current_Plate_Calculation/tools/r2_diagnostics'); ov=struct('seed_alpha',0.60); result=run_pod_vlsm_parameter_acceptance('attempt_id',7,'random_seed',20256828,'colorbar_abs_limit',3.0,'parameter_overrides',ov); save('tmp/pod_vlsm_parameter_acceptance_36x3/attempt_07/generation_return.mat','result','-v7.3');"
```

对某轮做规定模型审核：

```bash
python tools/r2_diagnostics/run_pod_vlsm_codex_subagent_review.py \
  --attempt-dir tmp/pod_vlsm_parameter_acceptance_36x3/attempt_07 \
  --round 1 --batch-size 6 --max-workers 3 --retries 2 --force
```

三轮审核完成后评分：

```bash
python tools/r2_diagnostics/score_pod_vlsm_parameter_acceptance.py \
  --attempt-dir tmp/pod_vlsm_parameter_acceptance_36x3/attempt_07
```

静态检查：

```bash
python tests/matlab_check.py tools/r2_diagnostics
python -m py_compile \
  tools/r2_diagnostics/run_pod_vlsm_visual_review.py \
  tools/r2_diagnostics/run_pod_vlsm_codex_subagent_review.py \
  tools/r2_diagnostics/score_pod_vlsm_parameter_acceptance.py
git diff --check
```

【关键本地产物】

- 当前最终图形修复批次：`tmp/pod_vlsm_parameter_acceptance_36x3/attempt_06/`
- 当前 manifest：`tmp/pod_vlsm_parameter_acceptance_36x3/attempt_06/manifest.json`
- MATLAB 生成日志：`tmp/pod_vlsm_parameter_acceptance_36x3/attempt_06_matlab_generation.log`
- GPT 审核日志：`tmp/pod_vlsm_parameter_acceptance_36x3/attempt_06_codex_review.log`
- 每轮纯图：`attempt_06/round_XX/pure_frames/frame_*.png`
- 每轮聚类图：`attempt_06/round_XX/cluster_frames/frame_*.png`
- 每轮视觉结果：`attempt_06/round_XX/round_XX_visual_review.json`
- 每轮模型审计副本：`attempt_06/round_XX/subagent_gpt56sol_audit.json`
- POD 基底：`tmp/pod_energy_sweep/pod_energy_sweep_basis.mat`
- 评分输出（运行后出现）：`attempt_06/acceptance_summary.json`、`acceptance_report.md`、`parameter_adjustment_recommendation.json`

【不要重复 / 不要做】

- 不要重跑 attempt_06 的 MATLAB 生成和 108 帧视觉审核；这些已经完成。当前只差评分。
- 不要使用 attempt_01 作为证据。
- 不要把 attempt_02 的旧色标审核当作最终视觉基准。
- 不要把 attempt_03–05 当作 overflow-safe 最终图，因为它们生成时还没有外层 extrema levels 修复。
- 不要继续机械执行评分器“降低 seed_alpha 0.05”的建议；attempt_05 已表明这可能恶化结果。
- 不要只比较 VLSM 计数；必须查看同号、位置、长度、IoU、边缘和 unmatched objects。
- 不要同时改 alpha、seed、closing、merge 等多个机制。
- 不要直接用大 `merge_gap_cells=20/40`；先从小间隙开始并要求 y 重叠。
- 不要删除或覆盖旧 attempt；每轮新建独立目录，保留完整审计链。
- 不要把 FOV 触边结构过滤掉。
- 不要把 GPT 视觉称为物理真值。
- 不要改 `tandem_baseline_r2_case.m` 或上游数值核心。
- 不要碰工作树里的无关用户修改，也不要提交。

【接管后的第一条回复】

先向用户简洁说明：已经读取接管状态，`attempt_06` 的 108 帧 `gpt-5.6-sol` 审核完整，当前从对象级评分继续；随后直接运行评分，不要重新询问已经明确的参数、色标或边缘口径。

【接管后的前五步】

1. 运行 `score_pod_vlsm_parameter_acceptance.py --attempt-dir .../attempt_06`。
2. 汇总三轮 F1、precision/recall、sign、x-IoU、length error、position、edge F1，并定位 unmatched vision/cluster 对象最集中的帧。
3. 根据漏检形态判断是 seed、growth、断裂合并、孔洞闭合还是边缘语义问题，不接受自动降 seed 的单一结论。
4. 在固定 attempt_06 帧集和视觉标签上设计一次单变量、小范围参数测试；把候选过程图、匹配 JSON 和说明写入新目录。
5. 选出稳定候选后，再进行新的随机 36×3 最终验收；三轮全通过才向用户报告验收成功。
