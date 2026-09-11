你正在接手一个进行中的“周期法向表面变形主动流动控制 PIV 数据分析 MATLAB 程序”任务。请按以下上下文继续；不要重新讨论已经确定的总体架构。若本提示与当前工作区证据冲突，以当前文件为准，并说明冲突。

【用户目标】
按“独立重写 → 新旧对比 → 人工审阅 → 回写”流程，完成本 section 的代码评审与改进，并保持既有架构与产物合同。

【工作目录】
D:\Users\Frank_7840HSw\Desktop\202605实验快反计算\Current_Plate_Calculation

环境为 Windows PowerShell 5.1、MATLAB R2022b。工作区非常脏，存在大量用户历史修改、删除和未跟踪文件；相关 `+tbl/+periodic/`、两个周期 case 目录、测试和 `third_party/` 均为未跟踪或已修改状态。禁止 reset、checkout、清理或覆盖无关改动。

【本轮目标：SECTION 2 独立重写与回写】
不依赖本对话的既有实现记忆，由你作为新 agent 背靠背地独立重写“Section 2：时间统计、壁面坐标、边界层与摩阻”代码，并完成测试、新旧对比、人工审阅后回写。

流程：
1. 阅读当前 case 脚本 Section 2 与 `+tbl/+periodic/mean_stats_cache.m`、`mean_bl_friction.m`。
2. 联网检索 MATLAB/File Exchange/GitHub 中湍流统计、Welford 流式均值、边界层厚度、Clauser/log-law、动量积分 Cf 的可复用实现或参考。
3. 在草稿中独立写出新的 Section 2 实现，并用合成数据验证。
4. 对比新旧实现优劣，输出对比评价，供人工审阅。
5. 根据人工意见修改。
6. 测试通过后写回 case 脚本，并同步更新共享函数、测试和 README。

【必须遵守的要求】
- [verified] Section 2 的输出为 `results.statistics` 和 `results.mean_bl`，分别写入 `mat/02_statistics.mat`、`mat/02_mean_boundary_layer_friction.mat`。
- [verified] `cfg.stages.statistics` 和 `cfg.stages.mean_bl` 只允许 `compute`、`reuse` 或 `skip`；核心统计不允许 skip。
- [verified] 统计必须逐块读取 `mat/01_sequence_cache.mat`，不能一次性载入全部帧。
- [verified] 壁面坐标合同：首保留行到真实壁面距离为 `dy_h*h`；`wall_distance_grid` 是唯一公共入口。
- [verified] 时间统计字段包含 `Uavex/Vavex/uu/vv/uv/u_rms/v_rms/TKE/uv_rey` 等，后续 Section 4–8 依赖这些字段名。
- [verified] 摩擦速度来源由 `cfg.normalization.u_tau_source` 决定，`mean_bl_friction` 已改调 `tbl.singlecase.select_u_tau`。
- [verified] 活跃云图只使用 `contourf(...,'LineStyle','none') + turbo(256) + colorbar`。
- [verified] 不运行真实完整 3000/6000 帧重算；验证使用合成数据和现有缓存复用。

【已确认事实与决策】
- [verified] Section 2 当前调用链：
  `require_periodic_file(paths.sequence_cache)`
  → `tbl.periodic.mean_stats_cache`
  → `tbl.periodic.mean_bl_friction`
  → `tbl.periodic.preview_periodic_jobs(..., {'mean_turbulence','friction'})`。
- [verified] `mean_bl_friction` 使用 `prepare_case_views`、`extract_velocity_profile`、`loglaw_fit_chen`、`integral_params`、`prepare_drag_inputs`、`select_secant_theta`、`prepare_edge_velocity`、`system_secant_cf`、`shear_momentum`、`momentum_calibration_quality`。
- [verified] 两个 case 的 `profile.mode='range_avg'`、`params=[80 120]`；`loglaw.mode='auto'`、`dy_h=2.4`。
- [verified] baseline 使用 `u_tau_source='local_loglaw'`；f40a3 使用 `'baseline_inline'`。
- [verified] `test_singlecase_helpers.m` 和 `test_pressure_gradient_contract.m` 已覆盖 log-law、动量积分和压力梯度合同。
- [inferred] 新实现应继续复用 `+tbl/+wall`、`+tbl/+bl` 与 `+tbl/+stats` 的既有轮子，而不是在 Section 2 内重写数值公式。

【已完成】
- 统计、边界层、摩阻共享函数已存在并通过现有测试。
- `mean_bl_friction` 已改为复用 `tbl.singlecase.select_u_tau`。

【未完成 / 待验证】
- 尚未按本流程做 Section 2 的独立重写、新旧对比和人工审阅。
- `mean_stats_cache` 本身缺少直接数值合同测试；部分缺失/陈旧统计缓存没有专门测试。

【关键文件 / 命令 / 产物】
- `cases/per_case/tandem_baseline_r1/tandem_baseline_r1_case.m`
- `cases/per_case/tandem_f40a3_phi0_r1/tandem_f40a3_phi0_r1_case.m`
- `+tbl/+periodic/mean_stats_cache.m`
- `+tbl/+periodic/mean_bl_friction.m`
- `+tbl/+periodic/wall_distance_grid.m`
- `+tbl/+stats/prepare_case_views.m`
- `+tbl/+bl/loglaw_fit_chen.m`
- `+tbl/+wall/*.m`
- 产物：`mat/02_statistics.mat`、`mat/02_mean_boundary_layer_friction.mat`
- 测试：`tests/test_singlecase_helpers.m`、`tests/test_pressure_gradient_contract.m`、`tests/test_periodic_piv_core.m`

【不要重复 / 不要做】
- 不要改变统计字段名、壁面坐标合同或 Cf 公式口径。
- 不要把共享计算复制回 case 脚本。
- 不要新增独立于 `validate_config` 的参数自检。
- 不要删除旧 `_cache` 或旧 Section 输出目录。

【下一步】
1. 阅读 Section 2 相关函数和测试。
2. 联网检索湍流统计与边界层 Cf 参考实现。
3. 独立写出新的 Section 2 实现与合成测试。
4. 运行相关测试并输出新旧对比评价，等待人工审阅。
5. 审阅通过后回写并更新依赖、测试和 README。
