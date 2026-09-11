function mapped = map_joint_modes(joint_modes, sequence)
%MAP_JOINT_MODES Map joint-vector modes back to the sampled XOY grid.

n_modes = size(joint_modes, 2);
n_spatial = sequence.n_spatial;
if n_modes < 1
    error('tblR2:map_joint_modes:NoModes', ...
        'joint_modes 至少必须包含一列模态。');
end
if size(joint_modes, 1) ~= 2 * n_spatial
    error('tblR2:map_joint_modes:SizeMismatch', ...
        '联合模态的行数必须等于 2*sequence.n_spatial。');
end
sub_size = size(sequence.spatial_mask);
U_modes = nan([n_modes sub_size]);
V_modes = nan([n_modes sub_size]);
for im = 1:n_modes
    U_field = nan(sub_size);
    V_field = nan(sub_size);
    U_field(sequence.spatial_mask) = joint_modes(1:n_spatial, im);
    V_field(sequence.spatial_mask) = joint_modes(n_spatial + 1:end, im);
    U_modes(im, :, :) = U_field;
    V_modes(im, :, :) = V_field;
end
mapped = struct('U', U_modes, 'V', V_modes, ...
    'X_mm', sequence.X_grid_mm, 'Y_mm', sequence.Y_grid_mm, ...
    'mask', sequence.spatial_mask, 'row_ids', sequence.row_ids, ...
    'col_ids', sequence.col_ids);
end
