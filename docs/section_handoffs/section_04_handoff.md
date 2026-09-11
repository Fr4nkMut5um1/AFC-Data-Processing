你正在接手一个进行中的“周期法向表面变形主动流动控制 PIV 数据分析 MATLAB 程序”任务。请按以下上下文继续；不要重新讨论已经确定的总体架构。若本提示与当前工作区证据冲突，以当前文件为准，并说明冲突。

【用户目标】
按“独立重写 → 新旧对比 → 人工审阅 → 回写”流程，完成本 section 的代码评审与改进，并保持既有架构与产物合同。

【工作目录】
D:\Users\Frank_7840HSw\Desktop\202605实验快反计算\Current_Plate_Calculation

环境为 Windows PowerShell 5.1、MATLAB R2022b。工作区非常脏，存在大量用户历史修改、删除和未跟踪文件；相关 `+tbl/+periodic/`、两个周期 case 目录、测试和 `third_party/` 均为未跟踪或已修改状态。禁止 reset、checkout、清理或覆盖无关改动。

【本轮目标：SECTION 4 独立重写与回写】
不依赖本对话的既有实现记忆，由你作为新 agent 背靠背地独立重写“Section 4：瞬时场、平面涡判据与 LSM/VLSM”代码，并完成测试、新旧对比、人工审阅后回写。

流程：
1. 阅读当前 case 脚本 Section 4 与 `+tbl/+periodic/structure_analysis_cache.m`、`planar_criteria.m`、`gradient_y_sensitivity.m`、`identify_structures.m`。
2. 联网检索 MATLAB/File Exchange/GitHub 中 PIV 瞬时涡量、Q、lambda2、lambda_ci、连通域识别、LSM/VLSM 判据、Image Processing Toolbox `bwconncomp` 等可复用实现。
3. 在草稿中独立写出新的 Section 4 实现，并用合成场验证。
4. 对比新旧实现优劣，输出对比评价，供人工审阅。
5. 根据人工意见修改。
6. 测试通过后写回 case 脚本，并同步更新共享函数、测试和 README。

【必须遵守的要求】
- [verified] `cfg.instantaneous.frame_ids=[首帧 末帧]`，`cfg.instantaneous.n_output_frames` 决定代表帧数量；不允许把范围展开成全部帧保存完整瞬时结构。
- [verified] `instantaneous_frame_ids` 使用 `floor(linspace(first,last,n_output_frames))` 并保持唯一有序。
- [verified] Section 4 输出为 `results.structures`，写入 `mat/09_structure_analysis.mat`。
- [verified] 瞬时场包含原始 `u`、`v`、总脉动 `u'=u-Uavg`、`v'`、随机分支（受控 case）和平面涡判据。
- [verified] 结构识别必须按正/负脉动符号分离，使用 4 或 8 邻域连通；`tbl.vlsm.connected_components_2d` 是 4 邻域回退。
- [verified] LSM/VLSM 判据使用 `Lx/delta99`，并受 `max_wall_normal_delta`、`min_pixels`、附壁/边缘选项约束。
- [verified] 活跃云图只使用 `contourf(...,'LineStyle','none') + turbo(256) + colorbar`。
- [verified] 不运行真实完整 3000/6000 帧重算；验证使用合成场和缓存复用。

【已确认事实与决策】
- [verified] Section 4 当前调用链：
  `tbl.periodic.run_section(..., 'structures', @() tbl.periodic.structure_analysis_cache(...), {'instantaneous_fields','instantaneous_vortex','structures'}, {'statistics','mean_bl'[, 'phase']}, ...)`。
- [verified] `structure_analysis_cache` 通过 `instantaneous_frame_ids` 选取代表帧，逐帧读取 `read_cache_chunk`。
- [verified] `planar_criteria` 使用 `gradient` 计算 `omega_z`、平面 Q、lambda2、lambda_ci。
- [verified] `identify_structures` 使用 `bwconncomp`，缺 IPT 时回退 `tbl.vlsm.connected_components_2d`；几何量已抽取到 `tbl.vlsm.structure_geometry`。
- [verified] `test_periodic_piv_core.m` 已覆盖梯度、连通性、结构表和瞬时代表帧重构。

【已完成】
- `structure_analysis_cache.m`、`planar_criteria.m`、`gradient_y_sensitivity.m`、`identify_structures.m` 已存在并通过测试。
- `identify_structures` 与 `identify_frame` 共用 `structure_geometry`。

【未完成 / 待验证】
- 尚未按本流程做 Section 4 的独立重写、新旧对比和人工审阅。
- 真实 LSM/VLSM 目录未运行；只有合成连通测试。

【关键文件 / 命令 / 产物】
- `cases/per_case/tandem_baseline_r1/tandem_baseline_r1_case.m`
- `cases/per_case/tandem_f40a3_phi0_r1/tandem_f40a3_phi0_r1_case.m`
- `+tbl/+periodic/structure_analysis_cache.m`
- `+tbl/+periodic/planar_criteria.m`
- `+tbl/+periodic/gradient_y_sensitivity.m`
- `+tbl/+periodic/identify_structures.m`
- `+tbl/+periodic/instantaneous_frame_ids.m`
- `+tbl/+vlsm/structure_geometry.m`
- 产物：`mat/09_structure_analysis.mat`
- 测试：`tests/test_periodic_piv_core.m`、`tests/test_vlsm_cluster_connectivity.m`

【不要重复 / 不要做】
- 不要把 `cfg.instantaneous.frame_ids` 重新解释为离散帧列表。
- 不要改变结构表字段名或 LSM/VLSM 判据。
- 不要把 `imagesc/surface/pcolor` 用于活跃云图。
- 不要删除旧输出或修改 `archive`。

【下一步】
1. 阅读 Section 4 相关函数和测试。
2. 联网检索涡判据与连通结构识别参考。
3. 独立写出新的 Section 4 实现与合成测试。
4. 运行相关测试并输出新旧对比评价，等待人工审阅。
5. 审阅通过后回写并更新依赖、测试和 README。
