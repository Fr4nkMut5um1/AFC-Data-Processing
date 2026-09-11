function output = plot_dmd_products(dmd_result, cfg, varargin)
%PLOT_DMD_PRODUCTS Plot DMD spectrum, eigenvalues and optional spatial modes.

parser = inputParser;
parser.addParameter('mode_indices', [], @(x) isempty(x) || ...
    (isnumeric(x) && isvector(x)));
parser.addParameter('visible', false, @(x) islogical(x) || isnumeric(x));
parser.parse(varargin{:});
opts = parser.Results;
if ~isstruct(dmd_result) || ~isfield(dmd_result, 'eigenvalues')
    error('tblR2:plot_dmd_products:InvalidDMD', ...
        'dmd_result 缺少 eigenvalues。');
end
visible = 'off'; if logical(opts.visible); visible = 'on'; end
figures = gobjects(0, 1); files = cell(0, 1);

f = figure('Visible', visible, 'Color', 'w', 'Name', 'DMD spectrum');
ax = axes('Parent', f);
stem(ax, dmd_result.frequency_hz, ...
    abs(dmd_result.amplitudes), 'filled');
xlabel(ax, 'frequency [Hz]'); ylabel(ax, '|amplitude|');
grid(ax, 'on'); figures(end + 1) = f;

f = figure('Visible', visible, 'Color', 'w', 'Name', 'DMD eigenvalues');
ax = axes('Parent', f);
plot(ax, real(dmd_result.eigenvalues), ...
    imag(dmd_result.eigenvalues), 'ko');
hold(ax, 'on'); th = linspace(0, 2 * pi, 361);
plot(ax, cos(th), sin(th), 'r-'); axis(ax, 'equal');
xlabel(ax, 'real(lambda)'); ylabel(ax, 'imag(lambda)');
grid(ax, 'on'); figures(end + 1) = f;

if isempty(opts.mode_indices)
    modes = 1:min(4, numel(dmd_result.eigenvalues));
else
    modes = unique(opts.mode_indices(:).');
end
if any(modes < 1 | modes > numel(dmd_result.eigenvalues) | modes ~= fix(modes))
    error('tblR2:plot_dmd_products:InvalidModeIndices', ...
        'mode_indices 超出 DMD 模态范围。');
end
has_spatial_modes = isfield(dmd_result, 'modes') && ...
    isstruct(dmd_result.modes) && isfield(dmd_result.modes, 'U') && ...
    isfield(dmd_result.modes, 'V') && isfield(dmd_result.modes, 'X_mm') && ...
    isfield(dmd_result.modes, 'Y_mm');
if has_spatial_modes
    X = dmd_result.modes.X_mm; Y = dmd_result.modes.Y_mm;
    if ~isequal(size(X), size(Y)) || ...
            size(dmd_result.modes.U, 2) ~= size(X, 1) || ...
            size(dmd_result.modes.U, 3) ~= size(X, 2) || ...
            ~isequal(size(dmd_result.modes.U), size(dmd_result.modes.V))
        error('tblR2:plot_dmd_products:ModeGridMismatch', ...
            'DMD 模态、U/V 和 X/Y 网格尺寸不一致。');
    end
    modes = modes(modes <= size(dmd_result.modes.U, 1));
    for m = modes
        f = figure('Visible', visible, 'Color', 'w', ...
            'Name', sprintf('DMD mode %d', m));
        tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
        panel(nexttile, X, Y, squeeze(real(dmd_result.modes.U(m, :, :))), ...
            sprintf('DMD mode %d: Re(U)', m));
        panel(nexttile, X, Y, squeeze(real(dmd_result.modes.V(m, :, :))), ...
            sprintf('DMD mode %d: Re(V)', m));
        figures(end + 1) = f;
    end
end
output = struct('figures', figures, 'files', {files}, ...
    'mode_indices', modes, 'definition', ...
    'DMD eigenvalue/frequency/mode plots without GUI handles.');
end

function panel(ax, X, Y, Z, label)
surf(ax, X, Y, Z, 'EdgeColor', 'none'); view(ax, 2); axis(ax, 'tight');
set(ax, 'YDir', 'normal'); axis(ax, 'equal'); colorbar(ax);
title(ax, label, 'Interpreter', 'none'); xlabel(ax, 'x [mm]'); ylabel(ax, 'y [mm]');
end
