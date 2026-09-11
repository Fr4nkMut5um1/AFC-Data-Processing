# P5A 原 S2/S3 结果复用合同

变更符号：save_result/load_result、result_parameters、result_inputs、sequence_cache_identity、contract_difference；两主脚本 S2/S3 显式提供实际父文件。workspace_results 仅将这些已补齐阶段移出旧合同警告。

保存参数：S2 实际源/帧模式/fs/帧数/全部 repeat roots、ids、offsets/有效比例/块长/Uinf/旧统计版本及源码哈希；mean_bl 加剖面、拟合、摩阻/归一化参数和已保存统计 UUID；S3 加原 raw 相位来源、原算法源码/相位参数以及原统计 UUID。父缓存使用只读校验后的完整元数据、网格/帧 ID、文件大小/时间，不声称逐帧内容哈希。

加载先查元数据，缺生产身份的旧 MAT 明确拒绝，不补章、不重算。主脚本传入当前父文件时比较身份；S4 所需已保存 mean_bl 可作为冻结输入，检查保存的生产参数/统计身份，不要求旧 raw/DAT 在线。仍不凭网格或第一 repeat 证明整个序列身份。

科学计算体无改动。S5 保留自己的 provenance、闭合、断点/原子发布和原源码哈希；Section 6–9 其他旧合同没有在此批扩展，不能推广声称全阶段复用安全。

新 MATLAB 测试 test_r2_result_reuse_contract 是脚本入口，使用极小 MAT 元数据，覆盖同参数/绘图参数变化复用、源/第二 repeat offset/拟合/相位变化拒绝、实际缓存 fs/帧数错误拒绝、父统计更新拒绝、旧缺身份拒绝及冻结 BL 离线读取。静态语法检查通过；MATLAB 未执行，测试结果未宣称通过。
