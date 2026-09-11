你正在接手一个进行中的“周期法向表面变形主动流动控制 PIV 数据分析 MATLAB 程序”任务。请按以下上下文继续；不要重新讨论已经确定的总体架构。若本提示与当前工作区证据冲突，以当前文件为准，并说明冲突。

【用户目标】
按“独立重写 → 新旧对比 → 人工审阅 → 回写”流程，完成本 section 的代码评审与改进，并保持既有架构与产物合同。

【工作目录】
D:\Users\Frank_7840HSw\Desktop\202605实验快反计算\Current_Plate_Calculation

环境为 Windows PowerShell 5.1、MATLAB R2022b。工作区非常脏，存在大量用户历史修改、删除和未跟踪文件；相关 `+tbl/+periodic/`、两个周期 case 目录、测试和 `third_party/` 均为未跟踪或已修改状态。禁止 reset、checkout、清理或覆盖无关改动。

【本轮目标：SECTION 9 独立重写与回写】
不依赖本对话的既有实现记忆，由你作为新 agent 背靠背地独立重写“Section 9：正式导出、诊断清单与机器摘要”代码，并完成测试、新旧对比、人工审阅后回写。

流程：
1. 阅读当前 case 脚本 Section 9 与 `+tbl/+periodic/run_case.m`、`plot_products.m`、`write_case_card.m`、`write_diagnostics.m`、`write_machine_summary.m`。
2. 联网检索 MATLAB 图形导出、`exportgraphics`、`savefig`、UTF-8 CSV/JSON、product manifest、原子写入等可复用实现或最佳实践。
3. 在草稿中独立写出新的 Section 9 实现，并用合成结果验证。
4. 对比新旧实现优劣，输出对比评价，供人工审阅。
5. 根据人工意见修改。
6. 测试通过后写回 case 脚本，并同步更新共享函数、测试和 README。

【必须遵守的要求】
- [verified] Section 9 把已完成数值阶段统一改为 `reuse`，调用 `tbl.periodic.run_case(final_cfg)`，再覆盖 `results=report.results`。
- [verified] 正式导出前若 `cfg.preview.close_before_export=true`，必须关闭已登记预览图。
- [verified] 新产物只写入 `png/fig/eps/emf/pdf/mat/csv/json/md` 扩展名目录，文件名保留 `00_` 至 `13_` 前缀。
- [verified] `plot_products` 活跃云图只能使用 `contourf(...,'LineStyle','none') + turbo(256) + colorbar`，且文件中必须恰好出现 7 个 `contourf(` 和 7 个 `colormap(ax, turbo(256))`。
- [verified] 图导出通过 `tbl.viz.export_publication_figure` 统一完成，PNG 200 dpi，PDF/EPS/EMF 矢量，FIG 用 `savefig`。
- [verified] 必须写 `csv/12_product_manifest.csv`、`json/12_case_summary.json`、`md/12_case_summary.md` 和诊断 CSV/JSON。
- [verified] P01–P19 严格沿用 12 号编程指导编号；P20 单 case 只标 `DEFERRED`，不能用 baseline/f40A3 伪造 Level 2/3 图谱。
- [verified] 不运行真实完整 3000/6000 帧重算；验证使用合成结果和缓存复用。

【已确认事实与决策】
- [verified] `run_case` 从 `validate_config` → `build_paths` → `ensure_external_toolboxes` → 写 case card → 按 P01–P20 顺序执行各数值阶段 → 导出图 → 写诊断/清单/摘要。
- [verified] `run_case` 的阶段失败不会静默吞掉；`exception_diagnostic` 保留 `ME.identifier`、`ME.message`、`ME.stack(1)` 和受影响产物。
- [verified] `run_stage` 在 `compute` 时调用计算函数并 `save_stage_result`，`reuse` 时 `load_stage_result` 并做合同校验。
- [verified] `preview_periodic_jobs` 对 `preview.errors` 会发出带 job 名和原始错误的 warning。
- [verified] `test_periodic_piv_core.m` 已覆盖 run_case 缺输入错误 ID、五格式导出和扩展名目录；`test_singlecase_figure_style_contract.m` 覆盖绘图样式静态合同。

【已完成】
- `run_case.m`、`plot_products.m`、`write_diagnostics.m`、`write_machine_summary.m` 已存在并通过测试。
- `plot_products` 导出已统一走 `tbl.viz.export_publication_figure`。
- README 已记录共享层和外部轮子。

【未完成 / 待验证】
- 尚未按本流程做 Section 9 的独立重写、新旧对比和人工审阅。
- 图导出失败时的部分产物行为、混合 preview+export、重复运行覆盖语义没有专门测试。

【关键文件 / 命令 / 产物】
- `cases/per_case/tandem_baseline_r1/tandem_baseline_r1_case.m`
- `cases/per_case/tandem_f40a3_phi0_r1/tandem_f40a3_phi0_r1_case.m`
- `+tbl/+periodic/run_case.m`
- `+tbl/+periodic/plot_products.m`
- `+tbl/+periodic/product_catalog.m`
- `+tbl/+periodic/write_diagnostics.m`
- `+tbl/+periodic/write_machine_summary.m`
- `+tbl/+periodic/make_final_reuse_config.m`
- `+tbl/+viz/export_publication_figure.m`
- 产物：`png/fig/eps/emf/pdf/mat/csv/json/md` 各目录、`csv/12_product_manifest.csv`
- 测试：`tests/test_periodic_piv_core.m`、`tests/test_singlecase_figure_style_contract.m`

【不要重复 / 不要做】
- 不要把预览图当正式产物保存。
- 不要用 `print(` 代替 `exportgraphics`/`savefig`。
- 不要改变 P01–P20 编号或 P20 的 `DEFERRED` 语义。
- 不要删除旧输出、`_cache` 或 `archive`。

【下一步】
1. 阅读 Section 9 相关函数和测试。
2. 联网检索 MATLAB 出版级导出和清单/摘要最佳实践。
3. 独立写出新的 Section 9 实现与合成导出测试。
4. 运行相关测试并输出新旧对比评价，等待人工审阅。
5. 审阅通过后回写并更新依赖、测试和 README。
