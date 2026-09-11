function atomic_write_text(filename, text_value)
%ATOMIC_WRITE_TEXT Write UTF-8 text through a same-directory temporary file.
folder = fileparts(filename);
if ~isfolder(folder)
    mkdir(folder);
end
token = char(java.util.UUID.randomUUID());
temp_file = fullfile(folder, ['tmp_' token '.txt']);
cleanup = onCleanup(@() delete_if_present(temp_file));
fid = fopen(temp_file, 'w', 'n', 'UTF-8');
if fid < 0
    error('d23:atomic_write_text:OpenFailed', 'Cannot open %s.', temp_file);
end
file_cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', char(text_value));
clear file_cleanup;
[ok, message] = movefile(temp_file, filename, 'f');
if ~ok
    error('d23:atomic_write_text:MoveFailed', '%s', message);
end
clear cleanup;
end

function delete_if_present(filename)
if isfile(filename)
    delete(filename);
end
end
