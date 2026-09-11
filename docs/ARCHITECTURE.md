# 当前架构与调用关系

当前版本 `r2-local-20260910-cloud`。运行状态见 [进展](../PROJECT_PROGRESS.md)。
两个 case 各有一个可编辑主脚本、本地 lib/+tblR2、lib/+d23 和 third_party；命名空间保留。
根 lib 是集中维护副本，日常 case 不从根 lib 或另一 case 取函数。

| 入口 | 显式输入与调用 | 结果 |
|---|---|---|
| Section 0 | 脚本自身位置 → 本地路径、cfg、workspace_results | 参数与结果归属；无统计/绘图/全缓存读取 |
| Section 1 | 两明确 repeat 的 raw/PostProc roots/ids/offsets → prepare_sequence_cache | 原顺序缓存；离线复用只读核验 |
| Section 2 | 所选缓存 → mean_stats_cache → mean_bl_friction | 原 S2 统计与 BL；save/load_result 记录生产参数和父身份 |
| Section 3 | 原统计及 raw 相位 → phase_stats_cache；C 的 PostProc 云图准备仍在主脚本 | plot_section3_preview 承载实际绘制并返回错误清单 |
| Section 4 | section4_vlsm_analysis(postproc_cache,cfg,mean_bl_file,result_file) → d23 原计算链 | 本地 run/POD/目录与专用图组；不需 stats/phase/mean_bl 工作区参数 |
| Section 5 | cfg+paths → section5_run → 所选缓存 validate_sequence_cache → transport_analysis/figures | raw 或整体 postproc；本 case 独立 MAT/图表/复核记录 |
| Section 6–9 | 原相应模块与显式阶段开关 | 算法未重构；不作为本轮已动态验收范围 |

## 输入身份和复用

validate_sequence_cache 检查所选缓存的 fs、实际尺寸、帧/边界、全部 repeat 根/ID/offset、源及坐标约束，
不读取全部 U/V，不要求另一源或 DAT 在线，不把正式尺寸常数写进短样本核心。
主脚本只在实际需要的节点校验本地 which；发现其他 case 同名依赖停止，不重置用户工具箱路径。

工作区产物有 case/路径归属、参数与父输入记录，变量存在不等于可用。
S2/BL/S3 磁盘复用由 result_parameters、result_inputs、sequence_cache_identity 与 load_result 检查。
参数或父输入不一致时报具体差异，缺必要旧身份不直接补章。

S4 只在本 case 寻找 run，select_section4_run 优先处理明确 resume，使用原 d23 恢复合同。
section4_run_contract 区分计算与展示：源、POD、exclusion/length/connectivity 等参与计算身份；
匹配 run 的展示参数变化不使 POD 重算。仍保留严格 12000×89×640 和原 fast_in_memory 算法。
没有调用 d23.run_experiment 替代现行链，也没有 experiments fallback。

## 文件职责

| 位置 | 用途 |
|---|---|
| cases/per_case/<case>/ | 可独立复制的日常目录；自身 input/output/lib/third_party/maintenance |
| 每 case PARAMETER_MAP.csv / PARAMETER_GUIDE.md | 当前唯一参数入口、原位置、值、消费者和可调性 |
| 每 case maintenance/checks | 有限 MATLAB 测试；遵照每文件头部的调用类型 |
| 根 lib / tests / tools | 集中维护及保留研究代码；不是日常 case 的运行依赖 |
| validation / change_records | 只读静态核对、原 smoke 的 check 适配、逐批证据与映射 |
| docs/history / handoffs / section_reviews 等 | 原日期的研究与交接材料；不能整体当当前操作说明 |

Cf_chart.txt 和 piDMD/LICENSE 随每 case 保留。SPOD 缺省不提供；只有用户明确本地合法副本时可启用。
不使用全仓库 genpath/savepath，不向上搜索源仓库。

旧 MAT 的 source_root、provenance、context/POD 路径与 catalog_index.MatFile 仍是原身份记录。
只有完整原件可核实同数据时才可做一次性迁移，不整体字符串替换、不关闭校验、不把重算产物冒充旧件。
历史结果边界见 [P0](../change_records/P0_EVIDENCE.md)。
