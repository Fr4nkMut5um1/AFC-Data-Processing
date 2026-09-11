# 全量会话交接文档（迁移至 WSL / dsh）

> 生成时间：2026-08-14　模式：full　用途：把「本项目多轮 agent 会话」的完整状态迁移到 WSL 环境（dsh），供新 session 无缝续接。
> 生成依据：当前可见对话 + `docs/handoffs/` 三个历史 handoff + git 历史 + 工作区证据。
> 冲突裁决原则：本文件的「当前证据」优先级高于早期 handoff；若与磁盘现状再冲突，以磁盘/代码为准并明确指出。

---

## 【工作目录】

- Windows 现状：`D:\Users\Frank_7840HSw\Desktop\202605实验快反计算\Current_Plate_Calculation`
- WSL 预期：`/mnt/d/Users/Frank_7840HSw/Desktop/202605实验快反计算/Current_Plate_Calculation`（**已确认**；WSL 的 dsh 已直接挂载访问同一物理目录，**无需复制文件**）
- 数据源：`J:\Export0731\TempData0731_LinZheng` → WSL 文件系统对应 `/mnt/j/Export0731/TempData0731_LinZheng`（**已确认**；J: 是本地接入的移动硬盘，在线。`/mnt/j` 仅用于 WSL shell 层查看；MATLAB 代码与 MATLAB 内部命令仍使用 `J:\`）

## 【用户目标】

维护并完善 MATLAB PIV（粒子图像测速）快反后处理管线（tandem/parallel 双排板实验），并把进度从 Windows 迁移到 WSL 的 dsh 上继续。核心诉求：各 case 脚本分节运行正常、绘图配置可调、统计口径正确、过时文件已清理。

## 【必须遵守的要求】

- [verified] 与用户交互用简体中文；代码/标识符/文件路径/shell 命令/技术术语保持原文。
- [verified] 改动同步到全部 3 个正式 case：`tandem_baseline_r1`、`tandem_f40a3_phi0_r1`、`parallel_baseline_r1`（`f40a3`/`baseline_debug3000` 已归档，不再是正式 case）。
- [verified] 共享逻辑优先改 `+tbl/+periodic/`（一处修复全 case 生效）。
- [verified] 数据源在慢速网络盘，重建缓存/全量计算很耗时，尽量避免触发重算；优先轻量合成测试。
- [verified] MATLAB R2022b（9.13.0.2080170）。Windows 下 `D:\Academic\Software\MATLAB\R2022b\bin\matlab.exe`；WSL 下通过 `/mnt/d/Academic/Software/MATLAB/R2022b/bin/matlab.exe` 互操作调用（`-batch` 模式）。cd 到含中文路径正常。
- [verified] 缓存「不匹配时明确报错、不偷偷重算」；旧缓存只读复用/人工处置，**禁止自动重建或自动删除**。
- [verified] 文档/脚本 UTF-8 无 BOM；Windows GBK 控制台乱码是显示问题不是文件损坏。

## 【已确认事实与决策】

- [verified] 3 个正式 case 均走 `resolve_case_repeats` 双 repeat 拼接：每个 repeat 读 `cfg.n_frames=6000` 帧，`total_frames=12000`（**倒数两次尝试 `_3rd`+`_2nd`**）；`cfg.n_frames` 是「每 repeat 帧数」不是总帧数。
- [verified] ⚠️ 冲突：早期 `docs/handoffs/deepseek_v4_flash_implementation_plan.md`（Aug 5）的决策是「1st/2nd/3rd 各自独立 case、均用 `_1st`、不拼接」，**已过时**；当前正确口径是 dual-repeat 拼接 12000 帧（git 提交 `1992011` 引入）。以当前代码为准。
- [verified] 缓存 schema_version=4；`repeat_means` 为 `2×n_repeats×J×I`（同时存 U 和 V 的 per-repeat 均值）；旧 schema<4 缓存缺 `y_mapping`，reuse 时被拒并提示重建。
- [verified] 统计口径对齐参考函数 `averagedU_TKE`：`uu/vv` 为有量纲方差；`uv_rey = -⟨u'v'⟩`（**带负号**）；`TKE = 0.5(uu+vv)/Uinf²`（**无量纲**）；`Uinf=25 m/s`。
- [verified] v 分量符号（上下颠倒）：`wall_side='top'` 时 `V=-V_all` + `remap_y_to_wall` 反转 Y，二者各反转一次恰好配套，**无错位**；`wall_side='bottom'` 时只 `flip` 不取负，也正确。
- [verified] Section 1 写 12000 帧（缓存实测 `U/V/sampleValid=[12000 89 640]`）；Section 2 统计用全部 12000 帧（`n_frames = whos(cache,'U').size(1)` 动态取缓存实际帧数，非 cfg.n_frames）。
- [inferred] 数据源 PostProc 与 PIV 网格一致（`I=640`，`J` 按实测填 89/90/91 左右，需按当前 case 脚本确认）。

## 【已完成】（本会话 + 其他对话）

### 本会话（当前对话，已提交 3 个 commit）
1. **git 区清理与提交**（`dc352ef`）：删除临时 `t.m/t2.m/t3.m`、`.asv`；`.gitignore` 追加 agent 工具目录、`*.asv`、大 PPT；提交 field 化绘图配置 + 瞬时动画 + v3 wall cache。
2. **Section 2 三组无量纲云图**（`e8a6cd4`）：`plot_mean_turbulence` 拆成 3 张上下排布图（U/V ÷Uinf、u'/v' RMS ÷Uinf、-⟨u'v'⟩/TKE ÷Uinf²）；新增 `resolve_free_stream_velocity`。
3. **统计口径修复**（`7fc4da8`）：
   - `repeat_means` 补 V 分量（修复双 repeat 的 vv/uv 数值 bug，schema 3→4）；
   - `uv_rey`/`random_uv_phase` 统一存 `-⟨u'v'⟩`，下游符号翻转（plot/transport/streamwise/quadrant）；
   - `TKE` 无量纲化，`mean_stats_cache` 加可选 `Uinf` 参数，调用点传 `cfg.Uinf`；
   - 归档 `f40a3`/`baseline_debug3000` → `archive/legacy_per_case_cases/`，重定向 8 个测试的 contract 引用。
4. **v 符号数学验证** + `test_wall_side_orientation.m` 补 remap 后 V 为正的断言。
5. **Section 1 性能调研**（联网）：保留 v7.3 缓存架构；唯一有效优化是 `fileread` 整读（本地快盘 1.23x，网络盘收益更大）；textscan 参数微调几乎无效。
6. **`fileread` 整读优化**（2026-08-18 已提交 `c4bbb4b`）：`load_tecplot_dat.m` 的 `read_single_dat` 改为 `fileread` + `textscan('HeaderLines',4,'CollectOutput',1)`；已验证解析结果逐元素 `isequal` 一致、`checkcode` 0 lint。
7. **删除 5 个过时缓存**（schema<4，缺 `y_mapping`）：`parallel_baseline_r1` 的 raw+postproc、`tandem_baseline_r1` 的 postproc、`tandem_f40a3_phi0_r1` 的 raw+postproc。**2026-08-18 磁盘实测**：`tandem_baseline_r1` 的 raw 与 postproc 均已存在且 schema=4、y_mapping=1；`parallel_baseline_r1` 与 `tandem_f40a3_phi0_r1` 无 sequence cache。

### 其他对话（历史 handoff 摘要）
- `fable5_review_handoff_full.md`（Aug 5）：Section 0-9 独立 review + 重写 + 合成验证，18/18 测试通过；工作区整理（分支、归档 `archive/legacy_pipeline_20260715/`）。**已闭环**。
- `deepseek_v4_flash_implementation_plan.md`（Aug 5）：双源（PIV raw + PostProc）接入计划 + 网格/帧数/1st2nd3rd 决策。**多数已被后续 dual-repeat 取代**（见冲突）。
- `maintenance_improvements_handoff.md`（Aug 13）：维护性任务 T1–T9（见【未完成】），大部分未执行。

## 【未完成 / 待验证】

- [verified] **WSL 环境已确认，且源码路径保持 `J:\Export0731\...` 不变（2026-08-18 实测纠正）**：① MATLAB 通过 `/mnt/d/Academic/Software/MATLAB/R2022b/bin/matlab.exe` 互操作调用，这是 Windows 版 MATLAB；② D:/J: 盘在 WSL 挂载为 `/mnt/d`、`/mnt/j`，数据源 `/mnt/j/Export0731/...` 在 WSL shell 层可达；③ 实测 Windows MATLAB 内 `exist('J:\Export0731\TempData0731_LinZheng','dir')=7`、`exist('/mnt/j/Export0731/TempData0731_LinZheng','dir')=0`（`/mnt/j` 会被解析为 `D:\mnt\j`）。因此**不要**把源码 `J:\...` 改为 `/mnt/j/...`。
- [verified] **缓存现状（2026-08-18 MATLAB 实测，以磁盘为准）**：`tandem_baseline_r1` 的 raw 与 postproc 缓存均存在且 schema=4、y_mapping=1；`parallel_baseline_r1` 与 `tandem_f40a3_phi0_r1` 目前无 sequence cache。待用户批准后才串行重建缺失缓存（2026-08-18 用户决定暂缓，见【下一步】）。
- [verified] **原 14 个未提交改动已于 2026-08-18 按用户审核全部提交**：`dc5996c`（phase_h_smoke_cfg 路径）、`c4bbb4b`（fileread 优化）、`117dac2`（tandem_baseline_r1 人工调试配置）、`8fbb5fc`（README/PROJECT_PROGRESS）、`e90f5cb`（section_handoffs）。工作区 tracked 文件干净；`docs/handoffs/maintenance_improvements_handoff.md` 与 `docs/handoffs/wsl_dsh_migration_handoff.md` 保持 untracked。
- [unverified] 维护任务 T1–T9 未执行：T1（.mcp.json 明文 key 轮换，需用户）、T2（重算两个旧产物 case，需用户确认）、T3（run_case_serial.ps1）、T4（缓存 schema 失配提示增强）、T5（拆分 plot_products/validate_config）、T6（run_all_tests.m）、T7/T8（暂缓）。
- [unverified] 真实全流程（重算后）未跑；`tandem_f40a3_phi0_r1` preview 曾有「ZData 为复数」contourf 警告，待复现记录（勿为此改绘图代码）。
- [unverified] 物理参数 `dy_h=2.0`、`baseline_u_tau=0.95`、`f0_hz=40`、`n_bins=24` 仍待人工确认。

## 【关键文件 / 命令 / 产物】

- 共享层：`+tbl/+periodic/`（`prepare_sequence_cache`/`mean_stats_cache`/`phase_stats_cache`/`plot_products`/`read_cache_chunk`/`transport_analysis`/`streamwise_development_analysis`/`quadrant_streaming`/`run_case`/`dy_h_selection_materials`/`locate_periodic_case_script`）、`+tbl/+io/load_tecplot_dat.m`。
- case：`cases/per_case/{tandem_baseline_r1,tandem_f40a3_phi0_r1,parallel_baseline_r1}/*_case.m`。
- 归档：`archive/legacy_per_case_cases/`（f40a3、baseline_debug3000）、`archive/legacy_pipeline_20260715/`。
- 测试：`tests/test_periodic_piv_core.m`、`test_section{0,1,2,3,4,5,6,7,9}_*.m`、`test_wall_side_orientation.m`、`test_pilot_case_scripts_contract.m` 等。
- 文档：`PROJECT_PROGRESS.md`、`README.md`、`docs/handoffs/`、`docs/section_handoffs/section_{00..09}_handoff.md`。
- MATLAB 调用：Windows `cd "<项目根>" && D:/Academic/Software/MATLAB/R2022b/bin/matlab -batch "..."`；WSL `/mnt/d/Academic/Software/MATLAB/R2022b/bin/matlab.exe -batch "..."`（末尾 `Java is shutting down` 为无害噪声）。
- 全量测试（Windows）：`matlab -batch "files=dir(fullfile(pwd,'tests','test_*.m')); names=cellfun(@(f) fullfile(files(1).folder,f), {files.name}, 'UniformOutput', false); r=runtests(names); disp(table(r));"`
- 静态检查：`python tests/matlab_check.py`（基线 0 错误）。
- 缓存 schema 快查：`matlab -batch "for f=dir('cases/per_case/*/output/mat/01_sequence_cache*.mat')'; m=load(fullfile(f.folder,f.name),'cache_meta'); fprintf('%s schema=%d y_mapping=%d\n', f.name, m.cache_meta.schema_version, isfield(m.cache_meta,'y_mapping')); end"`

## 【不要重复 / 不要做】

- 不要回到「1st/2nd/3rd 不拼接、用 _1st」的旧决策（已被 dual-repeat 12000 帧取代）。
- 不要重开已定的 `window_size`/`colormaps`/`contour_levels`/`color_limits` field 化结构，不要逐个 case 手改共享逻辑。
- 不要实现「自动重建/自动删除旧缓存」（项目明令禁止）。
- 不要触发 GB 级缓存重建或全量重算，除非用户明确要求。
- 不要把 J: 绝对路径、任何凭据、`.mcp.json` 明文 key 写进对外/入库内容。
- 不要覆盖用户未跟踪文件（`.reasonix/`、`reasonix.toml`、`other_case_scripts/`、`docs/handoffs/`、`AFC课题讨论V9-林正-20260718.pptx` 等）。

## 【下一步】

1. **路径格式：保持 `J:\Export0731\TempData0731_LinZheng\...` 不变（2026-08-18 实测纠正，不要再改成 `/mnt/j/...`）**。WSL 通过 `/mnt/d/Academic/Software/MATLAB/R2022b/bin/matlab.exe` 启动的是 Windows MATLAB：进程内 `pwd` 为 `D:\...`，只认 Windows 盘符；`/mnt/j` 会被解析成 `D:\mnt\j` 导致数据源找不到。3 个正式 case 脚本（各 2 处 `resolve_case_repeats` 路径）与 `+tbl/+periodic/phase_h_smoke_cfg.m`（4 处）均维持 `J:\...` 原样；`/mnt/j` 只在 WSL shell 层查看文件时使用。MATLAB 调用使用 `/mnt/d/Academic/Software/MATLAB/R2022b/bin/matlab.exe -batch "..."`（Windows 直接运行时仍为 `matlab -batch`）。
2. **处理未提交改动**：✅ 已完成（2026-08-18，按用户审核提交 `dc5996c`/`c4bbb4b`/`117dac2`/`8fbb5fc`/`e90f5cb`），tracked 文件干净。
3. **重建缺失缓存**（2026-08-18 用户决定暂缓/跳过）：`parallel_baseline_r1`、`tandem_f40a3_phi0_r1` 的 raw+postproc；若后续要执行，仍需用户逐项确认后串行重跑，逐 case 检查 `csv/01_diagnostic_messages.csv` 无 ERROR。
4. **按需推进维护任务 T1→T3→T4→T6**（详见 `docs/handoffs/maintenance_improvements_handoff.md`）。
5. WSL 验证：✅ 2026-08-18 已完成全量测试 20/20 与 `matlab_check.py` 170 文件 0 错误；至少一个 case 的 Section 1→2 真实流程待缓存重建/用户批准后执行（用户决定暂缓）。
