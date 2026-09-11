# 当前架构与文件分类

更新：2026-09-10。以下主体描述 2026-09-06 整理后的现行实现；下一轮目标是每个 case 一个主脚本＋本地函数库，见 [最新交接要求](handoffs/review_20260910/USER_REQUIREMENTS.md)。未来设计以新要求为准，本轮未实施重构。

日常入口为两个 r2 工况；本文件说明当前目录职责，历史报告中的
路径和“当前版本”表述按报告原日期理解。

## 调用关系

```text
两个 r2 主脚本
  └─ cases/per_case/bootstrap_r2_case.m
       └─ lib/ 加入 MATLAB path
            ├─ +tblR2：缓存、统计、相位、谱、模态、相关和绘图
            │    ├─ +bl、+io、+viz：基础计算与显示
            │    ├─ +vlsmpod：保留的结构研究扩展
            │    └─ section4_vlsm_analysis / section4_vlsm_figures
            │         └─ +d23：PostProc 统计、POD-E50、连通域和结构筛选
            └─ 第三方：third_party/piDMD；外装 spod.m
```

`+d23` 已作为正式 Section 4 依赖维护，不能因最初来自实验目录而归档。
`lib/+tblR2/+bl/data/Cf_chart.txt` 是计算资源，随库保留。
共享库的命名空间与函数签名保持原样；工况配置仍写在主脚本中。

## 维护边界

| 位置 | 分类 | 使用方式 |
|---|---|---|
| `cases/per_case/*_r2/*_case.m` | 日常入口 | 参数、阶段开关与处理顺序 |
| `lib/+tblR2`、`lib/+d23` | 当前共享库 | 从 `lib` 加入路径，避免递归加入 archive |
| `tools/preview_section3.m` | 当前预览工具 | 从已有 f40A3 缓存重绘 review 图 |
| `tools/research/` | 专题研究工具 | 校准、扫描、历史算法对比；先查工具说明 |
| `tests/` | 当前验证 | r2/d23 合同与合成数据测试 |
| `docs/methods/` | 方法与文献资料 | 保留原研究结论和适用条件，不替代主脚本配置 |
| `docs/history/` | 历史结果与阶段记录 | 追溯参数和版本演变 |
| `docs/handoffs/`、`plans/`、`section_handoffs/`、`section_reviews/`、`adr/`、`superpowers/`、`test-reports/` | 原有专题记录 | 按日期查阅，不能整体视为现行操作规则 |
| `docs/figures/` | 报告配图 | 与引用它们的报告一起保留 |
| `archive/legacy_r1_20260906/` | 旧代码及配套数据 | 只保留查阅和恢复能力 |
| `archive/development_20260906/` | 一次性调试与旧试验 | 已被替代的图形探针、日志、试验图与自动备份 |
| `archive/reorganization_20260906/` | 迁移记录 | 原路径、新路径、类别与执行清单 |

研究工具仍可能使用 `tblR2.structure_analysis_cache`、`identify_structures` 或
`+vlsmpod` 等较早研究路径。它们与正式 Section 4 的 `d23` 识别链不同。
这些函数仍被研究工具或测试使用，因此保留在共享库中，未按“主入口未直接调用”归档。

## 数据位置与结果版本

两个 r2 的正式 `output`、缓存内容、case 身份和数值参数未因本次整理而迁移或重算。
MAT 内可能存有绝对路径；`output/section4_vlsm/runs` 与实验目录的
`output/runs` 都是当前复用逻辑会搜索的位置，保留原位。

`cases/experiments/deshpande2023_baseline/` 现在只保留独立研究入口、说明和原运行数据；
代码库已迁到 `lib/+d23`。独立研究入口有自己的默认配置，不能与 r2 主脚本的
POD-E50 设置混用。

整理前已核对的输出版本：f40A3 正式 Section 4 摘要为 2026-08-31，图像采用
8 邻域、每结构最高通过长度档。baseline 的现存正式图为较早导出版本。
文件位于正式输出目录并不自动意味着已经按最新绘图逻辑重新导出；应核对
`summary.json`、图像清单和 run 记录。

旧 r1 工况连同其输出进入归档。归档 MAT/JSON 中原路径作为历史证据保留，未批量
改写；将来恢复运行时需重新处理路径。原路径可以在迁移 JSON/CSV 中检索。

## 论文与本地工具资料

| 位置 | 用途 |
|---|---|
| `Draft/` | 正在维护的论文写作资料，独立于 MATLAB 运行目录 |
| 根 `output/` | 早期总体规划、论文/PDF及对比研究产物；不是两个 r2 的正式输出根 |
| 根 PPTX | 课题讨论材料，保留原位置供既有文档引用 |
| `downloads/`、`tmp/` | 下载和临时工作数据，部分研究工具会引用 |
| `.ai4scholar_tmp/`、`.codex-literature-cache/`、`.dsh-research/`、`.firecrawl/` | 文献与检索工具本地缓存/工作目录 |
| `.claude/`、`.reasonix/`、`.mcp.json`、`reasonix.toml` | 本地工具配置与状态 |

这些目录不作为“无效科研文件”处理。目录职责已标明，既有工具配置与写作链接保留。

## 维护约定

新工况沿用现行 case 目录结构，通过 `bootstrap_r2_case` 使用共享库，不复制函数库。
正式可重复验证放 `tests`；真实数据预览放 `tools`；参数扫描和研究假设试验放
`tools/research`；一次性调查结束后连同记录归入历史区。

修改库位置时须检查 bootstrap、`d23.default_config`、研究工具和测试中的路径。
移动数据时还要检查 MAT 中的缓存和目录分区索引；不能只替换源码字符串。
