# 当前任务进展

更新：2026-09-10，版本 `r2-local-20260910-cloud`。
**本轮可在云端完成的源码整理、定向静态核对和交付说明已完成；MATLAB 动态及正式数据验收未执行。**
这不是“全部正式结果已验证一致”的版本。

## 分批完成情况

| 批次 / 提交 | 改动文件或主要符号 | 结果与范围 |
|---|---|---|
| P0 / e77f07e | 原 project 入库；参数、保存身份、保护哈希记录 | 原 ZIP/源码/expected 保留；发现 baseline 旧 BL 与当前剖面参数不同 |
| P1a / 63e83d3 | validate_sequence_cache、section5_run | 独立 S5 只校验所选缓存；保留全部 repeat/fs/帧数/源/坐标约束 |
| P1b / 7ec3cb9 | 两主脚本、workspace_results | 真实 %%0–9；轻量 0；归属与过期检查；不清空已算结果、不自动跑上游 |
| P2 / 059d470 | 每 case 本地 lib/third_party、require_case_library、S4 接口 | 取消日常父目录依赖；明确 3rd→2nd 输入；S4 显式 PostProc+mean_bl 文件 |
| P3 / 2075ffc | 两主脚本、参数表、S4 配置适配、S5 维护入口 | 单一重建开关、去重复入口、外提原值常量；不激活原无效参数 |
| P4 / e3d52db | plot_section3_preview、两主脚本 | 搬实际 S3 绘制；PostProc 相位计算条件留在主脚本；保留错误清单 |
| P5a / 75db40d | save/load_result、result_parameters/inputs、sequence_cache_identity | S2/BL/S3 参数与父输入合同；缺身份或失配报具体差异 |
| P5b / 8b69fbe | section4_run_contract、select_section4_run、S4 适配 | 本 case 候选、完整计算/源身份、明确 resume 优先；展示变化保留等价中间产物复用 |
| 定向收尾 / 37bcfe0 | phase 合成发布 fixture、旧布局断言、load_result 差异文本 | 科学断言与阈值不改；只修相关接口与定位问题 |
| 当前交付整理 | START_HERE/README/架构/进展/交接、verify_cloud_static.py、当前映射 | 纠正旧共享库与历史成功指引；旧文档原样另存；MATLAB 源码未再修改 |

逐批行为、调用链和验证边界见 change_records/P1_*.md、P2_*.md、P3.md、P4.md、P5A.md、P5B.md、CLOUD_DELIVERY.md。

## 保持与未扩大的范围

S1–4 原统计/相位/BL/拟合、帧序、repeat、坐标、单位、类型与 d23 数学核心未替换；
所有 51 个 d23 文件保持原字节。S5 同源有效域、逐 repeat 分解、实际样本加权、共同时均梯度主剪切生产项、
严格 H 大于、符号/概率分母/NaN、闭合、源文本哈希与原子保存保留。
transport_statistics 没有用于 S2/3。B 最终 figures=skip、C=compute，两份 transport=skip。

没有修旧 repeat_means、S3 分母或相位源的科学疑点；没有更换 POD 算法或降低正式门槛。
没有进一步拆 S2 绘图、重设计 S4/S5 图形，也没有实施可选的 S5 哈希/无关 friction 字段精简。
这些属于保留或另议事项，不是已完成项。S6–9 没有扩展到 P5 的新生产合同范围。

## 真实验证状态

| 项目 | 状态 | 证据或待验收边界 |
|---|---|---|
| 原件文件完整性 | 静态通过 | 469 个原件文件 SHA-256；旧 expected 未覆盖 |
| 原算法与资源 | 静态通过 | 每 case 164 个原 lib 文件原字节、全部 51 个 d23、Cf_chart/piDMD/LICENSE；其余变更逐文件列明 |
| 改动 MATLAB 文件静态解析 | 已有记录通过 | 37 文件 MISS_HIT；不是 MATLAB checkcode、执行或数值测试 |
| 参数/实际 S3 绘图体/S4 默认配置/原 smoke 容差 | 静态通过 | change_records/P3_P5_STATIC_CHECK.json；参数表不是运行后 cfg dump |
| 当前可重复文件与目录检查 | 静态通过 | change_records/CLOUD_STATIC_CHECK.json；仅字节、文本和资源完整性 |
| Run Section 0、0→5、case 切换与过期报错 | 未执行 | 必须在 MATLAB 编辑器实际操作；不能用 %% 扫描代替 |
| 小 MAT 身份与 S4 候选/resume 测试、相关 smoke | 未执行 | 各 case/VALIDATION.md 按脚本/函数类型调用 |
| S3 相同 MAT 重画与数据/样式核对 | 未执行 | 需要确认的正式 MAT；不得为重画自动从 DAT 重算 |
| 正式 S4 12000×89×640 相关段一次对照 | 未执行 | 短 POD smoke 不能替代；需完整 POD/目录/筛选/帧与计数对照 |
| 正式 S5 raw：B6/C15 PNG 及 FIG/CSV | 未执行 | 原 ZIP 只有历史 PNG、CSV/JSON，无正式 S5 MAT/FIG；wrapper 测试不等于图组验收 |
| 正式 S5 postproc 图组 | 未执行，单独验收 | 不能由 raw 历史结果或 smoke 填补 |

## 已知证据与待处理事项

1. baseline 保存 BL 的 profile_params=[240 320]，当前主脚本=[80 180]。可能影响 u_tau/Cf/壁单位和 S4 BL 输入；本轮未改旧结果、未盖新身份。
2. baseline 原 S4 图组是旧版本，不能作为“当前同代码同参数”参考。参考身份应在正式验收时另建。
3. 旧缓存/context/POD/catalog_index 的历史绝对路径仍需逐项核实。缺完整原件，未编写猜测性迁移工具；未来迁移须保留旧身份与逐字段记录。
4. SPOD 原 ZIP 未包含，当前默认 skip；启用需明确合法本地副本。

下一步按 [CURRENT_HANDOFF.md](docs/CURRENT_HANDOFF.md) 在可执行 MATLAB 的环境有限验收。
没有因为暂时缺环境而放宽 formal_required_frames 或科学 expected/容差。

## 历史记录

本次更新前根进展/README 等的原文位于 [历史副本说明](docs/history/pre_cloud_delivery_20260910/ARCHIVE_NOTE.md)。
其中 R2022b、41 项测试、正式 raw 图组与约 1e-15 闭合结果均按原日期理解，不代表本次云端执行。
