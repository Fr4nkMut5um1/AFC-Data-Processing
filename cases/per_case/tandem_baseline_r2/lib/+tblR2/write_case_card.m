function write_case_card(cfg, paths)
%WRITE_CASE_CARD Save only the case configuration and a short card.
save(paths.case_configuration, 'cfg');
fid = fopen(paths.case_card, 'w', 'n', 'UTF-8');
if fid < 0; error('tblR2:write_case_card:OpenFailed', '无法写入工况卡片。'); end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# %s\n\n', cfg.name);
fprintf(fid, '- Case ID: `%s`\n- Type: `%s`\n', cfg.case_id, cfg.case_type);
fprintf(fid, '- Grid: `[%d %d]`\n- Frames per repeat: `%d`\n', cfg.grid_size, cfg.n_frames);
fprintf(fid, '- Total frames: `%d`\n- Sampling rate: `%.12g Hz`\n', cfg.total_frames, cfg.fs);
fprintf(fid, '- Phase stage: `%s`\n', cfg.stages.phase);
fprintf(fid, '\nProcessing order is kept in the case script.\n');
clear cleanup
end
