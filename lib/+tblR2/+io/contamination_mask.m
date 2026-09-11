function invalid_mask = contamination_mask(X, Y, region, mode)
% CONTAMINATION_MASK Build the shared invalid mask for contamination data.
%   invalid_mask = tblR2.io.contamination_mask(X, Y, region, mode)
%
% region must be a scalar struct with finite scalar fields x_min, x_max,
% y_min, and y_max. The streamwise interval is always half-open:
% x_min <= x < x_max. Supported consumers are:
%   visualization - mask only y_min <= y <= y_max inside that interval
%   drag          - mask every y location inside that interval

    if ~isequal(size(X), size(Y))
        error('tblR2:io:contamination_mask:SizeMismatch', ...
            'X 和 Y 必须具有相同尺寸。');
    end
    if ~isnumeric(X) || ~isreal(X) || ~isnumeric(Y) || ~isreal(Y)
        error('tblR2:io:contamination_mask:InvalidCoordinates', ...
            'X 和 Y 必须是实数数值数组。');
    end

    validate_region(region);
    mode = normalize_mode(mode);

    in_streamwise_region = X >= region.x_min & X < region.x_max;
    switch mode
        case 'visualization'
            invalid_mask = in_streamwise_region & ...
                Y >= region.y_min & Y <= region.y_max;
        case 'drag'
            invalid_mask = in_streamwise_region;
    end
    invalid_mask = logical(invalid_mask);
end


function validate_region(region)
    required_fields = {'x_min', 'x_max', 'y_min', 'y_max'};
    is_valid = isstruct(region) && isscalar(region) && ...
        all(isfield(region, required_fields));

    if is_valid
        for iField = 1:numel(required_fields)
            value = region.(required_fields{iField});
            if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
                    ~isfinite(value)
                is_valid = false;
                break;
            end
        end
    end

    if is_valid
        is_valid = region.x_min < region.x_max && ...
            region.y_min < region.y_max;
    end

    if ~is_valid
        error('tblR2:io:contamination_mask:InvalidRegion', ...
            ['region 必须是标量结构体，包含有限标量 x_min、x_max、y_min、y_max，' ...
             '且边界必须严格递增。']);
    end
end


function mode = normalize_mode(mode)
    if isstring(mode) && isscalar(mode)
        mode = char(mode);
    end
    if ~ischar(mode) || ~isrow(mode) || ...
            ~any(strcmp(mode, {'visualization', 'drag'}))
        error('tblR2:io:contamination_mask:UnknownMode', ...
            'mode 必须是 ''visualization'' 或 ''drag''。');
    end
end
