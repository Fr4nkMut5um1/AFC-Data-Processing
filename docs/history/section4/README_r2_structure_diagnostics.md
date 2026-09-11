# R2 聚类连通法诊断工具

用于量化 `tandem_baseline_r2` 结构识别流程对阈值、连通性与预处理参数的敏感性。
**本工具只读取已有缓存并复跑识别，不修改 `identify_structures.m` 等正式识别逻辑，
也不覆写任何正式结果文件。**

## 1. 为什么需要它

`cfg.structures` 里的 `alpha = 0.40`、`seed_alpha = 0.70`、`connectivity = 8`、
`envelope_closing_radius_cells = 2`、`max_internal_hole_pixels = 64` 全部是直接写定的，
仓库内没有任何标定记录或敏感性证据。`docs/plans/2026-08-21_tandem_cluster_connectivity_analysis_plan.md`
曾规划 Section 4A 逾渗校准，但从未实现。

在没有量化基线之前，无法区分"改了参数结果变了"和"改了参数结果变好了"。
本工具补上这个基线。

## 2. 文件清单

全部位于 `tools/r2_diagnostics/`（2026-08-24 从 `+tblR2/` 迁出，解决库合同冲突）：

| 文件 | 作用 |
|---|---|
| `load_sweep_frames.m` | 一次性读入抽样帧与几何量，避免反复访问 4.5 GB 序列缓存 |
| `percolation_metrics.m` | 单帧逾渗量：最大簇占比、簇数、占据率、susceptibility |
| `structure_geometry_metrics.m` | 单帧几何量：面积分布、长宽比、尾部占比、边界剔除数 |
| `percolation_sweep.m` | Phase 1：`alpha` × `seed_alpha` × 连通性 扫描 |
| `sensitivity_sweep.m` | Phase 2：`sigma` × `seed_alpha` × 闭运算 × 孔洞 × 连通性 扫描 |
| `bootstrap_stability.m` | 逐帧 bootstrap 置信区间 + 稳定区判定 |
| `make_gaussian_spec.m` | 构造真正生效的高斯配置（见第 5 节的坑） |
| `plot_percolation_diagnostics.m` | Phase 1 四面板诊断图 |
| `plot_sensitivity_diagnostics.m` | Phase 2 主效应图 + sigma×closing 响应面 |

入口脚本：
- `tools/run_r2_structure_diagnostics.m` — 原始诊断（Phase 1 窄扫描 + Phase 2）
- `tools/run_r2_wide_percolation_sweep.m` — 宽扫描 + seed_alpha 联合标定（2026-08-24 新增）

## 3. 运行

```bash
matlab -batch "run('tools/run_r2_structure_diagnostics.m')"
```

输出（不覆盖任何正式产物）：

- `cases/per_case/tandem_baseline_r2/output/mat/09d_percolation_sweep.mat`
- `cases/per_case/tandem_baseline_r2/output/mat/09d_sensitivity_sweep.mat`

实测单帧成本（89×640 网格，R2022b）：识别 0.060 s，高斯预处理 0.005 s。

## 4. 两个阶段的设计意图

### Phase 1 — 逾渗标定（判 `alpha` 与连通性）

扫描 `alpha = 0.25:0.05:0.65`，连通性 `{4, 8}`，480 帧（两个 repeat 各 240 帧分层抽样）。

**关键设计**：Phase 1 刻意关闭 `min_pixels`、闭运算、孔洞填充、长宽比与边界剔除
（`min_pixels=1`、`max_internal_hole_pixels=0`、`envelope_closing_radius_cells=0`）。
逾渗理论关心的是阈值场本身的连通拓扑，若先做形态学修补，测到的就不再是阈值的逾渗行为。
正负号仍然分开标记，与生产一致——高速与低速区可以相邻但永不合并为一簇。

指标：

- `max_component_ratio = A_max / ΣA`：逾渗序参量。→1 表示一簇吞掉全场（误合并）；→0 表示全场碎化（误分割）
- `n_components`：簇数
- `occupancy`：阈值占据的有效域比例
- `susceptibility`：剔除最大簇后的二阶矩簇尺寸，逾渗转变处应出现峰值
- `small_component_fraction`：低于分辨率下限的簇占比

### Phase 2 — 预处理与形态学敏感性（判痛点 C）

固定 `alpha` 为生产值，扫描
`sigma ∈ {0.8, 1.0, 1.5, 2.0, 2.5}` ×
`seed_alpha ∈ {0.50, 0.60, 0.70, 0.80}` ×
`closing ∈ {0,1,2,3}` × `hole ∈ {16,32,64,128}` × 连通性 `{4,8}`
= 640 组，120 帧子样本。

**关键设计**：Phase 2 跑**完整生产流水线**（含全部形态学与剔除），
因此输出的几何量就是各参数选择下分析真正会报告的结果。

误分割诊断：`median_area` 下降、`tail_area_share` 变薄、`n_structures` 上升、
`small_component_fraction` 上升。

误合并诊断：`rejected_boundary` 上升（合并后的大团更易触边）、
`p95_aspect_ratio` 膨胀（细长噪声桥）、`lsm_count`/`vlsm_count` 下降
（独立结构被吸收进更少更大的团）。

## 5. 稳定区判定规则

`bootstrap_stability.m` 以**整帧**为重采样单位（帧内像素空间相关，
按像素重采样会严重低估不确定度），默认 500 次重采样、95% 区间。

稳定区要求连续至少 3 个扫描点同时满足：

1. 相邻 bootstrap 区间**重叠**
2. 中位数相对变化 **≤ 10%**

只满足其一不算稳定：条件 1 在区间很宽时过于宽松，条件 2 单独使用则忽略抽样误差。
若不存在这样的区间，函数返回 `stable_found = false` 并给出扩展扫描的提示，
**不会**退而输出一个勉强的推荐值。

## 6. [已修复] 高斯 sigma 生效缺陷

**2026-08-24 已修复**：`structure_analysis_cache.m` 中 `structure_preprocessing()` 的方向性字段预填
已移除，`sigma_cells=1.5` 现在正确传导到 `sigma_x_cells=1.5`、`sigma_y_cells=1.5`，
实际生效核为 9×9。

修复前的问题描述（历史记录）：

`simple_gaussian_filter2` 只用**方向性字段**
（`sigma_x_cells`、`sigma_y_cells`、`radius_x_cells`、`radius_y_cells`）构造卷积核。
它的 `normalize_options` 仅在这些字段**缺失或为空**时才从标量别名
`sigma_cells`/`radius_cells` 回填。

而 `structure_analysis_cache.m` 里的 `structure_preprocessing()` 会把方向性字段
预填为**非空默认值** `sigma 0.8 / radius 1`。于是案例脚本里设置的
`cfg.structures.preprocessing.gaussian.sigma_cells = 1.5` 与 `radius_cells = 4`
**永远到不了卷积核**。

实测证据（对 `09_structure_analysis.mat` 中缓存的生产 spec 打冲激响应）：

| spec | 有效 sigma | 冲激响应非零点数 |
|---|---|---|
| 缓存的生产 spec | 0.8 | **9**（即 3×3） |
| 配置本意 | 1.5 | 81（即 9×9） |

也就是说：产物名 `Gaussian_sigma1p5_9x9`、`cfg` 与 `docs/README_vlsm_cluster_method.md`
都声称 σ=1.5、9×9，**实际生效的是 σ=0.8、3×3**。

这直接关系到"斑点噪声导致误分割"的痛点：实际平滑强度远低于预期。

**本工具没有修改这个行为**（按约定不动正式识别逻辑）。
诊断侧通过 `make_gaussian_spec.m` 显式设置四个方向性字段来保证 sigma 真正生效，
并在 Phase 1 中同时标定 `as_cached`（σ=0.8/3×3，即当前真实生产状态）
与 `intended_sigma1p5`（σ=1.5/9×9）两种平滑水平——
因为最优 `alpha` 依赖于其前置平滑强度，两者不能混用同一个推荐值。

是否修正这个 bug 属于正式逻辑变更，需要单独决策。

## 7. 解释限制

- 二维截面无法恢复展向尺度与真实三维连通关系
- 逾渗曲线只能判定"阈值选择是否稳健"，不能证明识别出的结构在动力学上独立
- `min_pixels` 是分辨率下限，不是结构独立性的证明
- 稳定区推荐值是操作性口径，仍需与文献常用区间交叉核对
