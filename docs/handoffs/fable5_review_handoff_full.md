你正在接手一个已经进行过多轮的 agent session。请按以下上下文恢复任务状态；不要重新讨论已定事项。如果当前文件或可验证证据与这里冲突，以当前证据为准，并明确指出冲突。

【工作目录】
D:\Users\Frank_7840HSw\Desktop\202605实验快反计算\Current_Plate_Calculation

【用户目标】
由另一个高智能模型（fable5）对本轮成果做独立 review：重点审查 Section 0-9 的代码脚本、共享函数、测试、README 与各 section 报告，以及工作区整理结果（git 分支、两次提交、archive 归档、.gitignore），并输出可执行的问题清单、严重度分级与改进建议。

【必须遵守的要求】
- [verified] 当前分支为 `codex/section-0-9-review`；`master` 未被修改。
- [verified] 已提交 `b167c24 Review and harden Section 0-9 periodic PIV pipeline` 与 `b7f8453 Archive legacy pipeline source files`。
- [verified] 提交前全量 `tests/test_*.m` 共 18 个测试文件全部 Passed；提交内容与当时工作区内容一致。
- [verified] 禁止 reset/checkout/清理/覆盖用户未跟踪文件：`AFC课题讨论V9-林正-20260718.pptx`、`baseline_case.m`、`f40a1_case.m`、`other_case_scripts/`、`t.m`、`t2.m`、`t3.m`，以及用户对 `archive/README.md` 的未提交修改。
- [verified] 禁止删除旧输出、旧 `_cache`、`archive`；禁止运行真实 3000/6000 帧重算；验证只使用合成数据和临时目录。
- [verified] 活跃云图只能使用 `contourf(...,'LineStyle','none') + colormap(ax, turbo(256)) + colorbar`；正式导出只写 `png/fig/eps/emf/pdf/mat/csv/json/md` 扩展名目录。
- [verified] 保持一 case 一脚本、Section 0-9 顺序、`+tbl/+periodic` 共享层、P01-P20 产物合同与 P20 单 case `DEFERRED` 语义。

【已确认事实与决策】
- [verified] 两个正式入口：`cases/single/baseline_debug3000/baseline_periodic_piv_case.m`、`cases/single/f40a3/f40a3_periodic_piv_case.m`。
- [verified] Section 0-7 与 Section 9 各有专门合成测试；Section 8 合同由 `tests/test_periodic_piv_core.m` 覆盖。
- [verified] 每节报告位于 `docs/section_reviews/section_00_report.md` 至 `section_09_report.md`，含新旧对比、测试结果、参考来源与遗留风险。
- [verified] 工作区整理后 `git status --short` 仅剩 8 条：1 条用户未提交修改（`archive/README.md`）+ 7 条用户未跟踪文件。
- [verified] `.gitignore` 已忽略 `tmp/`、`downloads/`、`*.log`、`archive/legacy_pipeline_20260715/HistoryOut_output/`。
- [verified] 子代理统一使用 `deepseek-v4-flash` + `xhigh`（环境不接受 `max`，`xhigh` 为最高档）。
- [inferred] 归档提交只移动旧文件并登记，不改变可运行代码，因此不改变测试结果。
- [unverified] 真实 3000/6000 帧计算、真实外部同步信号相干性、真实 LSM/VLSM 目录与 P18 PARTIAL 场景尚未运行。
- [unverified] `dy_h=2.4`、`baseline_u_tau`、`f0_hz=40`、`n_bins=24` 等物理参数仍待人工确认。

【任务森林状态】
未发现 task-forest exports；本 handoff 依赖可见会话、工作区文件与 git 证据。

【已完成】
- 按 Section 0-9 完成独立评审/重写、合成验证、测试与回写；子代理中途停止的部分由主进程补齐测试修复与报告。
- 修复的代表性问题：`quadrant_analysis` 在 J=1 时的 `squeeze` 维度 bug、缓存替换非原子窗口、POD 参考测试截断模式、piDMD 合成秩不足、`add_diagnostic` 参数数量、R2022b 三维/二维隐式展开限制。
- 工作区整理 1-3：删除子代理临时目录、更新 `.gitignore`、显式暂存本轮成果。
- 工作区整理 4-5：创建分支、两次提交、98 个旧文件正式搬入 `archive/legacy_pipeline_20260715/`。

【未完成 / 待验证】
- 等待 fable5 的独立代码与工作区 review。
- 真实 case 全流程未跑；旧 `06/07/08_*_analysis.mat` 模态缓存因实现指纹变化会被拒绝复用，需人工决定何时重算。
- 剩余用户未跟踪文件是否保留、忽略或另行归档，需要用户决定。

【关键文件 / 命令 / 产物】
- 核心代码：`+tbl/+periodic/*.m`、`+tbl/+pod/snapshot_decomposition.m`、`+tbl/+stats/quadrant_analysis.m`、`+tbl/+spectra/welch_series.m`、`+tbl/+viz/export_publication_figure.m`。
- 测试：`tests/test_section0_rewrite.m`、`test_section1_sequence_cache.m`、`test_section2_mean_stats_cache.m`、`test_section3_phase_triple.m`、`test_section4_structure_analysis.m`、`test_section5_transport_quadrant.m`、`test_section6_spectra.m`、`test_section7_modes.m`、`test_section9_export.m`、`test_periodic_piv_core.m` 等。
- 报告：`docs/section_reviews/section_00_report.md` 至 `section_09_report.md`。
- 归档：`archive/legacy_pipeline_20260715/`。
- 全量测试命令：
  `matlab -batch "files=dir(fullfile(pwd,'tests','test_*.m')); names=cellfun(@(f) fullfile(files(1).folder,f), {files.name}, 'UniformOutput', false); r=runtests(names); disp(table(r));"`
- 状态命令：`git status --short`、`git log --oneline -3`、`git show --stat b167c24`、`git show --stat b7f8453`。

【不要重复 / 不要做】
- 不要重新设计一 case 一脚本或 Section 0-9 架构。
- 不要复制共享 helper 回 case 脚本，不要新增第二套参数校验。
- 不要对 `archive/legacy_pipeline_20260715` 执行 `git add -A`（会扫入大量旧输出图）；`HistoryOut_output/` 已忽略。
- 不要删除 `third_party/piDMD/LICENSE`，不要绕过 piDMD/SPOD adapter。
- 不要在未确认前继续提交、推送、删除或移动用户文件。

【下一步】
1. 阅读 `docs/section_reviews/*.md`，再对照两次提交的 diff 抽查核心函数。
2. 在当前分支运行全量测试，确认 18/18 Passed。
3. 检查 `git status --short` 与 `archive/legacy_pipeline_20260715` 结构，评估归档是否完整、是否误包含大文件。
4. 逐节核对 handoff 合同与代码实现，记录不一致、遗漏与数值口径风险。
5. 输出 review 报告：P0/P1/P2 问题、可执行修改建议、未验证项与建议的下一步。
