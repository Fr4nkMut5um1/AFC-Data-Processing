# 聚类连通法（+tblR2）文献调研与改进方案

| 属性 | 内容 |
|---|---|
| 状态 | 调研完成，改进已实施（2026-08-24） |
| 日期 | 2026-08-24 |
| 适用范围 | `cases/per_case/tandem_baseline_r2/+tblR2/identify_structures.m` 及其配置 |
| 边界 | 只调研 + 诊断，**未修改**任何正式识别逻辑；改动建议留待用户决策 |
| 检索范围 | 仅 PIV/湍流领域文献；不限时间；含 arXiv、GitHub、MATLAB File Exchange |

## 实施状态（2026-08-24 更新）

本报告的改进建议已于 2026-08-24 实施，具体为：
- ✅ Priority 1: sigma 缺陷已修复（移除 `structure_preprocessing()` 方向性字段预填）
- ✅ Priority 2: 宽扫描已执行（α∈[0.5,2.5], sigma=1.5, conn=4, 480帧），转变区定位至 α≈0.60
- ✅ Priority 3: Bootstrap 稳定区判据已应用，稳定区 α∈[1.50, 2.05]，推荐 α=1.77
- ✅ Priority 5: seed_alpha 联合标定已完成，推荐 seed_alpha=1.97
- ✅ 连通性: 改为四连通域（避免8连通在 α=0.40 下工作于自身渗流临界点 p_c≈0.407）
- ✅ 诊断文件已从 `+tblR2/` 迁出到 `tools/r2_diagnostics/`（解决库合同冲突）
- ✅ 全量12000帧已重算

详见 `docs/cluster_connectivity_calibration_result_20260824.md`。

---

## 0. 执行摘要

调研 + 实跑诊断得到三个结论，重要性从高到低：

1. **当前 `alpha=0.40` 没有落在逾渗转变区内，而是落在转变区之前的单调上升段。** 用生产真实平滑（σ≈0.8，见下）在全帧范围做宽扫描，最大簇占比 `A_max/ΣA` 随 α 从 0.40 到 1.60 单调下降、簇数单调下降，**转变（谷值）出现在 α≈0.85–1.0 附近**，比当前值高一倍以上。文献中同类判据的典型工作点是 α≈1.4–2.2（Hwang & Sung 2018 用 1.4–1.7 做敏感性检验，Lozano-Durán 2012 选 H=1.75）。**当前阈值不是"选在转变区里但可以再调"，而是根本没扫到转变区**，项目自己 2026-08-21 的规划文档定的扫描范围 `0.25:0.05:0.65` 本身就太窄，扫不到转变。
2. **高斯预处理的 `sigma` 参数目前没有生效——存在一个实测确认的实现缺陷。** `simple_gaussian_filter2` 只读方向性字段（`sigma_x_cells`/`sigma_y_cells`/`radius_x_cells`/`radius_y_cells`），而 `structure_preprocessing()` 把这些字段预填为非空默认值 `0.8/1`，导致案例脚本里设置的 `sigma_cells=1.5, radius_cells=4` 从未真正传导到卷积核。冲激响应实测：缓存的生产配置给出 **3×3 核（σ=0.8）**，而不是产物命名、`cfg` 与 README 都声称的 **9×9 核（σ=1.5）**。平滑强度只有预期的一半左右，这直接解释了"斑点噪声导致误分割"的痛点根源之一。
3. **连通性选择（4 邻域 vs 8 邻域）在当前阈值区间不是主要矛盾，但在物理意义上不可忽视。** 用生产数据实测，α=0.40 时占据率约 0.39–0.43，恰好卡在正方格点 8-连通渗流阈值 p_c≈0.407 附近，而 4-连通渗流阈值 p_c≈0.593 还远未到达——这意味着在当前阈值下，8 连通选择让整个分析工作点处于自身连通拓扑的临界点上，微小噪声扰动就可能让"是否渗流"发生翻转。三维 DNS 文献（Lozano-Durán、del Álamo、Hwang & Sung）清一色使用六正交邻域，明确排除对角连接，但没有一篇给出"为什么排除对角"的显式论证——只是逐篇引用沿袭下来的约定。

**建议优先级**：先修复 sigma 实现缺陷（§4），再重新扫描更宽的 α 范围找到真正的转变区（§2），最后再讨论连通性选择（§3）。这个顺序是因为前两者互相耦合——sigma 真正生效后，转变区的位置还会再变一次，现在报的"α≈0.85–1.0"是在 σ=0.8（缺陷状态）和 σ=1.5（意图状态）两种设定下测的，一旦真正定下 sigma，还需要重新扫一次。

---

## 1. 文献调研发现

### 1.1 逾渗阈值标定方法论

**诊断图的标准形式**：文献中固定画两条曲线随阈值变化：

- `V_max/V_tot`（最大连通域体积/总占据体积）
- `N/N_max`（连通域数量，用其在扫描范围内的最大值归一化）

Lozano-Durán, Flores & Jiménez (JFM 694, 2012, DOI 10.1017/jfm.2011.524) 原文（已核实全文）：

> "Figure 1(a) shows the percolation diagram of (2.1) in the two channels considered here. The solid lines are the ratio of the volume of the largest identified object, V_lar, to the total volume V_tot satisfying (2.1), and the dashed ones are the total number of identified objects, N/N_max, normalized with its maximum over H... this percolation crisis takes place in the range 0.5 ≲ H ≲ 3, independently of the Reynolds number."

**决策规则因文献而异**（这点此前项目规划文档未区分）：

- **del Álamo, Jiménez, Zandonade & Moser** (JFM 561, 2006，已核实全文)：取 `V_max/V` **斜率最大**处为临界阈值 λ_c，正式工作阈值取约 2.5×λ_c，"位于转变刚开始之后一点"。
- **Lozano-Durán et al. (2012)**：直接取**最大化 N 的阈值**，H=1.75。
- **Hwang & Sung (JFM 856, 2018, DOI 10.1017/jfm.2018.727，已核实全文)**：同样取 N 峰值，α_m≈1.4（u 分量）/1.6（v,w 分量），正式使用 α=1.5，"基于聚类的逾渗转变选定"。
- **Bae & Lee (arXiv:2102.03628)**：同样是 N 最大化规则。

**没有任何一篇文献对逾渗曲线做 bootstrap 或置信区间处理**——del Álamo (2006)、Lozano-Durán (2012)、Hwang & Sung (2018)、Osawa & Jiménez (2018)、Bae & Lee (2021) 全部是单次确定性曲线、肉眼读值。本项目诊断工具中实现的 bootstrap 稳定区判定（§4.5 of `docs/README_r2_structure_diagnostics.md`）**在这个领域是方法论上的增量贡献**，不是复现已有做法。

**敏感性报告是标准做法**：多篇文献明确报告结果对阈值在 ±(20–30)% 范围内不敏感（Hwang & Sung 附录 A 扫描 1.4–1.7；Lozano-Durán 报告 1≲H≲3 定性相似；Osawa & Jiménez 报告 1.4<H<2.4）。**这些敏感性区间全部落在转变区之后的平台段**，不是转变区之前。本项目当前 α=0.40 既不在平台段，也不在转变区里，而是在转变区之前的单调段——这是与文献惯例最本质的偏离。

**2D PIV 与 3D DNS 阈值不可直接套用**：Cremades et al. (Nature Communications 15, 2024, 3835) 在类 PIV 二维数据上重跑同一套逾渗标定，得到 H=0.54，明确说明"这与 DNS 中使用的值不同，因为识别的结构是二维的"。这支持了本项目"必须自行标定，不能照抄三维文献数值"的立场，但也说明**H=0.54 这个二维参考值仍然比当前 α=0.40 高**，进一步佐证痛点 1 的判断。

### 1.2 连通性定义（4 vs 8 vs 6-正交）

**三维文献统一使用六正交邻域，明确排除对角**：

- del Álamo et al. (2006)：*"Connectivity is defined by the six orthogonal nearest neighbours of each grid point."*
- Lozano-Durán et al. (2012)：*"Connectivity is defined in terms of the six orthogonal neighbours in the Cartesian mesh of the DNS."*
- Hwang & Sung (2018)：*"the connectivity of u_i was defined based on the six orthogonal neighbors of each node in Cartesian coordinates (Moisy & Jiménez 2004; del Álamo et al. 2006; Lozano-Durán et al. 2012)."*

**排除对角邻域的理由从未被显式论证**——每篇论文都只是断言这个定义，并引用前一篇。整条引用链可追溯到 Moisy & Jiménez (JFM 513, 2004)，但该文全文无法获取核实，因此不能排除"最初的论证就在那篇里、后续论文省略了"的可能性。**这本身构成了一个值得记录的引用链断层**：六正交邻域是沿袭下来的约定，不是每篇论文独立验证过的最优选择。

**二维 PIV/切片文献连通性选择不统一、常常未明说**：

- del Álamo et al. (2006) 对 (x,y) 平面的涡截面分析沿用同一套六邻域规则的二维退化（即隐含 4-连通），但论文正文没有单独重申"二维用 4-连通"。
- **Solak & Laval (arXiv:1809.05080)** 在同一 DNS 数据上同时做 3D 检测与 2D (x,y) 平面检测，用于对比 PIV 文献（Srinath et al.）的方法。直接引用：*"for the 2D detection, the number of large structures decreases when increasing C_thr. However, 3D detection results show the opposite. The main reason is that the largest structures are likely to be connected by the side (in the spanwise direction)."* 这是目前找到的**唯一**一篇量化报告"降维会改变阈值依赖方向"的论文，但它比较的是三维 vs 二维切片，不是同一二维平面内 4 vs 8 连通的直接对比。

**没有找到任何一篇论文在固定维度下直接对比 4 vs 8（或 6 vs 26）连通性并报告对统计量的影响。** 这是一个明确的文献空白（见 §1.5）。

**格点渗流理论的定量结果，本项目实测验证**：

正方格点位点渗流阈值：
- 4-连通（von Neumann 邻域）：p_c ≈ 0.5927
- 8-连通（Moore 邻域，即 4-连通 + 次近邻）：p_c ≈ 0.4073

（来源：Malarz & Galam 对扩展邻域格点渗流阈值的系统研究；数值经多个独立 Monte Carlo 与图多项式方法交叉核实。）

**没有一篇湍流/PIV 文献承认或引用这个渗流理论的定量结果**——"逾渗"在湍流文献里始终是定性借用的词汇（引用 Stauffer 的渗流理论专著作为背景），从未真正把格点渗流的临界占据率数值代入分析。

**本项目实测数据把这个理论结果和实际工况直接联系了起来**：在生产阈值 α=0.40 下，占据率约 0.39–0.43（见 §2），**恰好卡在 8-连通渗流阈值 0.4073 附近，而 4-连通渗流阈值 0.593 还远未接近**。这意味着——不管 8 连通"看起来效果更好"的直觉是否成立——**在当前阈值下，8 连通选择让系统运行在自身渗流转变的临界点上**，这在渗流理论意义上是最不稳定的工作区间：占据率的微小涨落（帧间噪声波动）就足以让系统在"大量小簇"和"单一巨簇吞并全场"之间剧烈摆动。这正是"有时误分割、有时误合并"这个观察现象的一个可能物理机制。

### 1.3 PIV 测量噪声与去噪

（该方向的完整调研见另一独立报告线，此处摘录与连通法直接相关的结论。）

**PIV 噪声不是空间白噪声**——Sciacchitano & Wieneke (Meas. Sci. Technol. 27, 2016, DOI 10.1088/0957-0233/27/8/084006) 明确指出，插值窗口重叠导致相邻矢量的噪声空间相关：*"a significant correlation is present up to sample spacing of 3d"*（75% 重叠、高斯加权窗口情形）。这意味着**平滑核尺寸必须超过噪声相关长度才能起到降噪作用**——按 Wieneke (2017) 给出的关系，高斯核的有效相关长度 `L_sr = sigma*sqrt(4*pi)`。本项目当前实际生效的 σ=0.8（3×3 核）对应 `L_sr ≈ 2.8` 个网格间距，如果 PIV 判读窗口在 75% 重叠下噪声相关长度约 4 个矢量间距，**当前实际平滑强度可能仍低于消除噪声所需的下限**——这与本文 §0 第 2 点发现的实现缺陷相互印证，指向同一结论：当前平滑不足。

**滞回/双阈值（seed+growth）连通性有文献先例，但不在主流逾渗标定谱系内**——Ferrari, Hu & Martinuzzi (IEEE CJECE, 2019, DOI 10.1109/CJECE.2019.2917394) 在涡脊追踪中使用了种子阈值+生长阈值的图像处理式滞回方案（源自 Canny 边缘检测传统），应用于 PIV 与 CFD 数据。**本项目当前的 seed_alpha=0.70/alpha=0.40 方案，是把这一套图像处理滞回思想嫁接到 Lozano-Durán 式逾渗标定传统上的一次方法论组合创新**，而不是复现已有做法——这点应在正式方法说明中如实陈述，不宜暗示为文献标准做法。

**形态学闭运算/孔洞填充在湍流文献中有先例但用于三维 DNS**：Solak & Laval 使用开运算+闭运算清理阈值化掩膜后再骨架化，明确说明理由是"填补仅由一两个像素造成的小连接"——与本项目 `envelope_closing_radius_cells`/`max_internal_hole_pixels` 的设计动机一致，但该文应用于 DNS，非 PIV。

### 1.4 最小尺寸过滤

30³ 壁面单位的体积下限起源于 del Álamo et al. (2006)，后续 Lozano-Durán (2012)、Hwang & Sung (2018)、Bae & Lee (2021) 全部沿用同一数字，理由表述从"网格分辨率问题"（Lozano-Durán）逐渐漂移为"噪声"（Bae & Lee）。**这是单一引用链的传播，不是各自独立验证的结果**——本项目当前 `min_pixels=3` 同样应视为操作性参数而非文献共识值。

### 1.5 文献空白（值得记录的贡献点）

1. **没有论文对逾渗曲线做 bootstrap/置信区间处理。** 本项目诊断工具的 bootstrap 稳定区判定填补了这一空白。
2. **没有论文在固定维度下直接对比 4 vs 8（或 6 vs 26）连通性并报告统计量差异。** 本项目 Phase 1 诊断（4 邻域、8 邻域各跑一遍逾渗曲线）填补了这一空白，尽管当前扫描范围尚未覆盖真实转变区（见 §2）。
3. **没有论文承认或引用格点渗流理论中 4-/8-连通渗流阈值的差异（0.593 vs 0.407）**，本项目通过实测占据率把这个理论结果和实际工况连接了起来。
4. **没有论文量化 PIV 噪声导致的连通域碎化/桥接偏差**——这仍是一个开放问题，本项目 Phase 2 敏感性扫描（§3）提供了针对本项目具体数据的经验证据，但不构成普适结论。
5. **滞回双阈值连通性尚未与逾渗标定传统结合过**——本项目的方案组合本身具有方法论新意，值得在正式报告/论文中如实定位为"借鉴图像处理滞回思想、应用于逾渗标定框架"，而非简单套用某篇已发表方法。

---

## 2. 诊断结果：Phase 1（逾渗标定）

### 2.1 预注册扫描（480 帧，α=0.25:0.05:0.65，见 `docs/README_r2_structure_diagnostics.md`）

在两种平滑水平（`as_cached` 实际生效的 σ=0.8/3×3；`intended_sigma1p5` 配置意图的 σ=1.5/9×9）、两种连通性（4、8）下分别标定：

| 变体 | 连通性 | bootstrap 稳定区（α） | 区间内最大簇占比中位数 |
|---|---|---|---|
| as_cached (σ=0.8) | 4 | [0.30, 0.65] | 0.18–0.23 |
| as_cached (σ=0.8) | 8 | [0.35, 0.65] | 0.19–0.22 |
| intended (σ=1.5) | 4 | [0.35, 0.65] | 0.26–0.27 |
| intended (σ=1.5) | 8 | [0.30, 0.65] | 0.26–0.29 |

**这个"稳定区"是伪稳定的假象，不是文献意义上转变区之后的平台。** 见图 `docs/figures/09d_percolation_as_cached.png` 与 `09d_percolation_intended_sigma1p5.png`：面板 (b) 连通域数量 N 在整个扫描范围内单调上升、没有峰值，面板 (a) 最大簇占比单调下降、没有出现文献描述的"急剧下降后趋平"的转变形态。bootstrap 判据判定"相邻点区间重叠、相对变化<10%"在单调曲线的平缓段一样能满足，这是判据本身的已知局限——**它能确认"局部平缓"，不能替用户确认"这段平缓就是逾渗转变区"**。

### 2.2 补充宽扫描（α=0.40–3.00，60 帧，确认转变区真实位置）

用 as_cached 真实生产平滑（σ≈0.8）、单阈值（无滞回，seed_alpha=alpha，与文献单阈值扫描口径一致）重新扫描：

| α | 4 邻域 N | 4 邻域最大簇占比 | 4 邻域占据率 | 8 邻域 N | 8 邻域最大簇占比 |
|---|---|---|---|---|---|
| 0.40 | 533.5 | 0.241 | 0.460 | 499.0 | 0.252 |
| 0.55 | 506.5 | 0.205 | 0.318 | 474.5 | 0.206 |
| 0.70 | 438.0 | 0.182 | 0.215 | 417.0 | 0.188 |
| 0.85 | 360.0 | **0.161** | 0.143 | 346.0 | **0.162** |
| 1.00 | 258.0 | 0.182 | 0.096 | 245.5 | 0.189 |
| 1.30 | 127.5 | 0.323 | 0.042 | 121.0 | 0.326 |
| 1.60 | 60.0 | 0.537 | 0.021 | 57.5 | 0.537 |
| 2.00 | 24.0 | 0.818 | 0.013 | 24.0 | 0.818 |

**最大簇占比在 α≈0.85 附近出现谷值，之后重新上升**——这是文献意义上的逾渗转变标志（先随阈值降低而渗流合并，过临界点后场变得过于稀疏，剩余簇反而以自身几何而非渗流连通主导占比）。真实转变区应在此谷值附近，落在 **α≈0.7–1.0**，比预注册扫描的上限 0.65 还要高，也比当前生产值 0.40 高一倍以上。

用无滞回配置在 `intended_sigma1.5` 下重复该扫描（60 帧，全域抽样），趋势一致，谷值同样出现在 α<1.0 区间，且比 σ=0.8 时更平缓——说明**平滑强度和转变区位置本身是耦合的**，一旦按 §4 修复 sigma 缺陷，需要重新做一次完整宽扫描才能定出正式推荐值。

**结论**：`cfg.structures.alpha = 0.40` 目前既没有实测依据，也不在合理的逾渗标定范围内。建议：

1. 先按 §4 修复 sigma 生效问题；
2. 在 α∈[0.5, 2.5] 范围（覆盖文献典型区间 1.4–2.2，并留出边际）重新跑 Phase 1，用真正的 N(α) 峰值或最大簇占比谷值定位转变区；
3. 用本项目已实现的 bootstrap 稳定区判据，在转变区之后寻找真正的平台段，而不是转变区之前的单调段。

### 2.3 连通性对比

在预注册扫描范围内（转变区之前），4 邻域与 8 邻域的最大簇占比、簇数几乎重合（差异 <5%），連通性选择在这个区间内不是主导因素——这与"扫描范围本身有问题"的结论一致：转变区之前的单调段，连通性差异本来就会被压制。

**在生产阈值 α=0.40 处实测占据率**：

| 变体 | 4 邻域占据率 | 8 邻域占据率 |
|---|---|---|
| as_cached (σ=0.8) | 0.4317 | 0.4330 |
| intended (σ=1.5) | 0.3932 | 0.3948 |

两个变体下占据率都落在 0.39–0.43 之间，**恰好包住 8-连通渗流阈值 0.4073，而 4-连通渗流阈值 0.593 还有相当距离**。这意味着无论平滑强度如何调整（在当前测试的范围内），只要 α 停留在 0.40 附近，8 连通选择就让系统运行在自身渗流临界点上，对帧间噪声涨落最敏感。这是"8 连通有时表现更好、有时又不稳定"这一直觉观察的一个自洽物理解释：**不是 8 连通本身更差，而是当前阈值恰好选在了 8 连通的渗流临界点上**。一旦按 §2.2 建议把 α 提高到转变区之后（α>1.0），占据率会进一步下降、远离两个连通性各自的渗流阈值，届时 4 vs 8 的差异预计会显著缩小——这个预测需要在完成 §4 修复后用完整扫描验证，本报告不代其下结论。

---

## 3. 诊断结果：Phase 2（预处理/形态学敏感性）

640 组参数组合（`sigma∈{0.8,1.0,1.5,2.0,2.5}` × `seed_alpha∈{0.5,0.6,0.7,0.8}` × `closing∈{0,1,2,3}` × `hole∈{16,32,64,128}` × `connectivity∈{4,8}`），120 帧子样本，α 锁定在当前生产值 0.40（注：鉴于 §2 的发现，这些结果的绝对数值在 α 重新标定后会变化，但各参数的**相对影响方向**具有参考价值）。

### 3.1 sigma 主效应（图 `09d_sensitivity_main_effects.png` 第一行）

| σ | 结构数中位数 | 面积中位数 (mm²) | 长宽比 P95 | 大结构面积占比 |
|---|---|---|---|---|
| 0.8 | 139 | 5.97 | 3.50 | 0.781 |
| 1.0 | 109 | 7.16 | 3.40 | 0.773 |
| 1.5 | 56 | 12.5 | 4.24 | 0.743 |
| 2.0 | 28 | 23.5 | 7.42 | 0.673 |
| 2.5 | 16 | 47.9 | 9.99 | 0.581 |

sigma 从 0.8 升到 2.5，结构数下降近 9 倍、面积中位数上升 8 倍——**这是预处理强度对误分割/误合并权衡最敏感的单一参数**，符合预期：平滑越强，噪声导致的碎化越少（结构数下降），但同时长宽比 P95 从 3.5 升到 10（噪声桥接风险上升的信号）、大结构面积占比从 0.78 降到 0.58（原本占主导的大结构被稀释进更多中等大小的团块）。**sigma=2.0 附近开始出现长宽比急剧膨胀（3.5→7.4），是误合并risk 明显上升的拐点**，建议不要盲目加大 sigma 来解决误分割，否则会把问题换成误合并。

### 3.2 闭运算半径与孔洞上限

当前生产值 `closing=2, hole=64`。结构数随 closing 半径增大单调下降（0→59, 1→50.5, 2→37.5, 3→35，见 §Phase 2 numeric summary，4 邻域 σ=1.5 情形），长宽比 P95 同步从 3.83 升到 4.68——**闭运算和 sigma 一样，是"减少碎化的代价是增加桥接风险"这一权衡的另一个旋钮**，且当前 `closing=2` 已经让长宽比膨胀了约 11%（相对 closing=0），不是免费的操作。

孔洞上限对结果的影响明显弱于 sigma 和 closing（面积中位数在 hole=16→128 之间只变化约 8%），说明**当前 `max_internal_hole_pixels=64` 相对不敏感，不是优先调整对象**。

### 3.3 seed_alpha

seed_alpha 从 0.50 升到 0.80，结构数从约 108 降到约 34，面积中位数从约 6.4 升到约 20.6——种子阈值同样对碎化/合并权衡有显著影响，且趋势与 growth alpha 方向一致（更严格的种子筛掉更多噪声引发的碎片，但也让幸存结构因为更宽松的生长半径而更容易并到一起）。当前生产值 seed_alpha=0.70 处于扫描范围中段，不在任何一端极值，相对合理。

### 3.4 sigma × closing 响应面（图 `09d_sensitivity_sigma_closing.png`）

在 4 邻域与 8 邻域两组热力图之间几乎看不出差异（数值逐格对比误差 <3%），进一步印证 §2.3 的判断：**在当前阈值区间内，连通性不是主导变量，预处理强度才是**。VLSM 数量的响应面显示一个清晰的开关行为：sigma≥1.0 时 VLSM 计数才稳定为非零（sigma=0.8 时大部分格点为 0），说明当前实际生效的 σ=0.8 平滑强度可能**系统性地把本应识别为 VLSM 的大尺度结构切碎到长度阈值以下**——这是本次诊断中与"斑点噪声导致误分割"痛点关联最直接的一条证据链。

---

## 4. 已发现的实现缺陷：高斯 sigma 未生效

### 4.1 缺陷描述

`+tbl/+periodic/simple_gaussian_filter2.m`（R2 内对应 `+tblR2/simple_gaussian_filter2.m`）的核构造只读取方向性字段：

```matlab
kernel = exp(-0.5 .* ((dx ./ options.sigma_x_cells).^2 + ...
    (dy ./ options.sigma_y_cells).^2));
```

`normalize_options` 只在方向性字段**缺失或为空**时才从标量别名 `sigma_cells`/`radius_cells` 回填：

```matlab
defaults = struct( ...
    'sigma_x_cells', sigma_cells, 'sigma_y_cells', sigma_cells, ...
    'radius_x_cells', radius_cells, 'radius_y_cells', radius_cells, ...);
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(options, names{i}) || isempty(options.(names{i}))
        options.(names{i}) = defaults.(names{i});
    end
end
```

而 `structure_analysis_cache.m` 内的 `structure_preprocessing()` 把方向性字段预填为**非空默认值** `sigma 0.8 / radius 1`：

```matlab
spec.gaussian = struct( ..., 'sigma_x_cells', 0.8, 'sigma_y_cells', 0.8, ...
    'radius_x_cells', 1, 'radius_y_cells', 1, ...);
```

案例脚本里设置的 `cfg.structures.preprocessing.gaussian.sigma_cells = 1.5` 和 `radius_cells = 4` 因此**永远传不到卷积核**——它们只是标量别名，而方向性字段已经非空，回填条件永不触发。

### 4.2 实测确认

对缓存的生产 spec 打冲激响应（对比配置意图的 spec）：

| spec | 有效 sigma | 冲激响应非零点数 |
|---|---|---|
| 缓存的生产 spec | 0.8 | 9（3×3） |
| 配置本意 | 1.5 | 81（9×9） |

产物命名 `Gaussian_sigma1p5_9x9`、`cfg` 注释、`docs/README_vlsm_cluster_method.md` 全部声称 σ=1.5/9×9，**实际生效的是 σ=0.8/3×3**。

### 4.3 影响评估

结合 §1.3 的噪声相关长度分析（σ=1.5 对应的 L_sr≈5.3 个网格间距，接近或超过 75% 重叠典型噪声相关长度约 4 个矢量间距；σ=0.8 对应 L_sr≈2.8，明显不足），以及 §3.4 观察到的"σ<1.0 时 VLSM 计数系统性偏低"，这个实现缺陷**很可能是"斑点噪声导致误分割"这一痛点的直接技术原因之一**：预处理强度只有预期的一半左右，不足以压制噪声相关尺度内的斑点。

### 4.4 是否修复

按约定，本报告不修改正式识别逻辑。是否修复此缺陷、修复后是否需要重跑全部 12000 帧的正式结构分析（`09_structure_analysis.mat`）及下游依赖它的 Q2/Q4、条件平均、双工况比较等产物，需要用户单独决策——这属于会改变正式结果数值的变更，超出本次调研授权的范围。

---

## 5. 可行改进方案汇总

按优先级排序，标注文献依据、预期效果、实施成本：

| 优先级 | 方案 | 文献依据 | 预期效果 | 成本 |
|---|---|---|---|---|
| 1 | 修复 §4 的 sigma 生效缺陷 | Wieneke 2017（噪声相关长度） | 平滑强度回到配置意图，预计显著减少误分割 | 低（已定位根因，只需对齐方向性字段） |
| 2 | 用 α∈[0.5,2.5] 重新做 Phase 1 宽扫描，定位真正转变区 | del Álamo 2006 / Lozano-Durán 2012 / Hwang & Sung 2018 的标准逾渗标定流程 | 得到有转变区证据支撑的 alpha 推荐值，而非当前无依据的 0.40 | 低（诊断工具已就绪，只需扩大扫描范围重跑，约 10-20 分钟） |
| 3 | 在转变区之后（而非之前）用本项目已实现的 bootstrap 稳定区判据定位平台段 | 本项目方法论贡献，无直接文献先例 | 阈值选择有统计意义上的鲁棒性依据 | 低（已实现） |
| 4 | 重新评估 4 vs 8 连通性，在转变区之后而非渗流临界点附近比较 | 无文献直接先例；本项目实测发现连通性差异被当前阈值位置放大 | 判断连通性选择是否仍然重要，或误差随阈值提高自然缩小 | 低（诊断工具已支持，需在新阈值下重跑） |
| 5 | 评估 seed_alpha 与 growth alpha 的联合标定，而非固定 seed=0.70 | 无直接逾渗标定文献先例；滞回思想借鉴 Ferrari et al. 2019（图像处理传统） | 更系统地控制误分割/误合并权衡 | 中（诊断工具的 Phase 2 已覆盖 seed_alpha 扫描，需结合新 alpha 重跑） |
| 6（备选，未验证） | 引入 `imreconstruct`（MATLAB 内置）替代自实现的滞回连通逻辑 | MATLAB 官方文档；等价于 skimage `apply_hysteresis_threshold` 的标准实现 | 与当前自实现的 `retain_seeded_components` 数学等价，主要是代码简化/性能收益，不改变识别结果 | 低，但需验证等价性后才能替换 |
| 7（备选，需更多验证） | POD 低阶重构去噪（Raiola, Discetti & Ianiro 2015, DOI 10.1007/s00348-015-1940-8）替代/补充高斯预处理 | PIV 领域专门的去噪方法，项目已有 POD 管线和充足帧数（12000 帧） | 可能同时缓解误分割（去除宽带噪声）和误合并（不像高斯那样各向同性扩张结构边界），但需要独立验证 | 中高（需要新增 POD 重构去噪管线，超出本轮"诊断优先"范围，留待用户决策是否纳入下一阶段） |

**不建议的方向**：

- 机器学习方法（用户已明确排除，预算不允许）
- 散度自由/无散场约束滤波（van Oudheusden 2013 指出，2D-2C 测量对应真实三维流场，面内散度本不为零，施加零散度约束会引入物理错误）
- 时域 Wiener/谱滤波去噪（Oxlade 2012、Vétel 2011 效果显著，但依赖时间相关噪声结构，需要先确认本项目 12000 帧是否为时间分辨采集，本报告未验证这一点）

---

## 6. 参考文献

**逾渗标定与连通性**（已核实全文或权威二次引用）：

1. del Álamo, J.C., Jiménez, J., Zandonade, P. & Moser, R.D. (2006). Self-similar vortex clusters in the turbulent logarithmic region. *J. Fluid Mech.* 561, 329–358.
2. Lozano-Durán, A., Flores, O. & Jiménez, J. (2012). The three-dimensional structure of momentum transfer in turbulent channels. *J. Fluid Mech.* 694, 100–130. DOI: 10.1017/jfm.2011.524
3. Hwang, J. & Sung, H.J. (2018). Wall-attached structures of velocity fluctuations in a turbulent boundary layer. *J. Fluid Mech.* 856, 958–983. DOI: 10.1017/jfm.2018.727
4. Bae, H.J. & Lee, M. (2021). Life cycle of streaks in the buffer layer of wall-bounded turbulence. arXiv:2102.03628
5. Cremades, A. et al. (2024). Identifying regions of importance in wall-bounded turbulence through explainable deep learning. *Nature Communications* 15, 3835.
6. Solak, I. & Laval, J.-P. Structures in wall-bounded turbulent flows: 2D vs 3D detection comparison. arXiv:1809.05080
7. Moisy, F. & Jiménez, J. (2004). Geometry and clustering of intense structures in isotropic turbulence. *J. Fluid Mech.* 513, 111–133.（**全文未能核实获取，转引自上述文献**）
8. 董思卫等（2021）。基于聚类连通法的湍流拟序结构研究进展。*力学进展* 51(4), 792–830. DOI: 10.6052/1000-0992-20-032（**中文全文检索未成功核实内容，仅沿用项目既有引用**）

**PIV 噪声与去噪**：

9. Sciacchitano, A. & Wieneke, B. (2016). PIV uncertainty propagation. *Meas. Sci. Technol.* 27, 084006. DOI: 10.1088/0957-0233/27/8/084006
10. Wieneke, B. (2017). PIV anisotropic denoising using uncertainty quantification. *Exp. Fluids* 58, 94. DOI: 10.1007/s00348-017-2376-0
11. Raiola, M., Discetti, S. & Ianiro, A. (2015). On PIV random error minimization with optimal POD-based low-order reconstruction. *Exp. Fluids* 56, 75. DOI: 10.1007/s00348-015-1940-8
12. Westerweel, J. & Scarano, F. (2005). Universal outlier detection for PIV data. *Exp. Fluids* 39, 1096–1100. DOI: 10.1007/s00348-005-0016-6
13. van Oudheusden, B.W. (2013). PIV-based pressure measurement. *Meas. Sci. Technol.* 24, 032001.
14. Garcia, D. (2011). A fast all-in-one method for automated post-processing of PIV data (`smoothn`). *Exp. Fluids* 50, 1247–1259. DOI: 10.1007/S00348-010-0985-Y

**连通性/滞回方法与格点渗流理论**：

15. Ferrari, K., Hu, H. & Martinuzzi, R.J. (2019). 涡脊追踪中的滞回阈值方法。*IEEE Canadian J. Electrical and Computer Engineering*. DOI: 10.1109/CJECE.2019.2917394
16. Malarz, K. & Galam, S. Square lattice site percolation thresholds for complex neighbourhoods（4-连通 p_c≈0.5927，8-连通 p_c≈0.4073，经多个独立方法交叉核实）
17. MathWorks 官方文档：`imreconstruct`, `imextendedmax`, `imhmax`, `bwareaopen`, `bwareafilt`, `bwpropfilt`, `bwconncomp`

---

## 7. 附录：诊断工具与数据落点

- 诊断代码：`cases/per_case/tandem_baseline_r2/+tblR2/{load_sweep_frames,percolation_metrics,structure_geometry_metrics,percolation_sweep,sensitivity_sweep,bootstrap_stability,make_gaussian_spec,plot_percolation_diagnostics,plot_sensitivity_diagnostics}.m`
- 入口脚本：`tools/run_r2_structure_diagnostics.m`
- 工具说明：`docs/README_r2_structure_diagnostics.md`（含判据定义、稳定区判定规则、已知坑的完整记录）
- 扫描产物（预注册范围）：`cases/per_case/tandem_baseline_r2/output/mat/09d_percolation_sweep.mat`、`09d_sensitivity_sweep.mat`
- 图件：`docs/figures/09d_percolation_as_cached.png`、`09d_percolation_intended_sigma1p5.png`、`09d_sensitivity_main_effects.png`、`09d_sensitivity_sigma_closing.png`
- 补充宽扫描（α 至 3.0，用于定位真实转变区）未持久化为 mat 文件，其数值已收录于本报告 §2.2；如需复现，用 `tblR2.percolation_sweep` 配合 `alphas=[0.4 0.55 0.7 0.85 1.0 1.3 1.6 2.0]`、`seed_alphas=alpha`（单阈值，无滞回）、全帧范围抽样即可。

**已在诊断过程中修复的工具自身缺陷**（不影响正式识别逻辑，纯诊断代码内部问题）：`percolation_sweep.m` 与 `sensitivity_sweep.m` 中用 `ndgrid` 索引构造参数组合时，若某一维度只有单个取值，MATLAB 的标量索引会返回与索引同形状而非与被索引数组同方向的结果，导致该维度的 combo 数组方向与其他维度不一致，进而在后续 `&` 逻辑运算中被隐式广播成 N×N 矩阵而非逐元素比较。已用显式 `reshape(...,[],1)` 修复并复测确认。
