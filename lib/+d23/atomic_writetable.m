function atomic_writetable(filename, value)
%ATOMIC_WRITETABLE Atomically publish a UTF-8 CSV table.
folder = fileparts(filename);
if ~isfolder(folder)
    mkdir(folder);
end
token = char(java.util.UUID.randomUUID());
temp_file = fullfile(folder, ['tmp_' token '.csv']);
cleanup = onCleanup(@() delete_if_present(temp_file));
writetable(value, temp_file, 'Encoding', 'UTF-8');
[ok, message] = movefile(temp_file, filename, 'f');
if ~ok
    error('d23:atomic_writetable:MoveFailed', '%s', message);
end
clear cleanup;
end

function delete_if_present(filename)
if isfile(filename)
    delete(filename);
end
end
