# P0：原始依据、当前参数与结果身份

日期：2026-09-10。本报告依据原 ZIP 的只读副本 `evidence/PIV_Review_20260910/`；所有源码行号均指原件。未执行主脚本取 cfg，未运行 MATLAB/Octave/Python 科学计算，未写入任何原 MAT、图形或 expected。

## 本批交付和检查边界

本批只新增报告与静态索引，没有修改源码或调用链。完整读取根 START_HERE、handoff 全部 7 个文件和附带审查/工作指令/源码证据；另核对真实主脚本、相关消费者和已保存参考身份。

- `current_parameter_inventory.csv`：556 条真实主脚本赋值记录（含容器、派生/继承、源路径变量及执行段条件赋值），每条列出原文件行号、原表达式、能静态确定的值、历史配置、消费者位置和可调性。**这是提取与索引，不是脚本执行后的 cfg dump**。动态来源不能从静态文本伪造为已运行配置；字段未命中直接读取时明确标为按调用组定位。
- `P0_saved_result_identities.json`：当前源码 SHA-256、历史配置差异、S2/S3 的 MAT 内身份、S4/S5 的摘要身份和本包实际文件数。JSON 中非有限数以字符串 `Inf` 等表达；未修改原 MAT。
- `P0_fixture_metadata.json`：四份样本的变量尺寸/类型属性、缓存元数据、帧号/原帧号/去壁行。没有读取 U/V/sampleValid 数值块，也没有重算样本。
- `P0_protected_hashes.json`：原 ZIP、只读 ZIP 副本、原两主脚本、两个 smoke_expected 的哈希、大小和权限记录。

附带 `03_source_evidence.md` 的 2,601 条带原行号源码摘录，与原 ZIP 对应文件逐行比对，**0 处不一致**。这仅确认报告摘录准确，不代表报告推断或算法已经动态验证。

原 ZIP SHA-256：`af95e05849b9f09116354fddaa19a660659207c354e3f3ef30ad7f763dfba1f9`。不可回写的比较副本位于 `evidence/PIV_Review_20260910.zip` 及只读展开树；日常改动从 `work/project/` 开始。

## 当前主脚本：参数以源码为准

B = `project/cases/per_case/tandem_baseline_r2/tandem_baseline_r2_case.m`。
C = `project/cases/per_case/tandem_f40a3_phi0_r2/tandem_f40a3_phi0_r2_case.m`。

| 项目 | B 当前实际赋值 | C 当前实际赋值 | 原位置 |
|---|---|---|---|
| cache / statistics / mean_bl | reuse / reuse / reuse | 同 B | B 27–29；C 26–28 |
| phase | skip；enabled=false | reuse；enabled=true | B 30、151；C 29、148 |
| structures | compute | compute | B 31；C 30 |
| transport | skip | skip | B 32；C 31 |
| temporal / spatial / pod / dmd / lcs / spod / correlations / harmonics | 全 skip | 全 skip | B 33–40；C 32–39 |
| 最终 figures | skip | compute | B 41；C 40 |
| preview.enabled | false | false | B 346；C 342 |
| fs；源网格；壁侧 | 960 Hz；[640 91]；top | 同 B | B 44–46；C 43–45 |
| n_frames / total_frames | 每 repeat 6000 / 总 12000 | 同 B | B 57–58；C 56–57 |
| formal_required_frames / allow_debug_snapshot | 6000 / false | 同 B | B 59–60；C 58–59 |
| chunk_frames | 48 | 48 | B 61；C 60 |
| Uinf / nu / rho / D_mm / x_max | 25 / 1.48e-5 / 1.20 / 30 / 328 | 同 B | B 47–51；C 46–50 |
| min_valid_fraction | 0.70 | 0.70 | B 52；C 51 |
| S2 源与帧范围 | raw / all | raw / all | B 74–75；C 73–74 |
| profile.mode / params | range_avg / [80 180] mm | 同 B | B 79–80；C 78–79 |
| loglaw.rmse_yplus_range / params.dy_h | [100 400] / 1.0 | [80 250] / 1.3 | B 87、91；C 86、90 |
| 受控相位 f0 / n_bins / min samples | 不适用，均 [] | 40 Hz / 24 / 20 | B 152–155；C 149–152 |
| phase_preview.marker_stride | 1 | 1 | B 166；C 163 |
| S4 source_mode / POD rank | pod_e50 / energy_fraction 0.50 | 同 B | B 189、216；C 186、213 |
| S4 connectivities / primary / figure | [8 4] / 8 / 8 | 同 B | B 190–194；C 187–191 |
| S4 length_thresholds / max_complete_ss_per_sign | [3 3.8 4.5] / Inf | 同 B | B 195–196；C 192–193 |
| S4 spatial_exclusion | disabled | enabled；x=[0 80] mm、wall y=4 mm | B 206–208；C 203–205 |
| S4 streamwise_edge_exclusion | disabled；buffer=3 | 同 B | B 212–213；C 209–210 |
| S4 max_figure_objects / reuse_existing_run / resume | Inf / true / 空 | 同 B | B 201–204；C 198–201 |
| S5 source / frame_mode | raw / all | 同 B | B 231–232；C 227–228 |
| S5 profile_x_range_mm / edge_buffer_cells | [80 320] / [2 16] | 同 B | B 233–234；C 229–230 |
| H / rbf_epsilon_scale | [0 1 2] / 1.2 | 同 B | B 133–134；C 131–132 |
| formats / export_dpi | png+fig / 200 | 同 B | B 307–308；C 303–304 |
| figures.colormaps.default | ocean | turbo | B 313；C 309 |

完整表达式以 CSV 为准。`cfg = validate_config(cfg)` 会规范 case_type/wall_side 并为缺失旧可选字段补值（原函数 16、61–77、113–114），两当前脚本已显式给出相应值。原 `rebuild_cache=false` 不是唯一有效开关：B 431/C 426 另根据 stages.cache 派生，prepare_sequence_cache 46–49 又处理 compute；P1/P2 不能把原 false 当作会阻止显式 compute 的承诺。

原 S4 消费者在 `section4_vlsm_analysis.m:299–364` 明确设置正式 chunk=48、reference_x=[100 220]、amplitude=1.0、spatial_block_dof=512、time_tile_frames=128、fast_in_memory=true、gaussian=false；这些当前不在顶部 cfg 中。`section4_vlsm_figures.m:196–216` 实际用 balance(257) 与 abs(field) 第 99.5 百分位色限，不能将 ocean 字段误认为已生效。S5 默认 stress_fraction_floor=1e-6 来自 section5_run 16，display_quantile=.995 来自 transport_figures 13；P0 只记录，不外提或改值。

## 当前源码与历史配置的真实差异

配置对照读取 `configuration_original.mat` 内 cfg_original，并参考 JSON 解释序列。MAT 的 Inf 在原 JSON 中可能为 null，不能把 null 自动改成有限值。

| 字段 | 当前 B | 历史 B | 当前 C | 历史 C |
|---|---:|---:|---:|---:|
| phase_preview.marker_stride | 1 | 8 | 1 | 2 |
| structures.max_complete_ss_per_sign | Inf | 1 | Inf | 1 |
| structures.section4.max_complete_ss_per_sign | Inf | 1 | Inf | 1 |
| structures.section4.max_figure_objects | Inf | 30 | Inf | Inf（JSON 为 null） |

这些不是本轮新改动。特别是 max_complete_ss_per_sign 会影响原 S4 对象保留，不能只修 marker_stride 后就将历史 configuration 当成当前参数参考。其余简单、可静态确定的赋值比较见 CSV；路径表达式、运行时探测结果、复杂消费者不存在已执行确认。

### repeat 身份：记录值与运行时来源要区分

原 B 394–400 / C 389–395 的 cfg.sources 值来自前面的缓存元数据恢复或 `resolve_case_repeats`，不是顶部写死值。源码 `resolve_case_repeats.m:68–70` 降序选择编号最大的两组，81–91 还会选择可用的最大候选起帧；没有 DAT 时不能断言重新扫描会产生相同输入。

历史配置与 S5 正式 raw provenance 相互印证的记录是：

| case | raw 顺序 | postproc 顺序 | 正式 offsets | repeat boundary |
|---|---|---|---|---:|
| B | Tandem_Baseline_PIV_3rd → Tandem_Baseline_PIV_2nd | Tandem_Baseline_PostProc_3rd → Tandem_Baseline_PostProc_2nd | [0 0] / [0 0] | 6000 |
| C | Tandem_f40A3_Phi+0_PIV_3rd → Tandem_f40A3_Phi+0_PIV_2nd | Tandem_f40A3_Phi+0_PostProc_3rd → Tandem_f40A3_Phi+0_PostProc_2nd | [0 0] / [0 0] | 6000 |

原数据父目录为 `J:\Export0731\TempData0731_LinZheng\Tandem`。独立 case 用显式本地根目录后，这些字符串是旧身份记录，不意味着 J: 仍为运行时 fallback。

**四份短样本的身份不同于正式源**：MAT 中 source_root=`review_fixture`，repeat_offsets=`[0 24]`，repeat_boundaries=24，总帧48、每 repeat24，created_utc=`2026-09-10T00:00:00Z`。source_frame_ordinals 保留 `[1:24,6001:6024]`，包内 frame_ids 为1:48。不能用正式 offsets `[0 0]` 去解释该样本，更不能把样本配置写回正式脚本。U/V 的 MATLAB class 是 single，sampleValid 为 logical；MATLAB 顺序尺寸48×89×640。检查仅读取字段/元数据，没有重算科学量。

## 历史结果身份与新疑点

| 产物 | B 原结果创建时间 UTC | C 原结果创建时间 UTC | 本包内容 |
|---|---|---|---|
| Section 2 statistics | 2026-08-23T06:15:38Z | 2026-08-27T09:22:27Z | full_run_reference 内 data+meta |
| Section 2 mean_bl | 2026-08-27T09:48:02Z | 2026-08-28T08:32:28Z | full_run_reference 内 BL 与独立meta |
| Section 3 phase | baseline未做 | 2026-08-31T09:36:44Z | 受控meta、xmean、random_global、assignment；不是完整phase MAT |
| Section 4 summary | 2026-08-30T12:36:08.463Z | 2026-08-31T13:35:55.931Z | 摘要、少量PNG、CSV；没有完整run/POD目录 |
| Section 5 raw | 2026-09-06T13:15:56Z | 2026-09-06T13:10:36Z | B6/C15 PNG、B3/C4 CSV、JSON；本包没有FIG或正式S5 MAT |

这些创建时间来自产物内部字段，不采用本次解压文件 mtime。配置卡、MAT打包时间与科学结果创建时间不同；full_run_reference 文件头的 2026-09-10 是导出参考文件的时间，不能当成该日重算S2。

**新确认的参考不一致：baseline 的保存 BL 用 [240 320]，当前主脚本用 [80 180]。**

证据为 `fixtures/baseline/full_run_reference.mat` → `reference.section2_bl.loglaw.profile_params` 和 `reference.section2_bl.clauser.option_a.profile_params` 均为 `[240 320]`；当前 B 80 为 `[80 180]`；`configuration_original.mat/json` 也记录 `[80 180]`。C 的保存 BL 则为 `[80 180]`。该发现来自只读 MAT，不是根据文件名猜测。

可能影响：基准 u_tau、Cf、后续壁单位/归一化及 S4 使用的 BL 输入身份。原 `load_result.m:10–20` 不检查 profile.params，因此原 mean_bl=reuse 可接受这样的旧文件；这不证明已交付论文结论错误，也不能推算变化量。**本轮不改科学参数、不重算/替换旧BL、不给该结果补盖当前参数身份。**应将“当前同代码同参数重跑”的 S2/BL/S4 参考作为单独本地验收事项，或先由用户确认要保留的旧产物口径。

`handoff/PROGRESS.md` 所称原正式 S5 有6/15个 FIG 是历史环境记录，不等于 ZIP 包含它们。P0 实际文件盘点为两 case 的 `reference_outputs/**/section5/**` 各0个 FIG、0个正式 MAT；不能据本包声称完成完整 FIG/CSV 图组对照。全量 postproc 图组仍未交付验收。

报告中的 baseline S4 旧图提示与上述时间证据一致。**没有建立或冒充“当前代码+当前参数+正式数据”的重跑参考。**smoke_expected 是当前打包代码在特定缩小配置下的局部数值参考，不能填补这个缺口。

## 历史 MAT 路径与迁移风险（独立审查）

| 路径/身份字段 | 实际读写证据（原源码） | 搬动后风险与本轮处理 |
|---|---|---|
| cache_meta.source_root / repeat_roots / offsets | prepare_sequence_cache 241–268 写入，332–358 复用校验仅主要核对第一根/offset | 缓存科学数组即便不变，本地路径仍可能不匹配；两个repeat必须一起核实。不能整段字符串替换或删除校验。 |
| S5 provenance.cache_file / bytes / datenum / cache_meta / implementation_sha256 | section5_run 70–89 | 路径和时间变化可使旧正式S5 reuse被拒绝；算法文本哈希不是逐帧哈希。本批不删。 |
| d23 context.cache_file / cache_source / utau_source / source_fingerprint | d23.prepare_source 76–114 | fingerprint含缓存及BL路径、大小、时间与created_utc；仅搬位置也改变identity，不能盲目重签。 |
| d23 manifest.config_hash / source_fingerprint | d23.initialize_run 3–16、28–39 | resume依赖该合同；显式resume不能被另一个自动候选绕开。 |
| POD文件及pod_meta指纹 | d23.build_pod_cache 25–35、103–105；section4_vlsm_analysis 67、142–150 | run目录引用与context必须一致；旧POD数学数组未提供，无法建立同数据迁移证明。 |
| catalog_index.MatFile | d23.run_detection 105–118；section4_vlsm_analysis 523–529 | 原代码直接load表中路径；目录复制后仍可能指向原机器/旧case。完整catalog和MAT分区未包含，不做伪迁移。 |
| section4_run_dir / result_file / 输出清单 | section4_vlsm_analysis 166–183；两份summary.json及S5 files | 此类路径是历史结果说明，不能据其字符串指向宣称本地文件真实存在。 |

本批没有需要搬入日常case的完整旧正式缓存、BL MAT、run/context/POD/目录分区集合，故**没有编写或执行一个声称已验证的结果迁移工具**。将来必须在完整旧产物可访问、明确映射且同数据核实后，另做显式一次性迁移；保存旧身份、变更字段清单和迁移记录。轻量 full_run_reference 不应冒充旧正式文件交给运行入口。

## 执行记录与停止条件

| 检查 | 结果 | 能说明什么 |
|---|---|---|
| 原ZIP、源副本、smoke_expected哈希和只读保护记录 | 已记录 | 比较起点固定；没有record或覆盖预期 |
| 报告源码摘录逐行比对 | PASS，2601行/0差异 | 摘录与源码一致；不是运行覆盖 |
| 两主脚本赋值索引、MAT历史配置对照 | 静态完成 | 发现marker/对象上限/导出上限差异，动态取源未伪执行 |
| full_run_reference 的 S2/BL/S3元数据与选择字段读取 | 完成，只读 | 识别baseline BL profile范围不一致 |
| 四份v7.3缓存元数据/尺寸/类型属性读取 | 完成，只读 | 确认样本身份；未重算速度统计 |
| 本环境 MATLAB可执行文件 | 未找到 | Run Section、which解析、MATLAB单测未执行 |
| MATLAB编辑器0、0→5、B→C切换 | **未执行** | 不能用%%扫描或Python静态检查代替 |
| run_review_smoke/check、section5_run保存/复用/导出、正式S4/图组对照 | **未执行** | 不能宣称正式结果一致 |

包内 `validation/environment.json` 报告历史验证环境为 **MATLAB 9.13.0.2080170 (R2022b) Update 1、PCWIN64**；历史 SPOD 路径在原机器 MATLAB toolbox 下，当前 ZIP 没有该库。原 installed_products 是安装清单，不是经本轮实测的最小依赖。`sample_check_report.json` 的 PASS 属于交接方历史执行，本轮没有重新宣称通过。

`run_review_smoke` 33 直接调用 transport_analysis，不覆盖 section5_run 的文件复用、原子保存和图组导出。正式每 repeat6000、controlled24箱/min20、S4 12000×89×640 闸门均应保持；任何48帧验证通过也不能覆盖formal fast_in_memory POD、完整结构筛选或正式图组。

本轮遇到新的 baseline BL 参考身份疑点，已提交独立证据。P0不会通过增加无关测试或科学重算来“消除”这个问题；P1/P2 可静态完成结构工作，进入P3–P5和正式结果接受规则前须遵守根报告的批次停止决定。
