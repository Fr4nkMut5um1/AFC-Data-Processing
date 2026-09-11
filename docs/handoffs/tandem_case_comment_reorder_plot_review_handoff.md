# 会话交接：tandem_baseline_r1 参数整理与 Section 2–9 绘图排布 review

> 来源会话：session-fb22eaf2-af58-4429-9265-57f09e4f41ac（dsh session 日志）
> 生成时间：2026-08-19 00:05（UTC+8），由接续会话依据 session.jsonl 与磁盘现状生成
> 工作目录：`D:\Users\Frank_7840HSw\Desktop\202605实验快反计算\Current_Plate_Calculation`
> （WSL 挂载为 `/mnt/d/Users/Frank_7840HSw/Desktop/202605实验快反计算/Current_Plate_Calculation`，同一物理目录）

## 0. 给接手者的一句话

本会话已完成用户要求的两项主体工作：**case 脚本 Section 0 的参数整理/注释规范** 与
**Section 2–9 图窗尺寸/子图排布 review 返修**；最后一个有效需求
“全局显示比例改回 1:1”已在本接续会话写入磁盘并通过静态检查。
当前磁盘上有两个 tracked 文件未提交（详见 §1），需要接手者完成
**1:1 比例下的出图复查、全量测试、按用户确认提交**。本文档即为让新会话无上下文接手的 handoff。

## 1. 磁盘当前状态（以磁盘为准）

```text
 M +tbl/+periodic/plot_products.m
 M cases/per_case/tandem_baseline_r1/tandem_baseline_r1_case.m
?? docs/handoffs/maintenance_improvements_handoff.md   <- 历史未跟踪文件，勿提交
?? docs/handoffs/wsl_dsh_migration_handoff.md          <- 历史未跟踪文件，勿提交
?? docs/handoffs/tandem_case_comment_reorder_plot_review_handoff.md  <- 本文档，勿提交
```

按项目 git 纪律：`docs/handoffs/` 不提交、不删除；本会话对上述两个 tracked 文件的改动
也**先不要自行 commit**，等用户确认后按其指示处理。

## 2. 用户需求与完成情况

| # | 用户需求 | 状态 |
|---|---|---|
| 1 | 以 `cases/per_case/tandem_baseline_r1/tandem_baseline_r1_case.m` 为例：规范注释对齐格式；Section 0 的 cfg 按 section 先后次序排列，全局 cfg 前置，最前面放 stages 策略、case 身份、输入、输出、实验常量 | ✅ 已完成（磁盘） |
| 2 | 很多 cfg 除默认选项外还有其他选项，需在注释中标注当前可选项 | ✅ 已完成（磁盘，关键字段均已标注） |
| 3 | 调查并汇报 Section 2 / Section 4 分别做了什么计算、得到哪些物理量、绘制哪些图 | ✅ 已汇报（无文件改动；摘要见 §3） |
| 4 | 平均速度剖面 log-law 没有在 Section 2 被绘制，修复 | ✅ 已完成：`plot_products.m` 新增 `loglaw` job |
| 5 | 每个 Section 的绘图参数统一放到 Section 0 各 Section 分区的最前面 | ✅ 已完成：C1–J1 均为“本 Section 绘图参数”，K 只保留全局绘图/预览 |
| 6 | Section 2 运行时出现无用的瞬时流场动图；要求 `close all` 移到脚本最后（F5 全跑最后统一关窗，分节运行不关窗） | ✅ 已完成：顶部 `close all` 删除，末尾新增 `close all`，`cfg.preview.close_before_export=false` |
| 7 | 修改时 Section 0-A 不要动（用户正在调试，需要临时 skip 一些 section） | ✅ 已遵守：A 区各 `cfg.stages.*` 值原样保留，只对齐了注释 |
| 8 | 评估 Section 2–9 figure 窗口大小、云图/点线图大小与排布，允许用识图功能和 reuse 模式出图 | ✅ 已完成一轮 review（当时 fov=2.4） |
| 9 | 按 review 返修，允许调整组图子图排布 | ✅ 已完成（见 §4） |
| 10 | **全局显示比例改回 1:1** | ✅ 已由本接续会话完成：`cfg.figures.fov_aspect_ratio = [1 1]` |
| 11 | 对本对话生成 handoff，让其他对话接手 | ✅ 本文档 |

## 3. Section 2 / Section 4 调查结论（用户问过的内容，保留在此供接手者复核）

### Section 2（statistics + mean_bl）
- **statistics（`mat/02_statistics.mat`）**：分块读取 `mat/01_sequence_cache.mat`，
  按每个点的有效样本逐点统计：`Uavex/Vavex`（平均场）、`uu_rey/vv_rey`
  （有量纲脉动方差）、`uv_rey=-⟨u'v'⟩`（负雷诺剪切应力）、
  `u_rms/v_rms`、`TKE=0.5(uu+vv)/Uinf²`（无量纲）、`valid_count/valid_fraction/accepted_mask`。
  双 repeat 口径：平均场整体平均；脉动先逐 repeat 去均值再拼接统计。
- **mean_bl（`mat/02_mean_boundary_layer_friction.mat`）**：壁面坐标
  `wall_distance_grid`（首行壁距 `dy_h*h`）；代表剖面抽取；Clauser 法 log-law 拟合
  （`u_tau/Cf/κ/B/RMSE/拟合窗口`）；三种 Cf 口径（log-law 单值、system secant 平均、
  local Cf(x) 分布）；积分厚度、边界层 `delta99`、压力梯度敏感性诊断。
- **绘制**：三组无量纲云图（U/V、u′/v′ RMS、-u′v′/TKE）→
  `02a/02b/02c_*.png`；log-law 拟合（preview 为 Cf chart + 壁面律两张，export 合并为
  `06_loglaw.png`）；`11_friction_and_BL.png`（Cf 与边界层厚度沿程）。

### Section 4（structures）
- 先建立/复用 PostProc 序列缓存并做双源网格一致性校验；
  对代表帧读取 raw/total 场，计算 `u′=u−Uavg`、`v′=v−Vavg`、`u′v′`、
  `−u′v′`；`planar_criteria` 计算 `omega_z/Q/lambda2/lambda_ci` 平面判据；
  `identify_structures` 按 `u′/u_rms` 正负符号分离、4/8 邻域连通、LSM/VLSM 按
  `Lx/delta99` 判定；输出代表帧瞬时场/判据/结构目录与全帧结构目录
  （`mat/09_structure_analysis.mat`）。
- **绘制**：`03_instantaneous_fields_*`（原始 u 与 u′）、`03_instantaneous_uv*`、
  `03_instantaneous_uvprime*`、`10_instantaneous_vortex_*`（四判据 2×2）、
  `10_time_mean_planar_vortex_criteria`（时间平均判据 2×2）、
  `09_structures_frame_*`（归一化场 + 连通标签）、`09_structures_distribution*`
  （LSM/VLSM 尺度/强度分布）。

## 4. 本会话对两个 tracked 文件的具体改动

### 4.1 `cases/per_case/tandem_baseline_r1/tandem_baseline_r1_case.m`

- Section 0 重组为：
  - A：各 Section compute/reuse/skip 策略（值未动，只对齐注释）；
  - B：case 身份 / 帧网格采样 / 双源路径 / 实验常量 / 绘图容器；
  - C–J：按 Section 1–8 顺序，每个分区的**绘图参数在最前**（C1–J1），
    其后才是数值参数；
  - K：只保留 Section 9 全局导出格式、`contour_levels`、`fov_aspect_ratio`、
    默认窗口、`export_dpi`、默认 colormap、`cfg.preview`。
- 注释对齐与可选项标注：例如 `可选 bottom | top`、`可选 true | false`、
  `可选 []（自动）| 标量 | [横向 纵向]`、colormap 可选项列表等。
- `close all` 从脚本顶部移除，新增到脚本最后一行（F5 全跑最后统一关窗；
  分节运行不会执行到该行）；`cfg.preview.close_before_export = false`。
- 窗口尺寸（old→new，像素 [宽 高]）：
  ```text
  mean_turbulence        [700 350]  -> [900 650]
  instantaneous_uv       [1100 900] -> [1300 900]
  instantaneous_uvprime  [1100 900] -> [1300 900]
  instantaneous_planar   [1300 760] -> [1450 1000]
  planar_mean            [1450 760] -> [1450 1000]
  structures             [1250 560] -> [1000 1000]
  transport              [1350 620] -> [1450 900]
  pod                    [1250 560] -> [1450 760]
  correlations           [1250 560] -> [1450 900]
  loglaw                 （新增）    -> [1250 560]
  ```
- **最后一步（本接续会话）**：`cfg.figures.fov_aspect_ratio = [1 1]`，
  注释更新为“当前 [1 1]（宽:高 = 1:1）”；`mean_turbulence` 注释同步改为
  `fov=1:1 时按 2×1 排布`。文件中已无 `2.4` 残留。

### 4.2 `+tbl/+periodic/plot_products.m`

- `jobs` 注册表新增 `'loglaw', @plot_loglaw`；新增 `plot_loglaw` 及
  `draw_cf_chart_axes` / `draw_loglaw_axes` 两个局部函数。
- Section 5 输运图：`1×3` → `2×2`；三个云图占前三 tile，第 4 个 tile 用
  `axis off + text` 放置图题，消除主标题与 panel 标题重叠。
- Section 4 结构图：`1×2` → `2×1` 上下排布；去掉全局 `title(layout,...)`，
  改为第一面板标题 `u'/u_rms, frame N [PostProc]`；fallback 窗口 `[1000 1000]`。
- POD 云图与相关性图两点相关面板：在 `apply_fov_aspect` 后追加
  `pbaspect(ax,[1.8 1 1])` / `pbaspect(ax_two_point,[1.8 1 1])`，改善左右面板高度差。
- 瞬时场静态图（`instantaneous_fields` 非动画分支）：`Padding` 由 `compact`
  改为 `loose`，避免标题与 panel 贴边。

## 5. 已验证

- `python tests/matlab_check.py`：**170 个 .m 文件无结构错误**（本接续会话在 fov 1:1 修改后重跑）。
- `checkcode` case 文件：**0 条消息**（fov 1:1 修改后重跑）。
- **全量 MATLAB 测试：20 passed / 0 failed**（本接续会话重跑）。
  - 初次全量跑发现 `test_pilot_case_scripts_contract` 失败：case 文件
    `cfg.loglaw.params.dy_h` 当前值为 `1.5`，而静态合同与注释都要求 `2.0`。
  - 已把该行恢复为 `cfg.loglaw.params.dy_h = 2.0;`（与上一行注释
    “初始默认 dy_h=2.0”一致），重跑该测试及全量测试均通过。
  - 该修复不在用户“Section 0-A 不要动”的范围内（位于 D4 块），且是恢复
    合同值而非新改动；如用户调试时是有意设为 1.5，需用户明确告知后再说。
- fov=2.4 时上一会话已用 reuse 模式重新导出全部标准 PNG（`errors=0`）并用识图
  渠道 review 返修，最终尺寸示例：输运 2909×1558(1.87)、结构 1998×1898(1.05)、
  瞬时平面判据 2905×1673(1.74)、时间平均判据 2905×1663(1.75)、
  POD 2913×1549(1.88)、相关性 2903×1842(1.58)。
- `checkcode plot_products.m`：仅剩 1 条历史警告（1458 行“变量似乎要更改每个循环
  迭代的大小”，属于 `produced=[produced;...]` 增长数组提示，不是本次新增）。
- 审查图片临时目录（fov=2.4 产物，仍可查）：`%TEMP%\tandem_figure_review_final2\png`。

## 6. 未完成 / 待办（按建议顺序）

1. **1:1 比例出图复查**（最重要）：当前 `fov_aspect_ratio` 已改 `[1 1]`，
   但 §5 的识图 review 是在 2.4 下做的。用 reuse 模式重导全部标准 PNG 并抽查
   关键图（至少 `02a/02b/02c`、`04`、`09`、`10_*`、`13`、`06_loglaw`），
   确认 1:1 下无标题重叠、无过度留白或面板挤压。**不要触发任何重算**：
   `mat/` 下所有输入 MAT 已存在，只调用 `plot_products(...,'export')`。
   可参考的 review 脚本骨架见 §7。
2. 若 1:1 下某图排布不佳：只允许改 `cfg.figures.window_size.*`（在 case 文件）或
   共享 `plot_products.m` 的 tiledlayout/pbaspect；**不要动 Section 0-A**。
   改后重跑 `matlab_check.py` + `checkcode` + 全量测试（命令见 §7）。
3. 询问用户是否需要把本次 case 文件/plot_products 的改动**同步到另外两个正式 case**
   （`tandem_f40a3_phi0_r1`、`parallel_baseline_r1`）。本会话按用户要求只改
   `tandem_baseline_r1` 一个样例，未传播。
4. 用户确认后按 git 纪律提交两个 tracked 文件；不要提交 `docs/handoffs/`。

## 7. 命令速查

环境：WSL 里 `matlab` 已封装为 Windows MATLAB R2022b 互操作
（`/mnt/d/Academic/Software/MATLAB/R2022b/bin/matlab.exe`）。项目根目录为本文档
上两级目录。MATLAB 进程严格串行，跑完确认无残留 `matlab.exe` 再启动下一个。

- 静态检查：
  ```bash
  cd "/mnt/d/Users/Frank_7840HSw/Desktop/202605实验快反计算/Current_Plate_Calculation"
  python3 tests/matlab_check.py
  ```
- case 文件 lint：
  ```bash
  matlab -batch "msgs=checkcode('D:\\Users\\Frank_7840HSw\\Desktop\\202605实验快反计算\\Current_Plate_Calculation\\cases\\per_case\\tandem_baseline_r1\\tandem_baseline_r1_case.m'); fprintf('case_mlint=%d\\n',numel(msgs)); for i=1:numel(msgs), fprintf('%d: %s\\n',msgs(i).line,msgs(i).message); end"
  ```
- plot_products lint：
  ```bash
  matlab -batch "msgs=checkcode('D:\\Users\\Frank_7840HSw\\Desktop\\202605实验快反计算\\Current_Plate_Calculation\\+tbl\\+periodic\\plot_products.m'); fprintf('plot_mlint=%d\\n',numel(msgs)); for i=1:numel(msgs), fprintf('%d: %s\\n',msgs(i).line,msgs(i).message); end"
  ```
- 全量测试（MATLAB 内执行，Windows 下同样可用）：
  ```matlab
  addpath(pwd);
  files=dir(fullfile(pwd,'tests','test_*.m'));
  names=cellfun(@(f) fullfile(files(1).folder,f), {files.name}, 'UniformOutput', false);
  r=runtests(names);
  disp(table(r)); fprintf('passed=%d failed=%d\n', nnz([r.Passed]), nnz([r.Failed]));
  ```
- 1:1 reuse 出图复查（写为 `D:\TEMP\review_fov_1to1.m` 后
  `matlab -batch "run('D:\\TEMP\\review_fov_1to1.m')"`）：
  ```matlab
  function review_fov_1to1()
  repo_root='D:\Users\Frank_7840HSw\Desktop\202605实验快反计算\Current_Plate_Calculation';
  addpath(repo_root,'-begin');
  case_dir=fullfile(repo_root,'cases','per_case','tandem_baseline_r1');
  out_root=fullfile(tempdir,'tandem_figure_review_fov_1to1');
  if isfolder(out_root), rmdir(out_root,'s'); end
  paths=tbl.periodic.build_paths(out_root);
  paths.sequence_cache_postproc=fullfile(case_dir,'output','mat','01_sequence_cache_postproc.mat');
  cfg=load(fullfile(case_dir,'output','mat','00_case_configuration.mat'),'cfg'); cfg=cfg.cfg;
  cfg.figures.formats={'png'};
  cfg.figures.fov_aspect_ratio=[1 1];
  cfg.figures.instantaneous.animation.enabled=false;
  ws=cfg.figures.window_size;
  ws.mean_turbulence=[900 650]; ws.instantaneous_uv=[1300 900];
  ws.instantaneous_uvprime=[1300 900]; ws.instantaneous_planar=[1450 1000];
  ws.planar_mean=[1450 1000]; ws.structures=[1000 1000]; ws.transport=[1450 900];
  ws.pod=[1450 760]; ws.correlations=[1450 900];
  cfg.figures.window_size=ws;
  results=struct();
  pairs=struct('field',{'statistics','mean_bl','structures','transport','temporal','spatial','pod','dmd','spod','correlations','harmonics'}, ...
               'file',{'02_statistics.mat','02_mean_boundary_layer_friction.mat','09_structure_analysis.mat','04_transport_quadrant.mat','05_temporal_spectra.mat','05_spatial_spectra.mat','06_pod_analysis.mat','07_dmd_analysis.mat','08_spod_analysis.mat','13_correlation_analysis.mat','13_streamwise_harmonic_development.mat'});
  for k=1:numel(pairs)
      f=fullfile(case_dir,'output','mat',pairs(k).file);
      if isfile(f), s=load(f,'data'); results.(pairs(k).field)=s.data; end
  end
  results.phase=[];
  out=tbl.periodic.plot_products(results,cfg,paths,'export');
  fprintf('files=%d errors=%d\n',numel(out.files),numel(out.errors));
  for i=1:numel(out.errors), fprintf('ERR:%s:%s\n',out.errors(i).job,out.errors(i).message); end
  end
  ```
  说明：该脚本只加载现有 MAT 并重新出图，不写 case 输出目录、不触发重算。
  生成的 PNG 在 `%TEMP%\tandem_figure_review_fov_1to1\png`，可用识图工具逐个 review。

## 8. 禁止事项（继承项目纪律）

- **不改 Section 0-A**（用户明确：调试期需要临时 skip 某些 section）。
- 不自动重建/自动删除缓存；不触发 GB 级重算，除非用户明确批准。
- 不把 `J:\Export0731\...` 路径改成 `/mnt/j/...`（MATLAB 是 Windows 进程，只认盘符）。
- 不提交、不删除 `docs/handoffs/`、`.reasonix/`、`reasonix.toml`、
  `other_case_scripts/`、`AFC课题讨论V9-林正-20260718.pptx` 等未跟踪文件。
- 文档/脚本一律 UTF-8 无 BOM。
- MATLAB 一律串行；同一时刻只跑一个 `matlab -batch`。
