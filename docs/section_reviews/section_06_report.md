# Section 6 独立重写对比（人工审阅稿）

## 状态

已完成 `section_06_handoff.md` 规定的核心流程：阅读源码与 handoff、联网检索、独立评审/重写、
合成周期信号验证、回写主工作区、针对性回归测试。子代理在最终报告阶段提前终止后，由主进程补齐
回归验证、README 核对与本报告。

## 联网检索结论（可复核来源）

- MathWorks `pwelch` 官方文档确认 Welch 谱估计参数（window/noverlap/nfft/fs）语义；
- `fillmissing(...,'linear',...,'EndValues','nearest')` 是坏点修复标准做法；
- 预乘谱 `f*Phi_f = lambda*Phi_lambda` 由换元关系保证，Taylor 假设只用于
  `lambda_x_plus`，且对流速度必须显式设置 `Uc`；
- 空间谱直接对每帧 `u(x)` 做 FFT，采用单边谱约定，明确标记
  `'no Taylor hypothesis'` 与 `'One-sided'`。

## 旧实现评价

旧实现已具备 `temporal_spectra_cache`、`spatial_spectra_cache` 与共享
`welch_series`，但函数头合同不够完整，缺少数值口径的显式说明；本轮重点补充
“各 x 先 PSD 再平均 PSD”、Welch 频带切片、Taylor 适用范围与空间直接 FFT
的合同，并新增专门合成测试。

## 新实现改进（已回写）

1. `+tbl/+spectra/welch_series.m`：共享修复/PSD helper；低有效率或有效样本数
   不足 `nfft` 的整条序列排除，保留序列先 `fillmissing(...,'linear',...,
   'EndValues','nearest')` 再 `detrend('linear')` 后 `pwelch`。
2. `+tbl/+periodic/temporal_spectra_cache.m`：严格逐 x PSD 后按
   `cfg.temporal.x_interval_mm` 平均；频带只对 Welch 频率箱切片，不引入时域
   bandpass；Taylor 换算只用于 `lambda_x_plus`，`Uc` 为显式设置。
3. `+tbl/+periodic/spatial_spectra_cache.m`：每个流向窗口逐帧 `u(x)` 直接
   FFT，必要时插值到均匀 x 网格，单边谱约定（偶数长度 Nyquist 箱不加倍），
   PSD 按 `dx/sum(w^2)` 归一；不依赖 Taylor 假设。
4. 两个 case 脚本 Section 6：补充时域/空间谱合同注释；编排不变。
5. `tests/test_section6_spectra.m`（新增）：合成周期信号覆盖 8 Hz 峰、
   `f*Phi` 与 `lambda*Phi` 等价、固定点曲线、空间谱峰值、`order_of_operations`/
   `taylor_scope`/`spectrum_convention` 字符串合同、坏点修复与低有效率排除。
6. `README.md`：测试清单加入 `test_section6_spectra.m` 并说明覆盖内容。

## 测试结果（MATLAB R2022b，全部通过）

    matlab -batch "addpath('tests'); test_section0_rewrite; test_section1_sequence_cache; test_section2_mean_stats_cache; test_section3_phase_triple; test_section4_structure_analysis; test_section5_transport_quadrant; test_section6_spectra; test_refactor_shared_helpers; test_premultiplied_psd_reference; test_pressure_gradient_contract; test_vlsm_cluster_connectivity; test_singlecase_helpers; test_periodic_piv_core"

结果：13 个测试文件全部 PASS。未运行真实 3000/6000 帧重算；只使用合成周期信号与临时目录。

## 遗留风险

- 真实 3000/6000 帧频谱未运行；`pwelch` 频率分辨率、Uc 剖面与固定点曲线需在
  真实数据上人工核对。
- 空间谱依赖流向窗口内至少 8 个 x 列；窗口过窄会直接报错。
- `welch_series` 的 `fillmissing` 只对保留序列执行；整条排除序列保持 NaN，
  不参与平均。

## 修改文件清单

- `+tbl/+spectra/welch_series.m`
- `+tbl/+periodic/temporal_spectra_cache.m`
- `+tbl/+periodic/spatial_spectra_cache.m`
- `cases/single/baseline_debug3000/baseline_periodic_piv_case.m`
- `cases/single/f40a3/f40a3_periodic_piv_case.m`
- `tests/test_section6_spectra.m`（新增）
- `README.md`
