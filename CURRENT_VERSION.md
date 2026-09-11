# 当前版本身份与范围

- 版本名：`r2-local-20260910-cloud`，日期 2026-09-10。
- 唯一源码起点：原 `PIV_Review_20260910.zip` 内 `project/`。
- 原 ZIP SHA-256：`af95e05849b9f09116354fddaa19a660659207c354e3f3ef30ad7f763dfba1f9`。
- 本轮整理之前的 MATLAB 源码提交：`37bcfe0`；本次收尾只新增静态检查、映射与当前文档，没有改动 MATLAB 源码。
- 当前交付包内 `release_manifest.json` 记录最终提交与文件 SHA-256；`version_history.bundle` 保留本地逐批提交。
- 当前代码包与此前含原件、fixtures、原图及补丁的 `PIV_r2_P0_P5.zip` 用途不同。后者 SHA-256 为
  `49397fc28f5877b0ff8f029d16d7356d04a0788fdd1886bab3d12752b5133fe2`，继续保留作审查检查点。

## 可以据此确认

两个独立 case、当前参数入口、P1–P5 本轮源码改动、保护文件字节校验和有限测试入口已交付。
当前代码包没有正式数据、正式计算结果或已经通过的新 MATLAB 日志。
`change_records/` 中各日志有各自范围和时点，不将较早 PASS 累加为整仓库动态验收。

## 环境和证据

当前云端不能执行 MATLAB，未用 Python/Octave 代跑科学计算。
原件 environment.json 的 MATLAB 9.13.0.2080170 (R2022b) Update 1 / PCWIN64 是历史验证环境。
既有 41 项测试、S5 raw 图组与数值闭合记录是此前机器上的历史记录，不是本次执行结果。

原 ZIP 里的 smoke 样本为每 repeat 24 帧、6 箱/min2；正式仍为每 repeat 6000、24 箱/min20、S4 12000×89×640。
不得替换或 record 原 smoke_expected，也不得把短 joint_pod_array 当作正式 fast_in_memory 或完整目录验收。
