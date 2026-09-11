你正在接手一个进行中的“周期法向表面变形主动流动控制 PIV 数据分析 MATLAB 程序”任务。请按以下上下文继续；不要重新讨论已经确定的总体架构。若本提示与当前工作区证据冲突，以当前文件为准，并说明冲突。

【用户目标】
按“独立重写 → 新旧对比 → 人工审阅 → 回写”流程，完成本 section 的代码评审与改进，并保持既有架构与产物合同。

【工作目录】
D:\Users\Frank_7840HSw\Desktop\202605实验快反计算\Current_Plate_Calculation

环境为 Windows PowerShell 5.1、MATLAB R2022b。工作区非常脏，存在大量用户历史修改、删除和未跟踪文件；相关 `+tbl/+periodic/`、两个周期 case 目录、测试和 `third_party/` 均为未跟踪或已修改状态。禁止 reset、checkout、清理或覆盖无关改动。

【本轮目标：SECTION 8 独立重写与回写】
不依赖本对话的既有实现记忆，由你作为新 agent 背靠背地独立重写“Section 8：相关性与沿程/谐波综合”代码，并完成测试、新旧对比、人工审阅后回写。

流程：
1. 阅读当前 case 脚本 Section 8 与 `+tbl/+periodic/correlation_analysis_cache.m`、`streamwise_development_analysis.m`。
2. 联网检索 MATLAB 中自相关、互相关、两点相关、时空相关脊线、谐波幅值、跨产品汇总等可复用实现或参考。
3. 在草稿中独立写出新的 Section 8 实现，并用合成场验证。
4. 对比新旧实现优劣，输出对比评价，供人工审阅。
5. 根据人工意见修改。
6. 测试通过后写回 case 脚本，并同步更新共享函数、测试和 README。

【必须遵守的要求】
- [verified] Section 8 输出为 `results.correlations` 和 `results.harmonics`，分别写入 `mat/13_correlation_analysis.mat`、`mat/13_streamwise_harmonic_development.mat`。
- [verified] 相关性包含时间、流向、二维两点、时空、条件和外部相干性；外部信号为空时明确标记 unavailable。
- [verified] 受控 case 还计算 f0、2f0、3f0 谐波幅值；baseline 只生成非相位分支。
- [verified] 缺失可选上游时，`streamwise_development_analysis` 要保存可用核心并把 P18 标为 `PARTIAL`，不能伪造结果。
- [verified] `record_selection_diagnostics` 会把选择诊断写入 `csv/01_diagnostic_messages.csv`。
- [verified] 活跃云图只使用 `contourf(...,'LineStyle','none') + turbo(256) + colorbar`。
- [verified] 不运行真实完整 3000/6000 帧重算；验证使用合成数据。

【已确认事实与决策】
- [verified] Section 8 当前调用链：
  `tbl.periodic.compute_periodic_branches('correlation_analysis_cache', ...)`
  → `tbl.periodic.streamwise_development_analysis(results, cfg)`
  → `tbl.periodic.preview_periodic_jobs(..., {'correlations','harmonics'})`。
- [verified] `correlation_analysis_cache` 读取 `read_cache_chunk`，输出 `temporal/streamwise/two_point/space_time/conditional/coherence` 等结构。
- [verified] `streamwise_development_analysis` 汇总 P02/P07/P08/P10–P17 的沿程链接，受控 case 增加 f0/2f0/3f0 谐波。
- [verified] `test_periodic_piv_core.m` 已覆盖 `correlation_analysis_cache`、`streamwise_development_analysis` 和 P18 定义字符串。

【已完成】
- `correlation_analysis_cache.m`、`streamwise_development_analysis.m`、`record_selection_diagnostics.m` 已存在并通过测试。
- Section 8 已接入共享 `run_section` 和 `compute_periodic_branches`。

【未完成 / 待验证】
- 尚未按本流程做 Section 8 的独立重写、新旧对比和人工审阅。
- 真实外部同步信号相干性未测试。

【关键文件 / 命令 / 产物】
- `cases/per_case/tandem_baseline_r1/tandem_baseline_r1_case.m`
- `cases/per_case/tandem_f40a3_phi0_r1/tandem_f40a3_phi0_r1_case.m`
- `+tbl/+periodic/correlation_analysis_cache.m`
- `+tbl/+periodic/streamwise_development_analysis.m`
- `+tbl/+periodic/record_selection_diagnostics.m`
- 产物：`mat/13_correlation_analysis.mat`、`mat/13_streamwise_harmonic_development.mat`
- 测试：`tests/test_periodic_piv_core.m`

【不要重复 / 不要做】
- 不要把外部信号缺失误报为已计算。
- 不要改变 P16/P18 产物编号或 `PARTIAL` 语义。
- 不要为 baseline 伪造 f0/2f0/3f0 谐波。
- 不要删除旧输出或修改 `archive`。

【下一步】
1. 阅读 Section 8 相关函数和测试。
2. 联网检索相关分析和谐波综合参考。
3. 独立写出新的 Section 8 实现与合成测试。
4. 运行相关测试并输出新旧对比评价，等待人工审阅。
5. 审阅通过后回写并更新依赖、测试和 README。
