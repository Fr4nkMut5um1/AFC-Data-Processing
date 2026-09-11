function atomic_save(filename, payload)
%ATOMIC_SAVE Save structure fields to a temporary v7.3 MAT then rename.
folder = fileparts(filename);
if ~isfolder(folder)
    mkdir(folder);
end
token = char(java.util.UUID.randomUUID());
temp_file = fullfile(folder, ['tmp_' token '.mat']);
cleanup = onCleanup(@() delete_if_present(temp_file));
save(temp_file, '-struct', 'payload', '-v7.3');
[ok, message] = movefile(temp_file, filename, 'f');
if ~ok
    error('d23:atomic_save:MoveFailed', '%s', message);
end
clear cleanup;
end

function delete_if_present(filename)
if isfile(filename)
    delete(filename);
end
end
