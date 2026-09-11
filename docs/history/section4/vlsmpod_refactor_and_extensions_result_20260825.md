# POD-VLSM 聚类连通法：重构验收 + 三功能扩展小样本结果

日期：2026-08-25　分支：2026-08-22　MATLAB R2022b

---

## 一、重构验收：四组逐位相同

验收标准是逐位相同、不设容差——重构没有改动任何算术，不该出现浮点差异。

| 条件 | 行数 | 列数 | 结果 |
|---|---|---|---|
| gaussian / sampled（24 帧） | 995 | 34 | 逐位相同 |
| gaussian / continuous（48 帧） | 2162 | 34 | 逐位相同 |
| pod_E50 / sampled（24 帧） | 276 | 34 | 逐位相同 |
| pod_E50 / continuous（48 帧） | 542 | 34 | 逐位相同 |

比对范围是 catalog 全部 34 列 + `per_frame` + `summary` + `frame_ids`，用 `isequaln`
（NaN 位置也要一致）。三个扩展全关时列集合与基线完全相同。

基线本身的可信度：与 handoff 记录的已认可数值吻合到小数位——gaussian 每帧
41.46/3.88/0.50（记录 41.5/3.88/0.50），E=50% rank=382、每帧 11.50/3.83/0.71
（记录 11.5/3.83/0.71）。

复现命令：

```bash
"D:/Academic/Software/MATLAB/R2022b/bin/matlab.exe" -batch "addpath(pwd); addpath(fullfile(pwd,'tools','r2_diagnostics')); verify_refactor_equivalence()"
```

### 重构做了什么

`structure_opts` / `trusted_domain_spec` / `structure_preprocessing` / `pick` /
`load_case_config` / `mean_field_for_frame` / `annotate_structures` 这一组函数原先在
4 个入口脚本里各有一份**逐字副本**（`run_structure_pod_denoise`、
`run_pod_energy_sweep`、`run_pod_sweep_visual_audit`、
`run_pod_lowrank_structure_diagnostic`）。根因写在原代码注释里：它们是
`structure_analysis_cache.m` 的私有局部函数，外部取不到。后果是改一处阈值口径要同步
改 4 份，漏一份就悄悄跑出不可比的结果。

现收进 `+tblR2/+vlsmpod/` 的唯一实现，12 个文件各司一职：

| 文件 | 职责 |
|---|---|
| `load_case_config.m` | 读 `00_case_configuration.mat` |
| `resolve_settings.m` | cfg.structures + overrides → opts/trusted_domain/preprocess_spec/merge_opts |
| `prepare_context.m` | 几何上下文（delta_grid、masks、dx/dy、壁面单位、dt） |
| `frame_field.m` | 单帧 u'/v'/mask（POD 或 Gaussian 两条路径） |
| `identify_frame.m` | identify_structures + 可选流向合并 |
| `run_catalog.m` | 帧循环 + 汇总，即插即用主入口 |
| `annotate.m` | 插 FrameID/Branch/Preprocessing 列 |
| `classify_wall_attached.m` / `wall_attached_statistics.m` | 功能 (a) |
| `decompose_superstructure.m` / `superstructure_statistics.m` | 功能 (b) |
| `track_structures.m` | 功能 (c) |

`run_structure_pod_denoise.m` 410 行 → 245 行薄壳，签名/返回字段/落盘内容不变。

**数值核心一行未改**：`identify_structures.m`、`+vlsm/merge_streamwise_neighbors.m`、
`+vlsm/structure_geometry.m`、`+vlsm/connected_components_2d.m`、
`pod_denoise_prepare.m`、`pod_denoise_reconstruct_frame.m` 全部字节不变。三个新功能都
实现为 identify 之后的后处理装饰器，不介入连通判定。

`resolve_settings` 另外把旧参数陷阱收成一个告警点：读到 alpha=1.77/seed=1.97（缓存
里固化的、实测 VLSM=0 的值）时显式 warning。原先这个陷阱靠 4 处注释提醒。

---

## 二、功能 (a) Wall-Attached 分类

判据改用外尺度，因为内尺度在本数据上不可用：**dy=0.515 mm → 每行 Δy⁺=33.7，最低可测
行就在 y⁺=33.7**，缓冲层（y⁺<30）整个落在测量域外，Hwang & Sung 的 y_min⁺≈0 恒为空集。
采用 `YMin_over_delta < 0.05`（对应 y⁺<111，最低 3 行）。

24 帧 / 276 个结构（E=50%, alpha=0.40/seed=0.70/conn=8）：

| 量 | 本数据 | Hwang & Sung 2018 |
|---|---|---|
| attached 数量占比 | 42.8%（118/276） | 20% |
| attached 面积/体积占比 | 60.3% | 67% |

面积占比 60.3% 与文献的体积占比 67% 接近；数量占比 42.8% 是文献的 2 倍多。这个差异是
判据宽严不同的直接后果，不是物理发现：外尺度 y⁺<111 比内尺度 y_min⁺≈0 宽得多，必然
纳入更多结构。`YMin_plus` 实测分界干净——attached 33.7-101.0，detached 134.7-2728.3，
正好是前 3 行与第 4 行以上。

**两者不可直接对标**，报告时必须声明判据差异。

Population density n_s(l_y) 对数分 bin 后从 21.32（l_y=1.2 mm）降到 1.577
（l_y=36.6 mm）：l_y 增大 30 倍、密度降 13.5 倍，双对数斜率约 −0.76，比
attached-eddy hierarchy 预言的 −1 平缓。但**118 个 attached 结构分 12 个 bin，每 bin
只有 3-18 个，这个斜率不足以支持或否证幂律**。

---

## 三、功能 (b) 超结构自相似分解：默认参数会压掉真界面

24 帧里 17 个 VLSM。默认 `amplitude_factor=0.5` 下 14 个只切出 1 段，平均 1.29 段。

**这个「1 段」是参数造成的，不是 concatenation hypothesis 不成立。** 诊断证据：逐
VLSM 看，v' 剖面 vbar 的原始符号变化有 6-19 次，但 max|vbar| 只有 0.7-1.9 而门限
0.5·v_rms≈0.6，三值化的零区吞掉了大部分变号。

敏感性（同一 17 个 VLSM）：

| amplitude_factor | 0.50 | 0.30 | 0.20 | 0.10 | 0.05 |
|---|---|---|---|---|---|
| 平均子结构数 | 1.29 | 2.06 | 2.53 | 3.00 | 3.24 |

曲线没有干净的平台段，**17 个样本也不足以定标定值，所以我没有改默认值**。改为把参数
随行落表（`SubAmplitudeFactor`、`SubMinLengthDelta`）并在 `superstructure_statistics`
输出 `caveats` 结构体（`amplitude_factor_calibrated=false`、`sample_adequate=false`），
让未标定状态无法被误读。正式标定应比照 alpha 的做法——宽扫描 + bootstrap 找稳定区，
样本量到数百个 VLSM。

另一处口径限制已做成字段（`reaches_superstructure_scale=false`）：Deshpande & Marusic
的 superstructure 定义是 Lx>6·δ99，本数据 VLSM 只到 3.04-5.19·δ99，**尚未进入他们报告
concatenation 的尺度段**。总长-段长相关 0.312 在 17 个样本（其中 14 个 NSub=1，几乎无
方差）上没有解释力。

---

## 四、功能 (c) 时间分辨追踪：Galilean 补偿确实在起作用

实测帧间对流位移 **45.7 格**（handoff 估的是 ~5 格，差一个量级——U_c 实际 24.5 m/s 而非
5 m/s）。位移是 0.75·δ99，所以逐结构 Galilean 补偿是必需项而非可选项。

关键验证（48 连续帧，overlap 阈值 0.2）：

| | continuation | split | merge | track 数 | 最大寿命 |
|---|---|---|---|---|---|
| 补偿开 | **240** | 107 | 83 | 302 | 12 帧 |
| 补偿关 | **95** | 204 | 149 | 447 | 6 帧 |

补偿把 continuation 提高 2.5 倍、split 减半。补偿有效。

overlap 阈值从 0.05 扫到 0.5，continuation 只在 233-246 之间变动，寿命中位恒为 1.0
——所以短寿命**不是阈值问题**。

未截断寿命中位 1.0 帧的成因有两条，都已做成 `caveats` 字段：

1. **小碎片主导**。PixelCount 分位 p10=42 / p50=356，12.2% 的结构 <50 px。
   `min_pixels_for_track=500` 时寿命中位升到 2.0。
2. **split/merge 按设计断链**（Lozano-Durán 同样把分裂视为 track 终止 + 新分支），
   断链链接占全部链接的 44%，机械压低寿命中位数。

**最大寿命 12 帧已达 FOV 穿越时间 14.0 帧的 86%**（FOV 640 格 ÷ 45.7 格/帧）。寿命上限
由 FOV 决定，不是物理寿命——`caveats.lifetime_ceiling_is_fov=true` 会自动标出。
**T ∝ V^(1/3) 不可在此数据上拟合。**

事件率有两种口径，已分开命名避免混淆：链接口径 split/merge = 107/83
（2.28/1.77 每帧对，与事件表一致），节点口径 = 50/43（一裂为三记 1）。
direct/inverse cascade 之比 1.29，与 Lozano-Durán & Jiménez 报告的「正向略强于逆向」
方向一致，但 48 帧窗口（< 4× FOV 穿越时间）不足以定量。

---

## 五、测试状态

| 项 | 结果 |
|---|---|
| `python tests/matlab_check.py` | 通过，319 个 .m 文件 |
| `test_r2_library_contract.m` | PASS（硬约束） |
| `test_r2_vlsmpod_extensions.m` | PASS（新增，12 个子测试） |
| 等价性验证 | 四组逐位相同 |
| 全量套件 | 29 passed / 2 failed |

两个失败是**既有问题，与本次重构无关**：

- `test_compact_case_contract`：case 文件里是 `cfg.stages = struct('cache', 'reuse')`，
  测试要求 `'compute'`。
- `test_r2_baseline_control_contract`：baseline/control 两个 case 脚本的 Section 1-9
  正文有差异。

证据：两个 case 脚本的 mtime 都是 2026-08-24 20:18，本次改动集里没有任何 case 脚本
（改动集为 `+vlsmpod/` 12 个新文件、`run_structure_pod_denoise.m`、3 个诊断工具、
1 个新测试、`matlab_check.py` 一个字符）。

顺带修了 `matlab_check.py` 的一个真实缺口：它减除数组下标 `end` 的字符集是
`)]},-+:`，**不含 `}`**，所以 `c{end}` 被误判成块结束符。MATLAB 自己的 `checkcode`
对同一文件报 0 解析错误。已补上 `}`（只会多减、不会漏报，不影响其他文件）。

---

## 六、新增文件

库模块（`cases/per_case/tandem_baseline_r2/+tblR2/+vlsmpod/`）：
`load_case_config.m`、`resolve_settings.m`、`prepare_context.m`、`frame_field.m`、
`identify_frame.m`、`run_catalog.m`、`annotate.m`、`classify_wall_attached.m`、
`wall_attached_statistics.m`、`decompose_superstructure.m`、
`superstructure_statistics.m`、`track_structures.m`

工具（`tools/r2_diagnostics/`）：
`capture_structure_baseline.m`（基线固化）、`verify_refactor_equivalence.m`（逐位比对）、
`run_vlsmpod_extension_audit.m`（三功能抽查）

测试：`tests/test_r2_vlsmpod_extensions.m`

产物：`tmp/refactor_baseline/`（基线 + 验证报告）、
`tmp/vlsmpod_audit/vlsmpod_extension_audit.mat`

未改动：`tandem_baseline_r2_case.m`、`identify_structures.m`、`+vlsm/*`、`+tbl/` 旧包、
`cases/*/output/` 下任何正式产物。

---

## 七、下一步该做什么

按收益排序：

1. **全量 12000 帧**（用户已确认等其指令）。三个功能都已就绪，`run_catalog` 直接接
   `frame_ids=1:12000`。注意时间追踪需按 repeat 分段——第 6000/6001 帧之间不是物理连续。
2. **标定 (b) 的 amplitude_factor**。这是 (b) 能否给出可用结论的前提。做法比照 alpha：
   宽扫描 + bootstrap 稳定区，样本量到数百个 VLSM（全量 12000 帧约可得 8500 个 VLSM）。
3. **(a) 的 attached 阈值敏感性**。0.05 是按「最低 3 行」定的，应扫 0.02-0.15 看数量/
   面积占比的稳定性。
4. **(c) 若要寿命统计**，需要更长的连续窗口，且必须用 survival analysis 处理 FOV 截断
   （Kaplan-Meier 之类），不能直接取中位数。或者只报 split/merge 事件率——那个量对
   截断不敏感。
