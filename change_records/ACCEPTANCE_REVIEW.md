# 本轮定向静态复核与修复

1. P5 新严格 phase 保存合同与现有 `test_r2_phase_smoke` 的最小合成保存 fixture 不兼容。定位至原测试 L60–61 的 save/load 调用。只在原数值计算/断言之后补合成发布元数据及父输入；原相位算法调用、singleton 检查、expected 和全部容差不变。该合成 fixture 不代表正式生产身份。
2. `test_r2_baseline_control_contract` 与 `test_compact_case_contract` 的文本断言仍要求旧 phase 四参和缓存自动恢复 sources，后者与用户 P2 要求冲突。仅更新布局/签名断言；未删除科学断言。
3. 原 load_result 最小头部比较会在 cfg.fs 等变化时抢先给出笼统错误。改为同一最小字段的具体差异；新严格生产合同继续覆盖全部参数和父输入。
4. 已逐项核对 S4 run contract 排除 utau_source.loaded_utc（读取时间，不是数据身份），保留实际 created_utc/UUID/缓存大小时间及所有 repeat 信息。保留旧 E50 目标一致性 1e-12 检查，没有放宽阈值。

以上为源码/测试接口静态复核发现，未称为 MATLAB 测试失败或通过。未启动全仓库试验；实际运行门槛仍是 MATLAB 与正式输入缺失。

5. 静态核对工具首次把 observed_ratio 当成独立 .m 文件，实际为 transport_statistics.m:276 的局部函数；改为由其原文件字节检查覆盖，没有改源码或科学门槛。最终静态核对通过。
6. 新参数 CSV 使用 CRLF 导致 git diff --check 报尾部空白；仅将新交付 CSV 行尾统一为 LF，字段值不变，复查通过。
