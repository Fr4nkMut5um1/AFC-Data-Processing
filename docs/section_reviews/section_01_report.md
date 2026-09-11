# Section 1 独立重写对比（人工审阅稿）

## 状态

已完成 `section_01_handoff.md` 规定的全部流程：完整阅读 handoff/README 与 Section 1
相关源码 → 联网检索 → 独立重写 → 合成 DAT 验证 → 新旧对比 → 回写主工作区 → 针对性测试。
本轮为子代理执行的“独立评审/重写 → 测试 → 回写 → 报告”全过程；人工审阅由主进程最后统一进行。
未在验证阶段重建真实 3000/6000 帧缓存，仅对现有 `_cache/sequence_cache.mat` 做了只读复用验证。

与 handoff 的冲突说明：未发现冲突。handoff 中 “人工审阅后回写” 的步骤在本轮由主进程统一承担，
本报告即回写后的独立评审记录，供人工审阅。

## 联网检索结论（可复核来源）

- MathWorks 官方确认 `matfile` 是 v7.3（HDF5）MAT 文件的分块读写轮子；“For very large
  files, the best practice is to read and write as much data into memory as possible
  at a time”，单点反复访问会明显拖慢性能。
  https://www.mathworks.com/help/matlab/import_export/load-parts-of-variables-from-mat-files.html
- “Version 7.3 MAT files use an HDF5-based format that stores data in compressed
  chunks. The time required to load part of a variable ... depends on how that data
  is stored across one or more chunks.” —— 这支持本项目“帧维度预分配 + 整块读写”的缓存布局
  （`U/V/sampleValid` 的第三维是流向 x、第一维是帧），而不是逐元素访问。
  https://www.mathworks.com/help/matlab/import_export/mat-file-versions.html
- `matfile` 与 “Large MAT Files” 官方页面：
  https://www.mathworks.com/help/matlab/ref/matfile.html 、
  https://www.mathworks.com/help/matlab/import_export/large-mat-files.html
- Tecplot 官方说明 ASCII DAT 是“最简单、可读可写”的格式，但数据量大时 ASCII 存储效率快速
  下降 —— 支持“DAT → 单精度二进制缓存”这一 Section 1 核心动机。
  https://tecplot.com/2016/09/16/tecplot-data-file-types-dat-plt-szplt
- MATLAB Central 上已有 Tecplot ASCII DAT 读取轮子 tec2mat（fopen/textscan 逐文件解析），
  与项目 `tbl.io.load_tecplot_dat` 同思路；未发现可整体替换本项目的通用轮子，因此保留现有
  DAT 解析器，不复制进 Section 1。
  https://www.mathworks.com/matlabcentral/fileexchange/66237-matlab-tool-to-read-tecplot-ascii-dat-tec2mat
- 可复现科学计算领域：Schubotz et al. (2022) 明确把缓存列为可复现研究软件的一部分，并讨论
  失效策略（TTL、版本、显式失效）：
  “Caching and Reproducibility: Making Data Science Experiments Faster and FAIRer”，
  Front. Res. Metr. Anal. 7:861944，DOI 10.3389/frma.2022.861944，
  https://pmc.ncbi.nlm.nih.gov/articles/PMC9075102
- 数据溯源/清单校验文献（支持 `csv/01_source_manifest.csv` 与缓存合同字段）：
  - Auge et al., “Towards dimensions and granularity in a unified workflow and data
    provenance framework”, arXiv:2504.11278（workflow/data 两类溯源、W7+1 溯源问题）。
  - Lin et al., “A survey of provenance in scientific workflow”, J. High Speed
    Networks 2023，DOI 10.3233/JHS-222017。
  - Hasan et al., “Preserving File Provenance Using Principles of Blockchain to
    Ensure Scientific Reproducibility”, IEEE e-Science 2023，
    DOI 10.1109/e-Science58273.2023.10254665（用文件哈希做输入溯源校验）。
- 通用缓存失效策略（TTL/显式失效/写穿）参考：
  https://oneuptime.com/blog/post/2026-01-30-cache-invalidation-strategies/view

## 旧实现评价

优点（保留不变的部分）：

- 缓存产物合同正确：`U/V/sampleValid` 为 n_frames×J×I（单精度/逻辑），
  `X/Y/h_mm/frame_ids/source_grid_size/j_wall_removed/cache_meta` 齐备，
  `cache_meta.schema_version=1`；与 handoff [verified] 列表逐项吻合。
- 写入临时文件、完成后才 move 进 `mat/01_sequence_cache.mat`，避免半成品缓存被下游读到。
- 重建时逐块 `tbl.io.load_tecplot_dat`，并校验坐标网格与 `j_wall_removed` 不随帧变化，
  防止把不同导出的帧拼进同一 case。
- reuse 优先新缓存、其次 legacy `_cache/sequence_cache.mat` 只读复用；复用验证只读检查
  schema/case_id/data_root/n_frames/fs/grid_size 与数组尺寸。
- `prepare_debug_cache` 正确把 `cfg.stages.cache` 的 compute/reuse 翻译成
  `rebuild_cache=true/false`，并拒绝 skip；case 脚本 Section 1 保持薄编排。

## 新实现改进（已回写）

1. `+tbl/+periodic/prepare_sequence_cache.m`
   - 头部补充完整合同文档（schema_version=1、变量清单、reuse/compute 语义、临时文件原子替换）。
   - 修复“先 delete 旧缓存再 movefile”的非原子替换窗口：改为
     `movefile(temp, paths.sequence_cache, 'f')` 一次覆盖；move 失败时旧缓存仍在
     （`prepare_sequence_cache.m:111-115`）。
   - `validate_existing_cache` 加固（`prepare_sequence_cache.m:129-216`）：
     - `cache_meta` 缺字段（如旧版/半成品没有 `fs`、`schema_version` 等）时抛干净的
       `CacheContractMismatch`，而不是 MATLAB 原始 “Unrecognized field name” 错误；
     - 新增 `meta.cached_size` 与数组尺寸一致性检查；
     - 新增 `X/Y` 尺寸必须等于 [J I] 的检查；
     - 新增 `source_grid_size` 必须等于 `cfg.grid_size` 的检查（此前该字段只要求存在、从不校验）；
     - 新增 `frame_ids` 必须严格等于列向量 `1:n_frames` 的检查；
     - 错误信息统一引导 `cfg.rebuild_cache=true`。
2. `+tbl/+periodic/prepare_debug_cache.m`：缓存报错指导补充清单文件路径与 legacy 只读复用、
   compute 强制重建的提示。
3. 两个 case 脚本 Section 1 注释块（`f40a3_periodic_piv_case.m:313-326`、
   `baseline_periodic_piv_case.m:317-330`）：写明缓存合同、manifest、legacy 只读复用与
   compute 语义；代码三行编排不变。
4. `tests/test_section1_sequence_cache.m`（新增）：合成 DAT（12 帧×8×12 网格、1 行壁下
   无效区、chunk=4，触发多块写入）覆盖：
   - 构建产物：必需变量齐全、U 单精度、sampleValid 逻辑、schema_version=1、
     `csv/01_source_manifest.csv` 每帧一行；DAT→缓存整链数值回读一致；
   - reuse 复用新缓存（`created_utc` 不变、文件不重写）；
   - legacy `_cache/sequence_cache.mat` 只读复用（`legacy_location=true`、不迁移、不复制）；
   - compute 强制重建（旧文件中追加的标记变量在重建后被清除）；
   - 合同失配：case_id / n_frames / fs / grid_size / data_root 五种变体 → `CacheContractMismatch`；
   - 缺变量 → `InvalidCache`；`cache_meta` 缺字段、`schema_version=2` → `CacheContractMismatch`；
   - 跨块流向间距变化 → `GridChanged`；跨块壁面裁剪变化 → `GridChanged`（尺寸检查先行，
     见“遗留风险”）；
   - `prepare_debug_cache` 的 compute/reuse/skip 语义；
   - `read_cache_chunk` raw（整段/等差跨帧/不规则跨帧/单帧）、total、random 分支与
     InvalidBranch/InvalidIndices/MissingStatistics 错误。
5. `README.md`：第 10 节测试清单加入新测试并补充说明。

## 新旧实现对比要点

| 维度 | 旧实现 | 新实现 |
|---|---|---|
| 缓存替换 | delete 后 movefile（失败窗口丢旧缓存） | movefile('f') 一次覆盖 |
| cache_meta 缺字段 | 抛原始 “Unrecognized field” | 干净 CacheContractMismatch + 重建指引 |
| cached_size 一致性 | 不检查 | 与数组尺寸核对 |
| X/Y 尺寸 | 只载入不核对 | 必须为 [J I] |
| source_grid_size | 仅要求存在 | 必须等于 cfg.grid_size |
| frame_ids | 仅要求存在 | 必须为 1:n_frames 列向量 |
| 合同文档 | 无头注释 | 函数头完整合同说明 |
| 边界测试 | 无专门测试（handoff 待验证项） | 新增 10 组合成用例 |

## 测试结果（MATLAB R2022b，`D:\Academic\Software\MATLAB\R2022b\bin\matlab.exe`）

运行方式（均从项目根目录，`matlab -batch`）：

    matlab -batch "cd('...Current_Plate_Calculation'); addpath('tests'); test_section1_sequence_cache"
    matlab -batch "cd('...'); addpath('tests'); test_periodic_piv_core; test_refactor_shared_helpers"
    matlab -batch "cd('...'); addpath('tests'); test_section0_rewrite; test_singlecase_helpers;
        test_singlecase_scripts_contract; test_singlecase_figure_style_contract; test_singlecase_plots;
        test_premultiplied_psd_reference; test_pressure_gradient_contract; test_vlsm_cluster_connectivity"
    matlab -batch "cd('...'); addpath('tests'); r = runtests('tests/test_section1_sequence_cache.m'); disp(table(r))"

结果（全部通过，退出码 0）：

- `test_section1_sequence_cache: PASS`（新增，`runtests` 亦可运行，1 passed）
- `test_periodic_piv_core: PASS`、`test_refactor_shared_helpers: PASS`
- `test_section0_rewrite / test_singlecase_helpers / test_singlecase_scripts_contract /
  test_singlecase_figure_style_contract / test_singlecase_plots / test_premultiplied_psd_reference /
  test_pressure_gradient_contract / test_vlsm_cluster_connectivity: PASS`
- 真实 legacy 缓存只读复用（不写任何真实输出目录，manifest 写入临时目录）：
  `single/baseline_periodic_piv_debug3000` → 3000×87×640 schema=1，
  `single/f40a3_periodic_piv` → 6000×87×640 schema=1，均 `reused=1 legacy=1`，耗时 <1s。

未运行真实 3000/6000 帧 DAT 重算，未删除/迁移任何旧缓存与 archive。

## 遗留风险 / 未解决问题

1. `WallCropChanged` 分支实际不可达：`load_tecplot_dat` 的壁面裁剪是“整行删除”，
   `j_wall_removed` 不同必然导致裁剪后 J 不同，而 `GridChanged` 的尺寸检查先于
   `j_wall_removed` 检查，所以跨块裁剪变化总是报 `GridChanged`（测试也验证了这一点）。
   `WallCropChanged` 保留为防御性分支，不影响合同正确性。
2. reuse 仍会重新 stat 数据目录并重写 `csv/01_source_manifest.csv`（每次运行记录当次 DAT
   元数据）；若 DAT 目录不存在，reuse 在复用缓存之前就会报 MissingFrame。这是既有设计
   （manifest 必须反映“声明的来源”），报告保留。
3. manifest 只记录 name/bytes/datenum，不做文件内容哈希（6000 个 DAT 的哈希代价过高）。
   若需要严格内容级溯源，可参考 Hasan et al. 2023 的做法加可选哈希校验，本轮未实现。
4. 大缓存断点续算仍未实现：重建中断后临时文件被删除，下次需从头重算。原子替换已保证不会
   留下半成品最终文件；断点续算是后续可选项，未在本轮范围。
5. `dat_manifest` 依赖 Windows `dir` 枚举不会把 8.3 短文件名重复计入；真实目录已验证通过，
   但极端文件系统环境下仍建议人工留意。
6. 新增 `tests/test_section1_sequence_cache.m` 的合成 DAT 需要 J≥12（`detect_wall_rows`
   有 `n_removed >= J-10` 保护），测试已按此选择网格，后续修改该保护时需同步调整测试。

## 修改文件清单（全部为正式工作区路径）

- `+tbl/+periodic/prepare_sequence_cache.m`（重写加固）
- `+tbl/+periodic/prepare_debug_cache.m`（报错指导补充）
- `cases/single/f40a3/f40a3_periodic_piv_case.m`（Section 1 注释）
- `cases/single/baseline_debug3000/baseline_periodic_piv_case.m`（Section 1 注释）
- `tests/test_section1_sequence_cache.m`（新增）
- `README.md`（测试清单与说明）
- 本报告：`docs/section_reviews/section_01_report.md`