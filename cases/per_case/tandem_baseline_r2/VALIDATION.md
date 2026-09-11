# 有限 MATLAB 验收清单（当前全部未执行）

建议在只添加本case lib的新MATLAB会话中，按相关批次逐项运行；失败只重跑失败及直接依赖项。以下脚本/函数/单元测试入口不同，不可统一当runtests。不要自动Run完整主脚本。

```matlab
addpath('lib'); addpath('maintenance/checks');
run('maintenance/checks/test_r2_result_reuse_contract.m'); % P5a小MAT元数据
run('maintenance/checks/test_r2_section4_reuse_contract.m'); % P5b实际候选判断
run('maintenance/checks/test_r2_sequence_cache_contract.m'); % fs/尺寸/第2repeat
run('maintenance/checks/test_r2_phase_smoke.m'); % 原相位及保存读取
run('maintenance/checks/test_r2_section5_transport.m'); % S5计算+wrapper复用+部分出图
```

P1/P2动态仍待验收的直接依赖：

```matlab
test_workspace_results; % 普通函数
run('maintenance/checks/test_r2_offline_cache_reuse.m');
run('maintenance/checks/test_r2_cache_statistics_smoke.m');
runtests('maintenance/checks/test_r2_local_dependencies.m');
runtests('maintenance/checks/test_r2_section4_local_inputs.m');
```

在需要对应S4绘图验收时运行 `runtests('maintenance/checks/test_r2_section4_vlsm_figures.m')`。

真实短样本 check（先将比较用原ZIP解压，下面传明确fixture目录及新报告路径）：

```matlab
run_review_smoke_for_case(pwd, '原件解压目录/fixtures/baseline', ...
    fullfile(pwd,'output','new_smoke_check.json'));
```

适配只检查本case，原计算/expected/容差保留，禁止record或覆盖旧expected。每repeat24帧、6箱/min2仅用于smoke。该smoke直接调用transport_analysis，不覆盖section5_run的文件复用/原子发布/图组导出。S5 wrapper定向测试不能替代正式完整图组或异常中断后的原子性验收。

人工编辑器验收：0不计算；已有所选缓存0→5、不运行2/3/4；缺输入明确错误；改参数后的过期产物报错；重跑0不清空results；同会话/复制目录切换case不混用函数。静态节标题检查不能代替。

正式数据验收：保持每repeat6000、总12000、controlled24箱/min20和S4完整12000×89×640。P3/P5触及S4编排/计算配置来源，须正式相关段一次对照，核对完整目录/筛选/掩膜/帧ID/repeat/计数精确一致及POD重建/子空间。旧baseline S4图另列，不冒充当前同代码同参数参考。

S3绘图搬迁须用已确认同一MAT重画，逐数据/坐标/limits/CLim/真实colormap/marker/5点显示平滑/字体/layout/图名/导出参数核对；当前包缺所需正式MAT，不从DAT重算只为重画。

S5正式raw本case应核对 6 张PNG及对应FIG、CSV；ZIP只有原PNG/部分CSV，无正式S5 MAT/FIG。formal postproc图组为单独未完成项，不能由smoke补齐。

动态状态：未执行。当前环境无MATLAB及正式输入，未用Python/Octave替代，未宣称科学结果一致。
