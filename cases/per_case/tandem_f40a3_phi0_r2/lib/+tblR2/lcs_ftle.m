function result = lcs_ftle(source, cfg, stats, mean_bl, branch, varargin)
%LCS_FTLE Compute 2-D Lagrangian FTLE on a regular seed grid.
%
% The legacy POD-DMD-LCS package used a GUI, globals and an explicit Euler
% backward step.  This function keeps that numerical convention while
% exposing a deterministic array/cache API:
%
%   result = tblR2.lcs_ftle(cache_file,cfg,stats,mean_bl,'raw')
%   result = tblR2.lcs_ftle(struct('X',X,'Y',Y,'U',U,'V',V),cfg,[],[], 'raw')
%
% U and V are [nFrames x nRows x nCols].  The returned seed fields are
% [nSeedRows x nSeedCols x nStartFrames].  Invalid interpolation points are
% marked false and their FTLE is NaN; NaN velocities are treated as zero for
% the trajectory update, matching the finished legacy code.

if nargin < 2 || isempty(cfg); cfg = struct(); end
if nargin < 3; stats = []; end
if nargin < 4; mean_bl = []; end %#ok<INUSD>
if nargin < 5 || isempty(branch); branch = 'raw'; end
if nargin < 6; varargin = {}; end
branch = lower(char(branch));
if ~ismember(branch, {'raw', 'total', 'random'})
    error('tblR2:lcs_ftle:InvalidBranch', ...
        'branch 必须是 raw、total 或 random。');
end

lcfg = struct();
if isfield(cfg, 'lcs') && isstruct(cfg.lcs); lcfg = cfg.lcs; end
if ~isempty(varargin)
    % Allow the documented name/value extension without forcing callers to
    % construct cfg.lcs for one-off studies.
    if mod(numel(varargin), 2) ~= 0
        error('tblR2:lcs_ftle:InvalidOptions', ...
            '附加选项必须是 name/value 对。');
    end
end
parser = inputParser;
parser.addParameter('direction', get_opt(lcfg, 'direction', 'backward'));
parser.addParameter('frame_ids', get_opt(lcfg, 'frame_ids', []));
parser.addParameter('frame_start', get_opt(lcfg, 'frame_start', []));
parser.addParameter('frame_end', get_opt(lcfg, 'frame_end', []));
parser.addParameter('frame_stride', get_opt(lcfg, 'frame_stride', 1));
parser.addParameter('integration_steps', get_opt(lcfg, 'integration_steps', 10));
parser.addParameter('dt_s', get_opt(lcfg, 'dt_s', []));
parser.addParameter('velocity_to_grid_scale', ...
    get_opt(lcfg, 'velocity_to_grid_scale', 1000), ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
parser.addParameter('phase_stats', [], @(x) isempty(x) || isstruct(x));
parser.addParameter('seed_x', get_opt(lcfg, 'seed_x', []));
parser.addParameter('seed_y', get_opt(lcfg, 'seed_y', []));
parser.addParameter('seed_region', get_opt(lcfg, 'seed_region', []));
parser.addParameter('seed_size', get_opt(lcfg, 'seed_size', [41 41]));
parser.addParameter('interpolation', get_opt(lcfg, 'interpolation', 'linear'));
parser.parse(varargin{:});
opts = parser.Results;
opts.direction = lower(char(opts.direction));
if ~ismember(opts.direction, {'backward','forward'})
    error('tblR2:lcs_ftle:InvalidDirection', ...
        'direction 必须是 backward 或 forward。');
end

[source_info, n_frames, J, I] = inspect_source(source);
X = source_info.X;
Y = source_info.Y;
[Xg, Yg, x_axis, y_axis] = normalize_grid(X, Y, J, I);
if isempty(opts.dt_s)
    if isfield(cfg, 'fs') && isfinite(cfg.fs) && cfg.fs > 0
        dt_s = 1 / double(cfg.fs);
    else
        dt_s = 1;
    end
else
    dt_s = double(opts.dt_s);
end
if ~(isscalar(dt_s) && isfinite(dt_s) && dt_s > 0)
    error('tblR2:lcs_ftle:InvalidTimeStep', 'dt_s 必须是有限正标量。');
end
if ~(isscalar(opts.integration_steps) && opts.integration_steps >= 1 && ...
        opts.integration_steps == fix(opts.integration_steps))
    error('tblR2:lcs_ftle:InvalidIntegrationSteps', ...
        'integration_steps 必须是正整数。');
end
n_steps = double(opts.integration_steps);
if ~(isscalar(opts.frame_stride) && isfinite(opts.frame_stride) && ...
        opts.frame_stride >= 1 && opts.frame_stride == fix(opts.frame_stride))
    error('tblR2:lcs_ftle:InvalidFrameStride', ...
        'frame_stride 必须是正整数。');
end

start_ids = choose_start_frames(opts, n_frames, n_steps);
[seed_x, seed_y] = make_seed_grid(opts, x_axis, y_axis);
n_seed_rows = size(seed_x, 1);
n_seed_cols = size(seed_x, 2);
n_start = numel(start_ids);
ftle = nan(n_seed_rows, n_seed_cols, n_start);
flow_map_x = nan(size(ftle));
flow_map_y = nan(size(ftle));
valid_mask = false(size(ftle));

sign_direction = 1;
if strcmp(opts.direction, 'backward'); sign_direction = -1; end
for it = 1:n_start
    start_id = start_ids(it);
    map_x = seed_x;
    map_y = seed_y;
    valid = true(size(seed_x));
    for step = 0:(n_steps - 1)
        if sign_direction < 0
            frame_id = start_id - step;
        else
            frame_id = start_id + step;
        end
        frame = read_velocity_frame(source_info, source, frame_id, ...
            branch, stats, opts.phase_stats, J, I);
        u = interp2(Xg, Yg, frame.U, map_x, map_y, opts.interpolation, 0);
        v = interp2(Xg, Yg, frame.V, map_x, map_y, opts.interpolation, 0);
        bad = ~isfinite(u) | ~isfinite(v) | ...
            map_x < min(x_axis) | map_x > max(x_axis) | ...
            map_y < min(y_axis) | map_y > max(y_axis);
        valid = valid & ~bad;
        u(~isfinite(u)) = 0;
        v(~isfinite(v)) = 0;
        % r2 coordinates are mm while PIV velocities are m/s; the default
        % factor converts m/s to mm/s. Set this to 1 for metre-coordinate
        % arrays or another factor for a different coordinate contract.
        map_x = map_x + sign_direction * dt_s .* ...
            opts.velocity_to_grid_scale .* u;
        map_y = map_y + sign_direction * dt_s .* ...
            opts.velocity_to_grid_scale .* v;
    end
    [ftle_i, derivative_valid] = flowmap_ftle(map_x, map_y, ...
        seed_x, seed_y, dt_s * n_steps, ...
        [min(x_axis) max(x_axis)], [min(y_axis) max(y_axis)]);
    valid = valid & derivative_valid;
    ftle_i(~valid) = NaN;
    map_x(~valid) = NaN;
    map_y(~valid) = NaN;
    ftle(:, :, it) = ftle_i;
    flow_map_x(:, :, it) = map_x;
    flow_map_y(:, :, it) = map_y;
    valid_mask(:, :, it) = valid;
end

result = struct();
result.ftle = ftle;
result.flow_map_x = flow_map_x;
result.flow_map_y = flow_map_y;
result.valid_mask = valid_mask;
result.seed_x = seed_x;
result.seed_y = seed_y;
result.X_grid_mm = Xg;
result.Y_grid_mm = Yg;
result.frame_ids = start_ids(:);
result.direction = opts.direction;
result.dt_s = dt_s;
result.integration_steps = n_steps;
result.integration_time_s = dt_s * n_steps;
result.velocity_to_grid_scale = opts.velocity_to_grid_scale;
result.branch = branch;
result.grid_size = [J I];
result.seed_size = [n_seed_rows n_seed_cols];
result.definition = ['2-D FTLE from a flow map generated by explicit Euler ' ...
    'advection with interp2; Cauchy-Green largest eigenvalue uses centered ' ...
    'finite differences on the seed grid. Invalid trajectories are masked.'];
end

function value = get_opt(S, name, fallback)
if isfield(S, name) && ~isempty(S.(name)); value = S.(name); else; value = fallback; end
end

function [info, n_frames, J, I] = inspect_source(source)
if isstruct(source)
    required = {'X','Y','U','V'};
    if ~all(isfield(source, required))
        error('tblR2:lcs_ftle:InvalidArraySource', ...
            '数组源必须包含 X、Y、U、V 字段。');
    end
    info = source;
    if ~isequal(size(source.U), size(source.V))
        error('tblR2:lcs_ftle:VelocitySizeMismatch', ...
            '数组源 U/V 必须具有完全相同的尺寸。');
    end
    sz = size(source.U); sz(end + 1:3) = 1;
    n_frames = sz(1); J = sz(2); I = sz(3);
    if n_frames < 1 || J < 1 || I < 1
        error('tblR2:lcs_ftle:InvalidArraySource', ...
            '数组源 U/V 必须包含至少一个帧和一个网格点。');
    end
    info.U = reshape(double(source.U), [n_frames J I]);
    info.V = reshape(double(source.V), [n_frames J I]);
else
    if ~(ischar(source) || (isstring(source) && isscalar(source))) || ...
            ~isfile(char(source))
        error('tblR2:lcs_ftle:InvalidCache', 'source 必须是有效缓存路径或数组结构。');
    end
    cache = matfile(char(source));
    item = whos(cache, 'U');
    item_v = whos(cache, 'V');
    if isempty(item) || isempty(item_v)
        error('tblR2:lcs_ftle:InvalidCache', ...
            '缓存必须同时包含 U 和 V 变量。');
    end
    sz = item.size; sz(end + 1:3) = 1;
    sz_v = item_v.size; sz_v(end + 1:3) = 1;
    if ~isequal(sz, sz_v)
        error('tblR2:lcs_ftle:VelocitySizeMismatch', ...
            '缓存中的 U/V 尺寸不一致。');
    end
    n_frames = sz(1); J = sz(2); I = sz(3);
    info = struct('X', double(cache.X), 'Y', double(cache.Y), ...
        'cache_file', char(source));
    if has_mat_variable(cache, 'h_mm'); info.h_mm = double(cache.h_mm); end
end
if isvector(info.X) && isvector(info.Y)
    if numel(info.X) ~= I || numel(info.Y) ~= J
        error('tblR2:lcs_ftle:GridMismatch', ...
            '坐标轴长度必须与 U/V 网格尺寸 [J I] 一致。');
    end
elseif ~isequal(size(info.X), [J I]) || ~isequal(size(info.Y), [J I])
    error('tblR2:lcs_ftle:GridMismatch', ...
        'X/Y 与 U/V 网格尺寸不一致。');
end
end

function tf = has_mat_variable(cache, name)
tf = ~isempty(whos(cache, name));
end

function [Xg, Yg, x_axis, y_axis] = normalize_grid(X, Y, J, I)
if isvector(X) && isvector(Y)
    x_axis = double(X(:).');
    y_axis = double(Y(:));
    [Xg, Yg] = meshgrid(x_axis, y_axis);
else
    Xg = double(X); Yg = double(Y);
    if ~isequal(size(Xg), [J I]) || ~isequal(size(Yg), [J I])
        error('tblR2:lcs_ftle:InvalidGrid', ...
            '矩阵 X/Y 尺寸必须与速度网格 [J I] 一致。');
    end
    x_axis = double(Xg(1, :));
    y_axis = double(Yg(:, 1));
end
if numel(x_axis) ~= I || numel(y_axis) ~= J || ...
        any(~isfinite(x_axis)) || any(~isfinite(y_axis))
    error('tblR2:lcs_ftle:InvalidGrid', 'X/Y 必须是有限的规则网格。');
end
if any(diff(x_axis) == 0) || any(diff(y_axis) == 0)
    error('tblR2:lcs_ftle:InvalidGrid', 'X/Y 网格轴不能重复。');
end
if ~(all(diff(x_axis) > 0) || all(diff(x_axis) < 0)) || ...
        ~(all(diff(y_axis) > 0) || all(diff(y_axis) < 0))
    error('tblR2:lcs_ftle:InvalidGrid', ...
        'X/Y 网格轴必须严格单调。');
end
if any(~isfinite(Xg(:))) || any(~isfinite(Yg(:)))
    error('tblR2:lcs_ftle:InvalidGrid', 'X/Y 网格矩阵必须全部有限。');
end
% Matrix-form grids must really be Cartesian mesh grids.  Taking only the
% first row/column would otherwise let a sheared or transposed grid through
% and make interp2 silently associate the wrong velocity with a seed point.
tol = 1e-9 * max(1, max(abs([x_axis(:); y_axis(:)])));
X_expected = repmat(x_axis, J, 1);
Y_expected = repmat(y_axis, 1, I);
if any(abs(Xg(:) - X_expected(:)) > tol) || ...
        any(abs(Yg(:) - Y_expected(:)) > tol)
    error('tblR2:lcs_ftle:InvalidGrid', ...
        'X/Y 必须是与速度数组同方向的规则笛卡尔网格。');
end
% Keep the source orientation and the velocity-array orientation coupled.
% MATLAB interp2 accepts strictly monotone ascending or descending axes;
% retaining them avoids silently mirroring the velocity field.
end

function ids = choose_start_frames(opts, n_frames, n_steps)
if ~isempty(opts.frame_ids)
    ids = double(opts.frame_ids(:).');
else
    first = opts.frame_start; last = opts.frame_end;
    if isempty(first)
        if strcmpi(char(opts.direction), 'backward')
            first = n_steps;
        else
            first = 1;
        end
    end
    if isempty(last); last = n_frames; end
    ids = first:double(opts.frame_stride):last;
end
if isempty(ids) || any(ids < 1 | ids > n_frames | ids ~= fix(ids))
    error('tblR2:lcs_ftle:InvalidFrameIds', 'FTLE 起始帧必须位于缓存范围内。');
end
if strcmpi(char(opts.direction), 'backward')
    if any(ids - n_steps + 1 < 1)
        error('tblR2:lcs_ftle:InsufficientBackwardFrames', ...
            'backward 积分需要 start_id-integration_steps+1 >= 1。');
    end
else
    if any(ids + n_steps - 1 > n_frames)
        error('tblR2:lcs_ftle:InsufficientForwardFrames', ...
            'forward 积分超出缓存帧范围。');
    end
end
ids = unique(ids, 'stable');
end

function [sx, sy] = make_seed_grid(opts, x_axis, y_axis)
if ~isempty(opts.seed_x) && ~isempty(opts.seed_y)
    if ~isequal(size(opts.seed_x), size(opts.seed_y))
        error('tblR2:lcs_ftle:SeedMismatch', 'seed_x 与 seed_y 尺寸必须一致。');
    end
    sx = double(opts.seed_x); sy = double(opts.seed_y);
    if any(~isfinite(sx(:))) || any(~isfinite(sy(:)))
        error('tblR2:lcs_ftle:InvalidSeedGrid', ...
            'seed_x/seed_y 必须全部为有限值。');
    end
    return;
end
if ~isempty(opts.seed_region)
    region = double(opts.seed_region(:).');
if numel(region) ~= 4
        error('tblR2:lcs_ftle:InvalidSeedRegion', ...
            'seed_region 必须是 [xmin xmax ymin ymax]。');
    end
else
    region = [min(x_axis) max(x_axis) min(y_axis) max(y_axis)];
end
if any(~isfinite(region)) || region(1) >= region(2) || region(3) >= region(4)
    error('tblR2:lcs_ftle:InvalidSeedRegion', ...
        'seed_region 必须满足 xmin<xmax、ymin<ymax 且全部有限。');
end
sz = double(opts.seed_size(:).');
if numel(sz) == 1; sz = [sz sz]; end
if numel(sz) ~= 2 || any(sz < 2) || any(sz ~= fix(sz))
    error('tblR2:lcs_ftle:InvalidSeedSize', 'seed_size 必须是两个正整数且至少为 2。');
end
x = linspace(region(1), region(2), sz(2));
y = linspace(region(3), region(4), sz(1));
[sx, sy] = meshgrid(x, y);
end

function frame = read_velocity_frame(info, source, frame_id, branch, stats, phase_stats, J, I)
if isfield(info, 'cache_file') && ~isfield(info, 'U')
    chunk = tblR2.read_cache_chunk(info.cache_file, frame_id, 1:J, 1:I, ...
        branch, stats, phase_stats);
    frame = struct('U', reshape(chunk.U, [J I]), ...
        'V', reshape(chunk.V, [J I]));
else
    % Use the normalized arrays stored in info so the array path shares the
    % same frame/row/column layout as the cache path.
    frame = struct('U', squeeze(double(info.U(frame_id, :, :))), ...
        'V', squeeze(double(info.V(frame_id, :, :))));
    frame = apply_array_branch(frame, frame_id, branch, stats, phase_stats, J, I);
end
if ~isequal(size(frame.U), [J I]); frame.U = reshape(frame.U, [J I]); end
if ~isequal(size(frame.V), [J I]); frame.V = reshape(frame.V, [J I]); end
end

function [value, valid] = flowmap_ftle(map_x, map_y, seed_x, seed_y, T, x_bounds, y_bounds)
ny = size(map_x, 1); nx = size(map_x, 2);
valid = true(ny, nx);
if ny < 3 || nx < 3 || ~(T > 0)
    value = nan(ny, nx); valid(:) = false; return;
end
dx = median(diff(seed_x(1, :)), 'omitnan');
dy = median(diff(seed_y(:, 1)), 'omitnan');
if ~isfinite(dx) || ~isfinite(dy) || dx == 0 || dy == 0
    value = nan(ny, nx); valid(:) = false; return;
end
[fx_y, fx_x] = gradient(map_x, dy, dx);
[fy_y, fy_x] = gradient(map_y, dy, dx);
a = fx_x .* fx_x + fy_x .* fy_x;
d = fx_y .* fx_y + fy_y .* fy_y;
b = fx_x .* fx_y + fy_x .* fy_y;
lambda_max = 0.5 .* (a + d + sqrt(max((a - d).^2 + 4 .* b.^2, 0)));
value = log(max(lambda_max, eps)) ./ (2 .* abs(T));
valid(1, :) = false; valid(end, :) = false;
valid(:, 1) = false; valid(:, end) = false;
valid = valid & isfinite(value) & isfinite(map_x) & isfinite(map_y) & ...
    map_x >= x_bounds(1) & map_x <= x_bounds(2) & ...
    map_y >= y_bounds(1) & map_y <= y_bounds(2);
value(~valid) = NaN;
end

function frame = apply_array_branch(frame, frame_id, branch, stats, phase_stats, J, I)
% Apply the same total/random fluctuation contract as cache-backed reads.
if strcmp(branch, 'raw')
    return;
end
if strcmp(branch, 'total')
    if isempty(stats) || ~isfield(stats, 'Uavex') || ~isfield(stats, 'Vavex')
        error('tblR2:lcs_ftle:MissingStatistics', ...
            'total 分支需要 statistics.Uavex/Vavex。');
    end
    if isfield(stats, 'repeat_means') && ~isempty(stats.repeat_means)
        if ~isfield(stats, 'repeat_boundaries')
            error('tblR2:lcs_ftle:MissingRepeatMetadata', ...
                'repeat_means 存在时必须提供 repeat_boundaries。');
        end
        rep = 1 + sum(frame_id > double(stats.repeat_boundaries(:).'));
        if rep < 1 || rep > size(stats.repeat_means, 2)
            error('tblR2:lcs_ftle:InvalidRepeatMetadata', ...
                'frame_id %d 映射到无效 repeat %d。', frame_id, rep);
        end
        frame.U = frame.U - reshape(stats.repeat_means(1, rep, 1:J, 1:I), [J I]);
        frame.V = frame.V - reshape(stats.repeat_means(2, rep, 1:J, 1:I), [J I]);
    else
        frame.U = frame.U - reshape(stats.Uavex(1:J, 1:I), [J I]);
        frame.V = frame.V - reshape(stats.Vavex(1:J, 1:I), [J I]);
    end
    return;
end
if isempty(phase_stats) || ~isfield(phase_stats, 'assignment')
    error('tblR2:lcs_ftle:MissingPhaseStatistics', ...
        'random 分支需要 phase_stats。');
end
bins = phase_bins_for_frame(phase_stats, frame_id);
if isfield(phase_stats, 'U_phase_rep') && ~isempty(phase_stats.U_phase_rep)
    if ~isfield(phase_stats, 'repeat_boundaries')
        error('tblR2:lcs_ftle:MissingRepeatMetadata', ...
            'U_phase_rep 存在时必须提供 repeat_boundaries。');
    end
    rep = 1 + sum(frame_id > double(phase_stats.repeat_boundaries(:).'));
    if rep < 1 || rep > size(phase_stats.U_phase_rep, 1)
        error('tblR2:lcs_ftle:InvalidRepeatMetadata', ...
            'frame_id %d 映射到无效 repeat %d。', frame_id, rep);
    end
    if ~isfield(phase_stats, 'V_phase_rep') || ...
            ~isequal(size(phase_stats.U_phase_rep), size(phase_stats.V_phase_rep))
        error('tblR2:lcs_ftle:PhaseMeanSizeMismatch', ...
            'U_phase_rep/V_phase_rep 尺寸不一致或 V_phase_rep 缺失。');
    end
    phase_u = reshape(phase_stats.U_phase_rep(rep, bins, 1:J, 1:I), [J I]);
    phase_v = reshape(phase_stats.V_phase_rep(rep, bins, 1:J, 1:I), [J I]);
else
    if ~isfield(phase_stats, 'U_phase') || ~isfield(phase_stats, 'V_phase') || ...
            ~isequal(size(phase_stats.U_phase), size(phase_stats.V_phase))
        error('tblR2:lcs_ftle:PhaseMeanSizeMismatch', ...
            'U_phase/V_phase 尺寸不一致或缺失。');
    end
    phase_u = reshape(phase_stats.U_phase(bins, 1:J, 1:I), [J I]);
    phase_v = reshape(phase_stats.V_phase(bins, 1:J, 1:I), [J I]);
end
frame.U = frame.U - phase_u;
frame.V = frame.V - phase_v;
end

function bin = phase_bins_for_frame(phase_stats, frame_id)
source = phase_stats.assignment.bin_index;
if isa(source, 'function_handle')
    bin = source(frame_id);
elseif isnumeric(source) && isvector(source) && frame_id >= 1 && ...
        frame_id <= numel(source)
    bin = source(frame_id);
else
    error('tblR2:lcs_ftle:InvalidPhaseAssignment', ...
        'bin_index 必须是帧索引向量或函数句柄。');
end
bin = double(bin);
if isfield(phase_stats, 'U_phase') && ~isempty(phase_stats.U_phase)
    n_bins = size(phase_stats.U_phase, 1);
elseif isfield(phase_stats, 'U_phase_rep') && ~isempty(phase_stats.U_phase_rep)
    n_bins = size(phase_stats.U_phase_rep, 2);
else
    error('tblR2:lcs_ftle:MissingPhaseMean', ...
        'phase_stats 必须包含 U_phase 或 U_phase_rep。');
end
if ~(isscalar(bin) && isfinite(bin) && bin == fix(bin) && ...
        bin >= 1 && bin <= n_bins)
    error('tblR2:lcs_ftle:InvalidPhaseBin', '帧 %d 的相位箱无效。', frame_id);
end
end
