function phase = assign_phase(varargin)
%ASSIGN_PHASE 按帧时钟为受控工况分配相对相位和相位箱。
% 数值实现保存在本工况专用的 +tblR2 核心函数库中。

frame_ids = varargin{1};
fs = varargin{2};
f0_hz = varargin{3};
n_bins = varargin{4};
if numel(varargin) >= 5; phi0_user_deg = varargin{5}; else; phi0_user_deg = []; end
if ~(isnumeric(frame_ids) && isvector(frame_ids) && ~isempty(frame_ids) && ...
        all(isfinite(frame_ids)) && all(frame_ids == fix(frame_ids)) && all(frame_ids >= 1))
    error('tblR2:assign_phase:InvalidFrameIds', ...
        'frame_ids 必须是正整数源帧编号。');
end
if ~(isscalar(fs) && isfinite(fs) && fs > 0 && isscalar(f0_hz) && ...
        isfinite(f0_hz) && f0_hz > 0 && f0_hz < fs/2)
    error('tblR2:assign_phase:InvalidFrequency', ...
        '必须满足 fs>0 且 0<f0_hz<fs/2。');
end
if ~(isscalar(n_bins) && n_bins == fix(n_bins) && n_bins >= 2)
    error('tblR2:assign_phase:InvalidBinCount', ...
        'n_bins 必须是大于等于 2 的整数。');
end
if ~(isempty(phi0_user_deg) || (isscalar(phi0_user_deg) && isfinite(phi0_user_deg)))
    error('tblR2:assign_phase:InvalidMechanicalOffset', ...
        'phi0_user_deg 必须为空或有限标量角度。');
end
frame_ids = double(frame_ids(:));
phi_relative_deg = mod((frame_ids - 1) .* (360*f0_hz/fs), 360);
bin_center_relative_deg = (0:n_bins-1)' .* (360/n_bins);
distance = abs(mod(phi_relative_deg-bin_center_relative_deg'+180,360)-180);
[~, bin_index] = min(distance, [], 2);
samples_per_cycle = fs/f0_hz;
if abs(samples_per_cycle-round(samples_per_cycle)) <= 64*eps(max(1,samples_per_cycle))
    samples_per_cycle = round(samples_per_cycle);
    cycle_index = floor((frame_ids-1)./samples_per_cycle)+1;
    assignment_mode = 'exact_frame_clock';
else
    cycle_index = floor((frame_ids-1).*f0_hz./fs)+1;
    assignment_mode = 'nearest_angular_bin';
end
if isempty(phi0_user_deg)
    phi_mechanical_deg = nan(size(phi_relative_deg));
    bin_center_mechanical_deg = nan(size(bin_center_relative_deg));
    mechanical_status = 'not_calibrated';
else
    phi_mechanical_deg = mod(phi_relative_deg+phi0_user_deg,360);
    bin_center_mechanical_deg = mod(bin_center_relative_deg+phi0_user_deg,360);
    mechanical_status = 'user_offset_applied';
end
phase = struct('frame_ids',frame_ids,'phi_relative_deg',phi_relative_deg, ...
    'phi_mechanical_deg',phi_mechanical_deg,'bin_index',bin_index, ...
    'cycle_index',cycle_index,'bin_center_relative_deg',bin_center_relative_deg, ...
    'bin_center_mechanical_deg',bin_center_mechanical_deg, ...
    'phi0_user_deg',phi0_user_deg,'assignment_mode',assignment_mode, ...
    'mechanical_status',mechanical_status,'samples_per_cycle',samples_per_cycle, ...
    'definition',['相位仅由帧时钟分配，不进行数据驱动的相位反演。']);
end
