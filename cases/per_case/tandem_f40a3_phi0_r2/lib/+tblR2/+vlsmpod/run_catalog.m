function result = run_catalog(ctx, source, resolved, options)
%RUN_CATALOG 帧循环 + 汇总。POD-VLSM 聚类连通法的即插即用主入口。
%
% 这是模块的门面：调用方给几何上下文、数据源、识别参数，拿回 catalog 与汇总。
% 不读 case 脚本、不写正式产物、不依赖任何全局状态——所有输入都通过参数传入。
%
% 三个功能扩展默认全关。全关时输出与重构前的基线逐位相同，这是回归验收的前提。
%
% 输入
%   ctx      : tblR2.vlsmpod.prepare_context 的输出
%   source   : 数据源规格，见 tblR2.vlsmpod.frame_field
%   resolved : tblR2.vlsmpod.resolve_settings 的输出
%   options  : 可选结构体
%              .frame_ids            要识别的帧号，必需
%              .branch               标注用分支名，默认 'total'
%              .progress             是否打印进度，默认 true
%              .progress_steps       进度打印次数，默认 20
%              .wall_attached        struct，见 classify_wall_attached；
%                                    .enabled 默认 false
%              .superstructure       struct，见 decompose_superstructure；
%                                    .enabled 默认 false
%              .tracking             struct，见 track_structures；
%                                    .enabled 默认 false。要求 frame_ids 连续。
%
% 输出 result 结构体
%   .catalog        全部帧的结构表纵向拼接
%   .per_frame      每帧的计数摘要
%   .frame_ids      实际识别的帧号
%   .summary        总体统计
%   .wall_attached  开启时的分组统计与 population density
%   .superstructure 开启时的子结构统计
%   .tracking       开启时的 track 表与事件统计

if nargin < 4 || isempty(options); options = struct(); end
options = merge_defaults(default_options(), options);
if isempty(options.frame_ids)
    error('tblR2:vlsmpod:run_catalog:MissingFrames', ...
        'options.frame_ids 不能为空。');
end
frame_ids = double(options.frame_ids(:).');
n = numel(frame_ids);

% 时间追踪要求连续帧：帧间对流位移约 50 格，跳帧后 overlap 必然失配。
if options.tracking.enabled
    if n < 2
        error('tblR2:vlsmpod:run_catalog:TrackingNeedsFrames', ...
            '时间追踪至少需要 2 帧。');
    end
    if any(diff(frame_ids) ~= 1)
        error('tblR2:vlsmpod:run_catalog:TrackingNeedsContiguous', ...
            ['时间追踪要求连续帧（stride=1）。实测帧间对流位移约 50 格，' ...
            '跳帧后结构不可能重叠。']);
    end
end

catalog_cells = cell(n, 1);
% per_frame 的字段集必须与重构前一致（4 个字段），否则 wall_attached 关闭时
% 也会与基线不匹配。第 5 个字段只在该扩展开启时才添加。
per_frame = struct('frame_id', num2cell(frame_ids(:)), ...
    'n_structures', num2cell(nan(n, 1)), ...
    'n_lsm', num2cell(nan(n, 1)), ...
    'n_vlsm', num2cell(nan(n, 1)));
if options.wall_attached.enabled
    for k = 1:n
        per_frame(k).n_wall_attached = NaN;
    end
end
% 时间追踪需要留住每帧的标签图与结构表，其他情况不留——12000 帧的标签图是
% 12000 x 89 x 640 uint32 ≈ 2.7 GB，不能无条件驻留。
keep_frames = options.tracking.enabled;
frame_store = cell(n, 1);

if options.progress
    fprintf('[POD-VLSM] 待识别 %d 帧，预处理=%s，alpha=%.4g seed=%.4g conn=%d\n', ...
        n, source.preprocessing, resolved.opts.alpha, ...
        resolved.opts.seed_alpha, resolved.opts.connectivity);
end

for k = 1:n
    frame_id = frame_ids(k);
    field = tblR2.vlsmpod.frame_field(ctx, frame_id, source);
    identified = tblR2.vlsmpod.identify_frame(ctx, field, resolved);
    T = identified.structures;

    if options.wall_attached.enabled
        T = tblR2.vlsmpod.classify_wall_attached(T, ctx, options.wall_attached);
    end
    if options.superstructure.enabled
        T = tblR2.vlsmpod.decompose_superstructure(T, identified, field, ...
            ctx, options.superstructure);
    end

    T = tblR2.vlsmpod.annotate(T, frame_id, options.branch, field.preprocessing);
    catalog_cells{k} = T;

    per_frame(k).n_structures = height(T);
    per_frame(k).n_lsm = sum(T.IsLSM);
    per_frame(k).n_vlsm = sum(T.IsVLSM);
    if options.wall_attached.enabled
        per_frame(k).n_wall_attached = sum(T.IsWallAttached);
    end

    if keep_frames
        frame_store{k} = struct('frame_id', frame_id, 'structures', T, ...
            'positive_labels', identified.positive_labels, ...
            'negative_labels', identified.negative_labels);
    end

    if options.progress && ...
            (mod(k, max(1, floor(n / options.progress_steps))) == 0 || k == n)
        fprintf('  %d/%d 帧（结构 %d，LSM %d，VLSM %d）\n', k, n, ...
            per_frame(k).n_structures, per_frame(k).n_lsm, per_frame(k).n_vlsm);
    end
end

catalog = vertcat(catalog_cells{:});

result = struct();
result.catalog = catalog;
result.per_frame = per_frame;
result.frame_ids = frame_ids(:);
result.preprocessing = char(source.preprocessing);
result.branch = options.branch;
result.structure_opts = resolved.opts;
result.trusted_domain = resolved.trusted_domain;
result.merge_enabled = resolved.merge_enabled;
result.summary = struct( ...
    'n_frames', n, ...
    'total_structures', height(catalog), ...
    'mean_structures_per_frame', mean([per_frame.n_structures], 'omitnan'), ...
    'mean_lsm_per_frame', mean([per_frame.n_lsm], 'omitnan'), ...
    'mean_vlsm_per_frame', mean([per_frame.n_vlsm], 'omitnan'), ...
    'total_lsm', sum([per_frame.n_lsm], 'omitnan'), ...
    'total_vlsm', sum([per_frame.n_vlsm], 'omitnan'));

result.wall_attached = struct();
if options.wall_attached.enabled
    result.wall_attached = tblR2.vlsmpod.wall_attached_statistics( ...
        catalog, options.wall_attached);
end
result.superstructure = struct();
if options.superstructure.enabled
    result.superstructure = tblR2.vlsmpod.superstructure_statistics(catalog);
end
result.tracking = struct();
if options.tracking.enabled
    result.tracking = tblR2.vlsmpod.track_structures( ...
        frame_store, ctx, options.tracking);
end
end

% =========================================================================
function opts = default_options()
opts = struct();
opts.frame_ids = [];
opts.branch = 'total';
opts.progress = true;
opts.progress_steps = 20;
opts.wall_attached = struct('enabled', false);
opts.superstructure = struct('enabled', false);
opts.tracking = struct('enabled', false);
end

% =========================================================================
function opts = merge_defaults(opts, user)
%MERGE_DEFAULTS 只允许已知选项；三个扩展的子结构体递归合并。
fields = fieldnames(user);
for k = 1:numel(fields)
    name = fields{k};
    if ~isfield(opts, name)
        error('tblR2:vlsmpod:run_catalog:UnknownOption', '未知选项 %s。', name);
    end
    if isstruct(opts.(name)) && isstruct(user.(name))
        sub = user.(name);
        merged = opts.(name);
        subnames = fieldnames(sub);
        for j = 1:numel(subnames)
            merged.(subnames{j}) = sub.(subnames{j});
        end
        if ~isfield(merged, 'enabled'); merged.enabled = true; end
        merged.enabled = logical(merged.enabled);
        opts.(name) = merged;
    else
        opts.(name) = user.(name);
    end
end
end
