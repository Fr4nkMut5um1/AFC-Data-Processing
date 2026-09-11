function output = plot_pod_products(pod_result, X_mm, Y_mm, cfg, varargin)
%PLOT_POD_PRODUCTS Plot POD energy, modes and optional reconstruction fields.

parser = inputParser;
parser.addParameter('mode_indices', [], @(x) isempty(x) || ...
    (isnumeric(x) && isvector(x)));
parser.addParameter('reconstruction', [], @(x) isempty(x) || isstruct(x));
parser.addParameter('visible', false, @(x) islogical(x) || isnumeric(x));
parser.parse(varargin{:});
opts = parser.Results;

if ~isstruct(pod_result)
    error('tblR2:plot_pod_products:InvalidPOD', 'pod_result 必须是结构体。');
end
if ~isequal(size(X_mm), size(Y_mm))
    error('tblR2:plot_pod_products:GridMismatch', 'X_mm/Y_mm 尺寸必须一致。');
end

% Cache POD exposes modes.U/V; the direct array API also exposes
% modes_U/modes_V for callers that do not have a sampled-grid mapping.
if isfield(pod_result, 'modes') && isstruct(pod_result.modes) && ...
        isfield(pod_result.modes, 'U') && isfield(pod_result.modes, 'V')
    U_modes = pod_result.modes.U;
    V_modes = pod_result.modes.V;
elseif isfield(pod_result, 'modes_U') && isfield(pod_result, 'modes_V')
    U_modes = pod_result.modes_U;
    V_modes = pod_result.modes_V;
else
    error('tblR2:plot_pod_products:InvalidPOD', ...
        'pod_result 缺少 modes.U/V 或 modes_U/modes_V。');
end
if ndims(U_modes) ~= 3 || ~isequal(size(U_modes), size(V_modes)) || ...
        ~isequal(size(U_modes, 2), size(X_mm, 1)) || ...
        ~isequal(size(U_modes, 3), size(X_mm, 2))
    error('tblR2:plot_pod_products:ModeGridMismatch', ...
        'POD 模态尺寸必须是 nModes×size(X_mm)。');
end
if isfield(pod_result, 'cumulative_energy_ratio')
    cumulative_energy = pod_result.cumulative_energy_ratio;
elseif isfield(pod_result, 'energy_ratio')
    cumulative_energy = cumsum(pod_result.energy_ratio);
else
    error('tblR2:plot_pod_products:MissingEnergy', ...
        'pod_result 缺少 energy_ratio/cumulative_energy_ratio。');
end

visible = 'off';
if logical(opts.visible); visible = 'on'; end
figures = gobjects(0, 1);
files = cell(0, 1);

f = figure('Visible', visible, 'Color', 'w', 'Name', 'POD energy');
ax = axes('Parent', f);
plot(ax, cumulative_energy, 'ko-', 'LineWidth', 1.1);
xlabel(ax, 'Mode'); ylabel(ax, 'Cumulative energy ratio');
grid(ax, 'on');
figures(end + 1) = f;

if isempty(opts.mode_indices)
    modes = 1:min(6, size(U_modes, 1));
else
    modes = unique(opts.mode_indices(:).');
end
if any(modes < 1 | modes > size(U_modes, 1) | modes ~= fix(modes))
    error('tblR2:plot_pod_products:InvalidModeIndices', ...
        'mode_indices 超出 POD 模态范围。');
end
for m = modes
    f = figure('Visible', visible, 'Color', 'w', ...
        'Name', sprintf('POD mode %d', m));
    tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    panel(nexttile, X_mm, Y_mm, squeeze(U_modes(m, :, :)), ...
        sprintf('POD mode %d: U', m));
    panel(nexttile, X_mm, Y_mm, squeeze(V_modes(m, :, :)), ...
        sprintf('POD mode %d: V', m));
    figures(end + 1) = f;
end

if ~isempty(opts.reconstruction)
    R = opts.reconstruction;
    if ~isfield(R, 'reconstructed_U') || ~isfield(R, 'reconstructed_V')
        error('tblR2:plot_pod_products:InvalidReconstruction', ...
            'reconstruction 缺少 reconstructed_U/V。');
    end
    if ~isequal(size(R.reconstructed_U), size(R.reconstructed_V)) || ...
            size(R.reconstructed_U, 2) ~= size(X_mm, 1) || ...
            size(R.reconstructed_U, 3) ~= size(X_mm, 2)
        error('tblR2:plot_pod_products:ReconstructionGridMismatch', ...
            'POD 重构场尺寸必须是 nFrames×size(X_mm)。');
    end
    if isfield(R, 'frame_ids')
        reconstruction_frame_ids = R.frame_ids;
    elseif isfield(R, 'frame_positions')
        reconstruction_frame_ids = R.frame_positions;
    else
        error('tblR2:plot_pod_products:InvalidReconstruction', ...
            'reconstruction 缺少 frame_ids/frame_positions。');
    end
    for k = 1:numel(reconstruction_frame_ids)
        f = figure('Visible', visible, 'Color', 'w', ...
            'Name', sprintf('POD reconstruction %d', reconstruction_frame_ids(k)));
        tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
        panel(nexttile, X_mm, Y_mm, squeeze(R.reconstructed_U(k, :, :)), ...
            sprintf('POD reconstruction U, frame %d', reconstruction_frame_ids(k)));
        panel(nexttile, X_mm, Y_mm, squeeze(R.reconstructed_V(k, :, :)), ...
            sprintf('POD reconstruction V, frame %d', reconstruction_frame_ids(k)));
        figures(end + 1) = f;
    end
end

output = struct('figures', figures, 'files', {files}, ...
    'mode_indices', modes, 'definition', ...
    'POD energy/mode/reconstruction plots on the r2 sampled grid.');
end

function panel(ax, X, Y, Z, label)
surf(ax, X, Y, Z, 'EdgeColor', 'none');
view(ax, 2); axis(ax, 'tight'); set(ax, 'YDir', 'normal');
axis(ax, 'equal'); colorbar(ax); title(ax, label, 'Interpreter', 'none');
xlabel(ax, 'x [mm]'); ylabel(ax, 'y [mm]');
end
