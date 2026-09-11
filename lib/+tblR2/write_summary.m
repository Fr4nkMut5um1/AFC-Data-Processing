function write_summary(report, paths)
%WRITE_SUMMARY Write a short final summary without a product framework.
summary = report;
if isfield(summary,'results'); summary = rmfield(summary,'results'); end
fid = fopen(paths.summary_json, 'w', 'n', 'UTF-8');
if fid < 0; error('tblR2:write_summary:OpenFailed', '无法写入 JSON 摘要。'); end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(summary, 'PrettyPrint', true));
clear cleanup
fid = fopen(paths.summary_md, 'w', 'n', 'UTF-8');
if fid < 0; error('tblR2:write_summary:OpenFailed', '无法写入 Markdown 摘要。'); end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# PIV processing summary\n\n- Case: `%s`\n- Status: `%s`\n', ...
    report.case_id, report.status);
clear cleanup
end
