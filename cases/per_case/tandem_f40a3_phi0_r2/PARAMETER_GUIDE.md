# 参数位置与依赖

日常参数均在本 case 主脚本 Section 0，仍按 A–P 分组；PARAMETER_MAP.csv 给出原位置、唯一新入口、当前表达式、消费者及可调性。原消费者行号指原 ZIP，不伪装为改后行号。

| 任务 | 唯一入口 | 当前值/关系 |
|---|---|---|
| 缓存重建 | stages.cache | 默认 reuse；改 compute 后重跑 0，rebuild_cache 仅派生一次 |
| 帧序/输入 | sources.raw/postproc、n_frames | 两明确 repeat：3rd→2nd，各 offset=0；6000×2 |
| 物理量 | fs/Uinf/nu/rho/D_mm/wall_side | 960 / 25 / 1.48e-5 / 1.2 / 30 / top |
| S2统计/BL | statistics_source/frame_mode、profile、loglaw、friction等 | 原算法，剖面 [80 180]；B/C拟合区间与dy_h保持各自值 |
| S3相位/预览 | phase、phase_preview | controlled 40Hz、24箱/min20；marker_stride=1，smooth_points=5 |
| S4计算/展示 | structures.section4 | 原E50、[8 4]、严格长度 [3 3.8 4.5]；排除区仍按case独立 |
| S4隐藏量外提 | section4.reference_x_mm/chunk_frames/amplitude_multiplier | [100 220] / 48 / 1.0；POD分块512/128 |
| S5整体选源/帧 | transport.source/frame_mode | raw/all；所有矩与有效支持域同步切换，不影响S2/3 |
| S5边缘/剖面 | transport.edge_buffer_cells/profile_x_range_mm | [2 16] / [80 320]；边缘控制生产域，范围控制显示平均 |
| S5阈值/分母 | friction.hole_thresholds、transport.stress_fraction_floor | [0 1 2] 严格 H>；floor=1e-6 只保护应力份额，不改变概率分母 |
| 固定/无效项 | profile_source、plot_colormap | 用户入口已移除；S4实际balance257，旧summary的ocean不代表真实色图 |
| 可选模态依赖 | spod.toolbox_dir | 原ZIP缺SPOD，启用须显式合法本地副本；当前skip |

S4 run 计算合同包含 exclusion/length/connectivity/POD/源身份；DPI、plot_normalization、figure_connectivity、max_figure_objects 不使匹配的 POD/检测重算。已保存的适配结果包含绘图选择，因此改展示参数后可需重新发布该结果；此时运行 S4 compute，日志应明确复用哪个匹配run。显式 resume 优先；已有候选但全部失配时停止。没有任何候选时，显式的 S4 compute 会新建 run；不要 Run 整个脚本仅为了取 cfg。

baseline旧BL参考的profile_params=[240 320]，不是当前[80 180]的同参数结果。本轮没有重算或迁移该旧参考。
