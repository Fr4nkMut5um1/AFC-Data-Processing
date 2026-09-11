# Section 5 独立重写对比（人工审阅稿）

## 状态

已完成 `section_05_handoff.md` 规定的核心流程：阅读源码与 handoff、联网检索、独立评审/重写、
合成速度场验证、回写主工作区、针对性回归测试。子代理在维度问题调试阶段提前终止后，由主进程
完成真实 bug 修复、测试修正、回归验证、README 与本报告。

## 联网检索结论（可复核来源）

- 象限分析采用经典 Q1-Q4 符号口径（正 V 离壁）：
  Q1 `u'>0,v'>0`、Q2 `u'<0,v'>0`、Q3 `u'<0,v'<0`、Q4 `u'>0,v'<0`；
  剪切应力贡献使用 `-u'v'`，Q2/Q4 通常为正。
- hole 函数采用 `abs(u'v') > H*local_scale`，周期流程合同为
  `hole_scale_definition='H times local u_rms*v_rms'`；
  单 case 参考路径使用逐点时间均值 `|<u'v'>|` 作为尺度。
- 湍动能输运与法向梯度复用项目既有有限差分/RBF-FD 灵敏度路径，本轮不重写数值公式。

## 旧实现评价

旧实现已具备 `quadrant_streaming`、`transport_analysis` 与共享 `quadrant_mask`，
但 `quadrant_analysis` 在 `J=1` 的合成/边界网格下存在 `squeeze` 维度塌缩 bug，
且缺少专门的 Section 5 合成测试。

## 新实现改进（已回写）

1. `+tbl/+stats/quadrant_analysis.m`：
   - 修复逐帧切片维度 bug：`squeeze(1×1×I)` 在 J=1 时变成 `I×1`，
     与 `1×I` hole scale 广播成 `I×I`；改用 `reshape(...,J,I)` 保持方向。
   - 累加切片统一用 `reshape(...,1,J,I)` 写入 `4×J×I` 数组，避免维度失配。
   - 补充函数头合同：象限定义、hole 语义、事件概率分母、`S*_frac` 定义。
2. `+tbl/+stats/quadrant_mask.m`：共享 Q1-Q4 mask，hole scale 缺省时仅对
   `H=0` 有意义，`H>0` 必须由调用方提供尺度。
3. `+tbl/+periodic/quadrant_streaming.m`：沿用共享 mask 与 hole 合同，
   输出 total/random 分支所需字段。
4. `+tbl/+periodic/transport_analysis.m`：保持 `results.transport` 合同与
   两类法向梯度路径，补齐说明。
5. `tests/test_section5_transport_quadrant.m`（新增）：覆盖象限符号、概率、
   `-u'v'` 应力、H=0/1/2 hole 语义、J=1 网格、共享 mask 交叉校验、
   `quadrant_streaming`/`transport_analysis` 与 case 脚本静态合同。
6. `README.md`：测试清单加入 `test_section5_transport_quadrant.m` 并说明覆盖内容。

## 主进程补齐的测试修正

- `Q1h.P*` 在 J=1 时是 `1×I` 向量，`assert` 改为 `all(...,'all')`。
- 生产代码中的 `squeeze` 维度 bug 通过新增 J=1 用例暴露后已修复。

## 测试结果（MATLAB R2022b，全部通过）

    matlab -batch "addpath('tests'); test_section0_rewrite; test_section1_sequence_cache; test_section2_mean_stats_cache; test_section3_phase_triple; test_section4_structure_analysis; test_section5_transport_quadrant; test_refactor_shared_helpers; test_pressure_gradient_contract; test_vlsm_cluster_connectivity; test_singlecase_helpers; test_periodic_piv_core"

结果：11 个测试文件全部 PASS。未运行真实 3000/6000 帧重算；只使用合成场与临时目录。

## 遗留风险

- 真实数据下的相位分辨 Q2/Q4 与 cycle-average 结果未运行；只有合成验证。
- `quadrant_analysis` 的 hole 尺度在单 case 参考路径为逐点 `|<u'v'>|`，
  周期路径为 `u_rms*v_rms`，两套口径由调用方显式传入，需保持调用处一致。
- 输运项中的 RBF-FD 灵敏度只做合同验证，未在真实网格上重算。

## 修改文件清单

- `+tbl/+stats/quadrant_analysis.m`
- `+tbl/+stats/quadrant_mask.m`
- `+tbl/+periodic/quadrant_streaming.m`
- `+tbl/+periodic/transport_analysis.m`
- `tests/test_section5_transport_quadrant.m`（新增）
- `README.md`
