# Section 8 独立重写对比（人工审阅稿）

## 状态

已完成 `section_08_handoff.md` 规定的核心流程：阅读源码与 handoff、联网检索、独立评审/重写、
合成场验证、回写主工作区、针对性回归测试。子代理在测试阶段提前终止后，由主进程完成回归验证、
README 核对与本报告。

## 联网检索结论（可复核来源）

- MATLAB `xcorr(...,'coeff')` 用于时间/流向相关；
- `cpsd` 与 `mscohere` 用于双信号互谱与相干性；
- 二维两点相关、时空相关脊线与谐波幅值沿用项目既有口径，本轮不重写公式。

## 旧实现评价

旧实现已具备 `correlation_analysis_cache`、`streamwise_development_analysis` 与
`record_selection_diagnostics`，且核心测试已覆盖；本轮重点补齐函数头合同、P16→P18
链接、外部信号缺失语义与诊断输出显式化。

## 新实现改进（已回写）

1. `+tbl/+periodic/correlation_analysis_cache.m`：
   - 输出 `temporal/streamwise/two_point/space_time/conditional/coherence`
     结构；外部信号为空时相关分支明确标记 `unavailable`。
   - 保持逐块读取与 `read_cache_chunk` 的 total/random 分支。
2. `+tbl/+periodic/streamwise_development_analysis.m`：
   - 汇总 P02/P07/P08/P10-P17 的沿程链接；
   - 受控 case 增加 f0/2f0/3f0 谐波与 coherent response；
   - 缺失可选上游时保存可用核心，P18 标为 `PARTIAL`，不伪造结果。
3. `+tbl/+periodic/record_selection_diagnostics.m`：
   - 把 temporal/spatial/correlations 的最近行回退写入
     `csv/01_diagnostic_messages.csv`，并显式标记 `LIMITED` 与
     “nearest measured point retained; no extrapolation performed”。
4. 两个 case 脚本 Section 8：补充相关性与沿程综合注释；编排不变。

## 测试结果（MATLAB R2022b，全部通过）

Section 8 合同由 `tests/test_periodic_piv_core.m` 覆盖（`correlation_analysis_cache`、
`streamwise_development_analysis`、P18 定义字符串、受控/基线分支）。本轮回归运行：

    matlab -batch "addpath('tests'); test_section5_transport_quadrant; test_section6_spectra; test_section7_modes; test_refactor_shared_helpers; test_pressure_gradient_contract; test_periodic_piv_core"

结果：6 个测试文件全部 PASS。未运行真实 3000/6000 帧重算；只使用合成场与临时目录。

## 遗留风险

- 真实外部同步信号相干性未测试；缺失时只走 `unavailable` 分支。
- 真实沿程 P18 的 PARTIAL 语义只在合成结果上验证，未跑真实上游缺失场景。
- `record_selection_diagnostics` 的 CSV 写入依赖 `log_path` 目录存在；运行前
  需由 `build_paths` 确保目录已创建。

## 修改文件清单

- `+tbl/+periodic/correlation_analysis_cache.m`
- `+tbl/+periodic/streamwise_development_analysis.m`
- `+tbl/+periodic/record_selection_diagnostics.m`
- `cases/single/baseline_debug3000/baseline_periodic_piv_case.m`
- `cases/single/f40a3/f40a3_periodic_piv_case.m`
