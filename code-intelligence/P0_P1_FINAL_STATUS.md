# P0/P1 最终状态与 Cloud MATLAB 事实记录

更新日期：2026-09-11。

本文件覆盖早期 P0 侦察报告中关于“MATLAB 尚未运行、仓库尚未接入、云端尚未验证”的历史状态。当前事实以本文件、CURRENT_BASELINE.md 和 evidence/STATUS.json 为准。

## P0：Repository Reconnaissance

- 当前仓库：Fr4nkMut5um1/AFC-Data-Processing
- 当前可见性：Public（经用户确认后修改）
- 源码基准：c860e5d2e259561147f70e0e932e0b6300bc512e
- 完整 Git 历史 bundle：未上传到 GitHub
- 主要入口：cases/per_case/tandem_baseline_r2/tandem_baseline_r2_case.m；cases/per_case/tandem_f40a3_phi0_r2/tandem_f40a3_phi0_r2_case.m
- 观察层：code-intelligence/
- 科学源码未因观察层建设而修改。

## P1：MATLAB Static Ground Truth

| Case | 状态 | 分析文件 | 失败文件 | 源码未改变 | Native required products |
|---|---|---:|---:|---|---|
| tandem_baseline_r2 | COMPLETE_WITH_LIMITATIONS | 135 | 0 | 是 | MATLAB |
| tandem_f40a3_phi0_r2 | COMPLETE_WITH_LIMITATIONS | 135 | 0 | 是 | MATLAB |

Runner 为 ubuntu-22.04，MATLAB 为 R2022b Update 10，架构为 glnxa64。使用 matlab.codetools.requiredFilesAndProducts。

COMPLETE_WITH_LIMITATIONS 表示静态采集过程完成，不表示完整 PIV pipeline 或科研结果已运行验证；文件图也不表示函数调用顺序。

[最新成功静态运行](https://github.com/Fr4nkMut5um1/AFC-Data-Processing/actions/runs/34553088328)

## Cloud MATLAB Feasibility

已验证 Public repository 自动许可、R2022b 启动、两个 case 原生静态分析和 evidence artifact 上传。smoke/static 两个 workflow 已对 main 相关源码变化自动触发，并保留 workflow_dispatch。没有自动提交 evidence。

## 当前边界

两个 case 的 input/ 目前只有 README，没有代表性 PIV 数据。P2 runtime 尚未开始；没有 profile、inmem 或实际调用顺序证据。不能把静态图当作运行路径。P3 schema、P4 Archify、P5 Cognition DeepWiki、P6 完整闭环仍属后续阶段。

固定迁移方向：云端 Cognition 官方 DeepWiki；未来本地 DeepWiki-Open。
