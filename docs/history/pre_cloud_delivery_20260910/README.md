# PIV 单工况数据处理

当前日常维护入口只有两个 r2 工况。打开对应主脚本，在 Section 0 调整参数和
`compute/reuse/skip`，再按 Section 顺序处理数据。两个工况共用 `lib/` 下的函数库。

| 工况 | 主脚本 |
|---|---|
| 串列基准 | [tandem_baseline_r2_case.m](cases/per_case/tandem_baseline_r2/tandem_baseline_r2_case.m) |
| 串列 40 Hz / A=3 mm 受控 | [tandem_f40a3_phi0_r2_case.m](cases/per_case/tandem_f40a3_phi0_r2/tandem_f40a3_phi0_r2_case.m) |

## 目录导航

```text
Current_Plate_Calculation/
  cases/
    per_case/
      bootstrap_r2_case.m          工况和共享库路径初始化
      tandem_baseline_r2/          主脚本 + 当前 output/
      tandem_f40a3_phi0_r2/         主脚本 + 当前 output/
    experiments/
      deshpande2023_baseline/      独立研究入口 + 可复用历史 run 数据
  lib/
    +tblR2/                       共享数据处理和绘图函数
    +d23/                         正式 Section 4 使用的识别算法
  tools/                          预览与专题研究工具
  tests/                          当前 r2 / d23 验证
  third_party/                    第三方算法及许可证
  docs/                           当前架构、方法资料、历史记录
  archive/                        旧流程、旧试验、一次性调试和迁移清单
  Draft/                          论文写作工作区
```

详细模块关系、数据位置与历史文件分类见 [架构说明](docs/ARCHITECTURE.md)。
[当前状态](PROJECT_PROGRESS.md)、[工具目录](tools/README.md)、
[测试说明](tests/README.md) 分别记录维护入口和验证方式。

## 运行

从项目根目录运行其中一个工况：

```matlab
run('cases/per_case/tandem_baseline_r2/tandem_baseline_r2_case.m')
% 或
run('cases/per_case/tandem_f40a3_phi0_r2/tandem_f40a3_phi0_r2_case.m')
```

也可在 MATLAB 编辑器中打开主脚本，先运行 Section 0，再按依赖顺序运行各节。
`bootstrap_r2_case` 会定位项目和 `lib/`，无需递归添加整个仓库路径。
不要对项目根目录执行 `addpath(genpath(pwd))`，以免将归档的同名旧函数加入路径。

运行前检查主脚本的阶段开关。当前配置复用 Section 1/2 缓存，受控工况复用
Section 3，Section 4 为 `compute`，其余阶段主要为 `skip`；完整运行可能重新导出
大量结构图。目录整理没有改动这些开关或物理参数。

| Section | 工作内容 | 主要实现 |
|---|---|---|
| 0 | 工况参数、路径和阶段开关 | 主脚本、`bootstrap_r2_case` |
| 1 | 双 repeat、raw/postproc 序列缓存 | `tblR2.prepare_sequence_cache` |
| 2 | 均值、Reynolds 应力、边界层和摩阻 | `tblR2.mean_stats_cache`、`mean_bl_friction` |
| 3 | 相位平均与三重分解 | `tblR2.phase_stats_cache` |
| 4 | POD-E50、8/4 邻域与超结构识别 | `tblR2.section4_vlsm_analysis` → `d23.*` |
| 5–8 | 输运、谱、模态、相关性 | `tblR2.*` 对应模块，按需开启 |
| 9 | 图像和结果汇总 | `tblR2.plot_products` 与主脚本汇总 |

基准工况的 Section 3 默认跳过。受控工况的应力剖面沿用统计数据源；相位云图
可独立使用 postproc。Section 4 使用自己的 PostProc 均值、POD 和检测 RMS。

## 数据与结果

Section 5 可独立运行，默认 raw，也可切换 postproc；每个 case 交付自己的图表。
使用 `addpath('tools/maintenance'); run_section5_from_saved_case('tandem_baseline_r2','raw','compute')`，
或将 case 名替换为 `tandem_f40a3_phi0_r2`。完整定义、复用规则与文件清单见
[Section 5 说明](docs/SECTION5.md)。

两个现行工况的目录、`cfg.case_id` 和 `output/` 路径保持不变。

- `output/mat/`：序列缓存与分节结果；已有缓存可用于数据盘离线时的复用。
- `output/section4_vlsm/`：当前 Section 4 摘要、目录、单结构图和运行记录。
- `output/section5/raw/`、`output/section5/postproc/`：同源输运统计、独立图表和数值 review 记录。
- `output/preview/section3/`：供人工 review 的相位云图和应力剖面。
- `cases/experiments/deshpande2023_baseline/output/runs/`：仍可能被 Section 4 复用的研究运行数据。

当前数据为双 repeat、每个 6000 帧。源盘位置、网格、频率、壁面参数等以各主脚本
Section 0 为准。需要强制更新时明确将对应阶段设为 `compute`。

## 环境与检查

项目使用 MATLAB；DMD 的 piDMD 位于 `third_party/piDMD`。SPOD 使用单独安装并加入
MATLAB path 的 `spod.m`，只在启用该阶段时检查。图形、连通域等所需工具箱以
当前 MATLAB 安装和具体测试为准。

```matlab
addpath('lib');
results = runtests('tests');
assert(all([results.Passed]));
```

```text
python tests/matlab_check.py
python tests/test_r2_extracted_modules.py
```

## 历史资料

旧根入口、r1、`+tbl` 及配套工具和测试位于
[archive/legacy_r1_20260906](archive/legacy_r1_20260906/README.md)。
它们用于查阅和恢复，不维护直接运行。历史报告不是当前操作说明。

本次分类与原路径映射见 [整理记录](archive/reorganization_20260906/README.md)。
论文、文献和本地工具状态保留独立用途，详见架构说明中的分类表。

旧 `tools/run_section5` 已移到 `tools/maintenance/run_section5_from_saved_case`，仅供旧布局维护。日常运行本 case 主脚本 Section 0→5；独立 case 的旧配置入口为 `maintenance/run_section5_legacy_config`，必须显式指定配置文件。
