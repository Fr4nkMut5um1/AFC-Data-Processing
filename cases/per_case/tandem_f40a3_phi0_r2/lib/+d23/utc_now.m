function value = utc_now()
%UTC_NOW ISO-8601 UTC timestamp.
value = char(datetime('now', 'TimeZone', 'UTC', ...
    'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z'''));
end
