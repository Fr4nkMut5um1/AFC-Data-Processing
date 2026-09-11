function cmap = resolve_case_colormap(name, n)
%RESOLVE_CASE_COLORMAP Return repository-local reference colormaps.

if nargin < 2 || isempty(n)
    n = 256;
end
if isnumeric(name)
    cmap = name;
    return;
end
switch lower(char(name))
    case {'balance', 'coolwarm', 'ocean'}
        % 红-白-蓝对称发散色图，即 cmocean('balance',20) 的本地副本。
        cmap = tblR2.viz.reference_balance_colormap();
    case {'turbo', 'turbo_kai'}
        cmap = tblR2.viz.turbo_clipped(n, 0.12, 0.06);
    case {'spectrum_rdbu8', 'rdbu8'}
        cmap = tblR2.viz.reference_spectrum_colormap();
    case 'parula'
        cmap = parula(n);
    case 'gray'
        cmap = gray(n);
    otherwise
        error('tblR2:viz:resolve_case_colormap:UnknownMap', ...
            '未知的色图名称：%s', char(name));
end
end
