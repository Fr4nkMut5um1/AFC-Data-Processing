# 有限验证入口

当前所有 MATLAB 动态检查尚未在云端执行。按实际改动选择相关测试，失败只定位与复跑失败项及直接依赖。
不要先 runtests 整个 tests 目录；不是所有 .m 都是同一种入口。

## 云端只读文件检查

从项目根运行（Python 3 标准库，无数值库）：

```text
python validation/verify_cloud_static.py
```

它仅核对原科学文件 SHA-256、两 case 库镜像、主脚本参数声明与资源，不能证明 Run Section、MATLAB 执行或科学等价。
可传 `--original-bundle <原ZIP解压根>` 核对展开原件（468 文件，含 smoke_expected），
以及 `--original-zip <原ZIP路径>` 单独核对 ZIP，共 469 项；
可传 `--report <新的JSON路径>` 保存报告，已有报告拒绝覆盖。没有 record 或自动更新基准选项。
这些参数检查针对交付快照；用户有意调参后出现差异，需单列评估，脚本不会回改参数或更新基准。
历史 Python 科学接口脚本未用来替代 MATLAB 验收。

## MATLAB：在一个 case 目录中执行

先进入对应 case，在新会话或确认只加载本 case 库的会话中：

```matlab
addpath('lib'); addpath('maintenance/checks');
run('maintenance/checks/test_r2_result_reuse_contract.m');
run('maintenance/checks/test_r2_section4_reuse_contract.m');
run('maintenance/checks/test_r2_sequence_cache_contract.m');
```

以上是 P5 元数据/候选和缓存合同定向脚本，使用极小 MAT，不绕过正式 S4 入口尺寸门槛。
其他直接依赖按需选择：

| 文件（本 case maintenance/checks/ 下） | 调用类型 | 覆盖边界 |
|---|---|---|
| test_r2_phase_smoke.m | run | 原相位核心与保存读取接口 |
| test_r2_section5_transport.m | run | S5 核心、wrapper 复用/正常原子发布与部分导出；不等于异常中断及正式图组验收 |
| test_r2_offline_cache_reuse.m / test_r2_cache_statistics_smoke.m | run | 离线缓存与原统计路径 |
| test_workspace_results.m | 普通函数 test_workspace_results | 归属、参数/父输入过期 |
| test_r2_local_dependencies.m / test_r2_section4_local_inputs.m | runtests，并检查结果 | 本地解析与 S4 显式输入 |
| test_r2_section4_vlsm_figures.m | runtests，并检查结果 | S4 既有绘制合同 |
| run_review_smoke_for_case.m | 普通函数，三个显式参数 | 原真实短样本 check；不覆盖 section5_run 文件发布和导出 |

例如函数测试应保存结果并断言：

```matlab
r = runtests('maintenance/checks/test_r2_local_dependencies.m');
assert(all([r.Passed]));
```

原 fixtures 路径及新报告路径的具体调用见各 case 的 VALIDATION.md。
smoke 每 repeat24帧、6箱/min2；原 expected 和容差不得放宽或重录。

编辑器 0→5、相同 MAT 重画、正式 12000×89×640 S4 和 S5 raw/postproc 图组仍需独立验收，
见 [当前交接](../docs/CURRENT_HANDOFF.md)。
