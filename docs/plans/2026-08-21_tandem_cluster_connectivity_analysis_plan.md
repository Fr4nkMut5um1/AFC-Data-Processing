# 串列基准—受控工况聚类连通分析改造方案

| 文档属性 | 内容 |
| --- | --- |
| 状态 | Draft — 待与其他方案融合 |
| 日期 | 2026-08-21 |
| 适用工况 | `tandem_baseline_r1`、`tandem_f40a3_phi0_r1` |
| 已锁定决策 | 双条件平均；baseline-total 与 controlled-total 共用 total 阈值；采用 log-law Cf 作为减阻主口径 |
| 待定决策 | 二维表观谱系的位移补偿模型 |

## 总体方案

只覆盖：

- `tandem_baseline_r1`：分析 `total`
- `tandem_f40a3_phi0_r1`：分析 `total`、`random`

保留现有 `09_structure_analysis.mat` 及其字段，采用增量扩展，避免破坏现有绘图和 P18 数据接口。流程拆为：

1. Section 4A：逾渗校准
2. 人工审查并锁定 `α/H`
3. Section 4B：全帧连通域、Q2/Q4 对象和条件平均
4. 双工况比较
5. Section 4C：追踪算法基准报告；正式追踪暂不实施，等待用户选择位移模型

## 脚本与接口修改

### 两个 case 脚本

修改 `cases/per_case/tandem_baseline_r1/tandem_baseline_r1_case.m` 和 `cases/per_case/tandem_f40a3_phi0_r1/tandem_f40a3_phi0_r1_case.m`：

- 保留 Section 0 路径自举及现有 Section 2–9 依赖。
- 将现有 Section 4 拆为 4A、4B、4C，不改变后续 Section 5–9 编号。
- baseline 禁止 `random`、相位分箱和伪相位结果。
- controlled 相位结果明确标为“帧时钟相对相位”；`phi0_user_deg=[]` 时不得表述为机械绝对相位。

新增配置合同：

```matlab
cfg.structures.percolation
cfg.structures.locked_thresholds.total
cfg.structures.locked_thresholds.random
cfg.structures.quadrant_objects
cfg.structures.conditional
cfg.structures.tracking_benchmark
```

其中正式分析使用显式锁定的：

```matlab
locked_thresholds.total.alpha
locked_thresholds.total.H
locked_thresholds.random.alpha
locked_thresholds.random.H
```

baseline 的 `random` 字段必须为空。

### Section 4A：逾渗校准

新增 `09a_structure_threshold_calibration.mat`，不修改正式结构结果。

均衡校准默认值：

- 每个 branch 抽取 480 帧。
- baseline 按两个 repeat 均匀分层。
- controlled 按 repeat 和 24 个相位 bin 分层。
- `α` 扫描：`0.25:0.05:0.65`。
- `H` 扫描：`0:0.25:3.0`。
- bootstrap：500 次，只重采样逐帧指标，不重复执行连通识别。
- `seed_alpha` 固定为现行 `0.70`；连通度、最小像素、可信域和预处理均保持正式设置。

每个阈值保存：

- 连通域数量及单位有效面积数量
- 最大簇面积/总占据面积
- 总占据面积率
- 正负簇或 Q2/Q4 分项结果
- 各 repeat、相位层及 bootstrap 95% 区间

稳定区选择规则：

- 先用最大簇占比的最大离散下降识别逾渗转变。
- 在转变后寻找不少于三个连续网格点的稳定区。
- 稳定区内相邻 bootstrap 区间应重叠，且对象数量密度的相邻相对变化不超过 10%。
- 推荐值取稳定区内部、综合归一化斜率最小的实际扫描节点，不插值。
- 如果稳定区触及扫描边界或不存在，4A 只报告失败原因并要求扩展扫描，不产生正式推荐值。

baseline-total 与 controlled-total 合并寻找共同稳定区并锁定完全相同的 `α/H`；controlled-random 单独锁定。4A 只输出推荐值和可复制配置文本，不自动修改 case 文件。

### Section 4B：全帧正式分析

扩展 `+tbl/+periodic/` 内的结构流水线，但保留现有结果字段。

正负 `u′`/`u″` 簇：

- 沿用现有符号分离、滞回阈值、8 邻域、可信域裁剪及 LSM/VLSM 标记。
- total 使用时间均值脉动；controlled-random 使用三重分解的随机脉动。
- 每个对象保存 case、branch、repeat、帧号、相对相位、符号、面积、质心、包围盒、`Lx/δ99`、`Ly/δ99`、峰值和平均幅值。
- 不保存 `640×89×12000` 标签立方体；采用逐帧处理，内存不随总帧数线性增长。

Q2/Q4 强事件域：

- 使用现有标准口径：`|u′v′| > H·u_rms·v_rms`，random 分支对应 `u″、v″` 和相位局部 RMS。
- Q2：`u<0,v>0`；Q4：`u>0,v<0`。
- Q2、Q4 分开执行 8 邻域连通识别。
- 默认 `min_pixels=3`，应用相同可信域和边界剔除；不执行孔洞填充或闭运算，避免人为合并动量交换事件。
- 保存面积、质心、尺度、峰值/平均 `-uv`、积分贡献及事件覆盖率。

对象关联：

- Q2 只关联负 `u′` 簇，Q4 只关联正 `u′` 簇。
- 保存所有非零交叠边及相对双方的覆盖比例。
- 主关联取 Q 事件覆盖比例最大的簇；无重叠时标记为 `unattached`，不强行配对。

### 两套条件平均

以局部 `δ99` 归一化坐标并流式累计：

1. Q2/Q4 事件中心：中心采用 `-uv` 加权质心。
2. 正负 `u′` 簇中心：采用几何质心。

默认窗口：

- `Δx/δ99 = [-4,4]`
- `Δy/δ99 = [-1.5,1.5]`

输出：

- `u/u_rms`、`v/v_rms`
- `-uv/(u_rms·v_rms)`
- Q2/Q4 出现概率
- LSM/VLSM 占据概率
- 原始和无量纲均值
- `sum`、逐点 `valid_count`、`event_count` 和覆盖率

按 case、branch、Q2/Q4 或正负号、LSM/VLSM 类型分组；controlled 另给 24 相位分组。少于 30 个触发样本的条件场保留数值但标记 `insufficient_samples`，不进入正式比较图。

## 双工况减阻比较

新增串列双工况汇总入口，读取两个 case 的已缓存结果，不重复处理原始 PIV。

主指标按已锁定选择使用：

```text
DR_loglaw = 100 ×
(Cf_loglaw,baseline − Cf_loglaw,controlled) /
Cf_loglaw,baseline
```

系统割线和局部 `Cf(x)` 仅作为审计附表，不主导结论。

比较输出包括：

- 正负簇数量、面积率、尺度和 LSM/VLSM 比例
- Q2/Q4 对象数量、占据率及 `-uv` 积分贡献
- Q2/Q4—LSM/VLSM 挂接比例
- 两套条件平均及 controlled−baseline 差值场
- controlled 的 total−random 差异及相位调制
- MAT、CSV、图件和一份 Markdown 机器摘要

任何结构差异只能表述为二维 PIV 测量平面中的交截变化；不能推断完整三维结构或真实三维生命周期。

## Section 4C：追踪模型决策报告

正式谱系追踪暂不进入主结果。本轮只实现可重复的模型比较器：

- 从 baseline-total、controlled-total、controlled-random 各抽 6 段连续 48 帧片段。
- 跨 repeat 边界禁止连接。
- 只追踪正负 `u′`/`u″` 簇；Q2/Q4 通过对象挂接关系跟随谱系节点，不独立追踪。
- 比较三种方法：
  - 背景均值平流
  - 背景平流加局部最大-IoU修正
  - 对象邻域互相关位移

报告匹配率、中位 IoU、断轨率、歧义边比例、分裂/合并稳定性、位移物理合理性、运行时间和逐帧叠加画廊。由于没有真实轨迹标签，这些指标只用于内部一致性评估。

报告完成后停止；不由实现者自行选择模型。待用户审查后，再单独确定正式“二维表观谱系”的位移补偿、门控阈值及分裂/合并规则。

## 缓存和兼容性

- 保留 `09_structure_analysis.mat` 的全部旧字段，新增 `quadrant_objects`、`attachments`、`conditional` 和 `threshold_provenance`。
- 新增 `09a_structure_threshold_calibration.mat` 和 `09c_tracking_benchmark.mat`。
- 缓存指纹包含扫描配置、锁定阈值、分支、预处理和可信域设置。
- 4B 在阈值未锁定、total 两 case 锁定值不一致、锁定值超出稳定区或校准指纹不匹配时拒绝运行。
- controlled 缺失时序缓存时允许按现有 Section 1 合同重建；不尝试从聚合 MAT 反推逐帧标签。
- 修正旧测试中“FFT 低通会改变结构结果”的过时假设，正式合同继续保持 Section 4 不执行流向 FFT 滤波。

## 测试与验收

在 `tests/` 增加：

- 合成逾渗转变、稳定区、无稳定区和扫描边界测试。
- Q2/Q4 符号、局部 hole scale、total/random 分支测试。
- baseline 禁止 random/phase 的合同测试。
- 两个 total 锁定值一致性及缓存失效测试。
- 对象挂接、双触发条件平均、NaN/边界有效样本计数测试。
- 12000 帧流式处理不保存全标签立方体的合同测试。
- 旧 `catalog`、`instantaneous`、`phase_distribution`、P18 和绘图消费者兼容性测试。
- 两个 case 的 Section 0 路径自举及 Section 4A/4B 独立 Run Section 测试。

验收标准：

- 4A 可独立得到可审查稳定区和推荐配置。
- 锁定后 4B 覆盖全部 12000 帧。
- baseline-total 与 controlled-total 使用完全相同的 `α/H`。
- 条件平均的 `event_count` 与对象目录逐组一致。
- 所有结果携带 case、branch、阈值、归一化、相位状态和二维限制说明。
- 4C 只交付追踪比较报告，不提前生成正式谱系结论。
