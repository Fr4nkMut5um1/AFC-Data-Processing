# POD-VLSM 聚类连通法：模块重构 + 三个功能扩展

日期：2026-08-25　分支：2026-08-22　MATLAB：R2022b

---

## 一、两个实测事实，都和 handoff 里的估计不同

开工前我先探了数据（`tmp/probe_wall_units.m`、`tmp/probe_convection.m`，只读）。两个数
和 handoff 的假设差得够多，足以改变功能 (a) 和 (c) 的设计。

### 事实 1：最低可测行在 y⁺ = 33.7，Hwang & Sung 的 y_min⁺≈0 判据恒为空集

```
dy = 0.515 mm  →  Δy⁺ = 33.7 每行
u_tau = 0.9675 m/s（local_loglaw）,  nu = 1.48e-5
y⁺ 范围（accepted_mask 内）= 33.68 … 2896.75
最低 5 个有效行的 y⁺ = 33.68 / 67.37 / 101.0 / 134.7 / 168.4
delta99 = 34.0 mm = 66.0 格,  delta99⁺ = 2223
```

缓冲层（y⁺<30）整个落在第一行以下，PIV 根本没测到。所以 attached 判据改用**外尺度**
（已确认）：`YMin_over_delta < 0.05`，对应 y⁺ < 111，即最低 3 行。物理含义是「结构根部
处于对数区下缘」，不依赖 u_tau 标定精度。同时输出连续列 `YMin_plus` 与
`YMin_over_delta`，阈值事后可任意重设，不必重跑识别。

**必须写进文档的声明**：这不是 Hwang & Sung 的内尺度 attached，两者不可直接对标。

### 事实 2：帧间对流位移是 ~50 格，不是 handoff 估的 ~5 格

handoff 假设 U_c ≈ 5 m/s。实测自由流 25.6 m/s，外层平均 24.5 m/s：

```
fs = 960 Hz  →  dt = 1.0417 ms
外层 U_c = 24.5 m/s  →  位移 25.5 mm = 49.6 格
位移 / delta99 = 0.75
逐高度位移：y/d99=0.05 时 31.5 格；y/d99=1.0 时 50.8 格（剪切导致相差 19 格）
```

后果有两条，都是硬约束：

1. **未补偿的 overlap 追踪不可行**。放宽阈值到 0.2 也救不回来——结构一帧移动 0.75δ99。
   必须做 Galilean shift 补偿，且因为剪切下不同高度位移差 19 格，**单一全局 U_c 会让近壁
   结构过度补偿**。方案：逐结构按其速度加权重心高度取 `Uavex` 的行平均作为该结构的 U_c，
   算整数格位移后平移像素集。残余位移 < 0.5 格。这也最接近 Lozano-Durán & Jiménez 的
   「结构以当地平均速度对流」。

2. **FOV 只够 12.9 帧的驻留时间**。FOV = 640 格 = 9.7δ99，穿越时间 = 640/49.6 ≈ 12.9 帧
   = 13.5 ms。一个 3δ99 长（198 格）的 VLSM，头尾在 FOV 内只有 442 格活动空间 ≈ 8.9 帧。
   **所以 T ∝ V^(1/3) 这个关系在本数据上必然被 FOV 截断严重低估（censoring bias）**。
   时间追踪能可靠给出的是「结构在 FOV 内驻留期间的 split/merge 事件率」，不是完整寿命
   分布。寿命统计只能作为下限报告，且必须标注截断比例（生命期触及 FOV 边界的结构占比）。

---

## 二、阶段 0：先建回归基线（重构前必做）

项目目前**没有任何回归基线机制**——测试全是合成数据的合同检查与解析参考值，没有「跑一次
存下来、下次比对」的机制。而本次要求是「功能和数值结果与重构前完全一致」。没有基线就无法
证明这一点，所以这是第一步，不是可选项。

新建 `tools/r2_diagnostics/capture_structure_baseline.m`：用**当前未改动的**
`run_structure_pod_denoise` 在固定帧集上跑，把完整 catalog 落到 `tmp/refactor_baseline/`。

帧集两组：
- **抽样组**：`denoise.frame_ids(1:500:end)` 共 24 帧，与已有 energy sweep 同帧集，可与
  已导出的 192 张审核图交叉核对。
- **连续组**：frames 1…48（在 repeat 1 内，不跨 6000 帧的 repeat 边界——第 6000/6001 帧
  之间不是物理连续的）。给时间追踪用。

两个预处理条件都存：`gaussian` 与 `pod_denoise` E=50%。识别参数用 r1 组
（alpha=0.40 / seed=0.70 / conn=8），因为实测只有这组能识别出 VLSM。

**E=50% 基底不重新分解**。已有 `tmp/pod_energy_sweep/pod_energy_sweep_basis.mat`
（2.6 GB，rank=2811 = E80）。POD 模态与截断秩无关，E=50% 就是它的前 382 阶，逐位相同。
直接 `mode_indices = 1:382` 取前缀，省掉 8–12 分钟的 12000×12000 特征分解。
（sweep 结果已确认 E=50% → rank=382。）

---

## 三、阶段 1：重构——把重复的样板收敛，数值核心一行不改

### 病灶：同一段 60 行样板被抄了 4 份

`structure_opts` / `trusted_domain_spec` / `structure_preprocessing` / `pick` /
`load_case_config` / `mean_field_for_frame` / `apply_overrides` 这一组函数，在下面 4 个
文件里各有一份**逐字复制**：

| 文件 | 重复的局部函数 |
|---|---|
| `cases/.../run_structure_pod_denoise.m` | 7 个 |
| `tools/r2_diagnostics/run_pod_energy_sweep.m` | 7 个 |
| `tools/r2_diagnostics/run_pod_sweep_visual_audit.m` | 7 个 |
| `tools/r2_diagnostics/run_pod_lowrank_structure_diagnostic.m` | 5 个 |

根因写在 `run_structure_pod_denoise.m:360` 的注释里：`structure_opts` 是
`structure_analysis_cache.m` 的私有局部函数，外部取不到，只能复制。这就是低内聚的来源——
改一处阈值口径要同步改 4 份，漏一份就悄悄跑出不可比的结果。

### 新建 `+tblR2/+vlsmpod/` 子包，做唯一的门面

七个新文件，每个只干一件事：

```
+tblR2/+vlsmpod/
  load_case_config.m      读 00_case_configuration.mat（含旧参数陷阱的唯一告警点）
  resolve_settings.m      cfg.structures + overrides → {opts, trusted_domain, preprocess_spec, merge_opts}
  prepare_context.m       cfg/stats/mean_bl → 几何上下文（X, Y_wall, delta_grid, masks, dx, dy, u_rms）
  frame_field.m           单帧 → total_U_f / total_V_f / structure_mask（POD 或 Gaussian 分支）
  identify_frame.m        frame_field + identify_structures + merge，返回单帧完整结果
  run_catalog.m           帧循环 + 汇总，即插即用的主入口
  annotate.m              补 FrameID / Branch / Preprocessing 列
```

`resolve_settings.m` 把「旧参数陷阱」收成一个点：读到 `alpha==1.77 && seed_alpha==1.97`
时打印显式告警，说明这是已知 VLSM=0 的固化值，需要 overrides。现在这个陷阱靠 4 份注释
提醒，很容易漏。

### 数值核心一行不改

`identify_structures.m`、`+vlsm/merge_streamwise_neighbors.m`、`+vlsm/structure_geometry.m`、
`+vlsm/connected_components_2d.m`、`pod_denoise_prepare.m`、
`pod_denoise_reconstruct_frame.m` —— **全部保持字节不变**。

理由：`identify_structures.m` 被主管线的 `structure_analysis_cache.m` 调用，而
`+tblR2/` 被 `tandem_baseline_r2` 与 `tandem_f40a3_phi0_r2` 两个工况共用。碰它就等于碰
主管线，与「效果完全一致」和「不修改 case 脚本」两条约束直接冲突。

三个新功能因此全部实现为**后处理装饰器**：在 `identify_structures` 返回之后，用它已经给出
的 `structures` 表 + `positive_labels` / `negative_labels` 标签图追加列。三个功能都不需要
介入连通判定本身，这个切面是干净的。

### 向后兼容

`run_structure_pod_denoise.m` 留在原路径、签名与返回字段全不变，内部改成 `+vlsmpod` 的
薄壳（预计 410 行 → ~70 行）。三个诊断工具同样处理。已有的调用方式和已落盘的产物读取
代码都不受影响。

---

## 四、阶段 2：三个功能扩展

三个都是 `+tblR2/+vlsmpod/` 内的独立模块，各自默认关闭，通过 `run_catalog` 的
name-value 参数开启。关掉时输出与重构后的基线逐位相同。

### (a) `classify_wall_attached.m` — Wall-Attached 分类

输入 structures 表 + delta_grid + u_tau/nu，追加 4 列：

| 列 | 含义 |
|---|---|
| `YMin_plus` | `YMin_mm * 1e-3 * u_tau / nu`，连续量 |
| `YMin_over_delta` | `YMin_mm / Delta99Ref_mm`，连续量 |
| `IsWallAttached` | `YMin_over_delta < attached_delta_threshold`（默认 0.05） |
| `AttachedDeltaThreshold` | 0.05，记录判据本身 |

再输出 attached/detached 的分组统计：数量占比、像素占比（对应 Hwang & Sung 的体积占比）、
`sum(|uMean| * PixelCount)` 占比（Reynolds 应力贡献的 2D 代理）。

加一个 population density 直方图：`log10(HeightY_over_delta)` 分箱内的 attached 结构计数，
用来检验 `n_s ∝ 1/l_y` 的 inverse power law。这是 attached-eddy hierarchy 最直接的可检验
预言，在 2D 截面上仍然成立（它是关于 y 方向自相似性的陈述，不需要展向信息）。

代价：几乎为零，纯表运算。

### (b) `decompose_superstructure.m` — 用 v' 找 VLSM 内部拼接点

对每个 `IsVLSM` 的结构：
1. 从标签图取它的像素集，得到流向跨度 `[XMin, XMax]` 与逐列的行范围。
2. 在结构内部逐列对 `v'` 做行向平均（只在结构像素上），得到 1D 剖面 `vbar(x)`。
3. 找 `vbar` 的零穿越点，做两道筛：幅值需超过 `v_rms` 的一定比例（默认 0.5，压掉噪声抖动）、
   相邻界面间距需超过 `min_sub_length_delta`（默认 0.5δ99，压掉毛刺）。
4. 界面把结构切成 N 段子结构，输出 `NSubStructures`、`SubLengthMedian_over_delta`、
   `SubLengthList`（cell 列）。

v' 是现成的——`frame_field` 已经算出 `total_V_f`，当前只是没往下传（`run_structure_pod_denoise.m:184`
算了它却只把 `total_U_f` 传给 identify）。POD 重构本来就同时给 U 和 V，不需要额外数据。

检验点：如果 concatenation hypothesis 成立，子结构长度应该聚集在 LSM 尺度（1–3δ99）而不是
随 VLSM 总长线性增长。

代价：每个 VLSM 一次列向 reduce，可忽略。

### (c) `track_structures.m` — 时间分辨追踪

**这一个受事实 2 的物理约束最重，必须按实测位移设计，不能照搬 handoff 的参数。**

逐帧对做匹配：
1. 对帧 k 的每个结构，取其 `CentroidVelWeightedY_mm` 所在行的 `Uavex` 行平均作为该结构的
   `U_c`（逐结构，不用全局值——剪切下不同高度差 19 格）。
2. 整数格位移 `shift = round(U_c * dt / dx_mm)`，把像素集在流向平移 `shift` 格。
3. 与帧 k+1 的结构算 overlap = `|A∩B| / min(|A|,|B|)`（用 min 而非 union，对分裂/合并不敏感）。
4. 阈值 0.2（handoff 给的值，在补偿后是宽松而非勉强）。构建二分图后判事件：
   1↔1 = continuation，0→1 = birth，1→0 = death，1→n = split，n→1 = merge。
5. 用 union-find 串起 track，输出每条 track 的 `lifetime_frames`、`n_splits`、`n_merges`、
   `max_pixels`、以及 **`touches_fov_boundary`**（生命期内是否触及流向边界）。

**FOV 截断必须显式报告**。`touches_fov_boundary == true` 的 track 其寿命是截断值。汇报时
分两组：未截断 track 的寿命分布（真值，但只覆盖短寿命结构，有选择偏差）与全部 track 的
寿命下限。`T ∝ V^(1/3)` 只在未截断子集上拟合，并标注该子集的尺度覆盖范围。**不报告未加
截断说明的平均寿命**——那个数在 FOV 只有 12.9 帧驻留时间的情况下是错的。

需要连续帧（stride=1）。小样本验证用 frames 1…48（repeat 1 内）。

代价：帧对之间 O(n_struct²) 的 overlap 计算，n_struct ~ 12（E=50% 实测每帧 11.5 个），
可忽略。

---

## 五、阶段 3：验证

### 数值一致性（这是「效果完全一致」的证明）

`tools/r2_diagnostics/verify_refactor_equivalence.m`：加载阶段 0 的基线，用重构后的
`+vlsmpod` 跑同一帧集同一参数，逐列 `isequaln` 比对 catalog。

- 数值列：要求逐位相同（`isequaln`，NaN 位置也要一致）。不设容差——重构不改算术，不该有
  浮点差异。若出现差异，说明重构改变了运算顺序，必须查到根因，不接受「差异很小」。
- 逻辑列（IsLSM / IsVLSM / CenterFallbackFlag）：要求完全相同。
- 三个新功能全关时，列集合也要与基线完全相同。

### 新功能正确性

`tests/test_r2_vlsmpod_extensions.m`（合成数据，沿用项目现有测试风格）：
- 手工构造已知 y_min 的结构，验证 `IsWallAttached` 与两个连续列的算术。
- 构造 v' 符号已知翻转 2 次的长结构，验证 `NSubStructures == 3`；再验证幅值筛与间距筛各自
  能压掉人为植入的噪声零穿越。
- 构造已知位移的两帧，验证 shift 补偿后 overlap 匹配成功、不补偿时失配；验证 split/merge/
  birth/death 四类事件各被正确识别。

### 现有测试必须继续 PASS

`test_r2_library_contract.m` 是硬约束。检查过它的断言：`required` 30 个函数都不动；
`excluded` 4 个名字（含 `benchmark_structure_tracking`）不会被我用到——新文件叫
`track_structures.m`，在 `+vlsmpod/` 子包内；不引入 `+r2` 层；`structure_analysis_cache.m`
不改所以行数与 token 黑名单都不受影响；case 脚本不改所以 `cfg.structures.tracking` 不会
出现。

`test_section4_structure_analysis.m:415` 对列名做精确匹配，但它测的是 `tbl.periodic.identify_structures`
（仓库根的 `+tbl/` 旧包），不是 `tblR2`。我不动旧包，这条不受影响。

全量套件 + `python tests/matlab_check.py` 串行跑一遍。

### 小样本产物

24 帧的对照报告（`tmp/refactor_baseline/` 下）+ 若干张带 attached/detached 着色与子结构
界面标注的审核图。**跑完停下等你确认，不自动跑 12000 帧**（已确认）。

---

## 六、不做什么

- 不修改 `tandem_baseline_r2_case.m`（硬约束）。
- 不修改 `identify_structures.m` 及 `+vlsm/*` 的任何算术。
- 不动 `+tbl/` 旧包。
- 不重新做 POD 分解（复用已有 E80 基底的前 382 阶）。
- 不删除任何已有产物、tmp 基底或 `tp*.mat`。
- 不 commit（除你明确要求）。
- 不把 24 帧结果称为正式验收；不外推三维结论；不把外尺度 attached 与 Hwang & Sung 内尺度
  口径混为一谈。
