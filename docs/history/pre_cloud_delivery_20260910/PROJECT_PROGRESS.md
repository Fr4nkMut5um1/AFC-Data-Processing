# 当前维护状态

更新：2026-09-10。2026-09-06 的结果与测试记录保留如下；本轮没有全量重跑。

## 2026-09-10 网页端审查交接

- 本轮只保存进度、汇总现状、制作代码与小样本 ZIP，不改现行 case/lib 算法或原 output。
- 下一轮目标调整为：每个 case 文件夹内一个 MATLAB 主脚本＋本地函数库，便于复制、独立运行和非程序员调参。
- Section 1–4 以及现行 Section 5 的结果/图形效果优先保护；不借架构重构改变数值定义，不新增复杂框架或反复校核。
- 完整本轮决策、未完成项、架构地图、保真边界与提示词见 [2026-09-10 交接](docs/handoffs/review_20260910/START_HERE.md)。包内 `validation` 区分历史证据与本轮样本验证。
- 21 图已按 ASCII 路径展示，用户确认可显示。此前 Word 合并失败，未作为完成成果；本轮最终交付改为一个 ZIP 和一段提示词。
- 本轮包内四份真实缓存切片与原帧逐值一致；MATLAB R2022b 小样本回读比较通过。只验证交接样本覆盖的计算路径，不代表全量重算。

- 日常入口：`tandem_baseline_r2_case.m` 和 `tandem_f40a3_phi0_r2_case.m`。
- 共享库：`lib/+tblR2`、`lib/+d23`；原命名空间保留。
- 现行 case 目录、case_id、正式 output 和缓存位置保留。
- 旧 r1、根旧入口与 `+tbl` 已归档，只维护追溯与恢复能力。
- 目录迁移、路径修正与验证已完成，共记录 113 项文件或目录迁移。
- Section 5 已按 raw 默认、postproc 可切换完成独立计算与图表交付；没有跨工况对比。

## Section 5 交付

- 两个 case 各完成 12,000 帧 raw 计算与严格复用校验。
- baseline：6 张 PNG + 6 张 FIG + 3 张 CSV；controlled：15 张 PNG + 15 张 FIG + 4 张 CSV。
- 各自输出位于 `output/section5/raw/`，配套 MAT、来源合同和 JSON 数值复核记录。
- 同源有效样本、逐 repeat 分解、H=0 象限贡献和统一时均梯度生产项均通过闭合检查，相对残差约为 1e-15。
- 6 个相关 MATLAB 测试脚本及 Python 检查通过；21 张最终 PNG 已完成视觉检查。
- postproc 切换和独立保存通过合成缓存验证，本轮未全量生成 postproc 图表。

运行与定义见 [Section 5 说明](docs/SECTION5.md)，完整证据见
[交付复核记录](docs/SECTION5_REVIEW_20260906.md)。

## 目录整理验证

- MATLAB 当前测试共 41 项：首轮 40 项通过，1 项旧标题格式合同修正后单独复跑通过。
- Python 静态结构检查：229 个 MATLAB 文件通过；数值接口检查通过。
- 两个 r2 的 raw/postproc 网格校验、统计/边界层/结构结果只读加载通过；受控相位结果加载通过。
- 113 项迁移目标均存在，Git 显示为移除的原跟踪文件均能在对应新位置找到。
- 独立复核未发现共享库解析、核心依赖或计算资源缺失；`git diff --check` 通过。

目录整理阶段没有完整重算 12,000 帧流程，也未全量重导出结构图。后续仅 Section 5 做了上述独立重算。
专题研究工具仍可能依赖原 `tmp` 数据、指定历史 run 或外部运行时，见工具目录说明。

入口与运行方法见 [README](README.md)，分类依据见
[架构说明](docs/ARCHITECTURE.md)，逐项移动见
[迁移记录](archive/reorganization_20260906/README.md)。

原进度文档完整保存在
[PROJECT_PROGRESS_before.md](archive/reorganization_20260906/PROJECT_PROGRESS_before.md)，
其中旧日期的“当前状态”和旧入口运行要求作为历史记录保留。
