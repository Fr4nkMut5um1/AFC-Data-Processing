你正在接手一个进行中的“周期法向表面变形主动流动控制 PIV 数据分析 MATLAB 程序”任务。请按以下上下文继续；不要重新讨论已经确定的总体架构。若本提示与当前工作区证据冲突，以当前文件为准，并说明冲突。

【用户目标】
按“独立重写 → 新旧对比 → 人工审阅 → 回写”流程，完成本 section 的代码评审与改进，并保持既有架构与产物合同。

【工作目录】
D:\Users\Frank_7840HSw\Desktop\202605实验快反计算\Current_Plate_Calculation

环境为 Windows PowerShell 5.1、MATLAB R2022b。工作区非常脏，存在大量用户历史修改、删除和未跟踪文件；相关 `+tbl/+periodic/`、两个周期 case 目录、测试和 `third_party/` 均为未跟踪或已修改状态。禁止 reset、checkout、清理或覆盖无关改动。

【本轮目标：SECTION 5 独立重写与回写】
不依赖本对话的既有实现记忆，由你作为新 agent 背靠背地独立重写“Section 5：四象限与平面输运项”代码，并完成测试、新旧对比、人工审阅后回写。

流程：
1. 阅读当前 case 脚本 Section 5 与 `+tbl/+periodic/transport_analysis.m`、`quadrant_streaming.m`。
2. 联网检索 MATLAB/File Exchange/GitHub 中雷诺应力象限分析、hole threshold、Q2/Q4、湍动能输运、RBF-FD/有限差分法向梯度等可复用实现或参考。
3. 在草稿中独立写出新的 Section 5 实现，并用合成速度场验证。
4. 对比新旧实现优劣，输出对比评价，供人工审阅。
5. 根据人工意见修改。
6. 测试通过后写回 case 脚本，并同步更新共享函数、测试和 README。

【必须遵守的要求】
- [verified] 正 V 指向离壁方向；象限定义为 Q1 `u'>0,v'>0`、Q2 `u'<0,v'>0`、Q3 `u'<0,v'<0`、Q4 `u'>0,v'<0`。
- [verified] 贡献量采用 `-u'v'`，Q2/Q4 通常为正。
- [verified] hole 阈值 `H=0/1/2` 使用 `abs(uv) > H*local_scale`；`hole_scale_definition='H times local u_rms*v_rms'` 是周期流程合同。
- [verified] `quadrant_streaming` 与 `quadrant_analysis` 共用 `tbl.stats.quadrant_mask`。
- [verified] Section 5 输出为 `results.transport`，写入 `mat/04_transport_quadrant.mat`。
- [verified] 受控 case 还计算 random 分支；baseline 的 phase 为空是合法输入。
- [verified] 活跃云图只使用 `contourf(...,'LineStyle','none') + turbo(256) + colorbar`。
- [verified] 不运行真实完整 3000/6000 帧重算；验证使用合成场和缓存复用。

【已确认事实与决策】
- [verified] Section 5 当前调用链：
  `tbl.periodic.run_section(..., 'transport', @() tbl.periodic.transport_analysis(...), {'transport'}, {'statistics','mean_bl'[, 'phase']}, ...)`。
- [verified] `transport_analysis` 依赖 `quadrant_streaming` 和两类法向梯度（有限差分、RBF-FD 灵敏度）。
- [verified] `test_periodic_piv_core.m` 已覆盖 `quadrant_streaming` 的 Q2/Q4、hole 阈值和输运结果。
- [verified] `test_singlecase_helpers.m` 已覆盖 `quadrant_analysis` 的概率、应力和符号合同。

【已完成】
- `quadrant_streaming.m`、`transport_analysis.m`、`quadrant_mask.m` 已存在并通过测试。
- 共享象限 mask 已接入周期与单 case 两条路径。

【未完成 / 待验证】
- 尚未按本流程做 Section 5 的独立重写、新旧对比和人工审阅。
- 相位分辨 Q2/Q4 与 cycle-average 结果只有合成测试，未跑真实 40 Hz 数据。

【关键文件 / 命令 / 产物】
- `cases/per_case/tandem_baseline_r1/tandem_baseline_r1_case.m`
- `cases/per_case/tandem_f40a3_phi0_r1/tandem_f40a3_phi0_r1_case.m`
- `+tbl/+periodic/transport_analysis.m`
- `+tbl/+periodic/quadrant_streaming.m`
- `+tbl/+stats/quadrant_mask.m`
- `+tbl/+stats/quadrant_analysis.m`
- 产物：`mat/04_transport_quadrant.mat`
- 测试：`tests/test_periodic_piv_core.m`、`tests/test_singlecase_helpers.m`

【不要重复 / 不要做】
- 不要改变象限符号口径或 hole 定义。
- 不要把 `mask_quadrant_output` 之外的旧输出结构重新引入。
- 不要把共享计算复制回 case 脚本。
- 不要删除旧输出或修改 `archive`。

【下一步】
1. 阅读 Section 5 相关函数和测试。
2. 联网检索四象限与输运分析参考实现。
3. 独立写出新的 Section 5 实现与合成测试。
4. 运行相关测试并输出新旧对比评价，等待人工审阅。
5. 审阅通过后回写并更新依赖、测试和 README。
