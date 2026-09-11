# 维护与历史研究工具

日常入口为两个 case 主脚本，各自使用本地 lib。S5 日常直接 Run Section 0→5，cfg 来自主脚本，
不从历史配置 MAT 推测当前参数。详见 [当前使用说明](../README.md)。

| 工具 | 当前定位 |
|---|---|
| 每 case maintenance/run_section5_legacy_config.m | 显式旧配置维护入口，必须传 configuration_file；检查其本 case 归属，不迁移历史路径 |
| tools/maintenance/run_section5_from_saved_case.m | 保留旧整仓库布局/已保存 cfg 的维护入口；内部使用根 lib，不能与日常 case 会话混用；本轮未动态验收 |
| tools/preview_section3.m | 保留旧配置与缓存预览工具；可能计算 PostProc 相位，不能当零计算重画；当前日常绘制在主脚本 Section 3 |
| tools/research/ | 旧 Gaussian/merge/POD 参数研究与固定历史 run 工具；不是正式 S4 的替代链 |
| tools/packaging/ | 原交接包和样本制作工具；当前验收只用 check，不运行会生成/覆盖 expected 的记录流程 |

明确需要旧布局维护时才使用以下入口（配置、数据和路径仍须匹配其原合同）：

```matlab
addpath(fullfile(repo_root, 'tools', 'maintenance'));
run_section5_from_saved_case('tandem_baseline_r2', 'raw', 'reuse');
```

上面不是日常入口，也不是当前代码包已有可用旧配置/数据的保证。
独立 case 的维护入口则在其目录执行：

```matlab
addpath('maintenance');
run_section5_legacy_config('明确的旧配置MAT绝对路径', 'reuse');
```

研究工具的历史用途、原目录和运行假设完整保留在更新前 tools/README 副本；
见 [历史副本说明](../docs/history/pre_cloud_delivery_20260910/ARCHIVE_NOTE.md)。
本轮没有运行专题研究、恢复历史 experiments/tmp 或修改它们的科学算法。
