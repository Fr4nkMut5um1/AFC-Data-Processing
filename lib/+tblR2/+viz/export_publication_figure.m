function export_publication_figure(fig, filename_base, formats, dpi)
%EXPORT_PUBLICATION_FIGURE Tight publication export for single-case figures.
% PNG uses exportgraphics at the requested DPI; FIG uses savefig; EPS, EMF,
% and PDF use exportgraphics with vector ContentType.

if nargin < 3 || isempty(formats), formats = {'png', 'eps', 'emf'}; end
if nargin < 4 || isempty(dpi), dpi = 300; end
if ~isgraphics(fig)
    error('tblR2:viz:export_publication_figure:InvalidFigure', ...
        'fig 必须是图形 figure 或坐标轴句柄。');
end
formats = cellstr(formats);
if isempty(formats)
    error('tblR2:viz:export_publication_figure:EmptyFormats', ...
        'formats 至少必须包含一种格式。');
end
if ~(isnumeric(dpi) && isscalar(dpi) && isfinite(dpi) && dpi > 0)
    error('tblR2:viz:export_publication_figure:InvalidDPI', ...
        'dpi 必须是有限正数标量；当前值为 %s。', ...
        mat2str(double(dpi)));
end
supported = {'png', 'fig', 'eps', 'emf', 'pdf'};
[folder, ~, ~] = fileparts(filename_base);
if ~isempty(folder) && ~isfolder(folder)
    mkdir(folder);
end
for k = 1:numel(formats)
    format = lower(strtrim(char(formats{k})));
    if ~ismember(format, supported)
        error('tblR2:viz:export_publication_figure:UnknownFormat', ...
            '不支持的出版图形格式：%s', format);
    end
    filename = [filename_base '.' format];
    switch format
        case 'png'
            exportgraphics(fig, filename, 'Resolution', dpi);
        case 'fig'
            savefig(fig, filename);
        case {'eps', 'emf', 'pdf'}
            exportgraphics(fig, filename, 'ContentType', 'vector');
    end
end
end
