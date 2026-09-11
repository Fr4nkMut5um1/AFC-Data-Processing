function cfg = validate_config(cfg)
%VALIDATE_CONFIG 检查物理量、数据源和阶段模式等核心配置。
required = {'case_id','case_type','name','script_file','data_root', ...
    'output_dir','grid_size','n_frames','formal_required_frames', ...
    'allow_debug_snapshot','fs','Uinf','nu','rho','D_mm','x_max', ...
    'min_valid_fraction','chunk_frames','rebuild_cache','profile', ...
    'loglaw','normalization','phase','instantaneous','structures', ...
    'temporal','spatial','pod','dmd','spod','correlations','friction', ...
    'stages','sources','frame_offset'};
for k = 1:numel(required)
    if ~isfield(cfg, required{k})
        error('tblR2:validate_config:MissingField', ...
            '缺少必需配置字段 cfg.%s。', required{k});
    end
end
cfg.case_type = lower(char(cfg.case_type));
if ~ismember(cfg.case_type, {'baseline','controlled'})
    error('tblR2:validate_config:InvalidCaseType', ...
        'case_type 必须是 baseline 或 controlled。');
end
if numel(cfg.grid_size) ~= 2 || any(cfg.grid_size < 2) || ...
        any(cfg.grid_size ~= fix(cfg.grid_size))
    error('tblR2:validate_config:InvalidGrid', ...
        'grid_size 必须包含两个整数维度。');
end
if ~(isscalar(cfg.n_frames) && cfg.n_frames >= 1 && cfg.n_frames == fix(cfg.n_frames))
    error('tblR2:validate_config:InvalidFrames', 'n_frames 必须是正整数。');
end
if ~(isscalar(cfg.frame_offset) && cfg.frame_offset >= 0 && cfg.frame_offset == fix(cfg.frame_offset))
    error('tblR2:validate_config:InvalidOffset', 'frame_offset 必须是非负整数。');
end
if ~(isscalar(cfg.min_valid_fraction) && cfg.min_valid_fraction > 0 && cfg.min_valid_fraction <= 1)
    error('tblR2:validate_config:InvalidValidity', ...
        'min_valid_fraction 必须位于 (0,1] 内。');
end
if ~(isscalar(cfg.chunk_frames) && cfg.chunk_frames >= 1 && cfg.chunk_frames == fix(cfg.chunk_frames))
    error('tblR2:validate_config:InvalidChunk', 'chunk_frames 必须是正整数。');
end
if ~isstruct(cfg.sources) || ~all(isfield(cfg.sources, {'raw','postproc'}))
    error('tblR2:validate_config:InvalidSources', ...
        'sources 必须同时包含 raw 和 postproc。');
end
for role = {'raw','postproc'}
    spec = cfg.sources.(role{1});
    if ~isstruct(spec) || ~all(isfield(spec, {'roots','offsets','ids'})) || ...
            numel(spec.roots) ~= 2 || numel(spec.offsets) ~= 2 || ...
            numel(spec.ids) ~= 2 || ~iscellstr(spec.roots) || ...
            ~iscellstr(spec.ids) || ~isnumeric(spec.offsets) || ...
            any(~isfinite(spec.offsets(:))) || any(spec.offsets(:) < 0) || ...
            any(spec.offsets(:) ~= fix(spec.offsets(:)))
        error('tblR2:validate_config:InvalidSourceSpec', ...
            'sources.%s 必须描述两个 repeat 序列。', role{1});
    end
end
% 原 ids 是完整目录名，PIV/PostProc 不同；只在对应性检查中忽略该源标记。
% 不改写 ids、不排序、不访问 DAT；其余 case/repeat 名称与偏移必须一致。
raw_repeat_keys = strrep(cfg.sources.raw.ids(:), '_PIV_', '_');
post_repeat_keys = strrep(cfg.sources.postproc.ids(:), '_PostProc_', '_');
if ~isequal(raw_repeat_keys, post_repeat_keys) || ...
        ~isequal(double(cfg.sources.raw.offsets(:)), ...
        double(cfg.sources.postproc.offsets(:)))
    error('tblR2:validate_config:RepeatPairMismatch', ...
        ['cfg.sources.raw/postproc 的 ids（忽略 PIV/PostProc 标记）和 offsets 必须逐 repeat 对应。' ...
        '请检查 Section 0 的两个显式序列；不会自动重排或猜测起帧。']);
end
% 核心阶段（任何 r2 版本都应有）必须齐全；缺了就说明配置不完整，直接报错。
core_stages = {'cache','statistics','mean_bl','phase','structures', ...
    'transport','temporal','spatial','pod','dmd'};
if ~all(isfield(cfg.stages, core_stages))
    error('tblR2:validate_config:MissingStage', ...
        'stages 必须至少定义核心阶段序列：%s。', strjoin(core_stages, ', '));
end
% 可选的增量阶段（spod/correlations/harmonics/figures/lcs）：
% 旧版本配置/旧工作区可能没有这些字段。缺失时按"跳过"补全并提示，
% 与下方 lcs 的"旧配置仍然有效"策略保持一致，避免分节运行时直接报错。
optional_stages = {'spod', 'correlations', 'harmonics', 'figures', 'lcs'};
for ostage = optional_stages
    if ~isfield(cfg.stages, ostage{1})
        cfg.stages.(ostage{1}) = 'skip';
        fprintf(['[配置校验] 提示：cfg.stages.%s 缺失，已按 skip 补全；' ...
            '如需启用该阶段，请设为 compute 后重新运行 Section 0。\n'], ...
            ostage{1});
    end
end
% LCS/FTLE is an optional r2 extension.  Older configuration cards remain
% valid and simply receive a skipped stage and default empty options.
if ~isfield(cfg, 'lcs') || ~isstruct(cfg.lcs)
    cfg.lcs = struct();
end
if ~isfield(cfg.stages, 'lcs')
    cfg.stages.lcs = 'skip';
end
if ~isstruct(cfg.phase) || ~isfield(cfg.phase, 'enabled')
    error('tblR2:validate_config:MissingPhaseConfig', ...
        'cfg.phase 必须至少包含 enabled 字段。');
end
if strcmp(cfg.case_type, 'baseline') && ...
        (logical(cfg.phase.enabled) || ~strcmp(char(cfg.stages.phase), 'skip'))
    error('tblR2:validate_config:BaselinePhase', ...
        'baseline 工况必须将 phase.enabled=false 且将 phase 阶段设为 skip。');
end
if ~strcmp(char(cfg.stages.phase), 'skip')
    if ~logical(cfg.phase.enabled)
        error('tblR2:validate_config:PhaseDisabled', ...
            'phase 阶段设为 compute/reuse 时必须启用 cfg.phase.enabled。');
    end
    required_phase = {'f0_hz','n_bins','phi0_user_deg', ...
        'minimum_samples_per_bin'};
    if ~all(isfield(cfg.phase, required_phase))
        error('tblR2:validate_config:MissingPhaseConfig', ...
            'phase 阶段需要完整的 cfg.phase 参数。');
    end
end
for name = fieldnames(cfg.stages).'
    if ~ismember(char(cfg.stages.(name{1})), {'compute','reuse','skip'})
        error('tblR2:validate_config:InvalidStage', ...
            'stages.%s 必须是 compute、reuse 或 skip。', name{1});
    end
end
if cfg.total_frames ~= 2 * cfg.n_frames
    error('tblR2:validate_config:InvalidTotalFrames', ...
        '串列 r2 工况要求 total_frames 等于 2*n_frames。');
end
if ~strcmp(cfg.data_root, cfg.sources.raw.roots{1})
    error('tblR2:validate_config:InvalidDataRoot', ...
        'data_root 必须等于 raw 的第一个 repeat 根目录。');
end
if ~isfield(cfg,'wall_side'); cfg.wall_side = 'bottom'; end
cfg.wall_side = lower(char(cfg.wall_side));
if ~ismember(cfg.wall_side, {'bottom','top'})
    error('tblR2:validate_config:InvalidWallSide', ...
        'wall_side 必须是 bottom 或 top。');
end
end
