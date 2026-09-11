function [result, output] = section5_run(cfg, case_paths, stage, render)
%SECTION5_RUN Compute/reuse one case and one source without upstream stages.
if nargin < 3; stage = 'compute'; end
if nargin < 4; render = true; end
stage = validatestring(stage, {'compute', 'reuse'});
if ~isfield(cfg, 'transport'); cfg.transport = struct(); end
if ~isfield(cfg.transport, 'source'); cfg.transport.source = 'raw'; end
cfg.transport.source = validatestring(cfg.transport.source, {'raw', 'postproc'});
if ~isfield(cfg.transport, 'frame_mode')
    cfg.transport.frame_mode = 'all';
    if isfield(cfg, 'statistics_frame_mode')
        cfg.transport.frame_mode = cfg.statistics_frame_mode;
    end
end
if ~isfield(cfg.transport, 'edge_buffer_cells'); cfg.transport.edge_buffer_cells = [0 0]; end
if ~isfield(cfg.transport, 'stress_fraction_floor'); cfg.transport.stress_fraction_floor = 1e-6; end
if ~isfield(cfg.transport, 'profile_x_range_mm')
    cfg.transport.profile_x_range_mm = [80 320];
end
source = cfg.transport.source;
if strcmp(source, 'postproc')
    cache_file = case_paths.sequence_cache_postproc;
else
    cache_file = case_paths.sequence_cache;
end
if ~isfile(cache_file)
    error('tblR2:section5:MissingCache', ...
        'Selected source cache is missing: %s. 请在 Section 1 compute 或读取匹配的所选源缓存。', cache_file);
end
% Section 5 may be run directly after Section 0. Keep the formal entry gate
% here, rather than imposing it on transport_analysis/transport_statistics,
% which also serve explicitly configured short synthetic/sample checks.
if ~all(isfield(cfg, {'n_frames', 'formal_required_frames', 'allow_debug_snapshot'}))
    error('tblR2:section5:MissingFramePolicy', ...
        ['Section 5 需要 cfg.n_frames、formal_required_frames 和 ' ...
         'allow_debug_snapshot；请先运行本 case 的 Section 0。']);
end
validateattributes(cfg.formal_required_frames, {'numeric'}, ...
    {'scalar', 'finite', 'integer', 'positive'}, mfilename, 'cfg.formal_required_frames');
validateattributes(cfg.allow_debug_snapshot, {'numeric', 'logical'}, ...
    {'scalar', 'binary'}, mfilename, 'cfg.allow_debug_snapshot');
if ~cfg.allow_debug_snapshot && cfg.n_frames < cfg.formal_required_frames
    error('tblR2:section5:InsufficientFormalFrames', ...
        ['Section 5 正式运行每个 repeat 需要至少 %d 帧，cfg.n_frames=%d。' ...
         '请恢复正式参数并在 Section 1 compute 或读取匹配的所选源缓存。'], ...
        cfg.formal_required_frames, cfg.n_frames);
end
% Read-only: inspect only the selected cache once; no DAT access and no
% requirement for the other source cache. Mismatches stop before result I/O.
tblR2.validate_sequence_cache(cache_file, cfg, source);
paths = tblR2.build_paths(fullfile(case_paths.root, 'section5', source));
contract = provenance(cache_file, cfg);
if strcmp(stage, 'reuse')
    result = tblR2.load_result(paths.transport, cfg, 'transport');
    if ~isfield(result, 'provenance') || ~isequaln(result.provenance, contract)
        error('tblR2:section5:StaleResult', ...
            'Section 5 source, parameters or implementation changed. Run compute for this source.');
    end
else
    fprintf('[Section 5] %s | %s | computing source-consistent statistics\n', cfg.case_id, source);
    result = tblR2.transport_analysis(cache_file, cfg);
    if ~any(result.calculation_mask(:))
        error('tblR2:section5:NoAcceptedData', 'No grid points meet the configured Section 5 support and edge criteria.');
    end
    result.provenance = contract;
    result.output_dir = paths.root;
    result.created_utc = char(datetime('now', 'TimeZone', 'UTC', ...
        'Format', 'yyyy-MM-dd''T''HH:mm:ssXXX'));
    check_closure(result.diagnostics);
    temporary = [tempname(paths.mat) '.mat'];
    cleanup = onCleanup(@() remove_temporary(temporary));
    tblR2.save_result(temporary, result, cfg, 'transport');
    [ok, message] = movefile(temporary, paths.transport, 'f');
    if ~ok; error('tblR2:section5:SaveFailed', '%s', message); end
    clear cleanup;
end
output = struct('files', {{}}, 'figures', gobjects(0,1), 'role', source);
if render
    fprintf('[Section 5] %s | exporting figures and tables\n', source);
    output = tblR2.transport_figures(result, cfg, paths, 'export');
    report = struct('case_id', cfg.case_id, 'source_role', source, ...
        'created_utc', result.created_utc, 'scope', result.scope, ...
        'diagnostics', result.diagnostics, 'provenance', result.provenance, ...
        'files', {output.files});
    filename = fullfile(paths.json, 'section5_review.json');
    fid = fopen(filename, 'w', 'n', 'UTF-8');
    if fid < 0; error('tblR2:section5:ReportWriteFailed', 'Cannot write %s.', filename); end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(report, 'PrettyPrint', true));
    clear cleanup;
    fprintf('[Section 5] delivered %d files: %s\n', numel(output.files), paths.root);
end
end

function contract = provenance(cache_file, cfg)
info = dir(cache_file);
small = load(cache_file, 'cache_meta');
contract = struct('schema_version', 2, 'cache_file', cache_file, ...
    'cache_bytes', info.bytes, 'cache_modified_datenum', info.datenum, ...
    'cache_meta', rmfield_if_present(small.cache_meta, 'repeat_means'), ...
    'case_type', cfg.case_type, 'fs', cfg.fs, 'min_valid_fraction', cfg.min_valid_fraction, ...
    'transport', cfg.transport, 'friction', cfg.friction);
if isfield(cfg, 'statistics_frame_mode'); contract.frame_mode = cfg.statistics_frame_mode; end
if strcmp(cfg.case_type, 'controlled'); contract.phase = cfg.phase; end
names = {'transport_statistics', 'transport_analysis', 'quadrant_streaming', ...
    'read_cache_chunk', 'read_cache_frames', 'assign_phase', ...
    'gradient_y_sensitivity', 'buffer_valid_mask', 'stats.quadrant_mask'};
digest = java.security.MessageDigest.getInstance('SHA-256');
for k = 1:numel(names)
    filename = which(['tblR2.' names{k}]);
    digest.update(unicode2native(fileread(filename), 'UTF-8'));
end
bytes = typecast(digest.digest(), 'uint8');
contract.implementation_sha256 = lower(reshape(dec2hex(bytes, 2).', 1, []));
end

function value = rmfield_if_present(value, name)
if isfield(value, name); value = rmfield(value, name); end
end

function check_closure(diagnostics)
names = fieldnames(diagnostics);
for k = 1:numel(names)
    d = diagnostics.(names{k});
    if isstruct(d) && isfield(d, 'relative_rms') && ...
            isfinite(d.relative_rms) && d.relative_rms > 1e-9 && d.max_abs > 1e-10
        error('tblR2:section5:ClosureFailed', '%s failed: relative RMS %.3g.', names{k}, d.relative_rms);
    end
end
end

function remove_temporary(filename)
if isfile(filename); delete(filename); end
end
