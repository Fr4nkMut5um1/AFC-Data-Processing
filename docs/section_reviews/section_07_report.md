# Section 7 独立重写对比（人工审阅稿）

## 状态

已完成 `section_07_handoff.md` 规定的核心流程：阅读源码与 handoff、联网检索、独立评审/重写、
合成模态数据验证、回写主工作区、针对性回归测试。子代理在测试修复阶段提前终止后，由主进程完成
测试修正、回归验证、README 核对与本报告。

## 联网检索结论（可复核来源）

- Snapshot POD 参考 `Comparison_Re30w_AoA2.m`：
  `C=Xf'*Xf/size(Xf,1)`、`eig` 降序、`Phi=Xf*As` 归一化、`Ac=Phi'*Xf`；
- DMD 使用 MIT 许可的 piDMD（baddoo/piDMD）`piDMD(X1,X2,'exact',r)`；
- SPOD 使用已安装的 Towne/Schmidt `spod.m`，通过 `spod_toolbox_adapter` 封装；
- 随机 SVD/`svds` 只作为可选参考，不改变上述既定算法合同。

## 旧实现评价

旧实现已具备 POD/DMD/SPOD 三个 stage 与外部轮子 adapter，但函数头合同、模式映射空模式
守卫、外部工具箱 info 字段与合成端到端测试不足；本轮补齐这些内容。

## 新实现改进（已回写）

1. `+tbl/+periodic/pod_cache.m`：显式保留
   `lambda/energy_ratio/cumulative_energy_ratio/temporal_coefficients/modes/
   orthogonality_matrix/reconstruction_*` 字段；`energy_ratio` 为每模态占比，
   `cumulative_energy_ratio` 为累计占比。
2. `+tbl/+periodic/dmd_cache.m`：固定等时间步快照矩阵，委托 piDMD exact，
   保留 `eigenvalues/frequency_hz/growth_rate_per_s/amplitudes/modes/harmonic_*`。
3. `+tbl/+periodic/spod_toolbox_adapter.m` / `spod_cache.m`：封装 Towne/Schmidt
   `spod.m`，保留 `frequency_hz/eigenvalues/selected_frequency_*/selected_modes/
   n_blocks` 等字段。
4. `+tbl/+periodic/modal_snapshot_matrix.m`：统一 ROI、空间降采样、`max_frames`、
   `frame_stride`、`n_modes` 采样合同，输出等时间步联合 `[u;v]` 快照。
5. `+tbl/+periodic/map_joint_modes.m`：空模态守卫；联合模态映射回 XOY 网格。
6. `+tbl/+periodic/ensure_external_toolboxes.m`：piDMD 自动加 path、SPOD 存在性
   校验，并返回已解析文件路径。
7. `tests/test_section7_modes.m`（新增）：参考 POD 公式、POD/DMD/SPOD 字段合同、
   快照采样旋钮、模式映射、case 脚本静态合同。
8. `README.md`：测试清单加入 `test_section7_modes.m` 并说明覆盖内容。

## 主进程补齐的测试修正

- 参考 POD 测试原先比较完整 `Phi(12×30)` 与截断 `pod.modes(12×12)`，改为比较前
  `n_modes` 列/行。
- 单精度缓存导致 POD 正交性与重建误差略高于 double 阈值，合成缓存用例按单精度
  数值精度放宽（double 参考用例仍保持严格容差）。
- 合成信号改为 4 个独立实振荡（sin8/cos8/sin16/cos16 各自独立空间模态），使
  piDMD 实秩与请求秩一致，稳定恢复 8/16 Hz；首模态能量占比断言相应改为 `>0.2`。

## 测试结果（MATLAB R2022b，全部通过）

    matlab -batch "addpath('tests'); test_section0_rewrite; test_section1_sequence_cache; test_section2_mean_stats_cache; test_section3_phase_triple; test_section4_structure_analysis; test_section5_transport_quadrant; test_section6_spectra; test_section7_modes; test_refactor_shared_helpers; test_premultiplied_psd_reference; test_pressure_gradient_contract; test_vlsm_cluster_connectivity; test_singlecase_helpers; test_periodic_piv_core"

结果：14 个测试文件全部 PASS。未运行真实 3000/6000 帧模态计算；只使用合成模态数据与临时目录。

## 遗留风险

- 真实 3000/6000 帧模态计算未运行；旧 `06/07/08_*_analysis.mat` 缓存因实现指纹变化
  会被拒绝复用，需要人工决定何时重算。
- piDMD 在请求秩大于数据实秩时会把缺失模态填为 eigenvalue=1；真实数据应选择
  不超过有效模态数的 `n_modes`。
- SPOD 依赖本机已安装的 Towne/Schmidt `spod.m`，目标机器需保证该工具箱可用。

## 修改文件清单

- `+tbl/+periodic/pod_cache.m`
- `+tbl/+periodic/dmd_cache.m`
- `+tbl/+periodic/spod_toolbox_adapter.m`
- `+tbl/+periodic/modal_snapshot_matrix.m`
- `+tbl/+periodic/map_joint_modes.m`
- `+tbl/+periodic/ensure_external_toolboxes.m`
- `+tbl/+pod/snapshot_decomposition.m`
- `cases/single/baseline_debug3000/baseline_periodic_piv_case.m`
- `cases/single/f40a3/f40a3_periodic_piv_case.m`
- `tests/test_section7_modes.m`（新增）
- `README.md`
