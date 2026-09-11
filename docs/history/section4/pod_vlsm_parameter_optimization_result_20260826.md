# POD 低阶重构场 VLSM 聚类联通法参数优化结果

日期：2026-08-26

## 结论

本轮优化在 POD E=50% 重构场上收敛到以下 POD 专用识别参数：

```matlab
alpha       = 0.40;   % signed hysteresis growth threshold
seed_alpha  = 0.60;   % seed threshold
connectivity = 8;     % 2-D eight-neighbour connectivity
min_pixels  = 3;
min_lsm_delta  = 1;
min_vlsm_delta = 3;
max_internal_hole_pixels = 64;
envelope_closing_radius_cells = 2;
merge_gap_cells = 0;
```

POD 分支采用 `valid_mask` 作为识别域，`trusted_domain.streamwise_edge_columns=0`、`wall_normal_top_rows=0`，并将 `reject_trusted_boundary_touching=false` 限定在本地 POD 诊断副本中。因此碰到 FOV 边缘的结构可以进入识别；Gaussian、Raw 和既有 case 配置没有被修改。

## 迭代证据

| 轮次 | 抽样帧数 | 参数变化 | 聚类 VLSM | 聚类含 VLSM 帧 | Codex 视觉估计 | 操作性一致度 |
|---:|---:|---|---:|---:|---:|---:|
| 1 | 24 | 初始 `0.40/0.70/8` | 21 个 | 17/24 | 23 个；21/24 帧 | 0.79 |
| 2 | 24 | `seed_alpha: 0.70 → 0.60` | 22 个 | 18/24 | 22 个；19/24 帧 | 0.88 |

停止原因：第二轮视觉/聚类操作性一致度 0.88 ≥ 0.80。流程未达到 16 轮上限。

两轮使用固定随机种子 `20260826`，每轮种子为 `20260826 + round - 1`；帧号、参数更新和视觉复核均写入 JSON/MAT 产物。

## 产物

- [优化脚本](../tools/r2_diagnostics/run_pod_vlsm_parameter_optimization.m)
- [完整优化结果 MAT](../tmp/pod_vlsm_parameter_optimization_rerun/pod_vlsm_parameter_optimization.mat)
- [第 1 轮参数更新](../tmp/pod_vlsm_parameter_optimization_rerun/round_01/round_01_parameter_update.json)
- [第 2 轮参数更新](../tmp/pod_vlsm_parameter_optimization_rerun/round_02/round_02_parameter_update.json)
- [第 1 轮视觉复核](../tmp/pod_vlsm_parameter_optimization_rerun/round_01_visual_review.json)
- [第 2 轮视觉复核](../tmp/pod_vlsm_parameter_optimization_rerun/round_02_visual_review.json)
- [第 1 轮 24 帧图像目录](../tmp/pod_vlsm_parameter_optimization_rerun/round_01/frames/)
- [第 2 轮 24 帧图像目录](../tmp/pod_vlsm_parameter_optimization_rerun/round_02/frames/)

所有瞬时场图均使用 `contourf`，并叠加 LSM 蓝色虚线框、VLSM 红色实线框。

## 联网调研依据

- Raiola、Discetti、Ianiro 的 POD/PIV 工作支持使用 POD 低阶重构降低随机误差；相关入口：[DOI 10.1007/s00348-015-1940-8](https://doi.org/10.1007/s00348-015-1940-8)。
- Brindise 与 Vlachos 说明 POD 截断阶数会直接影响去噪和重构结果，不应把任意累计能量阈值当作普适真值；[DOI 10.1007/s00348-017-2320-3](https://doi.org/10.1007/s00348-017-2320-3)。
- Semantic Scholar 检索到的 EHD/PIV 研究指出，低阶 POD 模态偏向大尺度结构，高阶模态承载更细尺度波动：[Reconstruction of reduced-order EHD flow fields using POD](https://www.semanticscholar.org/paper/a5e8688468c5c64323407665d364e984942544fc)。
- Google Scholar 检索到的高分辨率 PIV 研究将 LSM/VLSM 作为壁湍流中的二维/三维相干运动尺度进行分析，例如 [Investigation of large scale motions ...](https://arxiv.org/pdf/2104.00882)。

这些文献只用于支持“POD 截断影响尺度表现”和“VLSM 识别需采用尺度/连通判据”的方法选择；Codex 视觉判断不是物理 ground truth，当前结果仍限定为 2C-2D XOY 平面连通结构。

## 验证状态与限制

- `tests/test_r2_library_contract.m`：PASS。
- `python tests/matlab_check.py tools/r2_diagnostics`：19 个 MATLAB 文件通过静态结构检查。
- 这是 2 轮、每轮 24 帧的参数诊断，不是 12000 帧全量科学验收。
- `E=50%` 是本次优化固定的 POD 表示条件；若改变 POD rank/energy target，应重新做参数复核。
- 视觉复核是 Codex 对已生成图像的操作性判断，不能替代人工专家标注或三维 VLSM 真值。
- `merge_gap_cells=0` 在本轮保留，避免用合并规则人为制造长条结构；如后续人工确认“结构被明显断裂”而非“阈值过低”，再单独扫 `merge_gap_cells`。
