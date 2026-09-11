你正在接手一个进行中的“周期法向表面变形主动流动控制 PIV 数据分析 MATLAB 程序”任务。请按以下上下文继续；不要重新讨论已经确定的总体架构。若本提示与当前工作区证据冲突，以当前文件为准，并说明冲突。

【用户目标】
按“独立重写 → 新旧对比 → 人工审阅 → 回写”流程，完成本 section 的代码评审与改进，并保持既有架构与产物合同。

【工作目录】
D:\Users\Frank_7840HSw\Desktop\202605实验快反计算\Current_Plate_Calculation

环境为 Windows PowerShell 5.1、MATLAB R2022b。工作区非常脏，存在大量用户历史修改、删除和未跟踪文件；相关 `+tbl/+periodic/`、两个周期 case 目录、测试和 `third_party/` 均为未跟踪或已修改状态。禁止 reset、checkout、清理或覆盖无关改动。

【本轮目标：SECTION 7 独立重写与回写】
不依赖本对话的既有实现记忆，由你作为新 agent 背靠背地独立重写“Section 7：POD、DMD 与 SPOD”代码，并完成测试、新旧对比、人工审阅后回写。

流程：
1. 阅读当前 case 脚本 Section 7 与 `+tbl/+periodic/pod_cache.m`、`dmd_cache.m`、`spod_cache.m`、`modal_snapshot_matrix.m`。
2. 联网检索 MATLAB/File Exchange/GitHub 中 snapshot POD、DMD、SPOD、随机 SVD、`svds`、piDMD、Towne SPOD 等可复用实现和文献。
3. 在草稿中独立写出新的 Section 7 实现，并用合成模态信号验证。
4. 对比新旧实现优劣，输出对比评价，供人工审阅。
5. 根据人工意见修改。
6. 测试通过后写回 case 脚本，并同步更新共享函数、测试和 README。

【必须遵守的要求】
- [verified] POD 使用 `Comparison_Re30w_AoA2.m` 的参考快照算法：`C=Xf'*Xf/size(Xf,1)`、`eig` 排序、`Phi=Xf*As` 归一化、`Ac=Phi'*Xf`。
- [verified] `pod_cache` 输出必须保留 `lambda/energy_ratio/cumulative_energy_ratio/temporal_coefficients/modes/orthogonality_matrix/reconstruction_*` 等字段。
- [verified] DMD 使用 `third_party/piDMD`（MIT）的 `piDMD(X1,X2,'exact',r)`；必须保留 `eigenvalues/frequency_hz/growth_rate_per_s/amplitudes/modes/harmonic_*` 字段。
- [verified] SPOD 使用已安装 Towne/Schmidt `spod.m`；`spod_cache` 必须保留 `frequency_hz/eigenvalues/selected_frequency_* /selected_modes/n_blocks` 字段。
- [verified] 三个模态 stage 各自独立 `compute/reuse/skip`，受控 case 还计算 `random` 分支。
- [verified] 模态 ROI、空间降采样、`max_frames`、`n_modes` 由 `cfg.pod/dmd/spod` 控制，不写死进共享函数。
- [verified] 活跃云图只使用 `contourf(...,'LineStyle','none') + turbo(256) + colorbar`；DMD/SPOD 当前输出为曲线/散点。
- [verified] 不运行真实完整 3000/6000 帧重算；验证使用合成数据。

【已确认事实与决策】
- [verified] Section 7 当前调用链：
  `tbl.periodic.compute_periodic_branches('pod_cache'|'dmd_cache'|'spod_cache', ...)`
  → `tbl.periodic.preview_periodic_jobs(..., {'pod','dmd','spod'})`。
- [verified] `modal_snapshot_matrix` 负责从缓存构造显式等间隔联合 `[u;v]` 快照矩阵。
- [verified] `map_joint_modes` 把联合模态映射回 XOY 网格。
- [verified] `ensure_external_toolboxes` 会自动把 vendored piDMD 加入 MATLAB path，并检查 `spod` 可用。
- [verified] 旧 `06_pod_analysis.mat`、`07_dmd_analysis.mat`、`08_spod_analysis.mat` 会因实现指纹变化被拒绝复用；需要人工决定何时重算。
- [verified] `test_periodic_piv_core.m` 已覆盖 POD 能量/正交性、DMD 8 Hz 频率、SPOD 选频和 `n_blocks>=3`。

【已完成】
- POD/DMD/SPOD 已接入外部/参考轮子并通过合成测试。
- `snapshot_decomposition`、`spod_toolbox_adapter`、`ensure_external_toolboxes` 已新增。

【未完成 / 待验证】
- 尚未按本流程做 Section 7 的独立重写、新旧对比和人工审阅。
- 真实 3000/6000 帧模态计算未运行；只有合成数据验证。

【关键文件 / 命令 / 产物】
- `cases/per_case/tandem_baseline_r1/tandem_baseline_r1_case.m`
- `cases/per_case/tandem_f40a3_phi0_r1/tandem_f40a3_phi0_r1_case.m`
- `+tbl/+periodic/pod_cache.m`
- `+tbl/+periodic/dmd_cache.m`
- `+tbl/+periodic/spod_cache.m`
- `+tbl/+periodic/modal_snapshot_matrix.m`
- `+tbl/+periodic/map_joint_modes.m`
- `+tbl/+pod/snapshot_decomposition.m`
- `third_party/piDMD/`
- 产物：`mat/06_pod_analysis.mat`、`mat/07_dmd_analysis.mat`、`mat/08_spod_analysis.mat`
- 测试：`tests/test_periodic_piv_core.m`、`tests/test_refactor_shared_helpers.m`

【不要重复 / 不要做】
- 不要把 POD 改回随机 SVD 旧口径；除非人工审阅明确要求。
- 不要绕过 piDMD/SPOD adapter 直接复制第三方大段代码到 `+tbl/+periodic`。
- 不要在验证阶段重建真实 3000/6000 帧模态缓存。
- 不要删除 `third_party/piDMD/LICENSE`。

【下一步】
1. 阅读 Section 7 相关函数、`spod.m` 接口和 piDMD README。
2. 联网检索 POD/DMD/SPOD 文献和 MATLAB 实现。
3. 独立写出新的 Section 7 实现与合成模态测试。
4. 运行相关测试并输出新旧对比评价，等待人工审阅。
5. 审阅通过后回写并更新依赖、测试和 README。
