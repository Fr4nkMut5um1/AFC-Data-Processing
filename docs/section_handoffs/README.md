# Section 0–9 Handoff 文档

这些文档用于“每轮一个 section”的独立评审与重写流程。每个新对话粘贴对应文档即可开始，不继承本仓库的对话记忆。

| Section | 文件 | 主要内容 |
|---|---|---|
| 0 | `section_00_handoff.md` | 参数、路径、初始化、validate_config、build_paths、case card |
| 1 | `section_01_handoff.md` | DAT → 序列缓存、manifest、legacy 复用 |
| 2 | `section_02_handoff.md` | 时间统计、壁面坐标、边界层、摩阻 |
| 3 | `section_03_handoff.md` | 相位平均、三重分解、谐波 |
| 4 | `section_04_handoff.md` | 瞬时场、涡判据、LSM/VLSM |
| 5 | `section_05_handoff.md` | 四象限、输运项 |
| 6 | `section_06_handoff.md` | 时域 Welch PSD、直接空间 FFT |
| 7 | `section_07_handoff.md` | POD、DMD、SPOD |
| 8 | `section_08_handoff.md` | 相关性与沿程/谐波综合 |
| 9 | `section_09_handoff.md` | 正式导出、诊断、摘要、P01–P20 |

流程约定：

1. 打开新对话，粘贴对应 section 文档。
2. Agent 不依赖项目记忆，主动联网检索轮子/工具箱/算法，背靠背独立写出新代码并测试。
3. 输出新旧代码对比评价，交人工审阅。
4. 根据人工意见修改并测试。
5. 写回原脚本，同步更新依赖函数、测试和 README。

所有文档使用 `session-handoff-prompt` skill 的 `full` 模式、`privacy=local` 生成。
