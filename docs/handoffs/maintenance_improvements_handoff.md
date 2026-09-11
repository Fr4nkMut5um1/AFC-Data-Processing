# 维护性改进任务交接文档（maintenance_improvements_handoff）

> **用途**：把 2026-08 项目架构评审中"评估为有必要、但本轮未执行"的改进项，交给
> 下一个 agent（含 flash 级模型）逐项照做。每个任务都给出了背景、必要性结论、
> 精确步骤、验证命令和禁止事项，执行时**不需要**再翻阅本对话。
> **生成时间**：2026-08-13　**生成依据**：全仓库架构评审（README / PROJECT_PROGRESS /
> +tbl 全部 148 个源文件 / cases / tests / docs）。
> **前置阅读**：`PROJECT_PROGRESS.md`（硬约束与 git 纪律）、`README.md`（运行方式）。

---

## 0. 执行环境与基线命令（所有任务共用）

- 系统：Windows；MATLAB 建议 R2022b；项目根目录即本文件上两级目录。
- MATLAB 一律批处理串行运行，**禁止**同一 MATLAB 会话连续跑多个 case/测试：

  ```
  matlab -batch "addpath(pwd); run('cases/per_case/<case>/<case>_case.m')"
  ```

  启动下一个任务前确认无残留进程：

  ```
  tasklist //FI "IMAGENAME eq matlab.exe"
  ```

- 全量测试（任何代码改动后必须通过，基线：20 passed / 0 failed）：

  ```
  matlab -batch "addpath(pwd); files=dir(fullfile(pwd,'tests','test_*.m')); names=cellfun(@(f) fullfile(files(1).folder,f), {files.name}, 'UniformOutput', false); r=runtests(names); disp(table(r)); fprintf('passed=%d failed=%d\n', nnz([r.Passed]), nnz([r.Failed]));"
  ```

- 静态检查（基线：172 个 .m 文件 0 错误）：

  ```
  python tests/matlab_check.py
  ```

- **git 纪律**（摘自 PROJECT_PROGRESS.md，不可违背）：
  - 不提交、不删除用户未跟踪文件：`AFC课题讨论V9-林正-20260718.pptx`、
    `docs/handoffs/`、`other_case_scripts/`、`t.m`、`t2.m`、`t3.m`、
    `.reasonix/`、`reasonix.toml`；不覆盖 `archive/README.md` 的未提交修改。
  - 不拼接 1st/2nd/3rd 实验帧；不改 `data_root` 字段名；不自动推断 `frame_offset`。
  - 所有文档/脚本为 **UTF-8 无 BOM**；Windows GBK 控制台直接 `Get-Content` 显示
    乱码是显示问题，不是文件损坏。写文件请用 UTF-8（无 BOM），不要转码。
  - 改动 MATLAB 代码后必须跑全量测试 + `matlab_check.py`，再更新
    `PROJECT_PROGRESS.md` 的"最近完成的工作"一节。

---

## 1. 必要性评估总表

| # | 任务 | 评估结论 | 优先级 | 预计工作量 |
|---|---|---|---|---|
| T1 | `.mcp.json` 明文 API key 处理 | **必要（安全）**。文件已被 .gitignore 未入库，但 key 曾在对话中出现，应轮换并改环境变量引用 | 高 | 0.5 h |
| T2 | 重算 `tandem_f40a3_phi0_r1`、`parallel_baseline_r1`（旧代码产物） | **必要（数据时效）**。PROJECT_PROGRESS 已列为待办；需用户确认后执行 | 高 | 数小时机时 |
| T3 | `run_case_serial.ps1` 串行包装脚本 | **建议**。把"串行、查残留进程"的纪律固化成工具，成本低收益稳 | 中 | 1 h |
| T4 | 缓存 schema 失配修复提示增强 | **建议**。v2→v3 旧缓存不自动重建，报错信息应给出可照做的修复指令 | 中 | 2–3 h |
| T5 | 拆分 `plot_products.m`（1314 行）/ `validate_config.m`（788 行） | **建议**。两个最大最难审的文件；属纯重构，必须保持行为不变 | 中 | 1 天 |
| T6 | `tests/run_all_tests.m` 统一测试入口 | **可选**。README 第 10 节已改自动枚举，此脚本只是便利化 | 低 | 0.5 h |
| T7 | case 参数抽离为 `cfg_<case>.m` 函数 | **暂缓**。改动面大（case 脚本合同、9 个测试、10 篇 section_handoffs），且与"参数留在 case 脚本"的现行哲学冲突，需用户先拍板 | 暂缓 | 2 天 |
| T8 | 旧 `+singlecase` 流程退役/归档 | **暂缓**。旧流程仍是历史格式参照且有测试覆盖，需用户正式宣布冻结后再动 | 暂缓 | 1 天 |
| T9 | `tmp/`、`downloads/` 清理 | **无需代码行动**。两者已在 .gitignore 中，仅需人工定期清理本地文件 | — | — |

执行顺序建议：T1 → T3 → T4 → T6 →（用户确认后）T2、T5。

---

## T1. `.mcp.json` 明文 API key 处理【高优先级，安全】

**背景**：项目根 `.mcp.json` 内 `zotero` 服务器配置含明文
`ZOTERO_API_KEY`。已确认该文件被 .gitignore 覆盖、从未入库（
`git ls-files .mcp.json` 输出为空），不存在历史泄漏；但 key 已在
agent 对话上下文中明文出现过，应按"已暴露"处理。

**步骤**：
1. 用户在 Zotero 后台**吊销并重新生成** API key（此步只能人做）。
2. 把 `.mcp.json` 改为环境变量引用，不再落盘明文：

   ```json
   {
     "mcpServers": {
       "zotero": {
         "command": "C:\\Users\\Frank_7840HSw\\AppData\\Local\\Programs\\Python\\Python312\\Scripts\\zotero-mcp.exe",
         "env": {
           "ZOTERO_LOCAL": "true",
           "ZOTERO_EMBEDDING_MODEL": "default",
           "ZOTERO_API_KEY": "${ZOTERO_API_KEY}",
           "ZOTERO_LIBRARY_ID": "10407321"
         }
       }
     }
   }
   ```

   若所用 MCP 宿主不支持 `${VAR}` 展开，则改为在 Windows 用户环境变量中
   设置 `ZOTERO_API_KEY` 并从 `.mcp.json` 删除该行（zotero-mcp 会直接读
   进程环境）。
3. 验证：重启 MCP 宿主后 zotero 工具可用；`Select-String -Path .mcp.json -Pattern 'xUkv|API_KEY.*[A-Za-z0-9]{20}'` 不再命中明文。

**禁止**：不要把新 key 写进任何入库文件、README 或本文档。

---

## T2. 重算两个旧代码产物 case【高优先级，需用户确认】

**背景**（PROJECT_PROGRESS.md 第 5 节）：
- `tandem_baseline_r1`：已用最新代码全量重算 ✅。
- `tandem_f40a3_phi0_r1`：⚠️ 曾手动终止，产物只更新到 SPOD；
  correlations/harmonics/figures/summary 为旧产物。
- `parallel_baseline_r1`：全部为旧代码产物。

**前置条件**：用户明确确认后再跑；确认 `J:\Export0731\...` 数据源在线。

**步骤**（严格串行，一个跑完确认无 matlab.exe 残留再跑下一个）：
1. `matlab -batch "addpath(pwd); run('cases/per_case/tandem_f40a3_phi0_r1/tandem_f40a3_phi0_r1_case.m')"`
   —— 缓存可复用，主要耗时在 structures/SPOD；预期 exit 0。
2. `matlab -batch "addpath(pwd); run('cases/per_case/parallel_baseline_r1/parallel_baseline_r1_case.m')"`
3. 每个 case 跑完检查：
   - `cases/per_case/<case>/output/csv/01_diagnostic_messages.csv` 无 ERROR；
   - `cases/per_case/<case>/output/csv/12_product_manifest.csv` 中 P01–P19
     状态合理（P20 必须保持 `DEFERRED`，单 case 不得伪造 Level 2/3）；
   - `output/md` 下 summary 时间戳为本次运行。
4. **顺带观察**（PROJECT_PROGRESS 已知问题）：`tandem_f40a3_phi0_r1` preview
   阶段曾出现"ZData 为复数时无法显示等高线"警告（`plot_structures` /
   `contourf`）。若复现，记录出现该警告的 section 与图号，在
   PROJECT_PROGRESS 待办中更新定位结论；正式导出路径不受阻则**不要**为此
   改绘图代码，先报告。
5. 更新 PROJECT_PROGRESS.md 第 2、5 节状态表。

**禁止**：并行启动两个 `matlab -batch`；不要删旧产物目录再跑（复用缓存）。

---

## T3. `run_case_serial.ps1` 串行包装脚本【中优先级】

**目标**：新建 `scripts/run_case_serial.ps1`（新建 `scripts/` 目录），把
PROJECT_PROGRESS 的串行纪律固化：

**功能要求**：
1. 参数：`-CaseName`（必填，如 `tandem_baseline_r1`）、`-MatlabExe`（默认
   `matlab`）、`-TimeoutMinutes`（默认 0 = 不限）。
2. 运行前 `Get-Process matlab -ErrorAction SilentlyContinue`，有残留则报错
   退出（exit 2）并列出 PID，**不**自动 kill。
3. 校验 `cases/per_case/$CaseName/${CaseName}_case.m` 存在，否则 exit 3。
4. 调用 `matlab -batch "addpath(pwd); run('cases/per_case/<case>/<case>_case.m')"`
   （在项目根目录下，`$PSScriptRoot\..` 定位项目根），透传退出码；
   结束后再次检查残留进程并警告。
5. 全程写 `tmp/run_<case>_<yyyyMMdd_HHmmss>.log`（`tmp/` 已被 gitignore）。
6. 同时支持 `-WhatIf` 只打印将执行的命令。

**验证**：用 `-WhatIf` 自检；经用户同意后用它执行 T2 的两个 case。
**禁止**：不要在脚本里硬编码数据盘路径；不要给脚本加并行选项。

---

## T4. 缓存 schema 失配修复提示增强【中优先级】

**背景**：`cache_meta.schema_version` 已升到 3，v2 旧缓存 reuse 时报
`CacheContractMismatch` 且"不自动重建、不删除"。当前报错只提示改
`cfg.stages.cache='compute'`，对接手者不够直白。

**步骤**：
1. 在 `+tbl/+periodic/` 中找到抛 `CacheContractMismatch` 的位置
   （`prepare_sequence_cache.m`、`load_stage_result.m`），把报错消息统一改为
   三段式：
   - 实际：当前 schema 与缓存 schema 的具体值；
   - 动作：`把 case 脚本 Section 0 的 cfg.stages.cache 改为 'compute' 后重跑
     Section 0–1；旧缓存文件 <完整路径> 不会被删除，可人工确认后清理`；
   - 影响：列出会因重建而失效的下游阶段 MAT。
2. 同步更新 `tests/` 中匹配该错误 ID/消息的断言（先 `grep -r CacheContractMismatch tests/` 定位）。
3. 可选增强：新增 `+tbl/+periodic/report_stale_caches.m`，扫描
   `cases/per_case/*/output/mat/01_sequence_cache*.mat`，打印各缓存 schema
   与当前代码 schema 的对照表（只读，不删不改），并在 T3 脚本 `-WhatIf`
   输出中调用它。
4. 验证：构造一个 schema_version=2 的临时缓存 MAT，reuse 时新消息三段齐全；
   全量测试 20/0、`matlab_check.py` 0 错误。

**禁止**：不要实现"自动重建旧缓存"或"自动删除旧缓存"——这是项目明确
禁止的行为（旧缓存只读复用/人工处置）。

---

## T5. 拆分 `plot_products.m` 与 `validate_config.m`【中优先级，纯重构】

**背景**：`+tbl/+periodic/plot_products.m` 1314 行、`validate_config.m`
788 行，是全库最大、评审最难的两个文件。

**目标结构**（保持 public API 不变）：
- 新建 `+tbl/+periodic/+plots/` 子包，按 Section 拆：
  `plot_cache.m`（S1）、`plot_statistics.m`（S2）、`plot_phase.m`（S3）、
  `plot_structures.m`（S4）、`plot_transport.m`（S5）、`plot_spectra.m`（S6）、
  `plot_modes.m`（S7）、`plot_correlations.m`（S8）。
  `plot_products.m` 保留为薄分发层：按 section/产品名调用
  `tbl.periodic.plots.*`，函数签名、`preview`/`export` 模式语义完全不变。
- `validate_config.m` 拆为同文件内 local functions 或
  `+tbl/+periodic/+validate/`：`validate_identity.m`、`validate_data.m`、
  `validate_stages.m`、`validate_structures.m`、`validate_modes.m` 等；主函数
  只做编排。错误消息格式 `field=... | expected=... | observed=...`
  **逐字保持不变**（测试有匹配）。

**铁律**：
1. 一次只拆一个文件，拆完立即跑全量测试 + `matlab_check.py`，绿了再拆下一个。
2. 不改任何数值、默认值注入顺序和报错 ID；纯移动代码。
3. `tests/test_section9_export.m` 等引用预览/导出语义的测试是验收基准，
  不得为迁就重构改测试（除非测试本身引用了被移动函数的内部路径）。

**验证**：全量测试 20/0；`python tests/matlab_check.py` 0 错误；用
`tandem_baseline_r1` 以全 `reuse` 跑一遍 Section 9 预览，确认图窗与拆前
一致（可与拆分前截图对比）。

---

## T6. `tests/run_all_tests.m` 统一入口【低优先级，可选】

新建 `tests/run_all_tests.m`（函数，返回 results table），内容即 README
第 10 节的自动枚举逻辑；把 README 与 PROJECT_PROGRESS.md 第 7 节的命令
统一改为 `r = run_all_tests;`（保留 matlab -batch 单行版作为 CI 用法）。
验证：`matlab -batch "addpath(pwd); addpath tests; r=run_all_tests; assert(all([r.Passed]))"` exit 0。

---

## T7.（暂缓，需用户拍板）case 参数抽离 `cfg_<case>.m`

若用户批准：把三个 pilot 脚本 Section 0 的 cfg 赋值块抽成同目录
`cfg_<case>.m` 函数，case 脚本只保留定位逻辑 + `cfg = cfg_<case>();` +
Section 1–9 编排。注意：必须同步更新 `tests/test_pilot_case_scripts_contract.m`、
`test_section0_rewrite.m` 及 `docs/section_handoffs/*.md` 中对"Section 0
参数块"的描述。**本轮不执行**，仅记录方案。

## T8.（暂缓，需用户拍板）旧 singlecase 流程退役

若用户宣布旧九阶段流程冻结：把 `baseline_case.m`、`f40a1_case.m` 移入
`archive/legacy_pipeline_20260715/`，保留 `+tbl/+singlecase` 与其测试直到
引用清零；README 改为只讲周期流程。**本轮不执行**。

## T9. `tmp/` / `downloads/`

已在 .gitignore，无代码行动。人工定期清空本地文件即可；不要提交其中的内容。

---

## 完成标志

- 每个任务完成后：相关验证命令通过；`PROJECT_PROGRESS.md`"最近完成的工作"
  追加一条（日期 + 任务号 + 结果）；本文档对应任务的优先级标注改为 ✅ 已完成。
- 全部任务完成或经用户确认放弃后，本文档可移入 `docs/history/`。
