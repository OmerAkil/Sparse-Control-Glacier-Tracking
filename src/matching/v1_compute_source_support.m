function Support = v1_compute_source_support(cfg,TrustedTable,SourceTable)
% v1_compute_source_support
%
% Lightweight spatial-support diagnostics for progressive propagation.
%
% IMPORTANT:
%   - This function performs NO image matching.
%   - It uses only Epoch-1 coordinates plus the current trusted set.
%   - It is intentionally cheap enough to rerun after every accepted point.
%
% For each remaining source point it reports:
%   d1/d2/d3                distances to the three nearest trusted controls
%   nearest trusted IDs     provenance of those controls
%   counts within 20/40/60m
%   effective IDW N         1/sum(w.^2), using the frozen Stage-1 IDW power
%   dominant IDW weight     largest normalized IDW weight
%   angular support         geometry of the three nearest trusted controls
%   inside trusted hull     interpolation (true) vs extrapolation (false)
%
% No Epoch-2 source truth is read.

requiredTrusted = { ...
    'Point','Epoch1_X','Epoch1_Y','Epoch2_X','Epoch2_Y'};

requiredSource = { ...
    'Point','Epoch1_X','Epoch1_Y'};

assert(istable(TrustedTable), ...
    'TrustedTable must be a MATLAB table.');

assert(istable(SourceTable), ...
    'SourceTable must be a MATLAB table.');

assert(all(ismember(requiredTrusted,TrustedTable.Properties.VariableNames)), ...
    'TrustedTable has an invalid schema.');

assert(all(ismember(requiredSource,SourceTable.Properties.VariableNames)), ...
    'SourceTable has an invalid schema.');

assert(height(TrustedTable)>=3, ...
    'At least 3 trusted correspondences are required for support ranking.');

trustedIDs = normalize_point_ids(TrustedTable.Point,'trusted');
sourceIDs = normalize_point_ids(SourceTable.Point,'source');

assert(numel(unique(trustedIDs))==height(TrustedTable), ...
    'Trusted Point IDs must be unique.');

assert(numel(unique(sourceIDs))==height(SourceTable), ...
    'Source Point IDs must be unique.');

assert(isempty(intersect(trustedIDs,sourceIDs)), ...
    'Trusted and source Point IDs must not overlap.');

Xtr = double(TrustedTable.Epoch1_X);
Ytr = double(TrustedTable.Epoch1_Y);

Xs = double(SourceTable.Epoch1_X);
Ys = double(SourceTable.Epoch1_Y);

idwPower = cfg.stage1.idw_power;

n = height(SourceTable);

Point = sourceIDs;
Epoch1_X = Xs;
Epoch1_Y = Ys;

NearestTrusted1 = nan(n,1);
NearestTrusted2 = nan(n,1);
NearestTrusted3 = nan(n,1);

D1_m = nan(n,1);
D2_m = nan(n,1);
D3_m = nan(n,1);

TrustedWithin20m = zeros(n,1);
TrustedWithin40m = zeros(n,1);
TrustedWithin60m = zeros(n,1);

EffectiveIDWN = nan(n,1);
DominantIDWWeight = nan(n,1);

MaxAngularGap3_deg = nan(n,1);
AngularCoverage3_deg = nan(n,1);

InsideTrustedHull = false(n,1);

% ------------------------------------------------------------
% Trusted convex hull, if the trusted geometry is truly 2-D.
% ------------------------------------------------------------

canUseHull = false;
hullX = [];
hullY = [];

XYtr = [Xtr Ytr];

if height(TrustedTable)>=3

    centered = XYtr-mean(XYtr,1);

    if rank(centered)>=2
        try
            k = convhull(Xtr,Ytr);
            hullX = Xtr(k);
            hullY = Ytr(k);
            canUseHull = true;
        catch
            canUseHull = false;
        end
    end
end

% ------------------------------------------------------------
% Per-source support diagnostics.
% ------------------------------------------------------------

for i = 1:n

    dx = Xtr-Xs(i);
    dy = Ytr-Ys(i);

    d = hypot(dx,dy);

    [ds,ord] = sort(d,'ascend');

    assert(numel(ds)>=3, ...
        'At least 3 trusted correspondences are required.');

    D1_m(i) = ds(1);
    D2_m(i) = ds(2);
    D3_m(i) = ds(3);

    NearestTrusted1(i) = trustedIDs(ord(1));
    NearestTrusted2(i) = trustedIDs(ord(2));
    NearestTrusted3(i) = trustedIDs(ord(3));

    TrustedWithin20m(i) = nnz(d<=20);
    TrustedWithin40m(i) = nnz(d<=40);
    TrustedWithin60m(i) = nnz(d<=60);

    % IDW support diagnostics.
    dSafe = max(d,1e-6);

    w = 1./(dSafe.^idwPower);
    w = w/sum(w);

    EffectiveIDWN(i) = 1/sum(w.^2);
    DominantIDWWeight(i) = max(w);

    % Geometry of the 3 nearest trusted controls around the source.
    idx3 = ord(1:3);

    ang = mod(atan2d( ...
        Ytr(idx3)-Ys(i), ...
        Xtr(idx3)-Xs(i)),360);

    ang = sort(ang(:));

    gaps = [
        diff(ang)
        ang(1)+360-ang(end)
    ];

    MaxAngularGap3_deg(i) = max(gaps);
    AngularCoverage3_deg(i) = ...
        360-MaxAngularGap3_deg(i);

    if canUseHull
        InsideTrustedHull(i) = inpolygon( ...
            Xs(i),Ys(i),hullX,hullY);
    end
end

Support = table( ...
    Point, ...
    Epoch1_X, ...
    Epoch1_Y, ...
    InsideTrustedHull, ...
    NearestTrusted1, ...
    D1_m, ...
    NearestTrusted2, ...
    D2_m, ...
    NearestTrusted3, ...
    D3_m, ...
    TrustedWithin20m, ...
    TrustedWithin40m, ...
    TrustedWithin60m, ...
    EffectiveIDWN, ...
    DominantIDWWeight, ...
    MaxAngularGap3_deg, ...
    AngularCoverage3_deg);

end

function ids = normalize_point_ids(v,label)

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
