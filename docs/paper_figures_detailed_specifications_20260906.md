# 论文图表详细规范
# Detailed Specifications for Paper Figures

**项目 Project**: 音圈膜执行器 VLSM 主动控制实验  
**日期 Date**: 2026-09-06  
**用途 Purpose**: 论文投稿（JFM/PRF）  
**总图数 Total Figures**: 16 张主图 + 若干补充图（Supplementary）

---

## 全局图表规范 Global Figure Standards

### 基本要求 Basic Requirements
- **分辨率 Resolution**: 300 DPI（PNG），矢量格式（EPS/PDF）
- **尺寸 Size**:
  - Single-column: 8.5 cm (3.35 inch) 宽
  - Double-column: 17.0 cm (6.69 inch) 宽
  - 高度不超过 23 cm（全页）
- **字体 Fonts**:
  - 主体文字：Arial 或 Helvetica，10 pt
  - 坐标轴标签：10 pt
  - 图例：9 pt
  - 子图标签 (a,b,c)：粗体 Arial，12 pt，放置在左上角
- **颜色方案 Color Scheme**:
  - 主色系：深蓝 (#003f5c)，橙红 (#ef5675)，金黄 (#ffa600)，深绿 (#2f4b7c)
  - 背景：纯白 (#ffffff)
  - 网格线：浅灰 (#cccccc)，0.5 pt 虚线
  - 采用 colorblind-friendly palette（参考 ColorBrewer）
- **线条样式 Line Styles**:
  - 实验数据：实线，2 pt 粗细
  - 文献对比：虚线或点划线，1.5 pt
  - 辅助参考线：细虚线，0.75 pt
- **标记符号 Markers**:
  - 圆形 (○)、方形 (□)、三角 (△)、菱形 (◇)
  - 大小：6-8 pt
  - 填充色与线条色一致

### 坐标轴规范 Axis Standards
- **刻度方向 Tick Direction**: 向内（inward）
- **刻度长度 Tick Length**: 主刻度 4 pt，次刻度 2 pt
- **坐标轴线宽 Axis Line Width**: 1 pt
- **科学记数法 Scientific Notation**: 用 × 而非 e（例如 1.5×10³ 而非 1.5e3）
- **单位标注 Unit Notation**: 用括号，例如 U (m/s)，y⁺ (dimensionless)

### 图例规范 Legend Standards
- **位置 Position**: 优先右上角，避免遮挡数据
- **边框 Border**: 细黑线（0.5 pt）或无边框
- **背景 Background**: 半透明白色（80% 不透明度）或无背景
- **排列 Layout**: 垂直排列（除非水平排列更节省空间）

---

## Figure 1: Experimental Setup and Actuator Configurations
## 图 1：实验装置与执行器构型

### 用途 Purpose
展示实验硬件、测量域、执行器布置，建立物理图像

### 布局 Layout
**格式 Format**: Double-column (17 cm × 12 cm)  
**子图数量 Subpanels**: 4 个，2×2 排列

#### (a) Wind tunnel schematic（风洞示意图）
- **类型 Type**: 工程示意图（CAD 或手绘 + 标注）
- **内容 Content**:
  - 风洞测试段轮廓（侧视图）
  - 坐标系标注：x（流向，向右），y（法向，向上），z（展向，出页面）
  - 关键尺寸：测试段长度、高度
  - 来流方向箭头（U∞ = 25 m/s）
- **颜色 Color**: 灰度或淡蓝色填充，黑色轮廓线
- **标注 Annotations**: 最小化文字，用符号 + 图例

#### (b) PIV measurement domain（PIV 测量域）
- **类型 Type**: 俯视图/侧视图复合
- **内容 Content**:
  - FOV 矩形框（248 mm × 47 mm）
  - 激光片光位置（绿色虚线）
  - 相机视角（斜箭头）
  - 边界层厚度 δ₉₉ 标注（垂直标尺）
  - 壁面 y=0 参考线（粗黑线）
- **颜色 Color**: 激光绿，相机深灰，FOV 边框红色虚线
- **坐标轴 Axes**: x/δ₉₉ (横轴)，y/δ₉₉ (纵轴)

#### (c) Tandem configuration（串列构型）
- **类型 Type**: 三维示意图或俯视图
- **内容 Content**:
  - 两个执行器音圈膜（圆形或椭圆）
  - 流向间距 Δx 标注（双向箭头 + 数值）
  - 相位关系示意（正弦波 + 相位差 φ）
  - 流动方向箭头
- **颜色 Color**: 执行器 1（深蓝），执行器 2（橙红）
- **动画帧 Animation Frame**（可选）: 显示一个周期内的膜面变形

#### (d) Parallel configuration（并列构型）
- **类型 Type**: 三维示意图或俯视图
- **内容 Content**:
  - 两个执行器展向排列
  - 展向间距 Δz 标注
  - 相位关系（如有）
- **颜色 Color**: 与 tandem 一致，便于对比
- **标注 Annotations**: 强调展向位置

### 输出示例 Output Example
```matlab
% MATLAB 伪代码
figure('Units', 'centimeters', 'Position', [0 0 17 12]);

subplot(2,2,1); % Wind tunnel schematic
% [手绘或导入 CAD PNG]
axis off; title('(a) Wind tunnel', 'FontSize', 12, 'FontWeight', 'bold');

subplot(2,2,2); % PIV domain
rectangle('Position', [0 0 248/33 47/33], 'EdgeColor', 'r', 'LineStyle', '--');
xlabel('x/\delta_{99}'); ylabel('y/\delta_{99}');
title('(b) PIV measurement domain');

subplot(2,2,3); % Tandem
plot_tandem_schematic();
title('(c) Tandem');

subplot(2,2,4); % Parallel
plot_parallel_schematic();
title('(d) Parallel');

exportgraphics(gcf, 'figures/Fig01_experimental_setup.png', 'Resolution', 300);
```

---

## Figure 2: Baseline Mean Flow and Turbulence Statistics
## 图 2：基准平均流动与湍流统计

### 用途 Purpose
表征未受控边界层的基准状态，建立对比基准

### 布局 Layout
**格式 Format**: Double-column (17 cm × 8 cm)  
**子图数量 Subpanels**: 4 个，1×4 横向排列

#### (a) Mean velocity field ⟨U⟩（平均速度场）
- **类型 Type**: 填充等值线图（contourf）
- **坐标轴 Axes**:
  - 横轴：x/δ₉₉，范围 [0, 10]
  - 纵轴：y/δ₉₉，范围 [0, 1.5]
- **物理量 Variable**: ⟨U⟩/U∞
- **色标 Colorbar**:
  - 范围：[0.6, 1.0]（或根据实际数据调整）
  - 色图：'parula' 或 'viridis'
  - 等值线数：15 级
  - 色标标签：⟨U⟩/U∞
- **叠加内容 Overlay**:
  - δ₉₉ 轮廓线（白色虚线）
  - 壁面 y=0（黑色粗线）
- **绘图设置 Plot Settings**:
  ```matlab
  contourf(X/delta99, Y/delta99, U_mean/Uinf, 15, 'LineStyle', 'none');
  colormap(parula); colorbar; clim([0.6 1.0]);
  xlabel('x/\delta_{99}'); ylabel('y/\delta_{99}');
  title('(a) \langleU\rangle/U_\infty');
  axis equal tight;
  ```

#### (b) Streamwise turbulence intensity u_rms（流向湍流强度）
- **类型 Type**: 填充等值线图
- **坐标轴 Axes**: 同 (a)
- **物理量 Variable**: u_rms/U∞
- **色标 Colorbar**:
  - 范围：[0, 0.12]
  - 色图：'hot' 或 'YlOrRd'（强调高湍流区）
  - 标签：u_rms/U∞
- **叠加内容 Overlay**: δ₉₉ 轮廓线

#### (c) Wall-normal turbulence intensity v_rms（法向湍流强度）
- **类型 Type**: 填充等值线图
- **坐标轴 Axes**: 同 (a)
- **物理量 Variable**: v_rms/U∞
- **色标 Colorbar**:
  - 范围：[0, 0.06]（通常比 u_rms 小）
  - 色图：'hot'
  - 标签：v_rms/U∞

#### (d) Reynolds stress ⟨-u′v′⟩（Reynolds 应力）
- **类型 Type**: 填充等值线图
- **坐标轴 Axes**: 同 (a)
- **物理量 Variable**: ⟨-u′v′⟩/U∞²
- **色标 Colorbar**:
  - 范围：[0, 0.008]
  - 色图：'hot'
  - 标签：⟨-u′v′⟩/U∞²
- **叠加内容 Overlay**: 峰值位置标记（白色圆圈）

### 配色方案建议 Color Scheme
- 平均场用 sequential colormap（单向渐变，如 parula）
- 湍流量用 warm colormap（暖色调，如 hot/YlOrRd），强调高值区

---

## Figure 3: Baseline VLSM Catalog and Scale Distribution
## 图 3：基准 VLSM 目录与尺度分布

### 用途 Purpose
展示 VLSM 识别结果，建立尺度分布基准

### 布局 Layout
**格式 Format**: Double-column (17 cm × 10 cm)  
**子图数量 Subpanels**: 3 个，上下排列（1 大图 + 2 小图）

#### (a) Instantaneous VLSM snapshot（瞬时 VLSM 快照）
- **类型 Type**: 背景云图 + 结构轮廓叠加
- **坐标轴 Axes**:
  - 横轴：x/δ₉₉，范围 [0, 10]
  - 纵轴：y/δ₉₉，范围 [0, 1.5]
- **背景 Background**: u′(x,y,t)/u_rms，色图 'RdBu_r'（红-白-蓝）
  - 色标范围：[-3, 3]（归一化脉动）
- **结构轮廓 Structure Contours**:
  - 正脉动 VLSM（u′>0）：粗黑色实线（2 pt）
  - 负脉动 VLSM（u′<0）：粗黑色虚线（2 pt）
  - 只绘制 Lx/δ₉₉ ≥ 3 的结构
- **标注 Annotations**:
  - 每个 VLSM 旁标注流向尺度（如 "4.2δ"）
  - 用半透明文本框避免遮挡
- **尺寸 Size**: 占上半部分（高度 6 cm）

#### (b) Streamwise extent distribution（流向尺度分布）
- **类型 Type**: 直方图（histogram）
- **坐标轴 Axes**:
  - 横轴：Lx/δ₉₉，范围 [3, 10]（只统计 VLSM）
  - 纵轴：Count（计数）或 Probability Density（概率密度）
- **柱子样式 Bar Style**:
  - 颜色：深蓝 (#003f5c)，边框黑色
  - 柱宽：bin width = 0.5
- **叠加内容 Overlay**:
  - 均值位置（红色垂直虚线）
  - 中位数位置（绿色垂直虚线）
  - 图例标注：Mean = 4.2δ, Median = 3.8δ
- **统计信息 Statistics**: 在右上角文本框显示：
  ```
  Total VLSM: 183
  Mean Lx: 4.2δ
  Std: 1.5δ
  ```
- **尺寸 Size**: 占下半部分左侧（宽度 8.5 cm，高度 4 cm）

#### (c) Wall-normal centroid distribution（法向质心分布）
- **类型 Type**: 散点图（scatter）
- **坐标轴 Axes**:
  - 横轴：Lx/δ₉₉，范围 [3, 10]
  - 纵轴：⟨y_c⟩/δ₉₉（质心法向位置），范围 [0, 1.0]
- **数据点 Data Points**:
  - 标记：圆形，大小 6 pt
  - 颜色：按正/负脉动分（蓝色 = 正，红色 = 负）
  - 透明度：0.6（避免重叠遮挡）
- **趋势线 Trend Line**:
  - 线性拟合或 LOWESS 平滑（黑色虚线）
  - 显示 R² 或相关系数
- **参考线 Reference Lines**:
  - y/δ₉₉ = 0.5（对数层中心，水平虚线）
- **尺寸 Size**: 占下半部分右侧（宽度 8.5 cm，高度 4 cm）

### 绘图代码框架 Plotting Code Framework
```matlab
figure('Units', 'centimeters', 'Position', [0 0 17 10]);

% (a) Instantaneous snapshot
subplot(2,2,[1 2]); % 占上半部分
contourf(X/delta99, Y/delta99, u_prime/u_rms, 20, 'LineStyle', 'none');
colormap(redblue); clim([-3 3]); colorbar;
hold on;
plot_vlsm_contours(structures, 'k', 2);  % 自定义函数
xlabel('x/\delta_{99}'); ylabel('y/\delta_{99}');
title('(a) Instantaneous u''/u_{rms}');

% (b) Lx distribution
subplot(2,2,3);
histogram([structures.Lx_over_delta], 'BinWidth', 0.5, 'FaceColor', [0 0.25 0.36]);
xline(mean([structures.Lx_over_delta]), 'r--', 'LineWidth', 2, 'Label', 'Mean');
xlabel('L_x/\delta_{99}'); ylabel('Count');
title('(b) Streamwise extent');

% (c) Wall-normal centroid
subplot(2,2,4);
scatter([structures.Lx_over_delta], [structures.yc_over_delta], ...
    36, [structures.sign], 'filled', 'MarkerFaceAlpha', 0.6);
colormap(gca, [0 0 1; 1 0 0]); % 蓝=正，红=负
xlabel('L_x/\delta_{99}'); ylabel('\langley_c\rangle/\delta_{99}');
title('(c) Wall-normal position');
yline(0.5, 'k--');

exportgraphics(gcf, 'figures/Fig03_vlsm_catalog.png', 'Resolution', 300);
```

---

## Figure 4: Spectral Signatures (Temporal and Spatial)
## 图 4：谱特征（时域与空间）

### 用途 Purpose
证明激励频率选择的依据，表征 VLSM 的频率-波数特性

### 布局 Layout
**格式 Format**: Double-column (17 cm × 8 cm)  
**子图数量 Subpanels**: 2 个，1×2 横向排列

#### (a) Premultiplied temporal PSD（预乘时域功率谱密度）
- **类型 Type**: 2D 云图（log-log 坐标）
- **坐标轴 Axes**:
  - 横轴：λ_x⁺ = U_c/(f·ν/u_τ)（内尺度流向波长），对数刻度，范围 [10², 10⁵]
  - 纵轴：y⁺（壁面单位法向位置），对数刻度，范围 [30, 3000]
- **物理量 Variable**: f·Φ_uu(f, y)（预乘 PSD，无量纲）
- **色标 Colorbar**:
  - 范围：[0, 0.5]（或根据数据归一化）
  - 色图：'hot' 或 'YlOrRd'
  - 等值线级数：10-15 级
  - 标签：f·Φ_{uu}/u_τ²
- **叠加内容 Overlay**:
  - VLSM 峰值区域轮廓（白色粗线）
  - f₀ = 40 Hz 对应的 λ_x⁺ 位置（垂直虚线）
  - 文献数据点（如 Kim & Adrian 1999 的 λ_x⁺ ≈ 6δ）
- **标注 Annotations**:
  - 在峰值区标注："VLSM peak, St_δ ≈ 0.10"
  - 在 f₀ 线上标注："Actuation frequency"
- **参考线 Reference Lines**:
  - y⁺ = 100（对数层典型位置，水平虚线）
  - λ_x⁺ = 10³（VLSM 下限，垂直虚线）

#### (b) Spatial spectrum（空间谱）
- **类型 Type**: 1D 线图（log-log 坐标）
- **坐标轴 Axes**:
  - 横轴：k_x δ₉₉（无量纲流向波数），对数刻度，范围 [0.1, 10]
  - 纵轴：k_x·E_uu(k_x)（预乘能量谱），对数刻度，范围 [10⁻⁴, 10⁻¹]
- **数据曲线 Data Curves**:
  - Baseline（黑色实线，2 pt）
  - 不同 y/δ₉₉ 位置（y/δ = 0.1, 0.3, 0.5, 0.7）
  - 用不同颜色区分高度（深→浅 = 近壁→外层）
- **峰值标注 Peak Annotation**:
  - 在每条曲线的峰值处用小圆圈标记
  - 标注对应的 λ_x/δ₉₉（如 "λ_x = 4.5δ"）
- **参考线 Reference Lines**:
  - k_x δ₉₉ = 2π/3（VLSM 特征波数，垂直虚线）
  - -5/3 斜率参考线（惯性子区，灰色虚线）
- **图例 Legend**: 放置在右上角
  ```
  y/δ = 0.1 (深蓝)
  y/δ = 0.3 (蓝)
  y/δ = 0.5 (橙)
  y/δ = 0.7 (红)
  ```

### 绘图代码框架 Plotting Code Framework
```matlab
figure('Units', 'centimeters', 'Position', [0 0 17 8]);

% (a) Premultiplied PSD
subplot(1,2,1);
contourf(lambda_x_plus, y_plus, f_Phi_uu, 15, 'LineStyle', 'none');
set(gca, 'XScale', 'log', 'YScale', 'log');
colormap(hot); clim([0 0.5]); colorbar;
hold on;
xline(lambda_x_at_f0, 'w--', 'LineWidth', 2, 'Label', 'f_0 = 40 Hz');
xlabel('\lambda_x^+ = U_c/(f\nu/u_\tau)'); ylabel('y^+');
title('(a) f·\Phi_{uu}');
xlim([1e2 1e5]); ylim([30 3e3]);

% (b) Spatial spectrum
subplot(1,2,2);
y_positions = [0.1 0.3 0.5 0.7];
colors = [0 0.1 0.4; 0 0.3 0.6; 0.9 0.5 0.1; 0.8 0.1 0.1];
for i = 1:length(y_positions)
    loglog(kx_delta99, kx_Euu(:,i), 'Color', colors(i,:), 'LineWidth', 2);
    hold on;
end
xline(2*pi/3, 'k--', 'Label', '\lambda_x = 3\delta_{99}');
xlabel('k_x\delta_{99}'); ylabel('k_x·E_{uu}');
title('(b) Spatial spectrum');
legend(arrayfun(@(y) sprintf('y/\\delta = %.1f', y), y_positions, 'UniformOutput', false), ...
    'Location', 'northeast');
grid on; xlim([0.1 10]); ylim([1e-4 1e-1]);

exportgraphics(gcf, 'figures/Fig04_spectral_signatures.png', 'Resolution', 300);
```

---

## Figure 5: VLSM Count and Drag vs. Frequency
## 图 5：VLSM 数量与阻力 vs. 频率

### 用途 Purpose
展示频率扫描结果，识别最优激励频率

### 布局 Layout
**格式 Format**: Single-column (8.5 cm × 8 cm)  
**子图数量 Subpanels**: 1 个（双 y 轴）

#### 主图 Main Plot
- **类型 Type**: 双 y 轴折线图 + 柱状图组合
- **横轴 X-axis**:
  - 变量：f (Hz)，线性刻度
  - 范围：[0, 90]（包含 baseline=0 和 f=20,40,60,80）
  - 刻度：[0, 20, 40, 60, 80]
  - 标签：Actuation frequency f (Hz)

#### 左 y 轴（VLSM count）
- **类型 Type**: 柱状图
- **变量 Variable**: VLSM count（计数）
- **范围 Range**: [0, 250]（根据实际数据调整）
- **柱子样式 Bar Style**:
  - 颜色：深蓝 (#003f5c)，透明度 0.7
  - 边框：黑色，1 pt
  - 柱宽：10 Hz
- **误差棒 Error Bars**:
  - 样式：竖直线 + 端点横杠（'T' 型）
  - 误差来源：3 个时间窗口的标准差
  - 颜色：黑色，1 pt
- **标签 Label**: VLSM count

#### 右 y 轴（拖曳系数）
- **类型 Type**: 折线图
- **变量 Variable**: C_f（系统平均，x ∈ [160, 240] mm）
- **范围 Range**: [0.0020, 0.0028]（根据实际数据）
- **曲线样式 Line Style**:
  - 颜色：橙红 (#ef5675)
  - 线型：实线，2.5 pt 粗细
  - 标记：圆形，填充，大小 8 pt
- **误差棒 Error Bars**:
  - 样式：竖直线，颜色与曲线一致
  - 误差来源：空间标准差（x ∈ [160, 240] mm）
- **标签 Label**: Drag coefficient C_f

#### 叠加内容 Overlay
- **Baseline 参考线**:
  - VLSM count（左轴）：水平虚线，y = 183
  - C_f（右轴）：水平虚线，y = 0.00245
  - 颜色：灰色，线宽 1 pt
  - 图例标注："Baseline (uncontrolled)"
- **最优频率标注**:
  - 在 C_f 最小值处标注："f_{opt} = 40 Hz"
  - 用红色向下箭头指向数据点
  - 文本框背景半透明白色

#### 图例 Legend
- **位置 Position**: 右上角（不遮挡数据）
- **条目 Entries**:
  - 蓝色柱子：VLSM count
  - 橙红色线：Drag coefficient C_f
  - 灰色虚线：Baseline
- **边框 Border**: 无或细黑线

### 绘图代码框架 Plotting Code Framework
```matlab
figure('Units', 'centimeters', 'Position', [0 0 8.5 8]);

f_values = [0 20 40 60 80];
vlsm_count = [183 165 158 170 178];  % 示例数据
cf_mean = [0.00245 0.00241 0.00238 0.00240 0.00243];
vlsm_err = [8 7 6 7 8];  % 标准差
cf_err = [0.00003 0.00002 0.00002 0.00003 0.00003];

yyaxis left;  % 左轴：VLSM count
bar(f_values, vlsm_count, 'FaceColor', [0 0.25 0.36], 'FaceAlpha', 0.7, 'EdgeColor', 'k');
hold on;
errorbar(f_values, vlsm_count, vlsm_err, 'k', 'LineStyle', 'none', 'LineWidth', 1);
yline(183, 'k--', 'LineWidth', 1, 'Label', 'Baseline', 'LabelHorizontalAlignment', 'left');
ylabel('VLSM count');
ylim([0 250]);

yyaxis right;  % 右轴：Cf
plot(f_values, cf_mean, '-o', 'Color', [0.94 0.34 0.46], 'LineWidth', 2.5, 'MarkerSize', 8, 'MarkerFaceColor', [0.94 0.34 0.46]);
errorbar(f_values, cf_mean, cf_err, 'Color', [0.94 0.34 0.46], 'LineStyle', 'none', 'LineWidth', 1);
yline(0.00245, 'k--', 'LineWidth', 1);
ylabel('Drag coefficient C_f');
ylim([0.0020 0.0028]);

xlabel('Actuation frequency f (Hz)');
xlim([-5 85]);
xticks([0 20 40 60 80]);

% 最优频率标注
[~, idx_opt] = min(cf_mean);
text(f_values(idx_opt), cf_mean(idx_opt)-0.0001, 'f_{opt} = 40 Hz', ...
    'HorizontalAlignment', 'center', 'BackgroundColor', [1 1 1 0.7]);

grid on; box on;
exportgraphics(gcf, 'figures/Fig05_frequency_sweep.png', 'Resolution', 300);
```

---

## Figure 6: Reynolds Stress and Drag vs. Amplitude
## 图 6：Reynolds 应力与阻力 vs. 振幅

### 用途 Purpose
展示振幅扫描结果，分析 Reynolds 应力调制与减阻关系

### 布局 Layout
**格式 Format**: Double-column (17 cm × 8 cm)  
**子图数量 Subpanels**: 2 个，1×2 横向排列

#### (a) Reynolds stress profiles（Reynolds 应力剖面）
- **类型 Type**: 多条曲线叠加
- **坐标轴 Axes**:
  - 横轴：⟨-u′v′⟩/U∞²（Reynolds 应力，无量纲），范围 [0, 0.010]
  - 纵轴：y/δ₉₉（法向位置），范围 [0, 1.5]
- **数据曲线 Data Curves**:
  - Baseline（黑色实线，2 pt，参考基准）
  - A = 0.3 mm（深蓝，实线，1.5 pt）
  - A = 1.0 mm（橙色，实线，1.5 pt）
  - A = 3.0 mm（红色，实线，1.5 pt）
- **标记符号 Markers**: 每隔 5 个数据点放置一个标记（避免曲线过于拥挤）
  - Baseline: 圆形 (○)
  - A=0.3: 方形 (□)
  - A=1.0: 三角 (△)
  - A=3.0: 菱形 (◇)
- **峰值标注 Peak Annotation**:
  - 在每条曲线的峰值处标注数值（如 "0.0082"）
  - 用细虚线连接峰值点与标注
- **图例 Legend**:
  - 位置：右上角
  - 排列：垂直
  - 标题："Amplitude (f = 40 Hz)"
- **参考线 Reference Lines**:
  - y/δ₉₉ = 0.2（典型峰值位置，水平虚线）

#### (b) Drag coefficient vs. amplitude（阻力系数 vs. 振幅）
- **类型 Type**: 折线图 + 散点
- **坐标轴 Axes**:
  - 横轴：A/δ₉₉（无量纲振幅），范围 [0, 0.12]
  - 纵轴：ΔC_f/C_f,baseline（相对减阻百分比，%），范围 [-10, 5]
- **数据曲线 Data Curve**:
  - 主曲线：深蓝实线，2 pt
  - 数据点：圆形填充标记，大小 8 pt
  - 误差棒：竖直 'T' 型，黑色
- **参考线 Reference Lines**:
  - y = 0（无减阻，水平粗虚线，黑色）
- **最优点标注 Optimal Point**:
  - 在最大减阻点（如 A/δ = 0.091）标注：
    - "A_{opt} = 3.0 mm"
    - "ΔC_f = -6.5%"
  - 用红色星形标记 (★) + 箭头
- **填充区域 Shaded Region**（可选）:
  - 在减阻区（ΔC_f < 0）填充淡蓝色，透明度 0.2
  - 在增阻区（ΔC_f > 0）填充淡红色，透明度 0.2
- **文本框 Text Box**: 在右上角显示：
  ```
  f = 40 Hz, φ = 0°
  x ∈ [160, 240] mm
  ```

### 绘图代码框架 Plotting Code Framework
```matlab
figure('Units', 'centimeters', 'Position', [0 0 17 8]);

% (a) Reynolds stress profiles
subplot(1,2,1);
y_delta = linspace(0, 1.5, 50);
plot(reynolds_baseline, y_delta, 'k-', 'LineWidth', 2); hold on;
plot(reynolds_A03, y_delta, '-', 'Color', [0 0.3 0.6], 'LineWidth', 1.5, 'Marker', 's', 'MarkerIndices', 1:5:50);
plot(reynolds_A10, y_delta, '-', 'Color', [0.9 0.5 0.1], 'LineWidth', 1.5, 'Marker', '^', 'MarkerIndices', 1:5:50);
plot(reynolds_A30, y_delta, '-', 'Color', [0.8 0.1 0.1], 'LineWidth', 1.5, 'Marker', 'd', 'MarkerIndices', 1:5:50);
yline(0.2, 'k--', 'LineWidth', 0.75);
xlabel('\langle-u''v''\rangle/U_\infty^2'); ylabel('y/\delta_{99}');
title('(a) Reynolds stress profiles');
legend('Baseline', 'A=0.3 mm', 'A=1.0 mm', 'A=3.0 mm', 'Location', 'northeast');
xlim([0 0.010]); ylim([0 1.5]); grid on;

% (b) Drag vs. amplitude
subplot(1,2,2);
A_delta = [0 0.009 0.030 0.091];  % 归一化振幅
Delta_Cf_pct = [0 -2.1 -4.3 -6.5];  % 减阻百分比
Delta_Cf_err = [0 0.5 0.6 0.7];

plot(A_delta, Delta_Cf_pct, '-o', 'Color', [0 0.25 0.36], 'LineWidth', 2, 'MarkerSize', 8, 'MarkerFaceColor', [0 0.25 0.36]);
hold on;
errorbar(A_delta, Delta_Cf_pct, Delta_Cf_err, 'k', 'LineStyle', 'none', 'LineWidth', 1);
yline(0, 'k--', 'LineWidth', 1.5);
[min_val, idx_opt] = min(Delta_Cf_pct);
plot(A_delta(idx_opt), min_val, 'rp', 'MarkerSize', 15, 'MarkerFaceColor', 'r');
text(A_delta(idx_opt)+0.01, min_val-0.5, sprintf('A_{opt}=3.0 mm\n\\DeltaC_f=%.1f%%', min_val), ...
    'FontSize', 9, 'BackgroundColor', [1 1 1 0.8]);
xlabel('A/\delta_{99}'); ylabel('\DeltaC_f/C_{f,baseline} (%)');
title('(b) Drag reduction vs. amplitude');
xlim([0 0.12]); ylim([-10 5]); grid on;

exportgraphics(gcf, 'figures/Fig06_amplitude_sweep.png', 'Resolution', 300);
```

---

## Figure 7: Optimal Parameter Map (St_δ vs. A/δ)
## 图 7：最优参数图（St_δ vs. A/δ）

### 用途 Purpose
综合展示频率-振幅参数空间的减阻效果，提取最优参数组合

### 布局 Layout
**格式 Format**: Single-column (8.5 cm × 8.5 cm)  
**子图数量 Subpanels**: 1 个

#### 主图 Main Plot
- **类型 Type**: 填充等值线图 + 数据点叠加
- **坐标轴 Axes**:
  - 横轴：St_δ = f·δ₉₉/U∞（Strouhal 数，基于边界层厚度），对数刻度，范围 [0.02, 0.25]
  - 纵轴：A/δ₉₉（无量纲振幅），线性刻度，范围 [0, 0.12]
- **物理量 Variable**: ΔC_f/C_f,baseline（%，减阻百分比）
- **色标 Colorbar**:
  - 范围：[-10, 5]（负值 = 减阻，正值 = 增阻）
  - 色图：'RdYlBu_r'（红-黄-蓝反向）
    - 蓝色：减阻（< -5%）
    - 白色：中性（≈ 0%）
    - 红色：增阻（> 0%）
  - 等值线级数：15 级
  - 标签：ΔC_f/C_{f,baseline} (%)
- **数据点 Data Points**:
  - 实际测量工况（黑色圆圈，大小 8 pt，填充白色）
  - 用粗黑边框（2 pt）突出显示
- **最优点标注 Optimal Point**:
  - 位置：(St_δ ≈ 0.10, A/δ ≈ 0.091)
  - 标记：白色五角星 (★)，大小 12 pt，黑色边框
  - 标注文本：
    ```
    Optimal: St_δ = 0.10, A/δ = 0.091
    f = 40 Hz, A = 3.0 mm
    ΔC_f = -6.5%
    ```
  - 文本框背景：半透明白色，黑色边框
- **参考线 Reference Lines**:
  - St_δ = 0.08–0.15（VLSM 频率范围，垂直虚线，白色）
  - A/δ = 0.03（小振幅上限，水平虚线，白色）
- **插值方法 Interpolation**: 'cubic' 或 'natural'（从离散点生成平滑等值线）

### 绘图代码框架 Plotting Code Framework
```matlab
figure('Units', 'centimeters', 'Position', [0 0 8.5 8.5]);

% 构建网格（从实际测量点插值）
St_data = [0.024 0.048 0.072 0.096 0.120 ...  % f=20,40,60,80 @ A=0.3,1,3
           0.024 0.048 0.072 0.096 ...         % 每个 f 3 个 A
          ];  % 共 12 个点（示例）
A_delta_data = [0.009 0.009 0.009 0.009 0.009 ...
                0.030 0.030 0.030 0.030 ...
                0.091 0.091 0.091];
Delta_Cf_data = [-1.2 -2.1 -1.5 -0.8 ... % 示例减阻数据
                 -2.8 -4.3 -3.1 -1.9 ...
                 -4.5 -6.5 -5.2];

% 插值到规则网格
[St_grid, A_grid] = meshgrid(logspace(log10(0.02), log10(0.25), 50), linspace(0, 0.12, 50));
Delta_Cf_grid = griddata(St_data, A_delta_data, Delta_Cf_data, St_grid, A_grid, 'cubic');

% 绘制等值线图
contourf(St_grid, A_grid, Delta_Cf_grid, 15, 'LineStyle', 'none');
colormap(flip(redblue)); clim([-10 5]); colorbar;
set(gca, 'XScale', 'log');
hold on;

% 叠加实际数据点
plot(St_data, A_delta_data, 'ko', 'MarkerSize', 8, 'MarkerFaceColor', 'w', 'LineWidth', 2);

% 最优点标注
[~, idx_opt] = min(Delta_Cf_data);
plot(St_data(idx_opt), A_delta_data(idx_opt), 'wp', 'MarkerSize', 12, 'MarkerFaceColor', 'w', 'LineWidth', 2);
text(St_data(idx_opt)*1.2, A_delta_data(idx_opt), ...
    sprintf('Optimal:\nSt_\\delta=%.2f, A/\\delta=%.3f\nf=40 Hz, A=3 mm\n\\DeltaC_f=-6.5%%', ...
    St_data(idx_opt), A_delta_data(idx_opt)), ...
    'FontSize', 8, 'BackgroundColor', [1 1 1 0.9], 'EdgeColor', 'k');

% 参考线
xline(0.08, 'w--', 'LineWidth', 1, 'Label', 'VLSM range', 'LabelHorizontalAlignment', 'right');
xline(0.15, 'w--', 'LineWidth', 1);
yline(0.03, 'w--', 'LineWidth', 1, 'Label', 'Small amplitude');

xlabel('St_\delta = f\delta_{99}/U_\infty'); ylabel('A/\delta_{99}');
title('Drag reduction map: \DeltaC_f/C_{f,baseline} (%)');
xlim([0.02 0.25]); ylim([0 0.12]); box on;

exportgraphics(gcf, 'figures/Fig07_parameter_map.png', 'Resolution', 300);
```

---

由于篇幅限制，我将在此处暂停并总结已完成的内容。我已详细规范了前 7 张图表（Fig.1–7），涵盖：

1. ✅ **实验装置与构型**
2. ✅ **基准流场统计**
3. ✅ **VLSM 识别与尺度**
4. ✅ **谱特征**
5. ✅ **频率扫描**
6. ✅ **振幅扫描**
7. ✅ **参数优化图**

每张图都包含：
- 详细的子图布局（尺寸、排列）
- 完整的坐标轴规范（范围、刻度、标签、单位）
- 精确的物理量定义与色标设置
- 叠加内容与标注方案
- MATLAB 绘图代码框架

**需要继续完成剩余 9 张图（Fig.8–16）吗？** 它们将涵盖：
- Fig.8–11: 相位效应（Phase-averaged fields, VLSM vs. φ, Cf vs. φ, Reynolds stress decomposition）
- Fig.12–13: 构型比较（Tandem vs. Parallel）
- Fig.14–15: 模态分析（POD, DMD）
- Fig.16: 物理机制示意图

请告诉我是否继续交付后 9 张图的详细规范，或者你对前 7 张有任何修改需求？