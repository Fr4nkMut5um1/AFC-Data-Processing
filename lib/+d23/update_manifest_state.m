function manifest = update_manifest_state(run_dir, manifest, state, detail)
%UPDATE_MANIFEST_STATE Atomically update run state.
manifest.state = char(state);
manifest.updated_utc = d23.utc_now();
if nargin >= 4 && ~isempty(detail)
    manifest.detail = detail;
end
d23.atomic_save(fullfile(run_dir, 'manifest.mat'), struct('manifest', manifest));
end
