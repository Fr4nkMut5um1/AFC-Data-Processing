# PIV Code Intelligence：P0/P1 观察层

本目录属于现有 AFC-Data-Processing。它不是新项目，也不是科学计算的运行依赖。

**本轮状态：源码侦察及云端可行性调查已完成；P1 采集器已编写，MATLAB 原生执行尚未完成。**

先读 `CURRENT_BASELINE.md`。当前源码基准为 `c860e5d2e259561147f70e0e932e0b6300bc512e`，来自 `PIV_r2_current_code.zip` 的原始 Git bundle。Git 仓库根目录对应 ZIP 内的 `project/`；case 在 `cases/per_case/`。`P0_RECONNAISSANCE.md` 保留旧交付包的历史侦察，路径换算和当前差异见 CURRENT_BASELINE。

## 文件用途

| 文件/目录 | 用途与证据边界 |
|---|---|
| P0_RECONNAISSANCE.md | 中文架构、参数与依赖、许可调查、风险、下一步 |
| scripts/source_inventory.py | 可重跑的逐文件哈希、Section 与包名文本引用索引；只能 INFERRED |
| scripts/collect_static_evidence.m | MATLAB 原生文件依赖采集；每次只处理一个 case，不运行科学代码 |
| scripts/run_static_evidence.py | 顺序启动两个独立 MATLAB batch 进程，保留日志并检查原生采集状态 |
| evidence/source-review/ | 本轮实际产生的两个源码索引，非 MATLAB 输出 |
| evidence/STATUS.json | 当前没有 STATIC/RUNTIME 证据的明确状态 |
| evidence/protection_check.json | 本轮两个 case 所有文件未改的字节校核 |
| cloud/matlab-static.yml.example | 未激活的手动静态分析 PoC，不是已部署 CI |

## 在已有 MATLAB 中采集

已安装 Python 3 和合法 MATLAB 的机器，可在本包根目录一次启动两 case 的采集：

```bash
python code-intelligence/scripts/run_static_evidence.py
```

若 MATLAB 不在 PATH，指定其可执行文件。例如 Windows：

```powershell
python code-intelligence/scripts/run_static_evidence.py --matlab "C:\Program Files\MATLAB\R2022b\bin\matlab.exe"
```

这个入口仅通过操作系统启动 MATLAB `-batch`，不使用 MATLAB Engine、不下载软件、不配置许可。每个 case 分配新进程；一项失败后仍尝试另一项。退出码 0 表示两项采集均完成但仍有已声明的分析限制；1 表示部分失败；2 表示启动条件不满足。批次目录保存启动日志、`batch_summary.json` 和各 case 原生输出。没有 Python 时直接使用下述 MATLAB 命令。

每个 case 用一个新 MATLAB 进程，不将两个同名 `+tblR2` 同时放进 path。不执行根目录 genpath，不运行主脚本来“初始化路径”。

在包含 `cases/` 与 `code-intelligence/` 的根目录打开 MATLAB，执行：

```matlab
addpath(fullfile(pwd,'code-intelligence','scripts'));
collect_static_evidence(fullfile(pwd,'cases','per_case','tandem_baseline_r2'), ...
    fullfile(pwd,'code-intelligence','evidence','native'));
```

退出 MATLAB，再用新进程将 case 名改为 `tandem_f40a3_phi0_r2`。同一个采集器用于未来本地与云端；它记录 MATLAB 版本、分析路径、源码哈希与可用 GitHub commit 信息。不要使用 `-nojvm`，当前代码使用 Java 文件路径和 SHA-256。

不需要 DAT、正式缓存或短样本即可尝试 P1。需要安装相应 Toolbox，未安装产品可能导致依赖漏报。程序完成不等于所有缺失依赖已排除。

原生输出在每次新建的目录中：`static_native.mat` 保留原始函数输出、完整日志文字与错误；JSON 为便于阅读的附加输出。若失败或部分文件分析失败，保留已有证据并返回错误。`COMPLETE_WITH_LIMITATIONS` 只表示采集过程完成，不能解释成项目可运行或科学结果已验证。

`requiredFilesAndProducts(...,'toponly')` 给出**文件依赖**。不能将这些边写成局部函数调用次数、实际执行顺序或动态数据流。入口角色依然是源码判断；`which` 仅是路径解析，不是实际执行证据。缺失依赖集合不完备时显式写 `NOT_EXHAUSTIVELY_ASSESSED`。

`missing_dependencies.json` 列出未解析的已知探针，并保留全部探针结果。SPOD 是默认跳过的可选依赖，其目录不会被采集器自动加入 path；“未解析”不直接等于缺少文件或正式路径必然报错。采集器无法完整枚举所有缺失依赖。输出目录成功创建后，即使前置检查失败，也尝试保存 `failure.json`；MATLAB 启动或许可失败则查看外层 batch 日志。

## 重建源码索引

```bash
python code-intelligence/scripts/source_inventory.py cases/per_case/tandem_baseline_r2 code-intelligence/evidence/review-next/baseline
python code-intelligence/scripts/source_inventory.py cases/per_case/tandem_f40a3_phi0_r2 code-intelligence/evidence/review-next/controlled
```

输出目录必须是新目录；索引不覆盖前次证据。工具保留每个文本引用的物理行号，包含字符串、注释和路径检查引用，不能按引用数当调用次数，也不能按零引用删除函数。

## 云端试运行的准备顺序

1. 核实可访问的 GitHub 仓库与要分析的 commit，确认目录与本包一致。
2. 私有仓库必须先解决合法许可；MathWorks batch token 申请页当前暂停新申请，见报告。
3. 把本观察层加入已有仓库的审查分支，检查 Actions 引用及 runner/MATLAB 组合；需要复现历史环境时使用 R2022bU1。
4. 将 `.yml.example` 放入 `.github/workflows/` 并改成 `.yml` 后才会出现手动入口。建议正式使用前将第三方 Actions 固定到审核过的 commit SHA。
5. 只手动运行静态采集并下载 artifact，不运行 `*_case.m`，不上传正式实验数据，不自动推送证据回仓库。

本轮没有发布、启用或触发这个 workflow。缓存关闭；静态采集不值得先增加实验结果缓存。后续可启用 setup-matlab 自身的安装缓存，但不能把 cache 当证据存档。

## 后续阶段的固定方向

P2 只在本轮缺口补齐后开始。P3 再统一正式 schema。Archify 关系需要区分 MATLAB 证据与自身推断。当前云端 DeepWiki 使用 Cognition 官方版本；未来迁移到长期自控机器时优先 DeepWiki-Open。本轮不部署 Archify、DeepWiki、数据库或常驻服务。
