function export_figure(fig, stem, dpi)
%EXPORT_FIGURE Save a hidden figure as FIG and PNG, then close it.
folder = fileparts(stem);
if ~isfolder(folder)
    mkdir(folder);
end
savefig(fig, [stem '.fig']);
exportgraphics(fig, [stem '.png'], 'Resolution', dpi);
close(fig);
end
