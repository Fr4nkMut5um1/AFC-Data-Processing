# Section 3 独立重写对比（人工审阅稿）

## 状态

已完成 `section_03_handoff.md` 规定的核心流程：阅读源码与 handoff、联网检索、独立评审/重写、
合成周期数据验证、回写主工作区、针对性回归测试。子代理在测试修复阶段提前终止后，由主进程补齐
测试修正、回归验证与本报告。

## 联网检索结论（可复核来源）

- 相位平均/锁相平均与三重分解的经典口径采用 Hussain & Reynolds (1970)；
  分箱平均方案参考 Baj, Bruce & Buxton (2015) 的 bin-averaging 实现思路。
- MATLAB `fft` 沿第一维对 `n_bins×J×I` 做离散傅里叶变换，谐波幅值与相位按
  `A=2*|C(ih+1)|`、`phase=angle(C(ih+1))` 提取，属于标准做法。
- `assign_phase` 仅使用帧序号、`fs`、`f0_hz` 计算相对相位，不引入数据驱动相位恢复，
  与 handoff 的“机械相位未标定”合同一致。

## 旧实现评价

旧实现已具备相位箱分配、相位统计、谐波分析与 `read_cache_chunk`，但函数头缺少完整合同说明；
部分输入校验与“相位箱被拒绝后随机分支有效掩膜同步”的行为依赖测试隐式约定，边界行为不够显式。

## 新实现改进（已回写）

1. `+tbl/+periodic/assign_phase.m`：
   - 函数头写明相对相位公式、机械相位未标定语义、最近箱分配与帧时钟模式；
   - 增加 `frame_ids`、`fs/f0_hz`、`n_bins`、`phi0_user_deg` 的显式错误分支。
2. `+tbl/+periodic/phase_stats_cache.m`：
   - 函数头写明 `mat/03_phase_triple_statistics.mat` 字段合同、三重分解口径
     `u=<u>+utilde+u''`、逐块读取约束、每箱最小样本数策略；
   - 分两遍逐块累计：先相位箱均值，再随机二阶矩与三重重构残差；
   - 全局随机统计只使用“该点相位箱被接受”的帧样本；
   - 增加 `cfg.phase` 缺失字段、`f0_hz`、`n_bins`、`minimum_samples_per_bin`
     与缓存缺变量的干净错误。
3. `+tbl/+periodic/harmonic_analysis.m`：
   - 补全 DFT 谐波幅值/相对相位/机械相位合同与 `selected_y_plus` 最近行策略；
   - 未提供 `phi0_user_deg` 时机械相位保持 `NaN`。
4. `+tbl/+periodic/read_cache_chunk.m`：
   - 补全 `raw/total/random` 分支合同；分支变换后 `sampleValid` 与 `U/V`
     严格同步（随机分支中相位箱被拒绝或均值 NaN 的样本视为无效）。
5. 两个 case 脚本 Section 3：补充相位合同注释；baseline 保持 `skip` 与
   `results.phase=[]`，f40a3 保持 40 Hz / 24 箱 / 20 最小样本。
6. `tests/test_section3_phase_triple.m`（新增）：合成周期缓存覆盖帧时钟相位、
   相位箱分配、机械未标定、分块不变性、相位均值与三重恒等式、最小样本策略、
   输入错误、谐波幅值与相位、`read_cache_chunk` 分支一致性、case 脚本静态合同。
7. `README.md`：测试清单加入 `test_section3_phase_triple.m` 并说明覆盖内容。

## 主进程补齐的测试修正

- R2022b 对 `[n×J×I]` 与 `[J×I]` 的隐式展开不接受，测试中的谐波参考量改为显式
  `reshape(...,1,J,I)`。
- 二维/三维矩阵上的 `max(abs(...))` 会返回数组而非标量，改为
  `max(...,[],'all')`。
- `assign_phase` 非法机械偏置用例与当前实现校验一致后通过。

## 测试结果（MATLAB R2022b，全部通过）

    matlab -batch "addpath('tests'); test_section0_rewrite; test_section1_sequence_cache; test_section2_mean_stats_cache; test_section3_phase_triple; test_refactor_shared_helpers; test_pressure_gradient_contract; test_singlecase_helpers; test_periodic_piv_core"

结果：8 个测试文件全部 PASS。未运行真实 3000/6000 帧重算；只使用合成周期数据与临时目录。

## 遗留风险

- 真实 40 Hz / 24 箱相位统计未运行，只有合成周期验证；真实数据下每箱样本数与
  相位箱覆盖率需人工检查。
- `phase_stats_cache` 的全局随机统计口径限定为“相位箱被接受”的帧样本；若后续要改为
  全部有效帧，属于口径变更，需要人工确认。
- `harmonic_analysis` 按最近实测行选择 y+，不做法向插值；`selected_y_plus_in_range`
  只标记范围，不改变选择结果。

## 修改文件清单

- `+tbl/+periodic/assign_phase.m`
- `+tbl/+periodic/phase_stats_cache.m`
- `+tbl/+periodic/harmonic_analysis.m`
- `+tbl/+periodic/read_cache_chunk.m`
- `cases/single/baseline_debug3000/baseline_periodic_piv_case.m`
- `cases/single/f40a3/f40a3_periodic_piv_case.m`
- `tests/test_section3_phase_triple.m`（新增）
- `README.md`
