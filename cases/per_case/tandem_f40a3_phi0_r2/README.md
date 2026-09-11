# 控制 case：独立 MATLAB 数据处理目录

源码已分批完成 P1/P2、P3、P4、P5 的本轮改动。**当前只有静态检查通过；MATLAB、Run Section、数值及正式图组验收均未执行。**

1. 在 MATLAB 编辑器打开 `tandem_f40a3_phi0_r2_case.m`，先只 Run Section 0。它只定义参数/本地路径并检查工作区归属，不读取全部速度、扫描 DAT、统计或绘图。重跑参数节保留已算结果，过期结果在使用时明确报错。
2. 参数只在该脚本顶部修改；对应位置和当前值见 PARAMETER_MAP.csv、PARAMETER_GUIDE.md。需要重建缓存时改 `stages.cache='compute'`，Run 0→1，输入为 sources 明确列出的本地两个 repeat（3rd→2nd，offset[0 0]）。
3. 本地已有与 cfg 身份匹配的所选缓存时，设 `stages.transport='compute'` 或 `'reuse'`，选 `transport.source`，Run 0→5 即可。无需2/3/4，不要求另一源或 DAT 在线。输出为 `output/section5/raw` 或 `postproc`。
4. S2 compute 先接受相应 S1 缓存；S3 保留原 raw 相位计算和 controlled PostProc 预览条件。实际绘图在 `lib/+tblR2/plot_section3_preview.m`，错误清单保留，主脚本不隐藏额外相位计算。
5. S4 只需要本地 PostProc 和保存的 mean_bl 文件，仍严格要求12000×89×640。会核查 fs、repeat、坐标、BL生产参数；明确 resume 优先。同计算参数可复用run，展示变化不重算POD；已有候选但全部失配时，报具体差异并停止；没有任何候选时，显式的 S4 compute 会新建 run。确实要放弃旧候选新算时设 `reuse_existing_run=false`，没有自动重算上游整链。

默认模式保持：cache/statistics/mean_bl=reuse，phase=reuse，structures=compute，transport=skip，最终figures=compute，6–8均skip。不要为试参数 Run 整个脚本，以免按原默认启动正式S4。

本目录自带 lib/+tblR2、lib/+d23、Cf_chart.txt、piDMD及LICENSE。SPOD不在原ZIP内，启用时须将合法副本放入本case third_party 并明确 toolbox_dir；不会借用机器历史安装。同名函数解析到其他case时停止，请明确移除报出的旧路径或用新MATLAB会话，不restoredefaultpath/savepath。

本交付是代码包，**没有正式DAT、12000帧缓存、完整mean_bl/POD/run**。离线缓存包须另带身份已核实的缓存；完整可重建包须另带四个明确DAT目录。旧J:路径不能直接当新input身份；旧S2/S3/S4 MAT缺生产合同、旧run缺r2_reuse_contract时拒绝，不盖章、不自动迁移。本次没有足够旧原件证明同一数据，未提供猜测性路径替换工具。

有限验收按 VALIDATION.md 执行；历史原图与当前同代码同参数参考必须区分。baseline旧BL剖面[240 320]与当前[80 180]不同，旧S4 baseline图不能用作本轮同参数通过证明。
