# 当前版本接续与有限验收

起点为本项目当前代码，版本与证据见 [CURRENT_VERSION](../CURRENT_VERSION.md)。
不重新从其他历史工程、附件骨架或研究入口生成 case；原 ZIP/project 是唯一原始源码依据。
当前云端源码/静态交付完成，以下 MATLAB 项目均未执行，不能标成通过。

## 接续顺序

1. 确认 MATLAB 版本和本地依赖。每次只加载一个 case 的 lib；记录 which 实际解析。
   原环境 R2022b 是历史身份；SPOD 默认 skip，没有合法明确本地副本时保持缺失报错。
2. 按每 case/VALIDATION.md 运行与 P1/P2/P5 相关的小 MAT、缓存与候选测试。
   文件分 script、普通函数、functiontests；不要整仓库 runtests，不降低正式 S4 门槛。
3. 用原 fixtures 的 smoke_expected 做 check，输出新报告。baseline/controlled 分别检查本 case 本地库，
   包含各自 raw/postproc 核心；smoke 不覆盖 section5_run wrapper，后者另跑定向测试。
4. 编辑器实际 Run Section：只跑0无统计；重跑0结果保留；切换case归属明确；改参数后过期产物报具体节/文件；
   已有匹配本地缓存独立0→5，不先跑2/3/4；缺所选缓存明确报错。记录操作与输出，不用节标记扫描代替。
5. 只在输入身份确定后做正式对照。S3 用相同已确认 MAT 重画，核对 data、坐标、limits/CLim、实际colormap、
   marker、5点显示平滑、字号/layout/图例/图名/导出参数，并检查错误清单。
6. S4 保留正式12000×89×640，做受影响相关段一次对照：完整筛选/目录、帧ID/repeat/计数/掩膜精确一致，
   POD 符号按重建/子空间比较；短 joint_pod_array 不能替代 formal fast_in_memory。
7. S5 正式 raw 按 case 核对 B6/C15 图及 FIG/CSV、数值闭合与文件清单；postproc 是单独待验收图组。
   原子保存的异常中断恢复不能由正常保存成功或只数 PNG 代替。

失败只定位对应路径；修复后只复跑失败及直接依赖，不修改 expected、阈值、容差使其通过。
通过且无新疑点则停止，不自动继续拆函数或重新计算12000帧。

## 必须单列的输入问题

- baseline 旧 BL [240 320] 与当前 [80 180] 不同；旧图不代表当前同参数参考。
  在未确认身份前，不把该轻量参考 MAT 当作正式 mean_bl 文件。
- ZIP 没有正式完整缓存、mean_bl/POD/run 或 S5 MAT/FIG。可用输入须从真实原件核实后提供。
- 旧 source_root/provenance/context/POD/catalog_index.MatFile 的路径审查见 P0 记录。
  只有逐 repeat 同数据及原合同可核实后才设计一次性迁移工具，保留旧身份与逐字段变更。
  不整体字符串替换、不关闭校验、不把重算产物冒充原件。

## 验收记录至少包含

版本/提交、MATLAB版本、case、输入路径与身份（包含两个repeat）、当前参数、调用方式、
输出/错误、通过/失败/未执行、比较数组/掩膜/计数/图组范围，以及仍未覆盖的正式事项。
同环境且运算顺序未变的关键数组应保持原值；原 smoke 数值容差不放宽。

## 留在本轮之外

旧 repeat_means、S3 分母/相位源的科学修订；S2 进一步绘图搬迁；S5 无关 friction 字段精简/哈希去重；
未经核实的旧结果迁移；S6–9 新合同。若以后实施，独立提案与小批验证，不与当前验收混做。
