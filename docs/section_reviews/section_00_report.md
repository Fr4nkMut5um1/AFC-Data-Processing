# Section 0 独立重写对比（人工审阅稿）

## 状态

已按 `section_00_handoff.md` 完成阅读、联网检索、草稿、合成 cfg 验证和全量测试。
核对主工作区后确认：`validate_config.m`、`build_paths.m`、`write_case_card.m` 与两个
case 脚本已包含草稿同版本改进，`tests/test_section0_rewrite.m` 已覆盖对应合同。

## 联网检索结论

- MathWorks 官方推荐用 `arguments` 块做函数输入校验；`validateattributes` 和
  `inputParser` 是可借鉴的现有轮子，但 `cfg` 是 struct 字段校验，仍适合保留统一
  `validate_config` 层。
- 官方文档确认 `fopen(filename,'w','n','UTF-8')` 是 Windows 写 UTF-8 文本的标准做法；
  `jsonencode` 支持 `PrettyPrint` 和 `ConvertInfAndNaN`。
- `fullfile` 负责跨平台路径拼接；编辑器活动文件定位使用
  `matlab.desktop.editor.getActiveFilename`。
- 社区中 APT/JAABA/matRad 等 MATLAB 项目大量使用 `validateattributes` 集中校验配置
  字段，但未发现可直接替换本项目的通用 cfg 轮子，因此采用“官方 API + 现有项目契约”
  的最小改进。

## 旧实现优点

- 一 case 一文件夹、Section 0-9 顺序和 `cfg.*` 中文注释规则已经成立。
- 定位、路径、case card 已迁入 `+tbl/+periodic`，脚本保持薄编排。
- 参数校验集中在 `validate_config`，阶段缓存合同已经存在。

## 已落实的问题改进

1. `validate_config` 的 `invalid()` 统一输出 `field=... | expected=... | observed=...`，
   并增加 `require_fields` 对嵌套 struct 缺失字段的统一检查，避免先抛 MATLAB 原始
   `nonExistentField` 错误。
2. `write_case_card` 写 JSON 时使用 `ConvertInfAndNaN=true`，并以 UTF-8 短写检查
   保证写盘完整。
3. `build_paths` 对非法 `output_dir` 类型给出实际观察类型。
4. 两个 case 脚本增加 `cfg.schema_version=1`，用于 case card 追溯，不影响旧缓存复用。

## 验证结果

主工作区全量测试 10/10 通过（含 `test_periodic_piv_core`、`test_section0_rewrite`、
`test_singlecase_*`、`test_refactor_shared_helpers` 等）。未运行真实 3000/6000 帧
DAT 重算；只使用合成数据和临时输出目录。

## 待人工决策

- 是否接受新增 `cfg.schema_version` 字段（不影响旧缓存复用，只进 case card）。
- 是否接受 `validate_config` 错误消息格式统一升级。
- `dy_h=2.4`、`baseline_u_tau`、`f0_hz=40`、`n_bins=24` 等物理参数未改动，仍按
  handoff 标记为待人工确认。

## 参考来源

- MathWorks: `arguments`、`validateattributes`、`inputParser`
- MathWorks: `fopen` UTF-8 encoding、`jsonencode` `ConvertInfAndNaN`
- MathWorks: `matlab.desktop.editor.getActiveFilename`
