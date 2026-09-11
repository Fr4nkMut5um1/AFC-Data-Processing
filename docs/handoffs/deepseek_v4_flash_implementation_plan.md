# 双源 PIV 数据接入实施计划（交付 deepseek-v4-flash GA 编程）

生成时间：2026-08-05（v2，已并入用户 6 项决策）
基线提交：`6306750 fix: address fable5 review findings`（18/18 测试通过）
分支：`codex/section-0-9-review`

---

## 0. 本计划要解决的问题

正式数据位于 `J:\Export0731\TempData0731_LinZheng`，每个工况同时提供
**PIV 原始数据**与 **PostProc 后处理数据**两套 `B####.dat`。业务规则：

| 用途 | 数据源 |
|---|---|
| 统计量、相位平均、谱、POD/DMD/SPOD、相关、输运、摩阻 | **PIV 原始** |
| 瞬时场绘图呈现 | **PostProc** |
| 聚类连通法（LSM/VLSM） | **PostProc** |

当前代码只有单一 `cfg.data_root`，无法表达"同一 case 两个数据源"。
本计划即为此改造，并处理随之暴露的数据契约冲突。

## 0.1 用户已决策事项（不再讨论）

| 项 | 决策 |
|---|---|
| 网格尺寸 | **按实测填**：Parallel `[640 90]`、Tandem `[640 91]` |
| 帧数取向 | **取后 6000 帧**（6050 帧目录 → `B0051..B6050`） |
| `1st/2nd/3rd` | **同参数紧接着做的重复实验** → 各自独立 case，不拼接，Level 2/3 做集合平均 |
| `dy_h` | **由人工选定**，代码不得自动标定；需提供选定辅助产物 |
| baseline `u_tau` | **重新选定**，不沿用旧值 `0.95116051437100702` |
| 小范围工况 | **3 个**：`Tandem_Baseline`、`Tandem_f40A3_Phi+0`、`Parallel_Baseline`（均用 `_1st`） |

---

## 1. 已核实的数据事实（勿重新调查）

### 1.1 目录结构

```
J:\Export0731\TempData0731_LinZheng\
├── Parallel\        38 个目录 = 13 工况 × {PIV, PostProc} × {1st/2nd/3rd}
└── Tandem\f40A3\    40 个目录 =  9 工况 × {PIV, PostProc} × {1st/2nd/3rd}
```

命名规律：`{构型}_{工况}_{PIV|PostProc}_{1st|2nd|3rd}`，PIV 与 PostProc 严格成对。

工况清单（13 + 9 = 22 个独立工况）：

- Parallel：`Baseline`、`f40A1_Phi{+0,+30,+90,+180}`、`f40A3_Phi{+0,+30,+90,+180}`、`f80A1_Phi{+0,+60,+90,+180}`
- Tandem：`Baseline`、`f40A3_Phi{+0,+30,+45,+90,-30,-45,-90}`

### 1.2 文件格式（PIV 与 PostProc 完全一致）

```
TITLE = "B0001"
VARIABLES = "x [mm]", "y [mm]", "Velocity u [m/s]", "Velocity v [m/s]", "isValid"
ZONE T="Frame 0", I=640, J=90, F=POINT
STRANDID=1, SOLUTIONTIME=0.051046588
```

4 行表头 + 5 列 POINT 数据，与 `tbl.io.load_tecplot_dat` 现有约定一致。
**结论：加载器的解析逻辑无需改动**（但需加帧偏移参数，见 §2.3）。

### 1.3 网格尺寸（与现有 case 脚本冲突）

| 数据集 | 实测 ZONE | 现有脚本 `cfg.grid_size` |
|---|---|---|
| Parallel（PIV 与 PostProc） | `I=640, J=90` | `[640 98]` ❌ |
| Tandem（PIV 与 PostProc） | `I=640, J=91` | `[640 98]` ❌ |

`load_tecplot_dat` 第 53-54 行直接信任 `cfg.grid_size` 并
`reshape(data(:,3), I, J)`。实际 57600 行 vs 声明 62720 行 → **reshape 硬报错**，
不会静默出错。新脚本按实测填写（用户已决策）。
**注意 Parallel 与 Tandem 网格不同，不可共用一份配置。**

### 1.4 采样率核实

`SOLUTIONTIME` 前三帧：0.051046588 / 0.052088258 / 0.053129928
→ dt = 1.04167e-3 s → **fs = 960 Hz**，与 `cfg.fs = 960` 一致 ✅
→ `f0_hz=40`、`n_bins=24`（960/40=24）自洽 ✅

### 1.5 帧数与"取后 6000 帧"

实测：文件编号**连续无缺号**，从 `B0001` 起。

| 目录 | 帧数 | 取后 6000 帧 → |
|---|---|---|
| `Tandem_Baseline_PIV_1st` | 6000 | `B0001..B6000`（偏移 0） |
| `Tandem_f40A3_Phi+0_PIV_1st` | 6000 | `B0001..B6000`（偏移 0） |
| `Parallel_Baseline_PIV_1st` | 6000 | `B0001..B6000`（偏移 0） |
| `Parallel_Baseline_PIV_2nd` | 6050 | `B0051..B6050`（偏移 50） |
| `Parallel_f40A3_Phi+0_PIV_1st` | 6050 | `B0051..B6050`（偏移 50） |
| `Parallel_f80A1_Phi+0_PIV_{1,2,3}` | 6050 | `B0051..B6050`（偏移 50） |

**三个 pilot 工况恰好都是 6000 帧，偏移为 0。** 因此偏移功能可以先实现、
用合成数据测试，而 pilot 真实运行时走偏移 0 路径——风险被自然隔离。

**当前代码不支持偏移**：`load_tecplot_dat` 第 166 行按
`sprintf('B%04d.dat', iframe)` 直接用帧号构名，`dat_manifest` 第 16 行
硬编码 `for iframe = 1:n_frames`。必须新增偏移参数（见 §2.3）。

### 1.6 PIV 与 PostProc 的实际差异（重要）

以 `Parallel_Baseline_*_1st/B0001.dat` 逐点比对（57600 个数据点）：

| 指标 | 数值 |
|---|---|
| `isValid==0` 点数（PIV） | 3179 |
| `isValid==0` 点数（PostProc） | 2432 |
| u 值发生变化的点数 | 2180 |
| 其中 PIV 原本 `isValid==0` | 747 |
| 其中 **PIV 原本 `isValid==1`** | **1433** |
| PIV 有效 → PostProc 无效 | 0 |

**关键结论：PostProc 不只是填补空洞。** 它同时修改了 1433 个 PIV 已判定有效
的矢量（平滑/替换离群值）。这正是"统计量必须用原始、瞬时呈现可用后处理"
的物理依据——PostProc 的平滑会系统性削弱脉动量与谱能量。

**该差异必须写入产物元数据和图注**，否则读者无法判断某张瞬时图与某条谱
曲线是否来自同一数据源。

### 1.7 数据体量

单帧 ~2.03 MB → 单目录 6000 帧 ≈ **12.2 GB**；78 个目录合计 ≈ **950 GB**。
单 case 双源缓存（单精度 6000×J×640 × 2 场 × 2 源）≈ **5.5 GB**。
→ 3 个 pilot 双源缓存 ≈ **16.5 GB**，可接受；不可一次性全建 22 工况。

---

## 2. 设计决策

### 2.1 用 `cfg.sources` 结构替代单一 `data_root`（保持向后兼容）

```matlab
% 新增：双源声明
cfg.sources.raw       = '...\Tandem_Baseline_PIV_1st';       % 统计/谱/模态
cfg.sources.postproc  = '...\Tandem_Baseline_PostProc_1st';  % 瞬时呈现/聚类

% 保留：cfg.data_root 继续等于 cfg.sources.raw，令既有 18 个测试与
% stage_contract/write_case_card 无需改动即可通过。
cfg.data_root = cfg.sources.raw;
```

**理由**：`data_root` 出现在 17 个文件中（含 `stage_contract`、
`load_stage_result` 的指纹校验）。若直接改名，全部缓存指纹失效且改动面
过大。让 `data_root` 保持为"主源（raw）"语义，是最小侵入的方案。

### 2.2 两个独立序列缓存

```
output/periodic_piv/<case>/mat/01_sequence_cache.mat            % raw（现有路径不变）
output/periodic_piv/<case>/mat/01_sequence_cache_postproc.mat   % 新增
```

`postproc` 缓存**只在需要时构建**：`cfg.stages.structures ~= 'skip'`
或瞬时图任务启用时。Section 2/3/5/6/7 一律不碰它。

缓存指纹（`cache_meta`）增加 `source_role`（`'raw'`/`'postproc'`）与
`source_root`。`validate_existing_cache` 硬校验 `source_role` 匹配——
把 postproc 缓存当 raw 复用是本次改造**最危险的静默出错路径**。

### 2.3 帧偏移 `cfg.frame_offset`（取后 N 帧）

新增字段，语义为「跳过前 `frame_offset` 个文件」：

```matlab
cfg.n_frames     = 6000;
cfg.frame_offset = 0;   % 6000 帧目录；6050 帧目录填 50
% 实际读取文件 = B{frame_offset+1} .. B{frame_offset+n_frames}
```

**由脚本显式填写，不自动推断。** 自动数文件个数再反推偏移，会在目录
被误增删一个文件时静默改变分析窗口——宁可报错也不要猜。
`validate_config` 校验 `frame_offset` 为非负整数，且
`frame_offset + n_frames` 不超过目录实际文件数（构建缓存时校验）。

**必须改动的两处硬编码**：

1. `+tbl/+io/load_tecplot_dat.m:166`
   `sprintf('B%04d.dat', iframe)` → `sprintf('B%04d.dat', iframe + frame_offset)`
   （新增可选入参 `frame_offset`，默认 0）
2. `+tbl/+singlecase/dat_manifest.m:16`
   `for iframe = 1:n_frames` → 同样加偏移，令 manifest 记录**真实文件名**

**相位不受影响**：`phase_stats_cache.m:52` 调用
`assign_phase((1:n_frames)', ...)`，即相位基于**缓存内序号**而非源文件号。
偏移后缓存的第 1 帧就是 `B0051`，相对相位 0° 落在它身上。由于
`phi0_user_deg` 目前为空、机械相位保持 `not_calibrated`，这在物理上是
自洽的（只有相对相位有意义）。**但若日后标定机械相位，必须记住
相位零点绑定的是 `B{frame_offset+1}`**——此点写入 `cache_meta` 与
`assignment.definition`。

`stage_contract` 的 `cache` 与 `phase` 分支须纳入 `frame_offset`，
否则改了偏移而复用旧缓存会得到错窗口的结果。

### 2.4 `dy_h` 与 `u_tau` 人工选定（代码只提供依据，不自动决定）

用户已决策二者均由人工选定。代码侧的职责边界：

- **不得**自动扫描并"选出最优 `dy_h`"后静默使用。
- **应当**产出选定辅助材料：`dy_h` 候选扫描表（每个候选值对应
  `u_tau`、`Cf`、`RMSE`、`Re_theta`、`delta99`）+ log-law 拟合诊断图，
  写入 `csv/` 与 `png/`，供人工判读后回填脚本。
- `cfg.loglaw.params.dy_h` 与 `cfg.normalization.baseline_u_tau` 保持
  **必填、无默认值**；缺失即报错（阶段 A 已强化的校验继续生效）。
- 受控工况的 `baseline_u_tau` 必须来自**同构型**的新 baseline
  （Tandem 受控 ← Tandem baseline；Parallel 受控 ← Parallel baseline）。
  旧值 `0.95116051437100702` 作废，不得沿用。

### 2.5 `1st/2nd/3rd` 作为独立重复 case

用户确认为「同参数紧接着做的重复实验」。因此：

- 每个 repeat 是**独立 case**（独立 `case_id`、独立 `output_dir`、独立缓存），
  **不拼接**成一条长序列。
- 理由：拼接会在接缝处引入相位不连续与非平稳，污染谱与相位平均。
- 重复间的集合平均属于 **Level 2/3**（P20），单 case 仍为 `DEFERRED`。
- `case_id` 命名带 repeat 标识，例如
  `single/tandem_baseline_r1`、`single/parallel_baseline_r1`。
- 三个 pilot 均使用 `_1st`。

---

## 3. 分阶段任务（交付 deepseek-v4-flash 按序执行）

> 每阶段独立可测、独立提交。**每阶段必须跑全量测试确认不回归**
> （基线 18 passed / 0 failed，新增用例只增不减），
> 且只用合成数据 + 临时目录，**不得触发真实 6000 帧计算**（阶段 H 除外）。

### 阶段 A：`cfg.sources` 与 `cfg.frame_offset` 契约校验（不改行为）

1. `+tbl/+periodic/validate_config.m`
   - `require_fields(cfg, 'sources', {'raw','postproc'}, 'cfg.sources')`，
     两者均须非空文本。
   - 校验 `cfg.data_root` 与 `cfg.sources.raw` 一致，不一致报错。
   - 校验 `cfg.sources.postproc ~= cfg.sources.raw`。
   - 新增 `cfg.frame_offset`：非负整数标量（允许 0）。
2. `+tbl/+periodic/stage_contract.m`
   - 顶层公共段加入 `contract.frame_offset = cfg.frame_offset;`
     （影响所有 stage：换窗口则全部失效，这是正确的）。
   - `structures` 分支加入 `contract.postproc_source = cfg.sources.postproc;`
3. 测试 `tests/test_section0_rewrite.m` 新增：
   缺 `sources` / `raw~=data_root` / `postproc==raw` / `frame_offset` 缺失
   / `frame_offset` 为负或非整数 → 均须报错。

**验收**：18 + 新增用例全过。

---

### 阶段 B：帧偏移贯通加载器与 manifest

1. `+tbl/+io/load_tecplot_dat.m`
   - 新增可选第 4 入参 `frame_offset`（默认 0，保证既有调用不变）。
   - 第 166 行文件名改为 `iframe + frame_offset`。
   - 表头打印/诊断中显示真实文件名，便于排错。
2. `+tbl/+singlecase/dat_manifest.m`
   - 新增 `frame_offset` 入参；manifest 的 `name` 列记录**真实文件名**
     （`B0051.dat` 而非 `B0001.dat`），并新增 `cache_index` 列
     （1..n_frames）以便对照。
3. `+tbl/+periodic/prepare_sequence_cache.m`
   - 全部 `load_tecplot_dat` 调用传入 `cfg.frame_offset`。
   - 构建前校验目录实际文件数 ≥ `frame_offset + n_frames`，
     不足则报错并写明缺口。
   - `cache_meta` 新增 `frame_offset`、`source_first_file`、`source_last_file`。
4. 测试 `tests/test_section1_sequence_cache.m` 新增：
   - 合成 6050 帧目录、`frame_offset=50` → 缓存首帧内容等于 `B0051`；
   - `frame_offset` 使窗口越界 → 报错；
   - `frame_offset=0` 与改造前结果逐位相同（回归保护）。

**验收**：新增 3 用例 + 全量通过。

---

### 阶段 C：`prepare_sequence_cache` 支持源角色

1. 签名扩展为 `prepare_sequence_cache(cfg, paths, source_role)`，
   默认 `'raw'` 以兼容现有调用。
2. 按 `source_role` 选择读取根与输出路径：
   - `'raw'` → `cfg.sources.raw` / `paths.sequence_cache`
   - `'postproc'` → `cfg.sources.postproc` / `paths.sequence_cache_postproc`
3. `cache_meta` 增加 `source_role`、`source_root`（`schema_version` 保持 1，
   仅追加字段）。`validate_existing_cache` 对**缺失**该字段的旧缓存报
   "旧版缓存，请重建"而非崩溃；`source_role` 不符 → 报错。
4. `+tbl/+periodic/build_paths.m` 新增
   `paths.sequence_cache_postproc = fullfile(paths.mat, '01_sequence_cache_postproc.mat');`
5. 测试新增：双源分别构建、文件名正确；postproc 缓存冒充 raw → 报错；
   旧缓存 → 可理解的重建提示。

**验收**：新增 3 用例 + 全量通过。

---

### 阶段 D：Section 4 结构分析改用 postproc 源

1. `+tbl/+periodic/run_case.m`
   - 在 statistics/mean_bl/phase 之后、structures 之前，若
     `cfg.stages.structures ~= 'skip'`，构建/复用 postproc 缓存。
     失败按现有 `exception_diagnostic` 记录并令 structures 走
     `dependency_stage`，**不得让整个 run_case 崩溃**。
   - `structure_analysis_cache` 传入 `paths.sequence_cache_postproc`。
2. **网格一致性硬校验**：postproc 缓存的 `X/Y/j_wall_removed` 必须与
   raw 缓存逐点相同（raw 均值要与 postproc 瞬时场相减）。不同则报错，
   **不得插值凑合**。同时校验两源 `frame_offset` 相同。
3. 新增诊断 `PIV-SOURCE-MIXED-BRANCH`（`LIMITED`），明确写出
   "瞬时场与结构分析来自 PostProc，统计量来自 PIV 原始"，
   落入 `01_diagnostic_messages.csv`。
4. 测试 `tests/test_section4_structure_analysis.m` 新增：
   - 双源合成数据（postproc 刻意填补部分无效点 **且** 修改部分有效点，
     复现 §1.6 特征）→ 结构分析读到 postproc 值，而 `u'` 均值基准仍来自 raw；
   - 网格不一致 → 报错。

**验收**：新增 2 用例 + 全量通过。

---

### 阶段 E：瞬时场绘图改用 postproc 源

1. `+tbl/+periodic/plot_products.m`
   - 瞬时类图（`plot_instantaneous_vortex`、`plot_cache_raw` 瞬时片、
     相位蒙太奇瞬时底图）改取 postproc 数据；
     **统计/谱/模态图一律不动**，仍来自 raw。
2. **图注强制标注数据源**：瞬时图标题追加 `[PostProc]`，
   统计类图追加 `[PIV raw]`。由
   `tests/test_singlecase_figure_style_contract.m` 新增断言固化。
3. 样式合同不得破坏：仍
   `contourf(...,'LineStyle','none') + colormap(ax, turbo(256)) + colorbar`。
   **注意该测试第 44 行断言 `colormap(ax, turbo(256))` 恰好出现 7 次**——
   若新增云图站点，必须同步更新该计数。
4. `tests/test_section9_export.m` 新增：导出清单中瞬时图与统计图的
   `source_role` 元数据不同且正确。

**验收**：新增 2 用例 + 全量通过。

---

### 阶段 F：VLSM / 聚类连通法改用 postproc 源

1. `+tbl/+vlsm/analyze_sequence.m`、`+tbl/+vlsm/plot_overlay.m`
   输入切换到 postproc 缓存。
2. 阈值 `alpha`、`min_streamwise_delta` 的物理含义随数据源改变
   （PostProc 平滑改变连通域边界）→ 结果结构记录 `source_role`，
   文档说明阈值是在 PostProc 数据上标定的。
3. `tests/test_vlsm_cluster_connectivity.m` 新增 `source_role` 断言。

**验收**：全量通过。

---

### 阶段 G：三个 pilot case 脚本（一 case 一脚本）

按用户指定的小范围工况建 **3 个**脚本，全部用 `_1st`：

| case_id | 构型 | grid_size | case_type | frame_offset |
|---|---|---|---|---|
| `single/tandem_baseline_r1` | Tandem | `[640 91]` | `baseline` | 0 |
| `single/tandem_f40a3_phi0_r1` | Tandem | `[640 91]` | `controlled` | 0 |
| `single/parallel_baseline_r1` | Parallel | `[640 90]` | `baseline` | 0 |

公共设置：`n_frames = 6000`、`formal_required_frames = 6000`、
`allow_debug_snapshot = false`、`fs = 960`、`chunk_frames = 48`。

受控工况额外：`phase.enabled = true`、`f0_hz = 40`、`n_bins = 24`、
`phi0_user_deg = []`（机械相位保持未标定）。
baseline 工况：`phase.enabled = false`（`validate_config` 会强制这一点）。

路径示例（Tandem baseline）：

```matlab
cfg.sources.raw      = 'J:\Export0731\TempData0731_LinZheng\Tandem\f40A3\Tandem_Baseline_PIV_1st';
cfg.sources.postproc = 'J:\Export0731\TempData0731_LinZheng\Tandem\f40A3\Tandem_Baseline_PostProc_1st';
cfg.data_root        = cfg.sources.raw;
```

**`dy_h` 与 `baseline_u_tau` 先留占位并加显著 TODO 注释**，
待阶段 H 产出辅助材料、人工选定后回填。
两个 Tandem 受控/基准共享同一 Tandem baseline 的 `u_tau`；
Parallel baseline 自成一套。**不得填旧值 `0.95116051437100702`。**

新增静态契约测试（仿 `tests/test_singlecase_scripts_contract.m`）：
`sources.raw`/`sources.postproc`/`frame_offset` 均须出现，
`grid_size` 与构型匹配，**禁止出现 `[640 98]` 与旧 `u_tau` 常量**。

**验收**：静态契约测试通过；**此阶段仍不跑真实数据**。

---

### 阶段 H：小样本真实数据冒烟 + `dy_h`/`u_tau` 选定材料（需用户批准）

**这是第一次接触真实数据，必须用户明确批准后才执行。**

1. 临时 case：`n_frames = 48`、`allow_debug_snapshot = true`、
   `chunk_frames = 24`、`frame_offset = 0`，指向
   `Tandem_Baseline_*_1st` 与 `Parallel_Baseline_*_1st`。
2. 只跑 `cache → statistics → mean_bl`，其余 stage 设 `skip`。
   输出写**临时目录**，不污染 `output/`。
3. 核对：`j_wall_removed` 是否合理（Tandem J=91 与 Parallel J=90 应
   去掉不同行数）、实测 `Uinf`、`u_tau` 量级。
4. **产出 `dy_h` 选定材料**：对候选 `dy_h`（如 1.2/1.6/2.0/2.4/2.8/3.2）
   逐一拟合，输出对照表（`u_tau`/`Cf`/`RMSE`/`Re_theta`/`delta99`）
   与 log-law 诊断图。**代码不选，交人工判读。**
5. 人工选定 `dy_h` 与各构型 baseline `u_tau` → 回填 3 个 pilot 脚本。

**验收**：人工判读物理量合理 → 再决定是否对 3 个 pilot 全量 6000 帧重算。

---

## 4. 不要做的事

- 不要重新设计一 case 一脚本 / Section 0-9 架构 / `+tbl/+periodic` 共享层。
- 不要把共享 helper 复制回 case 脚本；不要新增第二套参数校验。
- 不要改 `cfg.data_root` 字段名（会令所有缓存指纹失效）。
- 不要自动推断 `frame_offset`（数文件个数反推）；必须脚本显式填。
- 不要让代码自动选定 `dy_h` 或 `u_tau`；只产出辅助材料。
- 不要沿用旧 `baseline_u_tau = 0.95116051437100702`。
- 不要把 `1st/2nd/3rd` 拼接成单条长序列。
- 不要把 PostProc 数据用于统计量、谱、模态、输运、摩阻。
- 不要对 `archive/legacy_pipeline_20260715` 执行 `git add -A`。
- 不要提交/推送/删除/移动用户未跟踪文件：
  `AFC课题讨论V9-林正-20260718.pptx`、`docs/handoffs/`、
  `other_case_scripts/`、`t.m`、`t2.m`、`t3.m`；
  不要覆盖 `archive/README.md` 的未提交修改。
- 不要运行真实 3000/6000 帧全量计算（阶段 H 的 48 帧冒烟除外，且需批准）。

---

## 5. 仍需用户确认（不阻塞阶段 A–G）

1. **`dy_h` 候选范围**：上述 1.2–3.2 是否覆盖你想比较的区间？
2. **Tandem `f40A3_Phi+0` 的 `u_tau` 来源**：确认用 Tandem baseline
   而非 Parallel baseline？（计划按同构型配对。）
3. **pilot 全量重算时机**：阶段 H 判读通过后，是否立即对 3 个 pilot
   跑全量 6000 帧（每 case 双源缓存 ≈ 5.5 GB，3 个 ≈ 16.5 GB）？

---

## 6. 给 deepseek-v4-flash 的执行须知

- **模型定位**：设计决策已全部前置。执行侧只需按阶段落代码 + 写测试，
  不需要再做架构判断。遇到与本文件冲突的现场证据，**停下报告**，
  不要自行改设计。
- **每阶段结束**必跑：
  ```
  matlab -batch "files=dir(fullfile(pwd,'tests','test_*.m')); names=cellfun(@(f) fullfile(files(1).folder,f), {files.name}, 'UniformOutput', false); r=runtests(names); disp(table(r)); fprintf('passed=%d failed=%d\n', nnz([r.Passed]), nnz([r.Failed]));"
  ```
  基线 **18 passed / 0 failed**；新增用例只增不减。
- **提交粒度**：一阶段一提交，信息写清"改了什么 + 为什么改"。
  实际 commit 需用户授权。
- **合成数据原则**：新测试用合成 `B####.dat`（临时目录）。
  postproc 合成数据须**同时**填补部分无效点与修改部分有效点，
  真实复现 §1.6 的差异特征；帧偏移测试须造出 6050 帧目录。
- **阶段依赖**：A → B → C → D → E/F（E 与 F 可并行）→ G → H。
  B 必须早于 C，因为 `cache_meta` 字段要一次加齐避免二次失效。

