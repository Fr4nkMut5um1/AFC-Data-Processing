你正在接手一个进行中的“周期法向表面变形主动流动控制 PIV 数据分析 MATLAB 程序”任务。请按以下上下文继续；不要重新讨论已经确定的总体架构。若本提示与当前工作区证据冲突，以当前文件为准，并说明冲突。

【用户目标】
按“独立重写 → 新旧对比 → 人工审阅 → 回写”流程，完成本 section 的代码评审与改进，并保持既有架构与产物合同。

【工作目录】
D:\Users\Frank_7840HSw\Desktop\202605实验快反计算\Current_Plate_Calculation

环境为 Windows PowerShell 5.1、MATLAB R2022b。工作区非常脏，存在大量用户历史修改、删除和未跟踪文件；相关 `+tbl/+periodic/`、两个周期 case 目录、测试和 `third_party/` 均为未跟踪或已修改状态。禁止 reset、checkout、清理或覆盖无关改动。

【本轮目标：SECTION 1 独立重写与回写】
不依赖本对话的既有实现记忆，由你作为新 agent 背靠背地独立重写“Section 1：加载 DAT 并建立/复用序列缓存”代码，并完成测试、新旧对比、人工审阅后回写。

流程：
1. 阅读当前 case 脚本 Section 1 与 `+tbl/+periodic/prepare_sequence_cache.m`。
2. 联网检索 MATLAB 大文件磁盘缓存、`matfile`、`-v7.3`、Tecplot DAT 解析、清单校验、缓存指纹/合同校验等可复用轮子或最佳实践。
3. 在草稿中独立写出新的 Section 1 实现，并用合成 DAT 或现有缓存做只读验证。
4. 对比新旧实现优劣，输出对比评价，供人工审阅。
5. 根据人工意见修改。
6. 测试通过后写回 case 脚本，并同步更新共享函数、测试和 README。

【必须遵守的要求】
- [verified] Section 1 的正式产物是 `results.cache` 和实际缓存文件路径；新缓存写入 `mat/01_sequence_cache.mat`，旧 `_cache/sequence_cache.mat` 只读复用。
- [verified] 首次运行会读取 DAT；验证阶段不跑真实完整 3000/6000 帧重算，除非人工明确要求。
- [verified] `cfg.stages.cache` 只允许 `compute` 或 `reuse`；`reuse` 在缓存不存在时创建，`compute` 强制重建。
- [verified] 缓存必须包含 `U`、`V`、`sampleValid`、`X`、`Y`、`h_mm`、`frame_ids`、`source_grid_size`、`j_wall_removed`、`cache_meta`，且 `cache_meta.schema_version=1`。
- [verified] 必须写 `csv/01_source_manifest.csv`，记录 `B####.dat` 清单。
- [verified] 缓存读取使用 `matfile` 和 `read_cache_chunk`，不得一次性载入全部帧。
- [verified] 不删除旧输出、不迁移大缓存、不修改 `archive`。

【已确认事实与决策】
- [verified] Section 1 当前实现位于 case 脚本内调用 `tbl.periodic.prepare_debug_cache(cfg, paths)`，最终调用 `tbl.periodic.prepare_sequence_cache`。
- [verified] `prepare_sequence_cache` 先检查 `cfg.data_root`，生成 DAT manifest，再按 `rebuild_cache` 决定复用新缓存、复用 legacy 缓存或重建。
- [verified] 重建时逐块 `tbl.io.load_tecplot_dat`，校验坐标和 `j_wall_removed` 不变化，写入单精度 `U/V/sampleValid`。
- [verified] 复用验证只读检查 schema、case_id、data_root、n_frames、fs、grid_size 和数组尺寸；不匹配时抛 `CacheContractMismatch`。
- [verified] baseline 旧缓存 3000 帧、f40a3 旧缓存 6000 帧已在当前环境验证可只读复用。
- [inferred] 新实现应继续使用 `tbl.io.load_tecplot_dat` 和 `tbl.singlecase.dat_manifest`，不要重写 DAT 解析。

【已完成】
- `prepare_sequence_cache.m`、`prepare_debug_cache.m`、`build_paths.m`、`read_cache_chunk.m` 已存在并通过测试。
- 真实旧缓存只读复用验证通过。

【未完成 / 待验证】
- 尚未按本流程做 Section 1 的独立重写、新旧对比和人工审阅。
- 大缓存断点续算、部分缺失缓存、陈旧缓存变量缺失等边界行为没有专门测试。

【关键文件 / 命令 / 产物】
- `cases/per_case/tandem_baseline_r1/tandem_baseline_r1_case.m`
- `cases/per_case/tandem_f40a3_phi0_r1/tandem_f40a3_phi0_r1_case.m`
- `+tbl/+periodic/prepare_sequence_cache.m`
- `+tbl/+periodic/prepare_debug_cache.m`
- `+tbl/+periodic/build_paths.m`
- `+tbl/+periodic/read_cache_chunk.m`
- `+tbl/+io/load_tecplot_dat.m`
- `+tbl/+singlecase/dat_manifest.m`
- 产物：`mat/01_sequence_cache.mat`、`csv/01_source_manifest.csv`
- 旧缓存：`cases/per_case/tandem_baseline_r1/output/mat/01_sequence_cache.mat`、`cases/per_case/tandem_f40a3_phi0_r1/output/mat/01_sequence_cache.mat`
- 测试：`tests/test_periodic_piv_core.m`、`tests/test_refactor_shared_helpers.m`

【不要重复 / 不要做】
- 不要重新设计缓存目录规则或 P01–P20 产物清单。
- 不要把 `load_tecplot_dat` 解析逻辑复制进 Section 1。
- 不要在验证阶段重建真实 3000/6000 帧缓存。
- 不要删除 legacy `_cache/sequence_cache.mat`。

【下一步】
1. 阅读 `prepare_sequence_cache.m` 与两个 case 脚本 Section 1。
2. 联网检索 MATLAB 大文件缓存和合同校验最佳实践。
3. 独立写出新的 Section 1 实现与合成/缓存复用测试。
4. 运行相关测试并输出新旧对比评价，等待人工审阅。
5. 审阅通过后回写并更新依赖、测试和 README。
