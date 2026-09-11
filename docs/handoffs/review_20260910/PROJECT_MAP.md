# 当前项目、依赖与阅读地图

这是 2C–2D PIV、双 repeat 单工况 MATLAB 程序。当前采样 fs=960 Hz，受控 f0=40 Hz，每 repeat 6000 帧；缓存空间为 89×640，U/V 的 MATLAB 维度是 [frame,y,x]。原始配置网格为 [Nx,Ny]=[640,91]，去壁面行后得到缓存尺寸。不要混淆源网格与缓存网格。

## 主路径

| Section | 配置位置 | 主要调用和数据 |
|---|---|---|
| 0 | 两个 `*_r2_case.m` 的 A–P 参数区 | `bootstrap_r2_case` 定位第三方目录和 lib；`validate_config`、`build_paths`；原数据盘 J: |
| 1 | source_root、source 名、帧数、chunk、wall_side | `prepare_sequence_cache` → +io 文件读入/坐标/有效掩膜；raw/postproc 分别缓存；双 repeat |
| 2 | statistics_source/frame_mode、profile、loglaw、modern_clauser、friction | `mean_stats_cache` → `mean_bl_friction` → +bl/+wall；均值应力、剖面、厚度、u_tau、Cf；大量预览也在主脚本 |
| 3 | phase、phase_preview | `phase_stats_cache`；raw 统计路径与 postproc 云图路径分开；主脚本内三重分解剖面、`plot_phase_averaged_maps` 云图 |
| 4 | cfg.section4 及相关预览/结构参数 | `section4_vlsm_analysis` → d23 的 PostProc 统计、POD-E50、重建RMS、阈值、连通域；`section4_vlsm_figures` 独立出图 |
| 5 | transport、friction.hole_thresholds、figures.section5 | `section5_run` → `transport_analysis` → `transport_statistics`/`quadrant_streaming`/`gradient_y_sensitivity` → `transport_figures`；`tools/run_section5.m` 是专用入口 |
| 6 | temporal/spatial | 时间 Welch 谱、空间谱；默认主要 skip |
| 7 | pod/dmd/spod/lcs | POD、piDMD、SPOD、平面 FTLE 扩展；多为可选，不能冒称全部全量验收 |
| 8 | correlations/harmonics | 时空相关与谐波/沿程分析；按需开启 |
| 9 | figures/preview/export | `plot_products`、`plot_core_products` 及结果清单；Section 4/5 另有专门导出 |

精确函数所在文件、行号、直接包调用、参数赋值行见 `provenance/code_index.json`、`provenance/parameter_index.csv`。索引是静态词法线索（含注释/字符串可能的误报），不是动态覆盖证明。

## 文件职责

- `cases/per_case/`：两个现行入口＋一个 bootstrap。
- `lib/+tblR2`：日常处理、绘图及保留的研究扩展；其 +bl/+io/+wall/+viz/+pod 等包不能仅凭文件名当作独立架构层。
- `lib/+d23`：正式 Section 4 使用的数值与对象识别链，不能作为过时实验库删掉。
- `lib/+tblR2/+bl/data/Cf_chart.txt`：Clauser/Cf 计算表，是运行资源，不是实验序列，已包含。
- `third_party/piDMD`：MIT 许可代码及 LICENSE，已完整包含。
- `tools/research` 与 `cases/experiments/deshpande2023_baseline`：研究入口，可能依赖旧 tmp/run；供判定是否移出日常库，不保证开箱运行。
- `tests`：既有合成数据与代码合同测试，随包保留，不要求每轮全部运行。
- `archive`：旧流程不属于当前运行范围，包仅包含迁移文字清单；旧源码/输出、论文 Draft、下载缓存、个人配置和凭据都排除。

## 依赖

- 验证环境：MATLAB R2022b；精确版本和本机工具箱清单见 `validation/environment.json`。本机安装清单不是最小依赖声明。
- Image Processing Toolbox：正式 Section 4 的 `bwconncomp`、`regionprops`；可选图像预处理也使用相关函数。
- Curve Fitting Toolbox：Section 2 速度/动量厚度平滑的 `csaps`、`fnder`。不能随便用另一平滑器替换。
- Signal Processing Toolbox：启用谱/相关等路径时的 `pwelch` 等，按实际调用核对。
- 基础优化中有 `fminsearch`；不能仅凭“拟合”推断必须有 Optimization Toolbox。看实际函数。
- SPOD 的 `spod.m` 需外部安装；当前仓库未 vendored。`ensure_external_toolboxes` 只在启用对应阶段时检查；包不包含个人安装目录，也不做假替代实现。
- Python 仅用于静态检查/包读取，非 MATLAB 正式运算依赖。样本为标准 MATLAB v7.3/HDF5，可用 h5py 读取；不要将 HDF5 的逆序维度误当 MATLAB 顺序。
- 无 MATLAB 的云环境可审查代码和读取参考值，不能声称已经跑过 MATLAB，也不要默认 Octave 与工具箱/图形/MAT 接口等价。

## 应优先审查的耦合（不是现已证实的错误）

1. bootstrap/locate_repository_root 向上找 `third_party`，输出目录由 repo_root 拼接，与自包含 case 目标冲突。
2. 主脚本参数长且重复，参数路径很多；如何按 Section 留在一个可见位置，同时减少重复默认值。
3. load/save/validate/provenance 在多层出现；哪些有实际必要、哪些可以在单入口做一次。
4. Section 4 的历史 run 搜索和配置常量与绝对路径耦合；移动库和数据不能只替换字符串。
5. 旧通用 plot 流程与专用 Section 3/4/5 绘图并存；日常可见入口能否更直接。
6. 名叫 `*_memory_friendly`、缓存/分块代码保护真实大数据内存；它们不属于可以因“简洁”直接删除的防御代码。

先查核心路径，再追必要调用；不要把 6–8 节或研究支路都判为失效而删除。
