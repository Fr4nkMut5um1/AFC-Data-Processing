function output = plot_lcs_ftle(lcs_result, cfg, varargin)
%PLOT_LCS_FTLE Plot FTLE fields returned by tblR2.lcs_ftle.

parser = inputParser;
parser.addParameter('frame_indices', [], @(x) isempty(x) || ...
    (isnumeric(x) && isvector(x)));
parser.addParameter('visible', false, @(x) islogical(x) || isnumeric(x));
parser.parse(varargin{:});
opts = parser.Results;
if ~isstruct(lcs_result) || ~all(isfield(lcs_result, ...
        {'ftle','seed_x','seed_y','frame_ids'}))
    error('tblR2:plot_lcs_ftle:InvalidResult', ...
        'lcs_result 缺少 ftle/seed/frame 字段。');
end
visible = 'off'; if logical(opts.visible); visible = 'on'; end
n_frames = size(lcs_result.ftle, 3);
if ~isequal(size(lcs_result.seed_x), size(lcs_result.seed_y)) || ...
        ~isequal(size(lcs_result.seed_x), size(lcs_result.ftle(:, :, 1))) || ...
        numel(lcs_result.frame_ids) ~= n_frames
    error('tblR2:plot_lcs_ftle:GridMismatch', ...
        'seed 网格、FTLE 场和 frame_ids 尺寸不一致。');
end
if isempty(opts.frame_indices)
    ids = 1:n_frames;
else
    ids = unique(double(opts.frame_indices(:).'));
end
if any(ids < 1 | ids > n_frames | ids ~= fix(ids))
    error('tblR2:plot_lcs_ftle:InvalidFrameIndices', ...
        'frame_indices 超出 FTLE 结果范围。');
end
figures = gobjects(0, 1); files = cell(0, 1);
for k = ids
    f = figure('Visible', visible, 'Color', 'w', ...
        'Name', sprintf('FTLE frame %d', lcs_result.frame_ids(k)));
    ax = axes('Parent', f);
    surf(ax, lcs_result.seed_x, lcs_result.seed_y, ...
        lcs_result.ftle(:, :, k), 'EdgeColor', 'none');
    view(ax, 2); set(ax, 'YDir', 'normal');
    axis(ax, 'tight'); axis(ax, 'equal'); colorbar(ax);
    xlabel(ax, 'x [mm]'); ylabel(ax, 'y [mm]');
    title(ax, sprintf('FTLE, frame %d, %s', ...
        lcs_result.frame_ids(k), lcs_result.direction), 'Interpreter', 'none');
    figures(end + 1) = f;
end
output = struct('figures', figures, 'files', {files}, ...
    'frame_indices', ids, 'definition', ...
    'FTLE field plots on the seed grid.');
end
