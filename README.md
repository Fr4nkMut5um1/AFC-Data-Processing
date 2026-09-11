# PIV：两个独立 r2 数据处理目录

当前交付为 MATLAB 源码和静态完成版本，动态与正式数据验收未执行。
状态以 [PROJECT_PROGRESS.md](PROJECT_PROGRESS.md) 为准；首次接手请读 [START_HERE.md](START_HERE.md)。

| 工况 | 独立目录与主脚本 | 参数位置 | 验收说明 |
|---|---|---|---|
| 基准 B | [tandem_baseline_r2_case.m](cases/per_case/tandem_baseline_r2/tandem_baseline_r2_case.m) | [参数表](cases/per_case/tandem_baseline_r2/PARAMETER_MAP.csv) | [VALIDATION](cases/per_case/tandem_baseline_r2/VALIDATION.md) |
| 受控 C：40 Hz / A=3 mm | [tandem_f40a3_phi0_r2_case.m](cases/per_case/tandem_f40a3_phi0_r2/tandem_f40a3_phi0_r2_case.m) | [参数表](cases/per_case/tandem_f40a3_phi0_r2/PARAMETER_MAP.csv) | [VALIDATION](cases/per_case/tandem_f40a3_phi0_r2/VALIDATION.md) |

## 使用

在 MATLAB 编辑器打开一个主脚本，编辑 Section 0 的参数后 Run Section 0，再明确选择要运行的节。
Section 0 只做参数、本地路径和工作区归属检查，不读取全部速度缓存、不扫描 DAT、不统计或绘图。
重跑它不会无条件清空已有结果；后续消费过期结果时会报出需重新 compute/读取的产物。

默认 cache/statistics/mean_bl 为 reuse；B phase=skip、C phase=reuse；两份 structures=compute、transport=skip；
最终 figures 保留 B=skip、C=compute，6–8 的阶段均 skip。完整 Run 可能启动正式 S4，不能用它仅提取 cfg。

- 从 DAT 重建缓存：在本 case/input 放置主脚本明确列出的四个 raw/PostProc repeat 目录；设 stages.cache=compute，Run 0→1。
  顺序保持 3rd→2nd，各 offset=0，不猜编号或起帧。
- 已有本地缓存独立做 S5：设 transport.source 为 raw 或 postproc，stages.transport 为 compute 或 reuse，Run 0→5。
  所选缓存必须与 cfg 身份匹配；不要求另一源、原 DAT 或 S2/3/4 在线。
- S4：显式使用本地 PostProc 缓存与保存的 mean_bl 文件，严格保留 12000×89×640。
  run 只在本 case 查找，明确 resume 优先；旧产物缺身份或参数失配时停止。

## 目录与依赖

每个 case 自带 lib/+tblR2、lib/+d23、Cf_chart.txt、piDMD 及 LICENSE；output/lib/third_party 均从自身脚本位置生成。
两份日常入口不依赖父目录 bootstrap、根 lib、另一 case 或 experiments。
根 lib 和 tools/tests 保留为集中维护与历史研究副本，不能与日常 case 路径混用。
无需 genpath、savepath 或 restoredefaultpath；同名函数解析到别处时按报错移除具体旧路径，或打开新 MATLAB 会话。

原 ZIP 不含 SPOD。启用时必须配置本 case/third_party 内的合法本地副本；不会借用机器上偶然存在的 spod.m。

本交付是代码包。离线缓存包还须配套身份已核实的缓存及所用阶段产物；完整可重建包还须包含明确 DAT 输入。
历史 MAT 绝对路径、POD/context 和 catalog_index.MatFile 未自动迁移，也未重签身份。

## 记录

- [架构与调用关系](docs/ARCHITECTURE.md)、[S5 定义](docs/SECTION5.md)、[有限验证入口](tests/README.md)。
- [当前旧→新文件映射](change_records/FILE_MAP_CURRENT.csv)、[P3 字段映射](change_records/P3_FIELD_MAP.csv)。
- [本轮进展与待验收](PROJECT_PROGRESS.md)、[下一轮交接](docs/CURRENT_HANDOFF.md)。
- 云端只读静态检查：`python validation/verify_cloud_static.py`；它不执行 MATLAB 或计算科学数组。

原图与“当前同代码、同参数重跑参考”分开记录。baseline 旧 BL 剖面范围为 [240 320]，当前主脚本为 [80 180]；
旧 baseline S4 图不能冒充本版本对照通过。详见 [P0 证据](change_records/P0_EVIDENCE.md)。
