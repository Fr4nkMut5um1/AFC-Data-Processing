# P1 主脚本分节与工作区生命周期

本报告记录 P1 主脚本小批的静态实现，未运行 MATLAB。后续 P2 会在这两个脚本上继续把 sources 改成明确的本地 repeat 序列、替换 bootstrap 并接入新的 S4 文件接口；以下并非宣称原布局现在已独立。

改动文件：两个 `cases/per_case/*/*_case.m`；新增 `lib/+tblR2/workspace_results.m`；新增 `tests/r2/test_workspace_results.m`。检查记录为 `P1_MAIN_STATIC.json`。

## 改变的行为

- 真实补齐 `%% 1`、`%% 2`，0–9 各只有一个节标题。Section 0 中没有缓存加载、DAT 源探测、统计或图形调用；原源恢复/探测段暂移到 Section 1，P2 将用明确 sources 完全替代。
- 去掉 `clearvars` 和 `clc`。`results` 只在首次或 case/脚本/输出目录改变时初始化；相同 Section 0 重跑保留已有数组。无法证明归属的旧 `results` 明确报错，请用户自行保存后明确清除该变量。
- 每节入口检查 cfg、paths 与结果归属，并比较实际执行脚本路径（兼容 `.m` 后缀；`mfilename` 为空时取编辑器当前文件），避免同 case 的另一个复制目录误用旧工作区。
- `workspace_results` 仅管理会话内证据，不运行、加载或保存任何科研阶段。记录已接受的参数、输入/结果文件存在性及大小/修改时间、已知父结果版本。下游发现参数改变、文件替换、父结果重新处理或缺记录时明确指向对应 Section；不会自动启动上游。
- 每节尝试计算/读取之前先撤销该产物的旧会话记录；失败不能让旧数组以“刚完成”身份继续使用。
- Section 4 的伪 `statistics`/`phase`/`mean_bl` 数组入口移除，改为 PostProc 与 mean_bl 文件。若当前工作区已有 mean_bl 的过期证据，不允许绕过它读取旧文件；没有该数组时依旧支持明确文件入口。S4 四参接口与 P2 适配器由集成时一并提交。
- Section 6–8 各自显式设置 PostProc 缓存路径，并在真正使用前提供缺输入提示。现行 total 谱/模态/相关性消费者不需要 phase 数组；仅 controlled 沿程谐波与 LCS random 分支保留真实 phase 要求。
- Section 9 根据实际记录给出 `completed/skipped/not_run/stale`，未运行的 compute/reuse 不再从配置直接冒称完成；只运行部分节时报告 `partial`。旧错误清单仍保留。

## 保持的行为

当前主脚本参数赋值逐行保持，包括 B 的 figures=skip、C 的 figures=compute，两份 transport=skip；正式 6000/12000、24箱/min20、各自 marker_stride 等均未修改。没有修改科学核心、缓存帧顺序、repeat、类型、公式、S2/3旧口径、S3的 PostProc 相位计算条件或绘图主体。

静态逐块比较确认：S2 statistics 分支、mean_bl 分支和 S3 phase 分支与原附件文本完全一致；S3 实际绘图块仅增加输入守卫，其余逐行相同，包括 controlled 的额外 PostProc 相位计算条件与调用。此文本证据不代表 MATLAB 数值或图形已经验收。

## 工作区记录的证据边界

`accepted_cfg` 是本次计算/读取时的配置；对旧 `load_result` 读取，它绝不是历史生产配置。旧 MAT 仍只有原最小 case/stage/grid/frame/fs 合同，读取时发出 `LegacyContractLimited` 警告并明确完整合同留待 P5。不会给旧 MAT 盖新章、写回元数据或静默声称完全兼容。

会话内文件 size/mtime 检查不是逐帧内容哈希，不能证明人为保持相同大小和时间的替换；未引入全速度扫描。字段组中的部分配置检查有意保守（例如完整 friction/structures 组），后续精确计算/绘图合同分离属 P3/P5；不存在自动重算。

S4 没有已知工作区 mean_bl 时的历史文件参数身份不足、旧 S2/3 持久化复用身份不足、S4 自动 run 复用参数不足，均仍是 P5 的独立风险，不能用本批工作区检查声称解决。

## 各节入口

| Section | 主要调用与依赖 |
|---|---|
| 0 | 本地路径/参数、`build_paths`、`workspace_results(init)`；不读速度 |
| 1 | 当前源声明/恢复 → `validate_config` → `prepare_sequence_cache(raw/postproc)` → `validate_dual_source_grid`；P2改明确源 |
| 2 | compute 要求本节所选缓存的当前工作区记录；`mean_stats_cache`或`load_result` → `mean_bl_friction`或`load_result` → 原预览 |
| 3 | compute 要求 raw 缓存/statistics；`phase_stats_cache`或`load_result`；预览要求当前 statistics/mean_bl/phase；controlled额外PostProc相位调用仍可见 |
| 4 | PostProc缓存＋已保存mean_bl文件 → `section4_vlsm_analysis`；复用仍按旧`load_result`，警告合同限制 |
| 5 | 本case cfg＋paths → `section5_run`；不要求2/3/4工作区结果，缓存完整检查由同批独立validator补丁承接 |
| 6 | 当前statistics/mean_bl＋显式PostProc → 原total时域/空间谱；reuse可独立读取 |
| 7 | 当前statistics/mean_bl＋所选缓存 → 原POD/DMD/SPOD/LCS；仅LCS random要求phase |
| 8 | 当前statistics/mean_bl＋显式PostProc → 原total相关性；controlled harmonics要求phase及所有实际已有可选输入当前有效 |
| 9 | 原绘图函数与错误清单；绘图前检查已有输入，摘要按真实会话状态编制 |

## 验证记录

- 通过：上述源文本定向比较、原参数赋值比较、0–9标题唯一性、Section 0调用范围静态检查。未调用 record smoke，未修改 smoke_expected。
- 未执行：`test_workspace_results`。已按函数入口编写，覆盖相同初始化保留、case/复制脚本归属、参数/第二repeat offset/S4 rank/exclusion变更拒绝、父结果版本变化、失效记录、文件变化与纯图形DPI不影响统计记录。调用方式见文件头；它不是编辑器分节测试。
- 未执行：MATLAB编辑器 Run Section 0、0→5、缺输入、B→C/同case复制目录切换。环境没有 MATLAB，未使用 Python/Octave 代替 MATLAB。静态标题扫描不能验收上述行为。
- 未执行：正式数据、全图组、S4完整尺寸及正式raw/postproc S5图组。该批未运行任何科研数值计算。

停止点：主脚本与工作区守卫完成静态实现，交接 P2 集成。只需在具备 MATLAB 的环境运行相关小测试及编辑器分节检查；失败只定位关联路径。不扩大到全仓库测试或正式结果保真结论。
