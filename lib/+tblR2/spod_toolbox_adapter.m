function result = spod_toolbox_adapter(sequence, cfg)
%SPOD_TOOLBOX_ADAPTER Wrap the installed Towne/Schmidt spod.m into the cache contract.
%
% Contract: input X is a snapshots-by-joint-DOF matrix sampled at the
% constant stride of `sequence`. Welch blocks use a periodic Hann window of
% cfg.spod.nfft with cfg.spod.overlap_fraction overlap; n_blocks is the
% number of starting positions. Output eigenvalues is n_modes-by-n_frequency
% (rows = ranked modes, columns = physical frequency bins), frequency_hz is
% the one-sided physical frequency vector, and selected_modes are joint
% modes mapped back to the XOY grid at cfg.spod.selected_frequencies_hz
% (default: dominant non-DC bin, plus f0/2f0/3f0 for controlled cases).

tblR2.ensure_external_toolboxes(cfg, {'spod'});
X = double(sequence.X).';          % snapshots x joint DOF
n_samples = size(X, 1);
nfft = cfg.spod.nfft;
if nfft > n_samples
    error('tblR2:spod_toolbox_adapter:InsufficientSamples', ...
        'SPOD 的 nfft=%d 超过采样序列长度 %d。', nfft, n_samples);
end
overlap = floor(cfg.spod.overlap_fraction * nfft);
step = nfft - overlap;
starts = 1:step:(n_samples - nfft + 1);
n_blocks = numel(starts);
if n_blocks < 3
    error('tblR2:spod_toolbox_adapter:TooFewBlocks', ...
        'SPOD 至少需要三个 Welch 数据块；当前设置只能产生 %d 个。', ...
        n_blocks);
end

window = hann(nfft, 'periodic');
opts = struct();
opts.mean = zeros(size(X, 2), 1);
opts.isreal = true;
opts.nsave = min(cfg.spod.n_modes, n_blocks);
opts.savefft = false;
[L, P, F] = spod(X, window, [], overlap, sequence.dt_s, opts);

frequency_hz = F(:).';
n_frequency = numel(frequency_hz);
n_modes = min(cfg.spod.n_modes, size(P, 3));
eigenvalues = max(real(L).', 0);
if size(eigenvalues, 1) < n_modes
    eigenvalues(end + 1:n_modes, :) = 0;
end
if size(eigenvalues, 2) < n_frequency
    eigenvalues(:, end + 1:n_frequency) = 0;
end
eigenvalues = eigenvalues(1:n_modes, 1:n_frequency);

selected_requested = optional(cfg.spod, 'selected_frequencies_hz', []);
if isempty(selected_requested)
    if n_frequency > 2
        [~, dominant_index] = max(eigenvalues(1, 2:end));
        selected_requested = frequency_hz(dominant_index + 1);
    else
        selected_requested = frequency_hz(max(1, end));
    end
    if strcmp(cfg.case_type, 'controlled') && ~isempty(cfg.phase.f0_hz)
        selected_requested = unique([selected_requested, ...
            cfg.phase.f0_hz .* (1:3)]);
    end
end
selected_indices = zeros(numel(selected_requested), 1);
for i = 1:numel(selected_indices)
    [~, selected_indices(i)] = min(abs(frequency_hz - selected_requested(i)));
end
selected_indices = unique(selected_indices, 'stable');

selected_modes_joint = complex(zeros(size(X, 2), n_modes, numel(selected_indices)));
for isel = 1:numel(selected_indices)
    ifreq = selected_indices(isel);
    modes_at_frequency = squeeze(P(ifreq, :, 1:n_modes));
    if n_modes == 1
        modes_at_frequency = modes_at_frequency(:);
    end
    selected_modes_joint(:, :, isel) = modes_at_frequency;
end

mapped_cells = cell(numel(selected_indices), 1);
for isel = 1:numel(selected_indices)
    mapped_cells{isel} = tblR2.map_joint_modes( ...
        selected_modes_joint(:, :, isel), sequence);
end
mapped_modes = vertcat(mapped_cells{:});

result = struct();
result.frequency_hz = frequency_hz;
result.eigenvalues = eigenvalues;
result.selected_frequency_indices = selected_indices;
result.selected_frequency_hz = frequency_hz(selected_indices);
result.selected_modes = mapped_modes;
result.nfft = nfft;
result.overlap = overlap;
result.n_blocks = n_blocks;
result.effective_fs_hz = 1 / sequence.dt_s;
result.n_modes = n_modes;
result.sampling = sequence.sampling;
result.definition = ['Welch-block SPOD computed by the Towne/Schmidt spod.m ' ...
    'toolbox with Hann window, configured overlap, and no additional mean ' ...
    'removal beyond the already-fluctuating branch data.'];
end


function value = optional(s, name, default)
if isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = default;
end
end
