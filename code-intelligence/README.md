# PIV Code Intelligence：P0/P1 观察层

本目录属于现有 AFC-Data-Processing，不是科学计算的运行依赖。

当前状态：P0 侦察与 P1 MATLAB 原生静态 Ground Truth 已完成；P2 runtime 尚未开始。

先读 [P0_P1_FINAL_STATUS.md](P0_P1_FINAL_STATUS.md)、[CURRENT_BASELINE.md](CURRENT_BASELINE.md)，再读 [历史 P0 侦察](P0_RECONNAISSANCE.md)。

## 已验证

- GitHub-hosted Runner：ubuntu-22.04
- MATLAB：R2022b Update 10
- Public 自动许可：成功
- 两个 r2 case：各分析 135 文件，失败 0，源码未改变
- Native required products：两个 case 都只返回 MATLAB
- 静态 evidence：已上传 Actions artifact

## Workflow

- .github/workflows/matlab-cloud-r2022b.yml：smoke test
- .github/workflows/matlab-static-r2022b.yml：native static analysis

两个 workflow 对 main 相关源码变化自动运行，也可手动运行；不自动提交 evidence，不上传真实实验数据。

## Evidence Classification

- STATIC：MATLAB 静态分析确认的文件关系
- RUNTIME：真实执行中观察到的关系
- BOTH：同一关系在相同版本上同时获得 STATIC/RUNTIME 支持
- INFERRED：源码阅读或 AI 解释
- DOCUMENTED：仅文档陈述

当前没有 P2 runtime evidence。两个 case 的 input/ 只有 README，不能据此声称完整 PIV pipeline 已在云端运行。
