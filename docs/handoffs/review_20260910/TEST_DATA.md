# 小样本与云端运行

## 内容

- baseline 与 controlled 各有 `raw.mat`、`postproc.mat`。
- 每份保留原缓存完整 89×640 空间网格，不做空间降采样、平滑或重建。
- 原始缓存帧号为 `[1:24, 6001:6024]`，即每 repeat 一个 40 Hz 周期；包内重新编号 1:48，repeat 边界改为 24，`source_frame_ordinals` 保存原帧号。
- U/V 原值及 single 类型、sampleValid 掩膜和原坐标保留；仅元数据帧数/路径/边界适配小样本。repeat_means 按既有 Section 1 plain mean 方式重新计算，未偷用 12,000 帧均值。
- 另含 `configuration_original.mat/json`、`full_run_reference.mat` 和 `smoke_expected.mat`。原配置保留供审查，不能直接认为它能跑短样本。

## 最短 MATLAB 命令

在 ZIP 解压后的根目录：

```matlab
addpath('validation');
run_review_smoke;
```

默认依次处理两 case，不并行开多份 MATLAB。不扫描原实验盘、不调用原主脚本、不启动完整 Section 4，不渲染海量图片。结果写 `validation/sample_check_report.json`。

运行路径覆盖 Section 2 核心统计、control Section 3 原相位函数、两 source 的 Section 5、Section 4 的小数组 joint POD 核心。**未覆盖完整 Section 1 原始 DAT 读取、Section 2 所有拟合/绘图、正式 Section 4 全量 POD/连通域/目录/导出和 6–9 节。** 相关既有合成测试随代码保留，可按改动选择。

为使一个周期内有多样本参与统计，smoke 显式使用 6 相位箱/最少 2 样本。正式参数仍为 24 箱/最少 20 样本，不能把 smoke 设置写回主脚本。这个样本没有统计收敛意义。

`record` 模式仅供打包时产生修改前参考。重构后请用默认 check；不要覆盖期望值让测试通过。

## 资源预算

每份 U+V+valid 展开约 23.5 MiB，共四份约 94 MiB；磁盘 MAT/ZIP 使用无损压缩。包内附图和小参考量，不含 GB 级缓存/结构目录。实际包体积见 `provenance/package_summary.json`。

单次仅加载一个 case/source 和较小相位数组；MATLAB 进程本身另占内存。建议给小样本运行预留约 2 GiB RAM、解压后额外 200 MiB 临时空间，此为保守使用建议，不是已测峰值或云服务器配额。不要调用大数据预计算/全量图形导出。

Python 可用 h5py 读 v7.3。h5py 中 U/V 是 `[x,y,frame]`，转到 MATLAB 同序用 `.transpose(2,1,0)`。JSON/CSV 和图文导读无需 MATLAB。没有 MATLAB 时只报告静态阅读和文件检查，不伪造 MATLAB 运行结果。
