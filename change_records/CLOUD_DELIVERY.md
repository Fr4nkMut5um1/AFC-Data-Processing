# 当前版本云端收尾批次

日期：2026-09-10；基于 MATLAB 源码提交 37bcfe0，未继续修改 .m 文件。
本批完成当前导航、版本和进展说明、可重复静态检查，以及当前代码快照的打包准备。

## 改动文件与行为

- 新增根 START_HERE.md、CURRENT_VERSION.md、docs/CURRENT_HANDOFF.md；更新根 README/PROJECT_PROGRESS、
  docs/ARCHITECTURE/README/SECTION5、tests/README、tools/README。
- 两 case 的 README/PARAMETER_GUIDE 明确 S4 区别：已有候选全部失配时停止；没有候选且明确执行 compute 时新建 run。
- 更新前的 7 份根文档在 docs/history/pre_cloud_delivery_20260910 原样保留。
  它们过去仍写共享库/bootstrap/experiments fallback 和历史 MATLAB 成功记录，容易误读为当前状态；现已分开说明。
- 新增 validation/verify_cloud_static.py、原文件哈希清单与 change_records/FILE_MAP_CURRENT.csv（422 行）。
  旧 FILE_MAP_P0_P5.csv 仍指此前完整审查包内的 cases/ 布局，原样保留；当前映射指本代码包 project/cases/per_case/。

MATLAB 调用链、科学参数、计算次序、图形和运行开关均未在本批改动。
S5 文档的 Definitions/Outputs 两部分也逐字保留，只替换日常入口和验证状态说明。
静态检查工具不读取科学数组、不执行 MATLAB，不提供 record 或更新预期模式，不自动改回用户参数。

## 执行记录

| 项目 | 结果 | 范围 |
|---|---|---|
| verify_cloud_static：首次 | 失败，已定位 | 检查脚本误把 baseline 的 phase.n_bins/minimum_samples_per_bin 空值按 controlled 24/20 检查 |
| 对照原/当前 baseline 主脚本 | 原值一致 | 原行153/155、当前行184/186均为空数组；只修新检查脚本的 case 区分，未改 MATLAB 参数 |
| verify_cloud_static：修复后 | PASS_STATIC_ONLY，25 项 | 469 个原件（ZIP+468展开文件）；每 case170个受保护文件（164 lib+6第三方）；两 case镜像；声明文本与正式S4尺寸闸门 |
| 已有报告拒绝覆盖 | 通过 | CLI返回2，原报告SHA-256不变；未写旧expected |
| 当前10份导航文档的本地链接 | 通过，47个 | 指向的当前文件均存在 |
| 7份旧文档副本 | 通过 | 与37bcfe0逐字节相同 |
| S5 Definitions/Outputs 文本 | 通过 | 与更新前完全相同 |
| .m变更检查 / git diff --check | 通过 | 相对37bcfe0无MATLAB源码变化；无空白错误 |
| MATLAB/Run Section/小MAT/正式数据/图组 | 未执行 | 当前云端不能运行；本批不以文件检查替代 |

首次与最终报告分别为 CLOUD_STATIC_INITIAL.json、CLOUD_STATIC_CHECK.json。
首次失败是新静态工具预设错误，不是 MATLAB 测试失败；修复没有放宽科学门槛。
原469项清单中一项是ZIP，展开树本身为468个文件；smoke_expected包含在展开树校验中。

调用示例（原件路径由使用者明确提供）：

```text
python validation/verify_cloud_static.py --original-bundle <原ZIP解压根> --original-zip <原ZIP路径> --report <新JSON路径>
```

本批通过后不继续扩展测试或拆函数。正式待验收项沿用 docs/CURRENT_HANDOFF.md；
尤其是编辑器0→5、同MAT S3重画、正式S4与S5 raw/postproc完整图组，仍未完成。
