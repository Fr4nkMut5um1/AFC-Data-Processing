% TEST_R2_BASELINE_CONTROL_CONTRACT
% 检查 r2 baseline/control 主脚本是否保持同一套 Section 0-9 编排。
% 允许差异仅限于工况身份、数据源、输出路径、相位配置和阶段 skip/compute。

repo_root = fileparts(fileparts(mfilename('fullpath')));
baseline_file = fullfile(repo_root, 'cases', 'per_case', ...
    'tandem_baseline_r2', 'tandem_baseline_r2_case.m');
control_file = fullfile(repo_root, 'cases', 'per_case', ...
    'tandem_f40a3_phi0_r2', 'tandem_f40a3_phi0_r2_case.m');
assert(isfile(baseline_file), '缺少 r2 baseline 主脚本。');
assert(isfile(control_file), '缺少 r2 controlled 主脚本。');

baseline = fileread(baseline_file);
control = fileread(control_file);

% 两个入口都必须完整声明 Section 0-9 的核心计算调用。
section_pattern = ...
    '(?m)^[ \t]*%{1,2}[ \t]*([0-9]+)(?:[ \t]*[.、:：)][ \t]*|[ \t]+)\S';
required_calls = {'tblR2.prepare_sequence_cache', 'tblR2.mean_stats_cache', ...
    'tblR2.mean_bl_friction', 'tblR2.phase_stats_cache', ...
    'tblR2.section4_vlsm_analysis', 'tblR2.section5_run', ...
    'tblR2.temporal_spectra_cache', 'tblR2.spatial_spectra_cache', ...
    'tblR2.pod_module', 'tblR2.dmd_module', 'tblR2.lcs_ftle', ...
    'tblR2.spod_cache', ...
    'tblR2.correlation_analysis_cache', ...
    'tblR2.streamwise_development_analysis', 'tblR2.plot_products'};
for text = {baseline, control}
    value = text{1};
    section_tokens = regexp(value, section_pattern, 'tokens');
    section_numbers = cellfun(@(token) str2double(token{1}), section_tokens);
    assert(isequal(section_numbers, 0:9), ...
        '主脚本必须按顺序且仅一次声明 Section 0-9 标题。');
    for k = 1:numel(required_calls)
        assert(contains(value, required_calls{k}), ...
            '主脚本缺少核心调用 %s。', required_calls{k});
    end
    assert(contains(value, 'paths.phase'), '主脚本缺少 Section 3 产物路径。');
    assert(contains(value, 'tblR2.load_result(paths.phase, cfg, ''phase'', phase_inputs)'), ...
        '主脚本缺少 phase reuse 分支。');
    assert(contains(value, 'tblR2.save_result(paths.phase, results.phase, cfg, ''phase'', phase_inputs)'), ...
        '主脚本缺少 phase 保存分支。');
    assert(contains(value, ...
        "results.postproc_cache = tblR2.prepare_sequence_cache(cache_cfg, paths, 'postproc');"), ...
        'Section 1 必须同时准备 postproc 缓存。');
    assert(contains(value, 'tblR2.validate_dual_source_grid'), ...
        'Section 1 缺少 raw/postproc 双源网格校验。');
    assert(~contains(value, 'recover_sources_from_cache') && ...
        contains(value, 'cfg.sources.raw.roots') && contains(value, 'cfg.sources.postproc.roots'), ...
        '入口须使用显式 repeat 序列，不从缓存回写配置。');
end

% Legacy names remain available only as compatibility wrappers.
for text = {baseline, control}
    value = text{1};
    assert(contains(value, 'tblR2.pod_module'), ...
        '主脚本必须调用新的 POD 模块接口。');
    assert(contains(value, 'tblR2.dmd_module'), ...
        '主脚本必须调用新的 DMD 模块接口。');
    assert(contains(value, 'tblR2.lcs_ftle'), ...
        '主脚本必须保留 LCS/FTLE 模块接口。');
end

% Preview calls may repeat modules; retain their first-occurrence order.
assert(isequal(core_call_sequence(baseline, required_calls), ...
    core_call_sequence(control, required_calls)), ...
    'baseline/control 的核心计算调用顺序存在差异。');

% 仅检查配置层面的预期差异。
assert(contains(baseline, "cfg.case_type = 'baseline';"));
assert(contains(baseline, "cfg.phase = struct('enabled', false);"));
assert(~isempty(regexp(baseline, "cfg\.stages\.phase\s*=\s*'skip';", 'once')));
assert(contains(control, "cfg.case_type = 'controlled';"));
assert(contains(control, "cfg.phase = struct('enabled', true);"));
assert(contains(control, 'cfg.phase.f0_hz = 40;'));
assert(contains(control, 'cfg.phase.n_bins = 24;'));
assert(contains(control, 'cfg.phase.minimum_samples_per_bin = 20;'));
assert(~isempty(regexp(control, ...
    "cfg\.stages\.phase\s*=\s*'(compute|reuse)';", 'once')));
assert(contains(control, 'Tandem_f40A3_Phi+0_PIV'));
assert(contains(control, 'Tandem_f40A3_Phi+0_PostProc'));
assert(contains(baseline, 'Tandem_Baseline_PIV'));
assert(contains(baseline, 'Tandem_Baseline_PostProc'));

fprintf('test_r2_baseline_control_contract: PASS\n');

function calls = core_call_sequence(text, required_calls)
calls = regexp(text, 'tblR2\.[A-Za-z_]+(?=\s*\()', 'match');
calls = calls(ismember(calls, required_calls));
calls = unique(calls, 'stable');
end
