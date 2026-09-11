# 从这里开始：两个独立 r2 case 的当前代码

版本：`r2-local-20260910-cloud`。P0–P5 已按小批落实本轮源码范围；
当前仅源码与静态检查完成，**MATLAB 动态验收尚未执行**。

1. 先读 [当前进展](PROJECT_PROGRESS.md) 与 [版本边界](CURRENT_VERSION.md)。
2. 日常使用只打开一个 case 的主脚本，在编辑器先 Run Section 0：
   [基准 case](cases/per_case/tandem_baseline_r2/README.md) 或
   [受控 case](cases/per_case/tandem_f40a3_phi0_r2/README.md)。每个目录可单独复制，自带本地 lib 和第三方资源。
3. 在本 case 的 PARAMETER_GUIDE.md / PARAMETER_MAP.csv 查参数。
   正式默认值保持原主脚本；不要整段运行主脚本仅为了获取 cfg，S4 默认仍为 compute。
4. 需要验收时读 [当前交接与验收顺序](docs/CURRENT_HANDOFF.md)，只运行相关路径。

已有身份匹配的本地缓存时，S5 可直接运行 0→5；不要为了 S5 启动 2/3/4。
本代码包不含正式 DAT、12000 帧缓存、完整 mean_bl/POD/run，也不包含新生成的科学结果。
原 ZIP、样本和历史图组继续作为单独比较依据；smoke_expected 禁止 record/覆盖。

历史交接仍保留在 [原始要求](docs/handoffs/review_20260910/START_HERE.md)，
源码差异、参数与结果身份疑点见 [P0 证据](change_records/P0_EVIDENCE.md)。
历史报告不是当前运行成功的证据。
