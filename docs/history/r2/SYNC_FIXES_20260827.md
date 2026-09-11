# tandem_f40a3_phi0_r2 同步修复记录
**日期**: 2026-08-27  
**修改文件**: `tandem_f40a3_phi0_r2_case.m`

---

## 问题1: dy_h 参数注释错误 ✅ 已修复

### 问题描述
原注释将 `dy_h` 描述为"单位 mm"的绝对值，但实际上 `dy_h` 是**相对于网格间距 h 的倍数**。

### 参考依据
传统 Clauser 法脚本 `TBL_logfit.m` (第14行):
```matlab
dy = 0.8*h;  % 0.8倍h，相对倍数
```

r2 库函数 `wall_distance_grid.m` (第27行):
```matlab
profile_mm = (row_from_first_valid + dy_h) .* h_mm;
```

### 修复内容
**第84行** - 修正注释:
```matlab
% 修复前:
cfg.loglaw.params.dy_h = 2.0;  % 第一保留网格点距壁高度 h，单位 mm。

% 修复后:
cfg.loglaw.params.dy_h = 1.0;  % 第一保留点距壁面的倍数（相对于网格间距h），实际距离=dy_h*h（mm）。
```

---

## 问题2: 与 baseline_r2 参数不一致 ✅ 已修复

### 对比发现的不一致项

| 参数 | baseline_r2 | f40a3_phi0_r2 (修复前) | 状态 |
|------|-------------|----------------------|------|
| `cfg.loglaw.params.kappa` | 0.41 | 0.40 | ✅ 已统一为 0.41 |
| `cfg.loglaw.params.dy_h` | 1.0 | 2.0 | ✅ 已统一为 1.0 |
| `cfg.loglaw.skip_nearwall` | 1 | 0 | ✅ 已统一为 1 |
| `cfg.structures.alpha` | 1.0 | 1.0 | ✅ 一致 |
| `cfg.structures.seed_alpha` | 1.2 | 1.2 | ✅ 一致 |

### 修复内容

**第82行** - 修正 kappa:
```matlab
cfg.loglaw.params.kappa = 0.41;  % (原为 0.40)
```

**第84行** - 修正 dy_h:
```matlab
cfg.loglaw.params.dy_h = 1.0;  % (原为 2.0)
```

**第79行** - 修正 skip_nearwall:
```matlab
cfg.loglaw.skip_nearwall = 1;  % (原为 0)
```

**第147行** - 修正注释:
```matlab
% 2026-08-24: 双机制改进（宽滞回 + 流向近邻合并），与 baseline r2 一致
% (原注释: "与 baseline 一致"，现明确为 "baseline r2")
```

---

## 问题3: Section 2 数据源选择参数 ✅ 已添加

### 需求
用户希望 Section 2 统计阶段能够选择使用 raw 或 postproc 数据源（类似 Section 4+ 的 `cfg.lcs.source_role`）。

### 实现方案

**第68行** - 添加新参数:
```matlab
cfg.statistics_source = 'raw';  % Section 2 统计使用的数据源：'raw' 或 'postproc'。
```

**第443-466行** - 修改统计计算逻辑:
```matlab
else  % 默认分支：从序列缓存重新计算统计量。
    % 选择统计数据源：raw（原始PIV）或 postproc（后处理速度场）
    statistics_cache = paths.sequence_cache;        % 默认使用 raw 缓存
    if isfield(cfg, 'statistics_source') && strcmpi(cfg.statistics_source, 'postproc')
        statistics_cache = paths.sequence_cache_postproc;  % 用户指定使用 postproc 缓存
        fprintf('[statistics] 使用 postproc 缓存计算统计量。\n');
    else
        fprintf('[statistics] 使用 raw 缓存计算统计量（默认）。\n');
    end
    % 以块为单位计算均值、脉动量和有效样本掩膜，控制峰值内存。
    results.statistics = tblR2.mean_stats_cache( ...
        statistics_cache, cfg.min_valid_fraction, ...
        cfg.chunk_frames, cfg.Uinf);
```

### 使用方法
```matlab
% 方式1: 使用原始 PIV 数据（默认）
cfg.statistics_source = 'raw';

% 方式2: 使用后处理速度场
cfg.statistics_source = 'postproc';
```

---

## 验证检查清单

- [x] dy_h 注释已修正为"相对倍数"
- [x] dy_h 数值已与 baseline_r2 同步 (1.0)
- [x] kappa 已与 baseline_r2 同步 (0.41)
- [x] skip_nearwall 已与 baseline_r2 同步 (1)
- [x] structures.alpha/seed_alpha 确认与 baseline_r2 一致
- [x] 已添加 cfg.statistics_source 参数
- [x] 已实现 Section 2 数据源选择逻辑
- [x] 保持向后兼容（默认使用 raw）

---

## 注意事项

1. **配置合同变更**: 由于 dy_h 从 2.0 改为 1.0，旧的 statistics/mean_bl 缓存与新配置不匹配，需要重新计算:
   ```matlab
   cfg.stages.statistics = 'compute';
   cfg.stages.mean_bl = 'compute';
   ```

2. **数据源选择**: 新增的 `cfg.statistics_source` 仅在 `cfg.stages.statistics='compute'` 时生效；`'reuse'` 模式直接读取已有结果。

3. **共享库**: 本工况仍使用 `tandem_baseline_r2/+tblR2` 共享库，无需修改库代码。

---

## 参考文件
- Baseline r2 脚本: `cases/per_case/tandem_baseline_r2/tandem_baseline_r2_case.m`
- 传统 Clauser 法参考: `Export/0601_Tandem/.../TBL_logfit.m`
- 壁面距离网格函数: `tandem_baseline_r2/+tblR2/wall_distance_grid.m`
