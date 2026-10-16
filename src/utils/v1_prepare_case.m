function v1_prepare_case(caseName)
% v1_prepare_case
%
% Generic preflight validation for a V1 case.
%
% Checks:
%   - case_config.m
%   - Epoch-1 / Epoch-2 rasters exist
%   - projected/metric CRS can be verified
%   - raster CRS agreement
%   - raster overlap
%   - trusted_correspondences.csv schema and uniqueness
%   - source_points.csv schema and uniqueness
%   - trusted/source Point IDs do not overlap
%   - case_metadata.csv and positive interval
%
% Creates only required output directories. It does not modify user inputs.

if nargin < 1 || strlength(string(caseName))==0
    error('Provide a case name.');
end

caseName = char(string(caseName));

thisFile = mfilename('fullpath');
utilsDir = fileparts(thisFile);
srcDir = fileparts(utilsDir);
v1Root = fileparts(srcDir);

caseRoot = fullfile(v1Root,'cases',caseName);
configFile = fullfile(caseRoot,'case_config.m');

inputRoot = fullfile(caseRoot,'input');

trustedCSV = fullfile( ...
    inputRoot,'trusted_correspondences.csv');

sourceCSV = fullfile( ...
    inputRoot,'source_points.csv');

metadataCSV = fullfile( ...
    inputRoot,'case_metadata.csv');

assert(isfolder(caseRoot), ...
    'Case folder not found: %s',caseRoot);

assert(isfile(configFile), ...
    'Missing case_config.m: %s',configFile);

clear cfg;
run(configFile);

assert(exist('cfg','var')==1 && isstruct(cfg), ...
    'case_config.m must create a struct named cfg.');

assert(strcmp(char(string(cfg.case_name)),caseName), ...
    'cfg.case_name does not match requested case.');

requiredCfg = {'epoch1','epoch2','expected_crs'};

assert(all(isfield(cfg,requiredCfg)), ...
    'case_config.m is missing required case fields.');

f1 = char(string(cfg.epoch1.raster));
f2 = char(string(cfg.epoch2.raster));

assert(isfile(f1), ...
    'Epoch-1 raster not found: %s',f1);

assert(isfile(f2), ...
    'Epoch-2 raster not found: %s',f2);

assert(isfile(trustedCSV), ...
    'Missing trusted_correspondences.csv: %s',trustedCSV);

assert(isfile(sourceCSV), ...
    'Missing source_points.csv: %s',sourceCSV);

assert(isfile(metadataCSV), ...
    'Missing case_metadata.csv: %s',metadataCSV);

%% Raster / CRS checks.

info1 = georasterinfo(f1);
info2 = georasterinfo(f2);

R1 = info1.RasterReference;
R2 = info2.RasterReference;

assert(~isempty(info1.CoordinateReferenceSystem), ...
    'Epoch-1 raster has no readable CRS.');

assert(~isempty(info2.CoordinateReferenceSystem), ...
    'Epoch-2 raster has no readable CRS.');

verify_metric_crs( ...
    info1.CoordinateReferenceSystem, ...
    cfg.expected_crs, ...
    'Epoch 1');

verify_metric_crs( ...
    info2.CoordinateReferenceSystem, ...
    cfg.expected_crs, ...
    'Epoch 2');

sig1 = crs_signature(info1.CoordinateReferenceSystem);
sig2 = crs_signature(info2.CoordinateReferenceSystem);

assert(strcmp(sig1,sig2), ...
    'Epoch rasters do not have the same projected CRS.');

% Common map overlap.
xmin = max(R1.XWorldLimits(1),R2.XWorldLimits(1));
xmax = min(R1.XWorldLimits(2),R2.XWorldLimits(2));

ymin = max(R1.YWorldLimits(1),R2.YWorldLimits(1));
ymax = min(R1.YWorldLimits(2),R2.YWorldLimits(2));

assert(xmax>xmin && ymax>ymin, ...
    'Epoch rasters have no common map overlap.');

%% CSV checks.

Trusted = readtable(trustedCSV,'TextType','string');
Source = readtable(sourceCSV,'TextType','string');
Meta = readtable(metadataCSV,'TextType','string');

requiredTrusted = { ...
    'Point', ...
    'Epoch1_X', ...
    'Epoch1_Y', ...
    'Epoch2_X', ...
    'Epoch2_Y'};

requiredSource = { ...
    'Point', ...
    'Epoch1_X', ...
    'Epoch1_Y'};

assert(all(ismember(requiredTrusted,Trusted.Properties.VariableNames)), ...
    'trusted_correspondences.csv has an unexpected schema.');

assert(all(ismember(requiredSource,Source.Properties.VariableNames)), ...
    'source_points.csv has an unexpected schema.');

assert(height(Trusted)>=3, ...
    'V1 propagation requires at least 3 trusted correspondences.');

assert(height(Source)>=1, ...
    'source_points.csv contains no points to propagate.');

assert(numel(unique(Trusted.Point))==height(Trusted), ...
    'Trusted Point IDs are not unique.');

assert(numel(unique(Source.Point))==height(Source), ...
    'Source Point IDs are not unique.');

assert(isempty(intersect(Trusted.Point,Source.Point)), ...
    'Point IDs overlap between trusted and source-only inputs.');

trustedCoords = Trusted{:,requiredTrusted(2:5)};
sourceCoords = Source{:,requiredSource(2:3)};

assert(all(isfinite(trustedCoords(:))), ...
    'Trusted correspondence coordinates contain non-finite values.');

assert(all(isfinite(sourceCoords(:))), ...
    'Source coordinates contain non-finite values.');

assert(height(Meta)==1, ...
    'case_metadata.csv must contain exactly one row.');

assert(ismember('dtDays',Meta.Properties.VariableNames) && ...
       ismember('dtYears',Meta.Properties.VariableNames), ...
    'case_metadata.csv must contain dtDays and dtYears.');

assert(isfinite(Meta.dtDays(1)) && Meta.dtDays(1)>0, ...
    'Invalid dtDays.');

assert(isfinite(Meta.dtYears(1)) && Meta.dtYears(1)>0, ...
    'Invalid dtYears.');

%% Output root.

% Progressive matching, finalization, and analysis stages create their own
% stage directories when needed. PREPARE only guarantees the case output
% root exists; it does not create obsolete or unused stage folders.
outputRoot = fullfile(caseRoot,'output');

if ~isfolder(outputRoot)
    mkdir(outputRoot);
end

%% Report.

fprintf('\n============================================================\n');
fprintf(' V1 CASE PREFLIGHT PASSED\n');
fprintf('============================================================\n');

fprintf('Case:                    %s\n',caseName);
fprintf('Epoch 1:                 %s\n',string(cfg.epoch1.name));
fprintf('Epoch 2:                 %s\n',string(cfg.epoch2.name));
fprintf('CRS:                     %s\n',sig1);

fprintf('\nEpoch-1 raster:\n');
fprintf('  rows x cols:           %d x %d\n', ...
    R1.RasterSize(1),R1.RasterSize(2));
fprintf('  pixel size:            %.6f x %.6f m\n', ...
    R1.CellExtentInWorldX,R1.CellExtentInWorldY);

fprintf('\nEpoch-2 raster:\n');
fprintf('  rows x cols:           %d x %d\n', ...
    R2.RasterSize(1),R2.RasterSize(2));
fprintf('  pixel size:            %.6f x %.6f m\n', ...
    R2.CellExtentInWorldX,R2.CellExtentInWorldY);

fprintf('\nCommon overlap:\n');
fprintf('  X: %.3f to %.3f m\n',xmin,xmax);
fprintf('  Y: %.3f to %.3f m\n',ymin,ymax);

fprintf('\nInputs:\n');
fprintf('  trusted correspondences: %d\n',height(Trusted));
fprintf('  source-only points:       %d\n',height(Source));
fprintf('  interval:                 %.0f days = %.6f yr\n', ...
    Meta.dtDays(1),Meta.dtYears(1));

fprintf('\n============================================================\n');

end

%% ============================================================
% LOCAL FUNCTIONS
% ============================================================

function verify_metric_crs(crs,expectedCRS,label)

sig = crs_signature(crs);

expectedCRS = char(string(expectedCRS));

if startsWith(upper(expectedCRS),'EPSG:')

    expectedCode = str2double(extractAfter(string(expectedCRS),'EPSG:'));

    assert(isfinite(expectedCode), ...
        'Invalid cfg.expected_crs value.');

    actualCode = resolved_epsg_code(crs);

    assert(isfinite(actualCode), ...
        ['%s CRS EPSG code could not be verified. ' ...
         'Readable CRS name: %s'], ...
        label,sig);

    assert(actualCode==expectedCode, ...
        '%s CRS mismatch: expected %s, found %s.', ...
        label,expectedCRS,sig);
end

unit = "";

if isprop(crs,'LengthUnit')
    unit = lower(string(crs.LengthUnit));
end

assert(strlength(unit)>0, ...
    '%s CRS linear unit could not be verified.',label);

assert(contains(unit,'met'), ...
    '%s CRS is not metric. Length unit: %s',label,unit);

end

function sig = crs_signature(crs)

code = resolved_epsg_code(crs);
nameText = "";

if isprop(crs,'Name')
    nameText = string(crs.Name);
end

if isfinite(code)
    sig = char("EPSG:" + string(code));
elseif strlength(nameText)>0
    sig = char(nameText);
else
    error('Could not construct CRS signature.');
end

end

function code = resolved_epsg_code(crs)
% Resolve EPSG directly when available, or from an unambiguous supported
% WGS 84 / UTM CRS name when MATLAB omits the public Code property.

code = NaN;

if isprop(crs,'Code')
    try
        c = double(crs.Code);
        if isscalar(c) && isfinite(c)
            code = c;
            return;
        end
    catch
    end
end

if ~isprop(crs,'Name')
    return;
end

name = strtrim(char(string(crs.Name)));

tok = regexp( ...
    name, ...
    '^WGS\s*84\s*/\s*UTM\s*zone\s*(\d{1,2})\s*([NS])$', ...
    'tokens','once','ignorecase');

if isempty(tok)
    return;
end

zone = str2double(tok{1});
hemisphere = upper(tok{2});

if ~isfinite(zone) || zone < 1 || zone > 60 || zone ~= floor(zone)
    return;
end

if strcmp(hemisphere,'N')
    code = 32600 + zone;
elseif strcmp(hemisphere,'S')
    code = 32700 + zone;
end

end
