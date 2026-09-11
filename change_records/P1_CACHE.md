# P1 缓存入口小批记录

状态：**静态完成；MATLAB 动态待验收**。本批没有执行 MATLAB、Octave 或 Python 数值替代，没有读取/覆写 `smoke_expected.mat`，没有生成正式科学结果。

## 改动文件与符号

| 文件 | 符号 / 改动 |
|---|---|
| `lib/+tblR2/prepare_sequence_cache.m` | 原局部 `validate_existing_cache` 提取；原复用入口和写完缓存后的检查改调 `tblR2.validate_sequence_cache`。DAT/分块/裁剪/坐标/单精度/旧 repeat_means 计算及原子替换主体未改。 |
| `lib/+tblR2/validate_sequence_cache.m` | 新增实质只读合同检查；读取 MAT 目录与小字段，不加载 U/V/sampleValid，不扫 DAT、不检查另一个源、不写入元数据、不重建。 |
| `lib/+tblR2/section5_run.m` | 仅取所选源的路径字段；在输出目录、provenance、加载旧结果、计算之前检查正式帧政策及所选缓存合同。其后 source 文本哈希、闭合、原子保存、图表输出保持原链。 |
| `tests/test_r2_sequence_cache_contract.m` | 新增 8 帧、3×3 网格的 MAT 元数据与 S5 入口拒绝测试，含离线 raw-only / postproc-only。脚本入口，不用 runtests。 |
| `tests/test_r2_section5_transport.m` | 仅 wrapper 测试新增独立完整 schema-4 fixture；原核心数值测试、expected、阈值、容差和断言原行保持。 |

原调用链：`S1 → prepare_sequence_cache → 局部 validate_existing_cache`；独立 `S5 → section5_run → provenance / transport_analysis`。

新调用链：`S1 → prepare_sequence_cache → validate_sequence_cache`；独立 `S5 → section5_run → 正式帧政策 → validate_sequence_cache(所选源) → 原 provenance / compute/reuse / 保存 / 绘图链`。没有调用 S2/S3/S4、没有自动启动上游。

## 合同内容与保留行为

- 源身份按当前 cfg 中的每个 repeat `roots`、`ids`、`offsets` 顺序逐值匹配；repeat 数量及边界由 cfg 推导，不能反过来信任缓存边界去决定期望总帧数。
- 检查 `case_id`、schema 4、源角色、首 repeat source/data root、每 repeat 帧数、总帧数、fs、offset、首末源文件名、源网格、wall_side、precision。
- `whos` 检查真实 U/V/sampleValid 尺寸和 single/single/logical 类型，与 `cached_size`、`total_frames`、frame_ids、源网格和去壁行数相互核对。
- 检查 X/Y 有限 double 网格、原 `first_retained_row_0_plus_h` Y 映射、正 h 与 repeat_means 尺寸。**不重算 repeat_means，不检查/修复其旧有效样本口径。** 原坐标比较容差 `1e-9` 未放宽。
- 不把正式尺寸或 6000 常量写到统计核心；`section5_run` 使用调用者原 `formal_required_frames` 和 `allow_debug_snapshot` 政策。正式主脚本的 6000、S4 的 12000×89×640、正式相位条件不在本批修改范围。
- 不一致错误指出字段与实际/期望值、缓存路径，并指向 Section 0 参数或 Section 1 compute/读取正确缓存；不自动采用旧结果或重算。
- 路径保持身份精确比较；缓存离线可读不意味着可把未知旧路径改成当前路径。新本地 cfg 与历史 MAT source_root 不一致应拒绝；本批不搬历史正式结果、不盖新身份。

## 原源码证据与报告关系

以原 ZIP `project/` 行号为准：

1. `prepare_sequence_cache.m:334–353` 从 cfg 仅取首 repeat root/offset；`363–376` 用缓存自身边界推导 repeat 数量和 expected_total。旧检查存在，但并非完整的全部 repeat 身份保证；本批按用户明示补齐。与评审报告 E11/E33 的风险指向一致，没有发现此处报告与源码矛盾。
2. `transport_statistics.m:26–76` 有字段/source/内部尺寸/边界检查，未完整对照 cfg fs/总帧/全部 repeats。因此不能把直接调用它的 smoke 通过当作新入口合同已验收。
3. 原 `test_r2_section5_transport.m:139–174` 的 wrapper 测试和 `228–234` 的 `write_cache` 使用简化 MAT（double 速度、故意不可靠 repeat 均值、非均匀且从 0 起的 Y、仅少量元数据），这些是合理的统计核心测试，却不满足现行 Section 1 schema-4 文件合同。适配只为 wrapper 新造完整 fixture：保留 U/V 样本值（合成值可由 single 精确表示）、另用符合 S1 映射的 Y；原非均匀坐标的核心梯度/统计测试完全保留。没有调松 validator 或原断言。
4. `prepare_sequence_cache.m:91–94` 原 legacy cache 路径回退与 `99–113` 原 S1 post/raw 裁剪对齐重建仍保留于 P1，以免混入 P2 路径策略变更。独立 S5 不走 prepare_sequence_cache，所以不依赖它们。P2 应让日常 paths 不含历史 fallback，或在路径小批明确移除。

## 已执行的有限检查

| 检查 | 本轮结果 |
|---|---|
| 源码追踪 + 定向 diff | 静态完成；上述输入/调用边界已人工复核。 |
| `git diff --check`（项目内，限定本批文件） | 通过。 |
| 保护核心文件字节比较 | 通过：transport_statistics、transport_analysis、quadrant_streaming、read_cache_chunk、read_cache_frames、assign_phase、gradient_y_sensitivity、buffer_valid_mask、mean_stats_cache、phase_stats_cache 与 ZIP 原源码一致，SHA-256 见 `P1_CACHE_STATIC.json`。 |
| S1 构建主体文本对照 | 通过：除两处校验函数调用名称外逐字相同，旧算法/运算顺序不动。 |
| 既有 S5 测试行对照 | 通过：除两处 wrapper cache 路径替换，其余原行按序保留，所有原断言与容差均保留。 |
| MATLAB 发现 | `command -v matlab` 未找到；本轮 MATLAB 测试未执行。 |
| HDF5 元数据辅助读取 | 未执行成功：当前 Python / primary runtime 均无 h5py；未安装或用其代替 MATLAB。此项不计为验证通过。 |

## MATLAB 待执行项目（不宣称通过）

在复制后的单 case 根目录，以脚本形式运行：

```matlab
run('tests/test_r2_sequence_cache_contract.m');
run('tests/test_r2_offline_cache_reuse.m');
run('tests/test_r2_cache_statistics_smoke.m');
run('tests/test_r2_section5_transport.m');
```

新增极小测试覆盖：相同合同读取且文件不改、改 fs 拒绝、第二 repeat offset/root/id 改变拒绝、真实速度数组截短拒绝、边界/总帧声明错误拒绝、Y映射/类型错误拒绝、缺文件提示、正式门槛拒绝、S5 不一致在创建 output 前停止、只选 postproc 时不要求 raw 路径字段或 DAT。

既有 S5 测试覆盖原子保存/两源分别保存/复用与部分导出路径；其 MATLAB 运行仍待完成。本批的静态检查不验证编辑器 Run Section。仍需在本地 MATLAB 实际执行 Section 0 不算统计、0→5 无 S2/3/4 的缓存入口；用正式匹配缓存核对 raw baseline 6 / control 15 的 PNG/FIG/CSV；全量 postproc 图组另待验收。没有改变 S4 数学路径，不以本批短测试宣称 S4 正式保真。
