# Section 4 独立重写对比（人工审阅稿）

## 状态

已完成 `section_04_handoff.md` 规定的核心流程：阅读源码与 handoff、联网检索、独立评审/重写、
合成场验证、回写主工作区、针对性回归测试。子代理在测试阶段被中止后，由主进程补齐测试修正、
回归验证、README 与本报告。

## 联网检索结论（可复核来源）

- PIV 平面涡判据采用 2D-2C 显式代理：`omega_z=dV/dx-dU/dy`、平面 Q、
  `lambda2` 与 `lambda_ci`；这些是平面测量下的常见代理，不冒充三维判据。
- 连通域识别优先使用 Image Processing Toolbox `bwconncomp`，无工具箱时回退
  `tbl.vlsm.connected_components_2d` 的 4 邻域实现；8 邻域缺失工具箱时明确报错。
- LSM/VLSM 采用 `Lx/delta99` 与 `max_wall_normal_delta`、`min_pixels`、
  附壁/边缘选项共同约束，符号按正/负脉动分离。

## 旧实现评价

旧实现已具备 `planar_criteria`、`gradient_y_sensitivity`、`identify_structures`、
`structure_analysis_cache` 与 VLSM 共享函数；本轮重点补充显式合同、输入校验与
合成端到端测试，未改动既有数值公式。

## 新实现改进（已回写）

1. `+tbl/+periodic/identify_structures.m`：
   - 增加 options 必填字段、`connectivity`、`sign_mode` 的显式校验；
   - 正/负符号分别连通，结构表统一添加 `StructureID`；
   - `min_pixels`、`max_wall_normal_delta`、LSM/VLSM 阈值保持原口径；
   - 空结构时返回带完整字段名的空 table。
2. 两个 case 脚本 Section 4：补充瞬时代表帧、涡判据、符号分离与 LSM/VLSM
   判据注释；编排代码不变。
3. `tests/test_section4_structure_analysis.m`（新增）：覆盖瞬时代表帧语义、
   解析涡判据、连通/符号/阈值/LSM/VLSM、结构表字段名、4 邻域回退、
   `structure_analysis_cache` 端到端与 case 脚本静态合同。
4. `README.md`：测试清单加入 `test_section4_structure_analysis.m` 并说明覆盖内容。

## 主进程补齐的测试修正

- `floor(linspace(first,last,1))` 在 MATLAB 中返回末端点，测试原先期望首端点；
  按 handoff 的公式契约改为期望末端点。
- 固体旋转速度场测试把网格单位搞混，`planar_criteria` 内部把 mm 转 m，
  速度场改用与内部网格一致的 0–1 m 坐标。
- 4/8 邻域对角结构是两个单像素块，测试原先未把 `min_pixels` 降到 1，
  导致两个结构都被过滤；修正后正确区分 4 邻域 2 个、8 邻域 1 个。

## 测试结果（MATLAB R2022b，全部通过）

    matlab -batch "addpath('tests'); test_section0_rewrite; test_section1_sequence_cache; test_section2_mean_stats_cache; test_section3_phase_triple; test_section4_structure_analysis; test_refactor_shared_helpers; test_pressure_gradient_contract; test_vlsm_cluster_connectivity; test_singlecase_helpers; test_periodic_piv_core"

结果：10 个测试文件全部 PASS。未运行真实 3000/6000 帧重算；只使用合成场与临时目录。

## 遗留风险

- 真实 LSM/VLSM 目录未运行；`Lx/delta99` 阈值与附壁/边缘选项对真实数据的影响
  需要人工检查。
- `planar_criteria` 的 Q/lambda2/lambda_ci 是平面代理，不能直接等同于三维判据；
  报告与产物中已用 `scope` 字段说明。
- 8 邻域识别依赖 Image Processing Toolbox；若目标机器未安装 IPT，需要改用
  项目内 8 邻域实现或接受报错。

## 修改文件清单

- `+tbl/+periodic/identify_structures.m`
- `cases/single/baseline_debug3000/baseline_periodic_piv_case.m`
- `cases/single/f40a3/f40a3_periodic_piv_case.m`
- `tests/test_section4_structure_analysis.m`（新增）
- `README.md`
