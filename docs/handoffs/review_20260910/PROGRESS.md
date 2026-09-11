# 对话进度快照

记录日期：2026-09-10。状态基于当前磁盘核查和 2026-09-06 的已有验证记录；不得把旧测试通过写成本轮全部重跑。

## 已完成

- 日常入口确定为 `tandem_baseline_r2`、`tandem_f40a3_phi0_r2`；r1/根旧入口及旧 +tbl 已移入历史区，历史只维护追溯与恢复。
- 共用代码集中到 `lib/+tblR2` 和正式 Section 4 依赖 `lib/+d23`；两个 r2 与正式 output 原位保留。迁移记录列 113 项。
- Section 3 云图布局与剖面 marker 已调整，用户要求保留 Section 1–4 调好的效果。
- Section 5 采用独立的同源统计，raw 默认、postproc 可切换；每个 case 独立交付，无关键剖面跨 case 比较。
- 受控数据各 repeat 独立相位均值/时均分解后按有效样本合并；总、相干、随机同有效样本；共同时间均值梯度计算主剪切生产项。
- 已存两 case 各 12,000 帧 raw Section 5 结果：baseline 6 PNG/6 FIG/3 CSV；control 15 PNG/15 FIG/4 CSV，另有 MAT/JSON。
- 旧复核记录显示 H=0 与分解闭合相对残差约 1e-15；6 个相关 MATLAB 脚本与 Python 检查通过，21 PNG 视觉检查完成。
- 21 图已在本对话逐图解释。最初有路径缺段/图片工具输出不可见，改到 ASCII 展示路径后用户确认图片可以显示。

## 范围与尚未完成

- postproc 切换已做合成缓存测试；本对话没有全量 real postproc Section 5 图组。
- 目录整理没有完整重跑 Section 1–4 12,000 帧流程。Section 4 保真不能靠本次小样本包或目录存在来宣称。
- baseline 已有正式 Section 4 摘要日期为 2026-08-30，control 为 2026-08-31；它们不是本轮新计算结果。详见各产物原时间。
- 用户未明确逐张批准所有 21 图科学效果；“能够显示”只是显示成功。本次把现行结果作为重构保护基线，不伪造新的用户验收。
- 上一项 Word 合并任务在 PNG 签名检查时报错：`readUInt32BE(1)` 应检查第 4 字节起的签名；生成没有成功，分页也未验证。`tools/create_section5_guide.js` 属于未完成的文档工具，不是 MATLAB 依赖，不放入当前运行代码包。
- 最新需求是为自包含 case 脚本做架构 review，尚未实施新架构。
- Git 工作区存在大量整理带来的删除/新增，r2/lib 有未跟踪文件；包按磁盘实际现状制作，不用旧 HEAD 冒充当前代码。

## 本轮交接工作

本轮新增交接说明、打包工具、缩小的真实样本和样本参考运行记录；只读取原实验缓存与结果，不改变现行 case/lib 数值算法或原 output。最新测试范围和执行结果以包内 `validation/` 记录为准。

- 2026-09-10：四份真实缓存切片（两 case × raw/postproc，每份 48 帧、89×640 网格）已导出；U/V、sampleValid 和空间坐标与原缓存逐值一致，见 `validation/fixture_integrity.json`。
- 包内代码在 MATLAB R2022b Update 1 中回读样本，与修改前样本参考值比较通过，见 `validation/sample_check_report.json`；范围为 Section 2 核心统计、受控 Section 3 相位函数、两 source 的 Section 5 以及 Section 4 joint POD 数值核心。
- 本轮没有重跑 12,000 帧全流程，也没有重新生成正式图组。上述通过不扩大为完整 Section 1–4 保真结论。

## 下一步

网页端先读包审查：解释现有执行路径和参数位置，识别影响易用性的具体间接调用，给出单主脚本＋本地库方案及逐步迁移计划。经用户选定方案后再实施；科学算法修改作为独立事项。
