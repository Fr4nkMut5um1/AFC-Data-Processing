# POD 低阶重构去噪与 LSM/VLSM 聚类联通扩展

## 结论与科研依据

本扩展把 `ELF-POD` 作为主去噪分支，把联合 `u-v` POD 累计总能量达到
80%、90%、95% 的连续低阶重构作为备选分支，同时保留独立的 Raw 与现有
Gaussian 结果。`Gaussian -> POD` 作为默认关闭的敏感性选项；不实现
`POD -> Gaussian`。

- Raiola, Discetti & Ianiro (2015), *On PIV random error minimization with
  optimal POD-based low-order reconstruction*,
  [DOI 10.1007/s00348-015-1940-8](https://doi.org/10.1007/s00348-015-1940-8)：
  直接支持使用 POD 低阶重构降低 PIV 随机误差。
- Brindise & Vlachos (2017), *Proper orthogonal decomposition truncation method
  for data denoising and order reduction*,
  [DOI 10.1007/s00348-017-2320-3](https://doi.org/10.1007/s00348-017-2320-3)：
  提供基于空间模态 DCT-Shannon entropy、两线拟合和 PPR 的 ELF 截断方法；
  允许保留非连续原始模态，并指出 PPR 小于 1.8 时不应信任自动截止点。
- Shehzad et al. (2021),
  [DOI 10.1016/j.expthermflusci.2021.110469](https://doi.org/10.1016/j.expthermflusci.2021.110469)：
  为 2C-2D PIV 中 POD 与大尺度运动识别的组合提供应用背景。

POD 去噪针对随机误差，不消除 PIV 系统偏差。所有 LSM/VLSM 结论仍限定为
XOY 平面的 2C-2D 连通结构，不外推为完整三维结构。

## 新入口与复用关系

运行入口：

```matlab
cases/per_case/tandem_baseline_r2/tandem_baseline_r2_pod_cluster_case.m
```

原文件 `tandem_baseline_r2_case.m` 未修改。新入口先 `run` 原 r2 脚本，再执行
Section 10。若原 r2 结果已经存在于工作区，可只运行 Section 10。

复用的现有实现：

- `tblR2.pod.snapshot_decomposition`：保持
  `C=Xf'*Xf/size(Xf,1)`、`Phi=Xf*eigvec`、单位范数模态和
  `Ac=Phi'*Xf`，与 `Comparison_Re30w_AoA2.m` 一致；
- `tblR2.pod_reconstruction`：按所选模态重构瞬时 `u'`；
- `tblR2.identify_structures` 与 `tblR2.vlsm.merge_streamwise_neighbors`：
  继续执行正负分离、四邻接、滞回阈值和现有流向合并。

新增函数只负责全分辨率序列合同、ELF/能量选阶、分块重构、结构分支汇总和
内存预检，没有替换上述 POD 或聚类算法。

## 输出合同

Section 10 保存：

```text
cases/per_case/tandem_baseline_r2/output/mat/13_pod_cluster_analysis.mat
```

主要结果：

- `data.raw`：未高斯处理的 PostProc `u'` 独立对照；
- `data.gaussian`：复用现有 Section 4 Gaussian 结构目录；
- `data.pod.ELF_POD`：ELF 有效时的主 POD 结构目录；无效时失败关闭；
- `data.pod.POD_E80/E90/E95`：达到各能量档的最小连续前 N 阶；
- `data.*.primary`：统一使用原始 `statistics.u_rms` 的主比较；
- `data.*.own_rms_sensitivity`：POD 重构场自有 RMS 的独立敏感性结果；
- `data.fixed_n_recommendation`：仅在 ELF 失效时检查 E90/E95 稳定性。

稳定判据为：每帧 LSM 数、每帧 VLSM 数、占据面积率、`Lx/delta` 中位数和
P90 的相对变化均不超过 10%，且长度经验 CDF 最大差不超过 0.10。满足时建议
固定 `N=N90`，否则不自动推荐固定 N。

POD 分支只计算 `u'` 的 LSM/VLSM；现有 Gaussian Q2/Q4 保持不变，不生成
POD-Q2/Q4。

## 精度与内存边界

代码强制：

- `frame_stride = 1`；
- `spatial_stride = [1 1]`；
- 不插值回填、不在粗网格上聚类；
- 继续使用现有双精度精确 snapshot POD。

2026-08-25 对当前真实缓存的预检结果：

| 项目 | 数值 |
|---|---:|
| 可信域空间点 | 52,288 |
| 联合 `u-v` 自由度 | 104,576 |
| 帧数 | 12,000 |
| 估计峰值内存 | 47.61 GiB |
| 当前 MATLAB 可用内存 | 10.75 GiB |
| 最大双精度场数组 | 9.35 GiB |

因此当前机器会在分解前由内存闸门停止，不会静默改用 `[2 2]`、单精度、减少
帧数或随机化算法。完整真实工况建议在至少 64 GiB、且运行时具有约 50 GiB
可用内存的机器上执行。若必须在当前机器运行，需另行确认改变科研合同，例如
分别处理两个 6000 帧 repeat，或批准截断/迭代 POD；这些方案当前均未擅自启用。

## 独立的内存友好 POD 计算版本

新增两个独立函数，不替换原 `snapshot_decomposition.m`，也没有接入或修改聚类
模块：

```text
+tblR2/+pod/snapshot_decomposition_memory_friendly.m
+tblR2/pod_denoise_prepare_memory_friendly.m
```

核心实现不驻留完整 `D×N` 快照矩阵，而是从 MAT 缓存按空间行块读取三遍：

1. 第一遍用 double 计算每个自由度的时间均值，分块累积
   `C = Xf'*Xf/D`；
2. 完整双精度 `eig(C)` 后，只为选定的连续或非连续模态生成
   `Phi = Xf*eigvec`，并使用实际累积的二范数归一化；
3. 第三遍显式计算 `Ac = Phi'*Xf`，没有使用单精度或低精度近似公式。

输出继续使用 `Phi_trunc`、`A_trunc`、`mean_snapshot`、`spatial_mask` 等字段，
因此现有 `pod_denoise_reconstruct_frame` 可以直接使用。

示例：

```matlab
options = struct( ...
    'rank_method', 'energy_fraction', ...  % 也支持 fixed_n/mode_indices/gavish_donoho
    'energy_target', 0.95, ...
    'row_block_size', 2, ...
    'covariance_update_columns', 64, ...
    'memory_guard', true, ...
    'memory_safety_factor', 1.25, ...
    'cache_path', '', ...
    'use_cache', false, ...
    'write_cache', false);

denoise = tblR2.pod_denoise_prepare_memory_friendly( ...
    paths.sequence_cache_postproc, cfg, results.statistics, options);
```

对于 `N=12000`，核心 `N×N` eigensystem 的保守常驻估计约为 4.29 GiB，
不再同时保留约 9.7 GiB 的 double 快照矩阵以及约 9.7 GiB 的全模态矩阵。
最终内存仍随保留秩 `r` 增长，因为 `D×r` 模态和 `r×N` 系数是实际输出，
不能凭空消除。
函数会在协方差/eig 和选定基底分配前分别检查当前 MATLAB 可用内存；不足时
明确停止，不会自动改成 single、减少帧数或降低网格分辨率。

该版本不降低数值类型、网格或帧数，但分块累积顺序与一次矩阵乘法的浮点加法
顺序不同，因此保证数学和双精度合同等价，不承诺逐 bit 一致。合成测试中截断
重构相对差小于 `1e-10`；真实缓存的全空间 10 帧 I/O/掩膜冒烟测试也已通过。

限制：完整 `N×N` 协方差和全特征分解仍然存在，计算复杂度没有降低，且三次
扫描会显著增加 I/O 时间。当前版本可直接用于 E80/E90/E95、固定 N、Gavish-
Donoho 或已知非连续 `mode_indices`；ELF 的“边生成全部模态边计算 entropy”仍需
单独的流式 entropy 阶段，尚未把它冒充为已经解决。
