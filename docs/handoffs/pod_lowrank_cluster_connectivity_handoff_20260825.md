你正在接手一个尚未完成的 MATLAB/PIV 科研代码任务。请从下面状态继续；不要因旧 session 中的模型表述而跳过当前文件核验。如果本 handoff 与工作区当前证据冲突，以当前文件和实测结果为准，并明确说明冲突。

【工作目录】

`D:\Users\Frank_7840HSw\Desktop\202605实验快反计算\Current_Plate_Calculation`

当前分支：`2026-08-22`。工作树很脏，整个 `cases/per_case/tandem_baseline_r2/`、相关测试、工具和文档仍是 untracked；不要 `git clean`、`git reset --hard`、整体覆盖或删除现有输出。Claude Code 原 session 为：
`C:\Users\Frank_7840HSw\.claude\projects\D--Users-Frank-7840HSw-Desktop-202605-------Current-Plate-Calculation\83350ab6-0eff-4c8a-92b7-37579426c78b.jsonl`。

【用户目标】

继续推进“使用 POD 低阶重构作为 2C-2D PIV 瞬时场前处理，再用聚类联通法识别平面 LSM/VLSM”。需要比较 POD 与现有 Gaussian 预处理，确定可辩护的 rank/累计能量选择，完成真实数据验证与人工审核，最后决定是否进入正式 r2 Section 10 管线。

【必须遵守的要求】

- [已验证] 只作 2C-2D XOY 平面速度簇、平面连通和表观长度结论；不得外推三维体积、三维连通或能量传递。
- [已验证] 原 `tandem_baseline_r2_case.m` 不应被实验入口直接改写；新能力保持独立入口或明确 cfg 开关。
- [已验证] POD 与 Gaussian 必须使用同一 PostProc 数据源、同一帧、同一空间域、同一 `u_rms` 和同一结构阈值才能比较；参数或数据源不一致的结果不得并表。
- [已验证] 不静默降低为 `[2 2]`、减少帧数、插值回填或 single 近似来冒充全分辨率正式结果。若改变科研合同，须先获用户确认。
- [已验证] `+tblR2` 同时被 baseline r2 与 f40a3-phi0 r2 共用；修改库函数会影响两个工况。
- [已验证] MATLAB R2022b 测试必须串行，一次只启动一个 `matlab -batch`。

【已确认事实与决策】

- [已验证] 当前存在两套不能混称为同一验收状态的实现：
  1. **Claude session 实验链**：`pod_denoise_prepare` → `pod_denoise_reconstruct_frame` → `run_structure_pod_denoise` / `run_pod_energy_sweep` / `run_pod_sweep_visual_audit`。它已经在 PostProc 数据上完成 24 帧、E20–E80 扫描和 192 张审核图。
  2. **正式 Section 10 扩展链**：`tandem_baseline_r2_pod_cluster_case.m` → `pod_cluster_analysis`，设计为 Raw/Gaussian/ELF-POD/E80/E90/E95 全帧比较；当前没有真实 `13_pod_cluster_analysis.mat`，且会被内存闸门阻止。
- [已验证] 实验基底来自 `01_sequence_cache_postproc.mat`，全 12000 帧，网格 `89×640`，`accepted_mask` 有效点 54,425，联合自由度 108,850；最大基底为 E80、rank=2811，文件约 2.62 GB。
- [已验证] 实验 POD 先从物理 U/V 减全局时间均值；识别时再减 repeat-specific 均值。代码注释称均值差很小，但该量级未在本轮重新实测。
- [已验证] 实验 POD 分解使用 `accepted_mask` 建基底，识别阶段才施加 trusted-domain；正式 Section 10 则先把 trusted-domain 纳入 POD 掩膜（52,288 点）。两套 POD 空间合同不同，rank 和模态不可直接互换。
- [已验证] Gavish–Donoho 在合成“低秩信号+白噪声”测试中正确恢复植入秩，但真实湍流数据没有清晰低秩/白噪声分界；当前实际扫描采用累计能量，不应继续把默认 GD 输出直接称为可靠去噪 rank。
- [已验证] 当前 PostProc 24 帧扫描使用 r1 结构参数 `alpha=0.40`、`seed_alpha=0.70`、`connectivity=8`，且 `min_abs_fluctuation=0`、无流向合并。它不是当前 r2 源码参数。
- [已验证] 参数存在三重冲突：
  - 当前 `tandem_baseline_r2_case.m`：`alpha=1.0`、`seed=1.2`、4 连通、`merge_gap_cells=40`、`min_abs_fluctuation=1.0`；
  - `00_case_configuration.mat`：`alpha=1.77`、`seed=1.97`、4 连通，无 merge/min_abs 字段；
  - `09_structure_analysis.mat`：同样是 `1.77/1.97/4`，Gaussian `sigma=1.5/radius=4`。
- [已验证] 原 r2 脚本设置 `cfg.stages.structures='reuse'`，而 `load_result` 只检查 case/stage/帧数/网格/fs，不检查 alpha、seed、merge 或预处理。若直接运行正式扩展，Gaussian 会复用旧 `1.77/1.97` 结果，而 Raw/POD 使用当前 `1.0/1.2/merge=40`，比较不成立。
- [已验证] 24 帧扫描为 `[1,501,...,11501]`；只是系统抽样小样本，不足以确定最终能量档，也可能受时间/周期采样结构影响。
- [推断] E50 是当前数值上的“折中候选”，不是已验收最优值：它兼顾 LSM 数量、VLSM、长度上尾和碎片数；E70 的平均 VLSM 更高，但长度上尾明显变差。

【任务森林状态】

未发现 `.agent-workbench/task-forest/exports/`，本 handoff 不依赖 task-forest。

【已完成】

- [已验证] 核心实验模块已存在：
  - `+tblR2/pod_denoise_prepare.m`：全帧 snapshot POD、GD/累计能量选 rank、basis cache。
  - `+tblR2/pod_denoise_reconstruct_frame.m`：按绝对帧号和 mode subset 重构单帧 U/V。
  - `run_structure_pod_denoise.m`：POD/Gaussian 独立入口，可覆盖已存在的结构字段。
  - `tools/r2_diagnostics/run_pod_energy_sweep.m`：一次分解，多能量档前缀切片。
  - `run_pod_sweep_visual_audit.m`：LSM 蓝色虚线框、VLSM 红色实线框。
  - `run_pod_lowrank_structure_diagnostic.m`：fixed-rank / energy-fraction 路径 B；但依赖当前不存在的正式 basis 文件。
- [已验证] 独立内存友好模块已存在：`+pod/snapshot_decomposition_memory_friendly.m` 与 `pod_denoise_prepare_memory_friendly.m`；三次空间分块扫描、保留完整 `N×N` eig，不驻留完整 `D×N` 快照矩阵。它尚未接入正式 cluster/ELF 链。
- [已验证] 正式扩展模块已存在：`pod_cluster_analysis`、`elf_mode_selection`、`select_energy_modes`、`cluster_raw_sequence`、`cluster_pod_reconstruction`、`gaussian_pod_sequence`、`pod_cluster_memory_preflight` 等。
- [已验证] 本轮 MATLAB R2022b 实跑通过：`test_r2_pod_denoise`、`test_r2_pod_memory_friendly`、`test_r2_pod_cluster_analysis`、`test_r2_library_contract`。17 个相关 `.m` 文件也通过 `tests/matlab_check.py`。这些只证明合成/合同与静态结构，不证明真实全帧科学有效性。
- [已验证] `tmp/pod_energy_sweep/` 现有 195 个文件、约 2.65 GB；包括基底、结果、谱图及 8×24=192 张 PNG。已抽查谱图及 frame 1 的 Gaussian/E50 图，尚未完成全量人工视觉验收。
- [已验证] 当前扫描数值（Gaussian、E20…E80）：rank=`[-,11,39,134,382,859,1621,2811]`；平均每帧结构=`[41.46,1.21,3.25,6.46,11.50,26.08,57.04,90.50]`；平均 VLSM=`[0.50,0.17,0.375,0.333,0.708,0.708,0.75,0.333]`；`Lx/delta` P90=`[0.938,3.490,3.234,2.591,2.287,1.444,0.701,0.438]`。

【未完成 / 待验证】

- [未验证] 192 张图尚未由用户逐帧确认“新增长结构是真实恢复而非低阶场虚连/过度合并”。
- [未验证] 尚无 100–1200 帧以上的分层抽样、repeat 分层、bootstrap 置信区间或能量档稳定性验证；E50 不能定为最终参数。
- [未验证] `run_pod_lowrank_structure_diagnostic` 需要的 `output/mat/09_structure_pod_denoise_basis.mat` 不存在；当前可用 basis 在 `tmp/pod_energy_sweep/`，接口尚未统一。
- [未验证] 正式 `13_pod_cluster_analysis.mat` 不存在。实时预检：52,288 点、D=104,576、N=12,000、峰值 47.611 GiB，当前可用/最大数组约 11.532 GiB，`sufficient=0`。
- [未验证] 内存友好实现没有接入正式 E80/E90/E95；ELF 仍要求全部空间模态做 entropy，尚无流式 ELF 方案。
- [未验证] `pod_eigenvalue_spectrum.png` 当前存在，但仓库 `.m` 中找不到生成它的可追溯脚本；需要补可复现绘图入口。
- [未验证] `run_pod_energy_sweep.m` 头部仍写 raw 旧结果“E80 rank=4737”，与 PostProc 当前 rank=2811 冲突，应在获准改代码时修正文档注释。
- [未验证] 输出目录有 3 个 `tp*.mat` 临时文件（最大约 2.81 GB），来源和可恢复性未审计；不要擅自删除。

【关键文件 / 命令 / 产物】

- 科研合同：`docs/POD_reconstruction_cluster_connectivity_extension.md`
- 本 handoff：`docs/handoffs/pod_lowrank_cluster_connectivity_handoff_20260825.md`
- PostProc 缓存：`cases/per_case/tandem_baseline_r2/output/mat/01_sequence_cache_postproc.mat`
- 实验结果：`tmp/pod_energy_sweep/pod_energy_sweep_result.mat`
- 实验基底：`tmp/pod_energy_sweep/pod_energy_sweep_basis.mat`
- 谱图：`tmp/pod_energy_sweep/pod_eigenvalue_spectrum.png`
- 审核图：`tmp/pod_energy_sweep/figures/{gaussian,E20,...,E80}/frame_*.png`
- 正式目标产物：`cases/per_case/tandem_baseline_r2/output/mat/13_pod_cluster_analysis.mat`（当前不存在）
- 合成测试命令示例：
  `D:/Academic/Software/MATLAB/R2022b/bin/matlab -batch "run('D:/Users/Frank_7840HSw/Desktop/202605实验快反计算/Current_Plate_Calculation/tests/test_r2_pod_denoise.m')"`

【不要重复 / 不要做】

- 不要再用 raw `01_sequence_cache.mat` 生成与 Gaussian 比较的 POD 基底；当前正确源是 PostProc。
- 不要把 GD 合成测试 PASS 解释为 GD 已适用于真实 TBL/PIV 数据。
- 不要把 24 帧统计、代码合同测试或三张抽查图称为正式视觉/科研验收。
- 不要直接运行当前正式 Section 10 并期待完成；它会被内存闸门阻止，而且 Gaussian/POD 参数目前不一致。
- 不要用已有旧 `09_structure_analysis.mat` 作为当前源码参数的 Gaussian 对照。
- 不要清理 untracked 文件、`tmp` 基底或 `tp*.mat`；先确认归属和是否可恢复。

【下一步】

1. 先让用户人工审核 Gaussian、E40、E50、E60 的同帧图，记录真连接、虚连接、结构截断和边界问题；E50 只作为推荐审核中心，不预设结论。
2. 统一参数来源：建议新增结果 provenance（data source、alpha、seed、connectivity、merge、min_abs、Gaussian spec、mask、frame IDs、源码版本），并重新生成与拟比较 POD 分支完全同参数的 Gaussian 对照。不要复用旧 `09_structure_analysis.mat`。
3. 将验证扩展到至少 100–1200 帧，并按 repeat/时间段分层；对 E40/E50/E60 加密，报告结构数、LSM/VLSM、占据率、`Lx/delta` 中位/P90、CDF 和 bootstrap 区间。
4. 决定主架构：短期可继续实验链；若要正式 Section 10，优先把 memory-friendly POD 接到连续 E80/E90/E95 分支，并单独设计/验证流式 ELF。未经用户同意不要改全帧/[1 1]/double 合同。
5. 修复正式比较入口的 stale-Gaussian 问题，再运行合成合同和小规模真实缓存 smoke；只有参数、域、RMS 和帧完全一致时才比较 Raw/Gaussian/POD。
6. 完成可复现谱图脚本、低阶诊断 basis 接口统一和用户视觉审核后，再决定是否对两个 r2 工况生成正式全帧产物。

模式：full。隐私：local。来源：目标 Claude Code session、当前工作区代码、MAT/PNG 产物、Git 状态、本轮 MATLAB R2022b 测试与实时内存预检。限制：没有运行真实全帧 Section 10，也没有替用户完成 192 张图的科学人工验收。
