> 历史记录：本文描述较早交付快照；当前基准、仓库接入及新增验证见 [CURRENT_BASELINE.md](CURRENT_BASELINE.md)。

# 本轮观察层验证记录

2026-09-10。

| 检查 | 结果 | 证明范围 |
|---|---|---|
| 两 case 全文件 SHA-256 前后对比 | PASS，422个文件，无新增/改动/删除 | 科学代码及case资源未被本轮修改 |
| source_inventory.py 在两个真实 case 运行 | PASS，211文件/case，866/868个文本引用 | 索引可以读取此快照，不是MATLAB静态分析 |
| 索引中来源文件存在性 | PASS | 行号/引用可回到源文件；不证明引用一定是调用 |
| Python AST | PASS | Python脚本可解析 |
| 双 case 启动器：MATLAB不存在 | PASS，退出码2，未启动MATLAB、未伪造原生输出 | 真实测试启动条件失败的处理 |
| 双 case 启动器：输出指向科学case | PASS，退出码2，在启动子进程前拒绝 | 真实测试输出路径保护 |
| Actions模板 YAML 与关键字段 | PASS，手动触发、contents:read、两case串行矩阵 | 文本结构，不是GitHub workflow实跑 |
| 激活的 .github/workflows | 未创建 | 没有自动部署或触发任务 |
| MATLAB采集器 | 已人工审阅；NOT_RUN | 没有原生checkcode、执行或数值结果 |
| 原生依赖边 / profiler / 小样本 | NOT_RUN | 不能给本版授予STATIC/RUNTIME/BOTH |

人工审阅修正了两个采集器问题：空which结果需要显式拒绝；which -all的cell必须作为一个字段保存，避免struct构造时展开。这些不是MATLAB测试发现，仍需真实MATLAB首次执行验证。

继续审阅修正：`which -all` 的空字符结果归一化后需要移除空项；输出目录创建后的前置检查失败也写入失败证据；已知探针未解析结果分别列出并标明SPOD可选边界；源码保护记录按路径排序。新增启动器按case启动独立batch进程，核查退出码和原生summary，不以进程成功单独认定采集完成。上述 MATLAB 改动仅人工审阅，未通过 MATLAB checkcode 或真实执行验收。

本次再次对原422个case文件进行SHA-256全量对比：无改动、无新增、无删除。两个Python文件AST、所有交付JSON、手动Actions模板结构检查通过。原生启动成功分支及MATLAB失败证据写出路径仍待真实执行；不能用Python启动条件检查替代它们。

停止边界：本轮不因没有MATLAB而编写替代科学计算、不扩大测试、不重跑/覆盖历史expected。P1仍待合法可访问MATLAB环境及原生证据补齐。
