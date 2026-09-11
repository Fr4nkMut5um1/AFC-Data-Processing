# P2：独立 case 整合与交付边界

本批以 P1a/P1b 后的工作源码为起点；仅做本地目录、显式输入、真实S4文件接口和依赖检查，不推进P3/P4/P5。

## 修改文件/符号和调用链

- 两个主脚本：从当前执行文件确定 case_root；直接添加本地 lib；Section 0 明列两源各两个 repeat 的完整目录名及 [0 0] offsets。validate_config 回到 Section 0 的纯配置检查；写配置卡留在 Section 1。删除运行期缓存取源覆盖、编号扫描、起帧猜测、父 bootstrap/repo_root。
- require_case_library：在对应 compute/reuse 分支检查实际会使用的包函数本地解析。它不运行 stage、不改 MATLAB 工具箱路径、不保存全局path。
- ensure_external_toolboxes、dmd_module、spod_toolbox_adapter：只检查实际使用的本地第三方代码；显式 cfg.script_file 定位本 case；SPOD 必須明确给本地合法副本。两消费者仅改依赖检查调用，无数学表达式变化。
- validate_config：显式检查所有 repeat spec、同源数据对应。ids 保留完整原目录名，仅在 raw/PostProc 对应检查中忽略 `_PIV_`/`_PostProc_` 角色标记，不排序、不写回。
- prepare_sequence_cache：P1a提取后的校验不变；P2删除 legacy_sequence_cache 路径 fallback。原缺缓存后从明确DAT构建及PostProc裁剪对齐策略保留，既有数组写入、去壁、repeat_means、分块/原子替换不变。
- section4_vlsm_analysis：四参显式BL文件接口，本地run寻址与活动路径审计。实际d23数值链及正式门槛保留；详见 P2_S4.md。
- 每个 case 完整复制本地lib、Cf表、piDMD和LICENSE。resolve_case_repeats移至maintenance显式维护工具；locate_repository_root未放入日常库。原共享库、旧tools等保留在原ZIP/原源码副本和变更历史中，不作为独立目录的运行依赖。

P1b的提交点暂以旧S4六参接口传三个未使用的[]，使其与原适配器接口相容；P2才切到显式四参。P1b尚未替换S1来源恢复段，因此独立0→5的完整配置边界以本P2终态为准。P1_MAIN.md描述的目标四参形态在P2落实，不能把中间提交冒称已完成独立目录验收。

新链：脚本Section0（本地参数/路径/归属）→ 手工选择节；S1明确sources→prepare_sequence_cache；独立S5→selected cache只读合同→原transport_analysis/统计/闭合→原子保存和原绘图；S4→显式PostProc+mean_bl文件→原d23链→原专用图组。

## 改变与不改变的行为

改变：轻量参数节、工作区陈旧/复制目录混用报错、完整所选缓存输入校验、独立目录和本地依赖解析、明确sources、S4显式BL输入及活动路径拒绝；摘要区分未运行/过期。旧结果缺身份或路径不匹配不被自动重签。

不变：当前科学参数/默认stage（B figures skip、C compute、transport两skip）、S1数据/帧序/类型/去壁/公式、S2/S3旧统计口径和绘图、S4正式12000×89×640及POD-E50/阈值/检测链、S5同源/逐repeat/有效支持域/共同均值梯度/H严格大于/NaN/概率分母/闭合/原子保存/文本哈希及图形主体。没有调用d23.run_experiment，没有替换POD算法。

## 测试入口适配

交付仅带相关MATLAB检查，放在每个case的maintenance/checks，定位由tests父目录调整为case根。S4 figure测试原两case仓库路径断言改为当前独立目录唯一主脚本断言，其绘图数值/阈值/数量断言不变。workspace测试只改使用说明。其他旧测试保留在comparison/project_original和原ZIP，不宣称所有旧布局测试已迁移/通过。

run_review_smoke_for_case是原smoke的check-only位置适配：只接收显式case_root、原fixtures子目录及新报告文件；计算主体和compare_values原容差完全保留，删除record入口，不写原expected。不从旧配置加载日常正式参数；这只是维护区固定样本检查。

## 实际验证结果

- PASS（静态）：当前两脚本所有原科学参数赋值表达式逐项保持；两个case各166个原库文件字节不变、7个原文件按上述范围修改、3个新实质检查/工作区函数；全部51个d23文件、关键数学/绘图核心、piDMD及Cf表字节不变。
- PASS（静态）：两份176个本地库文件彼此及审核源相同；无日常locator/resolver残余调用；原469个比较文件重新哈希均不变。
- PASS（静态语法）：MISS_HIT 0.9.44以最高支持的2022a语法目标、UTF-8检查22个最终相关文件。它不是MATLAB checkcode、Run Section或动态数值验证。
- 未执行：全部MATLAB单测、编辑器分节、0→5、B→C、DMD/SPOD启用、缓存读取/保存的实际MAT行为、原子保存/复用/图组导出。
- 未执行：正式S4同代码同参数参考及新链12000帧相关段；baseline6/controlled15 raw PNG+FIG+CSV逐case核对；postproc正式图组。

已知停止依据：baseline保存BL参考的profile_params=[240 320]与当前[80 180]不同，正式原MAT/FIG/POD目录未提供；没有已核实迁移。P3–P5未实施，旧load_result完整计算身份、S4自动reuse完整参数/source比较和显式resume优先级仍待独立补丁。不能把本次静态检查汇总为“正式结果已验证一致”。
