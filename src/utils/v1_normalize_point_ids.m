function ids = v1_normalize_point_ids(v,label)
% Convert numeric and P-prefixed point IDs to a column of positive integers.

if isnumeric(v)
    ids = double(v(:));
else
    s = upper(strtrim(string(v)));
    s = regexprep(s,'^P','');
    ids = str2double(s(:));
end

assert(all(isfinite(ids)), ...
    '%s Point IDs must be numeric or P-prefixed numeric labels.',label);

assert(all(ids>0 & ids==floor(ids)), ...
    '%s Point IDs must be positive integers.',label);

end
