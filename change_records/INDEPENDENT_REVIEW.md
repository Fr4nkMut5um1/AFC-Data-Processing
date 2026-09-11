# 独立定向静态复核

日期：2026-09-10。复核者只读源码，通过消息把具体问题交给对应实现者修复；本文档是复核记录，不是 MATLAB 动态验收。

## 范围与依据

以原 ZIP 解压后的 `evidence/PIV_Review_20260910/project/` 为旧源码，对照 `work/project/`。先读根 START_HERE、handoff 的要求、进度、架构、保护与样本说明，再追踪本批缓存、Section 4 定位、Section 5 入口、主脚本分节及新增工作区守卫。未以报告替代源码，未改科学 expected，未运行原主脚本取 cfg。

## 本轮发现并要求修复的具体问题

以下行号按工作源码复核时版本定位，后续路径整合会平移主脚本行号；符号和语句可直接定位。

| 问题 | 证据与可能影响 | 最小修复及复核状态 |
|---|---|---|
| 工作区结构结果漏记真实 S4 参数 | `workspace_results/input_record` 原新增 structures 分支只列 `cfg.structures`，而 `section4_vlsm_analysis/resolve_section4_config` 实际消费 `cfg.section4`。改 exclusion、rank、length 后旧结构可被当作当前结果使用。 | 已补 `section4`、`instantaneous`；当前 `workspace_results.m` L149–152 可见。这是工作区防过期，不是旧 MAT 科学身份认证。 |
| total 路径新增了假 phase 前置 | 新主脚本初稿把 controlled 的 Section 6、7、相关计算统一要求 phase；`temporal_spectra_cache.m` L20、`spatial_spectra_cache.m` L24、`correlation_analysis_cache.m` L8 只在 random 分支需要 phase。 | 已去除 total 分支的强制 phase 依赖；仅 LCS random 与 controlled harmonics 等真实消费者要求 phase。工作区 parents 同步收窄。 |
| correlations 漏记所用的时间谱参数 | `correlation_analysis_cache.m` L61–64、L345–358 读取 `cfg.temporal.nfft/overlap_fraction`；仅记录 correlations 字段不能识别这些输入变化。 | 已在 `workspace_results.m` L175 补 temporal 参数。 |
| 同 case 的不同文件夹副本会混用工作区 | 原新增各节只检查固定 case_id、cfg/results 相互归属。同 case 复制后，在新文件直接 Run Section 可继续操作旧 cfg/output。 | 各节把当前 `mfilename('fullpath')` 交给守卫；`workspace_results.m` L10–28 对当前脚本路径和 cfg.script_file 做独立比对，缺可靠路径或不同副本立即报错。编辑器真实行为仍待 MATLAB 验证。 |
| 已知过期的 mean_bl 可被 S4 绕过 | S4 去除假工作区参数正确，但同会话已存在 mean_bl 记录、随后改拟合参数时，不应忽略已知过期证据而读取其旧 MAT。 | 已在两脚本 Section 4 文件入口前增加条件检查：已有 mean_bl 记录才 require；没有工作区对象仍可独立 0→4。独立旧文件完整身份仍属 P5 未完成项。 |
| 本地候选目录仍可能物理指向其他 case | 仅按字符串枚举本 run root，不足以保证符号链接候选的物理目录在本 case。 | 已在 `section4_vlsm_analysis.m` L372–381 打开候选 MAT 前核对 canonical 路径；错误位于候选 catch 之外，不会转为自动重算。 |
| POD 文件检查未覆盖其物理归属 | 初稿在 local run 下对两份 POD 文件只做 isfile，`run/pod` 为目录链接时仍可能读取外部旧数据；catalog 的 MatFile 已有物理路径检查。 | 已按同一合同补 `section4_vlsm_analysis.m` L595–607：每份 POD 文件 canonical 路径必须位于当前 run，缺失或越界均明确报错。未修改 POD 算法或重新绑定旧身份。 |

新增 `validate_config.m` L43–65 也做了定向复核：对两个 repeat 的 roots/ids 类型及 offsets 有限非负整数先检查，然后仅在对应性比较时分别去掉 `_PIV_`/`_PostProc_` 标记；原 ids 不被改写，顺序不被排序，offset 不被猜测。这适配原源码保存的完整目录名 ids；不是把仅第一 repeat 的偏移检查误当整个序列对应。

## 不应当写成已经解决的旧问题

1. `section4_vlsm_analysis/find_reusable_run` 当前仍按 COMPLETE、case、帧序、POD 标记/能量筛候选，加载了 config 却没有比较完整有效计算参数与父输入身份。原源码同名函数已存在此缺口。本批只本地化路径，不代表排除区、长度、连通性变化后可安全复用。
2. 自动查找仍先于 `d23.initialize_run`；显式 resume 可被其他完成 run 抢占。原 `d23.initialize_run.m` L4–16 才执行 resume 的 config/source 合同。属于已声明留给 P5 的独立修改，不能被“本 case 路径检查通过”掩盖。
3. `load_result` 的旧磁盘合同不完整。工作区记录的 accepted_cfg 是本次接受对象时的配置，不能证明旧 MAT 的生产配置；当前守卫已显式写出这个区别并警告。独立 0→4 的 mean_bl 旧文件身份同样未由本批认证。
4. 本地 source 配置与旧缓存的 source_root/repeat_roots 不同会被新 validator 正常拒绝。没有经核实的正式数据迁移记录，不能声称旧正式缓存直接复制到新目录后已经能够离线复用。不得整体改写旧路径或给旧结果重新盖身份章。

## 已执行的有限检查

| 检查 | 真实结果与界限 |
|---|---|
| 63 个核心/资源文件原新字节比较 | 通过：51 个 `+d23` 文件及 mean_stats_cache、mean_bl_friction、phase_stats_cache、transport_analysis、transport_statistics、quadrant_streaming、gradient_y_sensitivity、transport_figures、section4_vlsm_figures、read_cache_chunk、read_cache_frames、assign_phase 均字节相同。仅证明这些文件未改；不能据此推断整个调用链的正式数值一致。 |
| 四份 fixture 的 HDF5 元数据只读检查 | cache_meta 含新增 validator 要求的字段；保存的 Y 与记录的 `(1:89)*h_y_mm` 精确一致；壁面裁掉 2 行；repeat_means 维度换回 MATLAB 顺序为 `[2,2,89,640]`；data_root/source_root 相同。未读取重算 U/V 或替代 MATLAB 统计。 |
| MISS_HIT 定向语法检查 | 九个当时修改库文件检查通过。命令使用 `--input-encoding utf-8 --matlab 2022a`，因为工具最高支持 2022a。初次默认 cp1252 出现 UTF-8 回退警告；指定 2022b 被工具本身拒绝；明确支持目标后通过。这不是 MATLAB R2022b 的 checkcode 或执行记录。 |
| MATLAB / 编辑器 Run Section | 未执行。无 MATLAB。没有用 Python/Octave 运算替代，也没有把分隔符数量当作 Run Section 通过。 |
| 正式 S4 / S5 图组及 postproc 验收 | 未执行。缺正式输入及 MATLAB；短样本不会补齐正式 S4 或 S5 文件复用/原子保存/图组验收。 |

本轮只围绕已改路径提出上述问题，未要求新的阶段框架或展开全仓库测试。P3/P4/P5 以及正式 MATLAB 验收不能从本静态记录推断为完成。

## P2 最终目录整合复核

已直接复核两份 `work/project/cases/per_case/<case>/` 中交付形态的脚本和本地库，未继续改源码。结论：在上述明确保留的 P5 缺口之外，未发现这次路径整合的新静态阻塞问题。

- 两个脚本 Section 0 使用当前脚本的规范化目录构造 `lib`、`input`、`output`，不再调用 bootstrap、仓库上溯、DAT 编号/起帧探测。Section 0 的外部调用只有本地路径检查、纯配置检查、建立空输出子目录及工作区初始化；没有读取速度缓存、扫描 DAT、统计或绘图。真实 Editor Run Section 仍为未执行。
- 逐行锚定实际 `cfg.stages.*` 赋值后与原源码比较一致：baseline phase=skip / figures=skip；controlled phase=reuse / figures=compute；两者 structures=compute、transport=skip，其余当前模式不变。未用注释里的 `phase='skip'` 文字作为实际赋值。
- 两脚本 L84–101 附近明确列出完整目录名 ids，均为 3rd→2nd、两 source offsets `[0 0]`。baseline 的对应键为 `Tandem_Baseline_3rd/2nd`；controlled 为 `Tandem_f40A3_Phi+0_3rd/2nd`。新 validate_config 只在比较中去除源标记，能保持这两组实际对应与原 ids。
- Section 5 只把主脚本 cfg、paths 和当前模式交给 section5_run；不要求 Section 2/3/4 工作区结果。Section 4 保留显式四参调用。每节根据 compute/reuse/skip 条件检查会使用的本地函数；第三方只在启用调用时解析，未新增整仓库 genpath/savepath 或历史安装 fallback。
- 最终 prepare_sequence_cache 已移除 legacy_sequence_cache 回退，仍保留原逐 repeat 读取、分块、公式和类型。目录探测维护工具已移出日常 lib；日常库中没有对已移除 locator/resolver 的残留调用。`d23.default_config` 的历史路径文本仍在，但正式 S4 适配器在交给消费者前明确覆盖，未用该路径读取文件。
- 两份 case 的 176 个本地库文件逐字节相同。必要 `Cf_chart.txt`、piDMD 及 LICENSE 已在本地结构内；未发现引入伪 SPOD 实现。
- 最终两个主脚本及四个末轮更新库文件（validate_config、prepare_sequence_cache、section4_vlsm_analysis、workspace_results）再作一次限定 MISS_HIT UTF-8/2022a 语法检查，六文件通过。仅重查末轮变更，没有扩大为全库测试或宣称 MATLAB 验收。

可提交本 P1/P2 静态小批并停止扩展；下一门槛是记录中列明的真实 MATLAB 分节与相关正式输入验收，而不是继续依靠静态检查累加“通过”数量。
