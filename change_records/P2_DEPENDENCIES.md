# P2 本地依赖小批（静态，MATLAB待验收）

改动：ensure_external_toolboxes；require_case_library；dmd_module / spod_toolbox_adapter 的依赖检查调用；新增 test_r2_local_dependencies。

第三方目录由显式 cfg.script_file 的 case 目录导出，仅 compute/真实调用的模块检查。DMD 保留原 piDMD 和 LICENSE；SPOD 未随 ZIP 提供，主脚本须显式配置位于本 case third_party 下的合法副本。发现同名外部函数报错，要求用户明确移除旧路径；不调用 savepath/restoredefaultpath，不搜索仓库或历史安装。数组入口启用 DMD/SPOD 也须显式声明所属 case 脚本，属于路径合同变化。

核心数学及绘图不变；dmd_module 与 spod_toolbox_adapter 只改检查调用，额外指定实际使用的依赖名，避免第三方实际调用落到机器偶然安装。包函数检查仅接收该 Section 实际会调用的函数名，不调度 stage，不加载数据。

已执行：MISS_HIT 0.9.44 静态语法/名称检查（工具最高语法目标2022a，不能代替MATLAB R2022b）。首次误指定2022b被工具拒绝，改工具支持的2022a后通过；未改MATLAB代码语言版本。MATLAB functiontests 新测试尚未执行，覆盖本地函数可解析、其他case同名拒绝、skip不查SPOD、本地piDMD、外部SPOD不能顶替。

待执行：两个独立case在原仓库外启动；同会话 B→C 冲突提示、显式 rmpath B/lib后C解析；编辑器Run Section 0/5；启用DMD时一次相关原测试。SPOD正式运行需先提供合法源码。
