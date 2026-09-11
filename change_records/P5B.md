# P5B S4 复用选择与输入合同（高风险独立批次）

变更符号：section4_vlsm_analysis、select_section4_run、section4_run_contract；save/load_result/result_parameters/result_inputs 扩展到保存的 S4 适配结果。原 local find_reusable_run 删除，真实选择逻辑在新函数中，非转发。

入口仍先检查正式 [12000 89 640]，随后只读检查 PostProc 缓存 fs/实际大小/全部 repeat/坐标及保存 mean_bl 的生产参数与统计身份，不要求 raw/DAT 在线。未修改任何 d23 核心文件。

显式 resume 优先；先检查同 run 完整新合同，再用其实际原 compute_config 进入原 d23.initialize_run config/source 校验。原 config_hash（仅排除 resume 指针）、POD/检测批次校验继续保留。展示参数不参与计算合同；重画仍使用当前绘图配置。对未完成 run 续跑时，计算调用使用原相同 compute_config，避免仅 DPI 变化使旧 POD/断点合同失配。

自动仅查本 case runs。比较有效 cfg（含 exclusion/length/connectivity/POD 全参数）、完整源元数据/网格/帧 ID/mean_bl 身份、计算源码哈希和 final_results/manifest 一致性。错误逐候选记录，无可用候选时停止；不自动重算 12000 帧。确实希望重新计算时显式 reuse_existing_run=false。新 run 才写 r2_reuse_contract.mat；缺身份的旧 run 拒绝，不能用当前代码给历史结果盖章。

同时核对 metadata/POD/checkpoint/catalog MAT 的本地路径，原 active context/catalog_index.MatFile/POD 路径审查保留。

保存的 S4 适配结果包含当前展示参数和显式 PostProc/mean_bl 父身份；展示变化可使该 MAT 需要重新发布，但 S4 compute 分支会复用匹配的 POD/检测 run，不为此重算 POD。

验证：新增极小 MAT 候选测试 test_r2_section4_reuse_contract，直接调用实际选择函数（不绕正式尺寸闸门），覆盖相同配置/仅绘图变化可复用、source/第二 offset/exclusion/length/connectivity 改变拒绝、显式 resume 不被完成候选抢占、缺身份不补章，并调用原 d23.initialize_run 的 resume 元数据验证。静态语法检查通过；MATLAB 测试未执行。

本批触及正式 S4 编排/复用路径，仍必须进行正式 12000 帧相关段对照。短 joint_pod_array 或 metadata 测试均不能替代；未声称 formal fast_in_memory、完整目录与图组已验收。
