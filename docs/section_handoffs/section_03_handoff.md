你正在接手一个进行中的“周期法向表面变形主动流动控制 PIV 数据分析 MATLAB 程序”任务。请按以下上下文继续；不要重新讨论已经确定的总体架构。若本提示与当前工作区证据冲突，以当前文件为准，并说明冲突。

【用户目标】
按“独立重写 → 新旧对比 → 人工审阅 → 回写”流程，完成本 section 的代码评审与改进，并保持既有架构与产物合同。

【工作目录】
D:\Users\Frank_7840HSw\Desktop\202605实验快反计算\Current_Plate_Calculation

环境为 Windows PowerShell 5.1、MATLAB R2022b。工作区非常脏，存在大量用户历史修改、删除和未跟踪文件；相关 `+tbl/+periodic/`、两个周期 case 目录、测试和 `third_party/` 均为未跟踪或已修改状态。禁止 reset、checkout、清理或覆盖无关改动。

【本轮目标：SECTION 3 独立重写与回写】
不依赖本对话的既有实现记忆，由你作为新 agent 背靠背地独立重写“Section 3：相位平均与三重分解”代码，并完成测试、新旧对比、人工审阅后回写。

流程：
1. 阅读当前 case 脚本 Section 3 与 `+tbl/+periodic/phase_stats_cache.m`、`assign_phase.m`、`harmonic_analysis.m`。
2. 联网检索 MATLAB/File Exchange/GitHub 中周期信号相位平均、锁相平均、triple decomposition、相位箱分配等可复用实现或参考。
3. 在草稿中独立写出新的 Section 3 实现，并用合成周期信号验证。
4. 对比新旧实现优劣，输出对比评价，供人工审阅。
5. 根据人工意见修改。
6. 测试通过后写回 case 脚本，并同步更新共享函数、测试和 README。

【必须遵守的要求】
- [verified] baseline 的 `cfg.stages.phase` 必须为 `skip`，且 `results.phase=[]`；禁止给 baseline 人为构造相位。
- [verified] 受控 case f40a3 的 `cfg.phase.enabled=true`、`f0_hz=40`、`n_bins=24`、`minimum_samples_per_bin=20`。
- [verified] `phi0_user_deg=[]` 时只保留内部相对相位，机械相位必须保持未标定，不能宣称绝对表面相位。
- [verified] Section 3 输出为 `results.phase`，写入 `mat/03_phase_triple_statistics.mat`。
- [verified] 相位统计必须从 `mat/01_sequence_cache.mat` 逐块读取，不允许一次载入全部帧。
- [verified] 相位三重分解必须分别保存总量、相干量和随机量分支，供 Section 4–8 的 `total/random` 分支消费。
- [verified] 活跃云图只使用 `contourf(...,'LineStyle','none') + turbo(256) + colorbar`。
- [verified] 不运行真实完整 3000/6000 帧重算；验证使用合成周期数据。

【已确认事实与决策】
- [verified] f40a3 Section 3 当前调用链：
  `tbl.periodic.run_section(..., 'phase', @() tbl.periodic.phase_stats_cache(...), {'phase_triple'}, {'statistics'}, ...)`。
- [verified] `phase_stats_cache` 使用 `assign_phase` 按帧时钟分配相位箱，并输出 `mechanical_status='not_calibrated'`。
- [verified] `test_periodic_piv_core.m` 已覆盖 16 箱合成相位、triple 重构残差和 `harmonic_analysis` 基波幅值。
- [verified] baseline 的 Section 3 在脚本中显式设置为 `results.phase=[]` 并打印 `NOT_APPLICABLE`。
- [inferred] 新实现应继续使用 `read_cache_chunk` 与 `phase_stats_cache` 合同，不改变 `total/random` 字段结构。

【已完成】
- 相位分配、相位统计、谐波分析函数已存在并通过现有测试。
- f40a3 的 Section 3 已接入共享 `run_section`。

【未完成 / 待验证】
- 尚未按本流程做 Section 3 的独立重写、新旧对比和人工审阅。
- 真实 40 Hz/24 箱相位统计未运行；只验证了合成数据。

【关键文件 / 命令 / 产物】
- `cases/per_case/tandem_f40a3_phi0_r1/tandem_f40a3_phi0_r1_case.m`
- `cases/per_case/tandem_baseline_r1/tandem_baseline_r1_case.m`
- `+tbl/+periodic/phase_stats_cache.m`
- `+tbl/+periodic/assign_phase.m`
- `+tbl/+periodic/harmonic_analysis.m`
- `+tbl/+periodic/read_cache_chunk.m`
- 产物：`mat/03_phase_triple_statistics.mat`
- 测试：`tests/test_periodic_piv_core.m`

【不要重复 / 不要做】
- 不要改变相位箱数、f0 或随机分支命名。
- 不要把机械相位未标定状态误报为已标定。
- 不要为 baseline 生成人工相位。
- 不要删除旧输出或修改 `archive`。

【下一步】
1. 阅读 `phase_stats_cache.m`、`assign_phase.m`、`harmonic_analysis.m` 和现有测试。
2. 联网检索周期信号相位平均/triple decomposition 参考。
3. 独立写出新的 Section 3 实现与合成周期测试。
4. 运行相关测试并输出新旧对比评价，等待人工审阅。
5. 审阅通过后回写并更新依赖、测试和 README。
