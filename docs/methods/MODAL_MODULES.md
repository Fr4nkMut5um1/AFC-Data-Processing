# r2 模态与 LCS 模块接口

这组函数位于共享库 `lib/+tblR2` 命名空间，全部为无 GUI 的纯计算/绘图入口。
成品 `POD-DMD-LCS` 目录没有被修改。

## POD

```matlab
pod = tblR2.pod_module(cache_file, cfg, stats, phase_stats, mean_bl, 'total');
```

`pod_module` 保留 `pod_cache` 的六参数缓存合同，并由 r2 主脚本直接调用；`pod_cache` 现在额外输出
`joint_modes`、`mean_snapshot` 和可选的 `reconstruction`。在 `cfg.pod.reconstruction.enabled=true`
时，重构接口由 `pod_reconstruction` 执行：

```matlab
R = tblR2.pod_reconstruction(cache_file, cfg, stats, phase_stats, mean_bl, ...
    'total', pod, 'frame_positions', [1 20 120], 'mode_indices', 1:20);
```

重构结果同时提供脉动场、加回分支均值的物理速度场、残差、相对误差、采样网格和有效掩膜。
`add_mean=false` 时只返回脉动重构；`include_raw=false` 时不再次读取原始帧。
也可用 `frame_start/frame_count` 代替 `frame_positions`，以兼容附件脚本的“起始帧+帧数”设置。

## DMD

```matlab
dmd = tblR2.dmd_module(cache_file, cfg, stats, phase_stats, mean_bl, 'total');
```

该函数使用 vendored `piDMD(...,'exact',r)`，输出 `eigenvalues`、`omega_per_s`、
`frequency_hz`、`growth_rate_per_s`、`amplitudes`、联合/网格模态和从 `t=0` 开始的重构诊断。
`dmd_module` 由 r2 主脚本直接调用；`dmd_cache` 仅作为旧调用名兼容的薄包装。

## LCS/FTLE

```matlab
lcs = tblR2.lcs_ftle(cache_file, cfg, stats, mean_bl, 'raw');
```

也可以直接传数组结构：

```matlab
lcs = tblR2.lcs_ftle(struct('X',X,'Y',Y,'U',U,'V',V), cfg, [], [], 'raw');
```

其中 `U/V` 为 `nFrames x J x I`，`X/Y` 为 `J x I` 规则网格。默认沿成品代码的
backward 方向，以显式 Euler 和 `interp2` 生成流映射，再由 Cauchy-Green 最大特征值计算 FTLE。
`cfg.lcs.velocity_to_grid_scale=1000` 负责把 m/s 转为 r2 网格的 mm/s；若坐标使用米，将其改为 1。
计算可能返回很多起始帧，但图形层默认只导出首/中/末；可用 `cfg.lcs.plot_frame_indices` 覆盖。
若 `branch='random'`，通过 name/value 传入 `'phase_stats', results.phase`。
主脚本还将速度源显式分为 `cfg.lcs.source_role='postproc'|'raw'`；默认使用 postproc
缓存中的 raw 速度字段，若要严格使用 raw 缓存则设置为 `raw`，避免把“分支”和“数据源”混为一谈。

## 绘图

- `tblR2.plot_pod_products(pod, X, Y, cfg, ...)`
- `tblR2.plot_dmd_products(dmd, cfg, ...)`
- `tblR2.plot_lcs_ftle(lcs, cfg, ...)`

这些函数只接收结果和坐标，不读取 GUI `handles`、不调用 `uigetdir`、不使用 `eval` 或当前目录隐式状态。
`plot_products` 的 `pod`、`dmd` 和 `lcs_ftle` 任务已转发到这些独立绘图函数。

数组式 POD 还支持不落地缓存的快速调用：

```matlab
pod = tblR2.pod_module(U, V, 20);   % U/V: nFrames x J x I
P = tblR2.plot_pod_products(pod, X, Y, cfg);
```

该路径会固定有限空间点掩膜，并将含 NaN 的 PIV 点保留为 NaN；缓存式路径则通过
`modal_snapshot_matrix` 使用同一 ROI/帧抽样合同。DMD 数值接口接受 `DOF x snapshots`
矩阵，自动按 SVD 数值秩截断；零或极小特征值会使用显式对数下限并记录在
`dmd.svd_diagnostics`，避免频率和增长率污染为 Inf/NaN。

## 主脚本接入

`tandem_baseline_r2_case.m` 和 controlled r2 入口都保留原有 POD/DMD 阶段，并增加可选的
`cfg.stages.lcs = 'skip'|'compute'|'reuse'`、`paths.lcs` 和 `results.lcs`。默认跳过 LCS，避免正式流程
在没有明确积分窗口时一次性计算全部起始帧。

## 原交付时的离线验证记录

未启动 MATLAB。已执行：

```text
python3 tests/matlab_check.py . -> 296 个 .m 文件通过结构检查
python3 tests/test_r2_extracted_modules.py -> PASS
```

Python 模拟覆盖 POD 重构维度/NaN 掩膜、DMD 频率/时间起点/数值秩，以及 FTLE
流映射梯度和规则网格合同；仍需在目标 MATLAB 版本上进行一次小网格实测，重点确认
`piDMD` 路径、`matfile` 变量尺寸和图形导出后端。
