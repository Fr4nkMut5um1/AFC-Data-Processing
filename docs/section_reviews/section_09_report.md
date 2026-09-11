# Section 9 独立重写对比（人工审阅稿）

## 状态

已完成 `section_09_handoff.md` 规定的核心流程：阅读源码与 handoff、联网检索、独立评审/重写、
合成结果验证、回写主工作区、全量回归测试。子代理在 README 阶段提前终止后，由主进程补齐
README、测试修正与本报告。

## 联网检索结论（可复核来源）

- MathWorks `exportgraphics` 是 R2020a+ 出版级图形导出推荐入口；
- `savefig` 用于保留可编辑 FIG；
- UTF-8 文本写入沿用 `fopen(...,'w','n','UTF-8')`，JSON 使用
  `jsonencode(...,'PrettyPrint',true,'ConvertInfAndNaN',true)`；
- 产品清单与原子写入参考通用发布工程实践，正式文件先写临时路径再覆盖。

## 旧实现评价

旧实现已具备 `run_case`、`plot_products`、诊断/摘要写入与产品目录，且核心测试覆盖
五格式导出与扩展名目录；本轮重点补齐图导出失败记录、预览/正式导出隔离、重复运行覆盖
语义和 UTF-8 诊断/摘要测试。

## 新实现改进（已回写）

1. `+tbl/+periodic/run_case.m`：保持 `validate_config → build_paths →
   ensure_external_toolboxes → case card → P01-P20 编排 → 导出 → 诊断/清单/摘要`；
   阶段失败保留 `exception_diagnostic`，不静默吞掉。
2. `+tbl/+periodic/plot_products.m`：活跃云图仍为
   `contourf(...,'LineStyle','none') + colormap(ax, turbo(256))`；图导出统一走
   `tbl.viz.export_publication_figure`。
3. `+tbl/+viz/export_publication_figure.m`：PNG 200 dpi，PDF/EPS/EMF 矢量，
   FIG 用 `savefig`，失败信息可被上层记录。
4. `+tbl/+periodic/write_diagnostics.m` / `write_machine_summary.m` /
   `product_catalog.m` / `make_final_reuse_config.m`：补强 UTF-8 写入、
   P01-P20 状态与最终 reuse 配置。
5. 两个 case 脚本 Section 9：补充正式导出、诊断清单与 P20 `DEFERRED` 注释。
6. `tests/test_section9_export.m`（新增）：覆盖扩展名目录隔离、预览不写正式产物、
   部分导出失败记录、重复导出覆盖、UTF-8 诊断/摘要与 P20 状态。
7. `README.md`：测试清单加入 `test_section9_export.m` 并说明覆盖内容。

## 主进程补齐的测试修正

- `add_diagnostic` 调用原先少传 `action_taken` 参数，已按 16 参数签名补齐，
  并把 UTF-8 中文文本放到 `plain_language_problem` 字段。

## 测试结果（MATLAB R2022b，全部通过）

全量测试命令（README 第 10 节）运行 18 个测试文件，全部 `Passed`：

    matlab -batch "files=dir(fullfile(pwd,'tests','test_*.m')); names=cellfun(@(f) fullfile(files(1).folder,f), {files.name}, 'UniformOutput', false); r=runtests(names); disp(table(r));"

含 `test_section9_export`、`test_singlecase_figure_style_contract`、
`test_periodic_piv_core` 等。未运行真实 3000/6000 帧重算；导出验证使用合成结果与
临时输出目录。

## 遗留风险

- 真实 case 的正式导出未运行；`exportgraphics` 对复杂等高线的性能提示不代表失败，
  但最终文件存在性需人工确认。
- P20 单 case 固定为 `DEFERRED`，不生成 Level 2/3 图谱；多 case 综合属于后续范围。
- 图导出失败时已记录部分产物状态，但“部分导出后清理”策略需人工确认。

## 修改文件清单

- `+tbl/+periodic/run_case.m`
- `+tbl/+periodic/plot_products.m`
- `+tbl/+periodic/write_diagnostics.m`
- `+tbl/+periodic/write_machine_summary.m`
- `+tbl/+periodic/product_catalog.m`
- `+tbl/+periodic/make_final_reuse_config.m`
- `+tbl/+viz/export_publication_figure.m`
- `cases/single/baseline_debug3000/baseline_periodic_piv_case.m`
- `cases/single/f40a3/f40a3_periodic_piv_case.m`
- `tests/test_section9_export.m`（新增）
- `README.md`
