# Section 2 独立重写对比（人工审阅稿）

## 状态

已完成 `section_02_handoff.md` 规定的核心流程：阅读源码与 handoff、联网检索、独立评审/重写、
合成数据验证、回写主工作区、针对性回归测试。子代理在报告阶段提前终止后，由主进程补齐测试修复、
回归验证与本报告。

## 联网检索结论（可复核来源）

- MathWorks 官方 `matfile` / MAT 版本文档确认 v7.3 适合大文件分块读写：
  https://www.mathworks.com/help/matlab/import_export/large-mat-files.html
- Welford / Chan-Golub-LeVeque 流式方差与协方差合并是数值稳定的标准做法；
  本项目用同一恒等式做跨块统计合并，避免 `sum(X^2)/n - mean^2` 抵消。
- 边界层厚度、Clauser/log-law 与动量积分 Cf 的参考公式沿用项目既有
  `+tbl/+bl`、`+tbl/+wall` 共享实现；本轮不重写数值公式。

## 旧实现评价

旧 `mean_stats_cache.m` 已是逐块读取，但块间合并采用简单 sum-of-squares 口径，
大样本或单精度缓存下存在抵消风险；旧 `mean_bl_friction.m` 已复用共享函数，
但缺少完整合同说明。两个 case 脚本 Section 2 注释较简略。

## 新实现改进（已回写）

1. `+tbl/+periodic/mean_stats_cache.m`：
   - 函数头写明 Section 2 输出字段合同、逐块读取约束与 `count<2` / 有效率阈值语义。
   - 块间合并改为 Chan-Golub-LeVeque（Welford 家族）恒等式，数值上与总体矩口径等价，
     但避免灾难性抵消；`chunk_frames` 只影响 I/O 粒度，不改变结果。
   - 增加对缓存变量缺失、`X/Y` 尺寸不匹配、`h_mm` 非法值的干净错误。
2. `+tbl/+periodic/mean_bl_friction.m`：
   - 补充壁面坐标、`select_u_tau`、log-law/system/local 三种 Cf 口径的合同注释；
   - 保留 `wall_distance_grid` 唯一壁面坐标入口与既有共享函数调用链。
3. 两个 case 脚本 Section 2 注释块：写明产物路径、逐块统计、字段名、壁面坐标与
   `u_tau_source` 约定；编排代码不变。
4. `tests/test_section2_mean_stats_cache.m`（新增）：合成缓存覆盖分块不变性、
   与内存总体矩参考一致、字段合同、无效样本策略、参数错误、缺失缓存变量、
   `wall_distance_grid` 合同、`mean_bl_friction` 端到端合同。
5. `README.md`：测试清单加入 `test_section2_mean_stats_cache.m`。

## 主进程补齐的测试修正

子代理留下的新测试最初有三类问题，主进程已修正：

- `make_cache` 中 `[n×J×I]` 与 `[J×I]` 网格做隐式展开，在本机 R2022b 不被接受，
  改为显式 `reshape(...,1,J,I)`。
- 内存参考未考虑缓存单精度舍入，改为 `double(single(U/V))` 后再比较；
  `count<2` 点的均值也按合同改为断言 `NaN`。
- 合成剖面改为沿流向增厚边界层，使动量积分 `theta` 向下游增长，
  system Cf 为正，端到端断言成立。

## 测试结果（MATLAB R2022b，全部通过）

    matlab -batch "addpath('tests'); test_section0_rewrite; test_section1_sequence_cache; test_section2_mean_stats_cache; test_refactor_shared_helpers; test_pressure_gradient_contract; test_singlecase_helpers; test_periodic_piv_core"

结果：7 个测试文件全部 PASS。未运行真实 3000/6000 帧重算；只使用合成缓存与临时目录。

## 遗留风险

- `mean_stats_cache` 以“每点自身有效样本数”为总体矩分母；若后续要改为流场统一有效率，
  属于口径变更，需要人工确认。
- 合成 `mean_bl_friction` 剖面仍非真实数据，log-law 拟合提示 `RMSE>0.5`，只验证了
  调用链与结构合同，不验证真实物理数值。
- `chunk_frames` 只改变 I/O 粒度；极端块大小下浮点顺序仍可能带来 ~1e-7 级差异，
  测试容差按单精度缓存设置。

## 修改文件清单

- `+tbl/+periodic/mean_stats_cache.m`
- `+tbl/+periodic/mean_bl_friction.m`
- `cases/single/baseline_debug3000/baseline_periodic_piv_case.m`
- `cases/single/f40a3/f40a3_periodic_piv_case.m`
- `tests/test_section2_mean_stats_cache.m`（新增）
- `README.md`
