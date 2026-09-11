你正在接手一个进行中的“周期法向表面变形主动流动控制 PIV 数据分析 MATLAB 程序”任务。请按以下上下文继续；不要重新讨论已经确定的总体架构。若本提示与当前工作区证据冲突，以当前文件为准，并说明冲突。

【用户目标】
按“独立重写 → 新旧对比 → 人工审阅 → 回写”流程，完成本 section 的代码评审与改进，并保持既有架构与产物合同。

【工作目录】
D:\Users\Frank_7840HSw\Desktop\202605实验快反计算\Current_Plate_Calculation

环境为 Windows PowerShell 5.1、MATLAB R2022b。工作区非常脏，存在大量用户历史修改、删除和未跟踪文件；相关 `+tbl/+periodic/`、两个周期 case 目录、测试和 `third_party/` 均为未跟踪或已修改状态。禁止 reset、checkout、清理或覆盖无关改动。

【本轮目标：SECTION 6 独立重写与回写】
不依赖本对话的既有实现记忆，由你作为新 agent 背靠背地独立重写“Section 6：时域 PSD 与直接空间预乘谱”代码，并完成测试、新旧对比、人工审阅后回写。

流程：
1. 阅读当前 case 脚本 Section 6 与 `+tbl/+periodic/temporal_spectra_cache.m`、`spatial_spectra_cache.m`。
2. 联网检索 MATLAB Signal Processing Toolbox、`pwelch`、`fillmissing`、`detrend`、`fft`、预乘谱、Taylor 对流速度、空间 FFT 谱等官方和社区参考。
3. 在草稿中独立写出新的 Section 6 实现，并用合成周期信号验证。
4. 对比新旧实现优劣，输出对比评价，供人工审阅。
5. 根据人工意见修改。
6. 测试通过后写回 case 脚本，并同步更新共享函数、测试和 README。

【必须遵守的要求】
- [verified] 时域谱严格“各 x 先 PSD、再平均 PSD”，不能先平均信号再 PSD。
- [verified] 使用 `pwelch` 做 Welch 估计；频带选择只作用于 Welch 频率箱，不再调用时域 `bandpass`。
- [verified] 坏点修复使用 `fillmissing(..., 'linear', ..., 'EndValues','nearest')`，低有效率整条序列排除。
- [verified] Taylor 换算只用于 `lambda_x_plus`，对流速度必须是显式 `Uc` 设置，不能静默替换成 Ue。
- [verified] 空间谱直接对每帧 `u(x)` 做 FFT，不使用 Taylor 假设；定义必须包含 `'no Taylor hypothesis'` 和 `'One-sided'`。
- [verified] Section 6 输出为 `results.temporal`、`results.spatial`，分别写入 `mat/05_temporal_spectra.mat`、`mat/05_spatial_spectra.mat`。
- [verified] `tbl.spectra.welch_series` 是时域谱与参考谱共享的修复/PSD helper。
- [verified] 活跃云图只使用 `contourf(...,'LineStyle','none') + turbo(256) + colorbar`。
- [verified] 不运行真实完整 3000/6000 帧重算；验证使用合成周期数据。

【已确认事实与决策】
- [verified] Section 6 当前调用链：
  `tbl.periodic.compute_periodic_branches('temporal_spectra_cache', ...)`
  → `tbl.periodic.compute_periodic_branches('spatial_spectra_cache', ...)`
  → `tbl.periodic.preview_periodic_jobs(..., {'temporal_spectra','spatial_spectra'})`。
- [verified] `temporal_spectra_cache` 保存 `frequency_hz`、`phi_uu_*`、预乘谱、`Uc` 灵敏度、固定点曲线和谐波索引。
- [verified] `spatial_spectra_cache` 保存多个流向窗口、直接空间 FFT、`lambda_x_over_delta99_ref` 和所选 y+ 曲线。
- [verified] `test_periodic_piv_core.m` 已覆盖 8 Hz 峰、f·φ 与 λ·φ 等价、固定点曲线和空间谱峰值。
- [verified] `test_premultiplied_psd_reference.m` 覆盖参考谱修复与频带合同。

【已完成】
- `temporal_spectra_cache.m`、`spatial_spectra_cache.m`、`welch_series.m` 已存在并通过测试。
- 时域谱已改调共享 `welch_series`。

【未完成 / 待验证】
- 尚未按本流程做 Section 6 的独立重写、新旧对比和人工审阅。
- 真实 3000/6000 帧频谱未运行；只有合成周期谱验证。

【关键文件 / 命令 / 产物】
- `cases/per_case/tandem_baseline_r1/tandem_baseline_r1_case.m`
- `cases/per_case/tandem_f40a3_phi0_r1/tandem_f40a3_phi0_r1_case.m`
- `+tbl/+periodic/temporal_spectra_cache.m`
- `+tbl/+periodic/spatial_spectra_cache.m`
- `+tbl/+spectra/welch_series.m`
- `+tbl/+spectra/premultiplied_psd_reference.m`
- 产物：`mat/05_temporal_spectra.mat`、`mat/05_spatial_spectra.mat`
- 测试：`tests/test_periodic_piv_core.m`、`tests/test_premultiplied_psd_reference.m`

【不要重复 / 不要做】
- 不要重新引入时域 bandpass。
- 不要把“先平均再 PSD”或“Ue 替代 Uc”作为实现。
- 不要改变 `order_of_operations`、`taylor_scope`、`spectrum_convention` 等字符串合同。
- 不要删除旧输出或修改 `archive`。

【下一步】
1. 阅读 Section 6 相关函数和测试。
2. 联网检索 Welch/预乘谱/空间 FFT 参考。
3. 独立写出新的 Section 6 实现与合成测试。
4. 运行相关测试并输出新旧对比评价，等待人工审阅。
5. 审阅通过后回写并更新依赖、测试和 README。
