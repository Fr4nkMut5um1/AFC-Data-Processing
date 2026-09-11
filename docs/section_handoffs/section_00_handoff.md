你正在接手一个进行中的“周期法向表面变形主动流动控制 PIV 数据分析 MATLAB 程序”任务。请按以下上下文继续；不要重新讨论已经确定的总体架构。若本提示与当前工作区证据冲突，以当前文件为准，并说明冲突。

【用户目标】
按“独立重写 → 新旧对比 → 人工审阅 → 回写”流程，完成本 section 的代码评审与改进，并保持既有架构与产物合同。

【工作目录】
D:\Users\Frank_7840HSw\Desktop\202605实验快反计算\Current_Plate_Calculation

环境为 Windows PowerShell 5.1、MATLAB R2022b。工作区非常脏，存在大量用户历史修改、删除和未跟踪文件；相关 `+tbl/+periodic/`、两个周期 case 目录、测试和 `third_party/` 均为未跟踪或已修改状态。禁止 reset、checkout、清理或覆盖无关改动。

【本轮目标：SECTION 0 独立重写与回写】
不依赖本对话的既有实现记忆，由你作为新 agent 背靠背地独立重写“Section 0：初始化与本 case 全部参数”代码，并完成测试、新旧对比、人工审阅后回写。

流程：
1. 阅读本项目当前文件，理解 Section 0 的输入、输出、数据流和硬合同。
2. 主动联网检索 MATLAB 官方文档、File Exchange/GitHub 社区中可复用或高度借鉴的“配置校验、路径组织、编辑器活动文件定位、UTF-8 写卡、结构体默认值、错误信息”等轮子或最佳实践。
3. 在临时文件或独立草稿中写出新的 Section 0 代码，不复制旧实现。
4. 用合成 cfg 和现有测试验证新代码。
5. 对比新旧实现优劣，输出对比评价，供人工审阅。
6. 根据人工意见修改。
7. 测试通过后写回原 case 脚本，并同步更新相关 `+tbl/+periodic` 函数、依赖、测试和 README。

【必须遵守的要求】
- [verified] 保持“一 case 一文件夹、一文件夹一个可直接运行 `.m` 主脚本”的架构，不把周期算法并回根目录旧脚本。
- [verified] 保持 Section 0–9 顺序和 `cfg.*` 赋值必须带中文物理含义/单位/调试影响注释的规则。
- [verified] Section 0 是纯参数与初始化节，不允许在这里运行真实 3000/6000 帧 DAT 数值流程。
- [verified] 不删除旧输出、不迁移大缓存、不修改 `archive`，不使用破坏性 Git 命令。
- [verified] 活跃二维云图只能使用 `contourf(...,'LineStyle','none') + turbo(256) + colorbar`；本节的 case card 不属于云图。
- [verified] `cfg.instantaneous.frame_ids` 必须是 `[首帧 末帧]` 两元素有序闭区间；`cfg.instantaneous.n_output_frames` 决定区间内均匀输出多少个代表帧。
- [verified] 所有 `cfg.xxx =` 赋值必须保留中文注释；`test_periodic_piv_core.m` 会静态检查这一点。
- [verified] 不新增“过多自检模块”；参数校验仍由 `tbl.periodic.validate_config` 统一承担，错误消息需包含字段路径、期望值和实际观察值。

【已确认事实与决策】
- [verified] 正式入口为：
  `cases/per_case/tandem_baseline_r1/tandem_baseline_r1_case.m`
  `cases/per_case/tandem_f40a3_phi0_r1/tandem_f40a3_phi0_r1_case.m`
- [verified] Section 0 当前调用链：
  `tbl.periodic.locate_periodic_case_script`
  → `tbl.periodic.locate_repository_root`
  → 定义全部 `cfg` 字段
  → `tbl.periodic.validate_config(cfg)`
  → `tbl.periodic.build_paths(output_dir)`
  → `tbl.periodic.write_case_card(cfg, paths)`
  → `tbl.periodic.periodic_artifact_paths(paths)`
  → 初始化 `results` 与 `preview_figures`。
- [verified] 定位、项目根查找、artifact 路径、缓存准备、依赖检查、预览、正式复用等脚本内 local helper 已迁入 `+tbl/+periodic`；当前 case 脚本只保留 cfg 与薄 Section 编排。
- [verified] `validate_config` 是唯一参数校验层；`invalid()` 会输出 `observed=...` 实际值。
- [verified] 外部轮子：DMD 使用 `third_party/piDMD`（MIT）；SPOD 使用 MATLAB path 上已安装的 Towne/Schmidt `spod.m`（Caltech 学术许可）；POD 使用 `Comparison_Re30w_AoA2.m` 的参考快照算法。
- [verified] 当前 9 个测试全部通过；真实旧缓存只读复用验证通过（baseline 3000 帧、f40a3 6000 帧）。
- [inferred] 新 Section 0 应继续使用共享 `+tbl/+periodic` 函数，而不是把逻辑重新塞回脚本。
- [unverified] 具体物理参数（如 `dy_h=2.4`、`baseline_u_tau=0.95116051437100702`、`f0_hz=40`、`n_bins=24`）是否应调整，需要人工确认。

【已完成】
- 两个周期脚本已瘦身，11 个 local helper 已迁入 `+tbl/+periodic`。
- `validate_config`、`build_paths`、`write_case_card`、`periodic_artifact_paths` 已存在并通过测试。
- README 已记录共享层、piDMD、SPOD 和错误信息约定。

【未完成 / 待验证】
- 尚未按本流程对 Section 0 做“背靠背独立重写 + 新旧对比 + 人工审阅”。
- 新 Section 0 的 cfg 字段清单、注释规则、静态 token 和错误消息需要重新验证。

【关键文件 / 命令 / 产物】
- case 脚本：
  `cases/per_case/tandem_baseline_r1/tandem_baseline_r1_case.m`
  `cases/per_case/tandem_f40a3_phi0_r1/tandem_f40a3_phi0_r1_case.m`
- 共享函数：
  `+tbl/+periodic/validate_config.m`
  `+tbl/+periodic/build_paths.m`
  `+tbl/+periodic/write_case_card.m`
  `+tbl/+periodic/periodic_artifact_paths.m`
  `+tbl/+periodic/locate_periodic_case_script.m`
  `+tbl/+periodic/locate_repository_root.m`
  `+tbl/+periodic/run_section.m`
- 测试：
  `tests/test_periodic_piv_core.m`
  `tests/test_refactor_shared_helpers.m`
- 文档：`README.md`
- 全测试命令：
  `matlab -batch "files=dir(fullfile(pwd,'tests','test_*.m')); names=cellfun(@(f) fullfile(files(1).folder,f), {files.name}, 'UniformOutput', false); r=runtests(names); disp(table(r));"`
- Section 0 单节运行：在 MATLAB 编辑器中打开 case 脚本，运行第一个 `%% SECTION 0` 块。

【不要重复 / 不要做】
- 不要重新设计一 case 一脚本、Section 0–9、`+tbl` 共享层架构。
- 不要把共享 helper 重新复制回 case 脚本尾部。
- 不要新增独立于 `validate_config` 的第二套 cfg 校验。
- 不要运行真实完整 3000/6000 帧重算；验证只使用合成数据和现有缓存复用。
- 不要删除或覆盖 `docs/section_handoffs/` 中其他 section 文档。

【下一步】
1. 先阅读两个 case 脚本的 Section 0、`validate_config.m`、`build_paths.m`、`write_case_card.m` 和 `test_periodic_piv_core.m` 的静态契约部分。
2. 联网检索 MATLAB 配置校验与路径组织的最佳实践，列出可复用轮子。
3. 在草稿中独立写出新的 Section 0 实现，并编写合成 cfg 测试。
4. 运行相关测试，输出新旧对比评价，等待人工审阅。
5. 审阅通过后回写 case 脚本，同步更新共享函数、测试和 README。
