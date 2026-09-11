# MATLAB PIV 项目审查交接包

快照日期：2026-09-10。用途：网页端 chat 模式的代码与架构审查；后续可在具备 MATLAB 的环境中做小样本修改测试。

## 先读哪些文件

1. `handoff/USER_REQUIREMENTS.md`：用户本轮要求，优先于旧文档的组织约定。
2. `handoff/PROGRESS.md`：本次对话完成了什么、哪些尚未完成。
3. `handoff/PROJECT_MAP.md`：主程序、库、配置、依赖和已知耦合。
4. `handoff/PRESERVATION.md`：Section 1–4 和现行 Section 5 的保护边界。
5. `handoff/TEST_DATA.md`：小样本用途、限制和最短运行命令。
6. `project/cases/per_case/` 两个 r2 主脚本，然后按 Section 有选择地读 `project/lib/`。

不要从 archive、旧报告或数十个研究脚本开始漫无目的地阅读。先理解日常入口和真实科学计算，再决定简化哪些组织代码。

## 包的组织

```
project/              当前代码的原路径快照：cases / lib / third_party / tools / tests / docs
handoff/              本轮目标、进度、架构说明、保护边界、提示词
fixtures/             baseline/control 各 raw/postproc 的小样本、原配置和参考数值
reference_outputs/    已有图、CSV、JSON 摘要（仅选定产物，不是完整 output）
validation/           小样本运行入口、环境与已执行记录
provenance/           文件清单、依赖索引、参数索引、原位置和日期
```

`project` 是当前实现的忠实快照，不是已经重构好的目标架构。用户要求的未来形态是每个 case 文件夹内一个可编辑 MATLAB 主脚本加本地函数库。本轮只交接，不改变算法。

包里不含完整实验数据、全量缓存、巨型 POD 中间量、完整结构目录、Git 对象、论文草稿、个人工具配置或凭据。例外只有明确标记的少量测试样本和轻量结果参考。

不要直接运行原主脚本：它们保持原有参数、外部数据盘位置和 Section 4 compute 开关。云端先用 `validation/run_review_smoke.m`。其通过只说明小样本路径正常，不能宣布全量结果保真。

正式结果来源与版本可能不同，尤其 baseline Section 4 的已存导出早于最新绘图逻辑。看原产物日期，不要把所有图片误当作同日重算。

## 预期审查产出

一份能直接指导下一轮实现的具体评审：当前执行图、最有收益的简化项、建议目录树、保留/合并/移动函数表、参数组织示例、最小迁移顺序和有限验证计划。引用真实文件与符号；区分已观察事实、推断和待确认事项。不要新增通用框架，不要在本轮直接重写科学算法。
