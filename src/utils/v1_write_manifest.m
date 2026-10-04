function Manifest = v1_write_manifest(caseName)
% v1_write_manifest
%
% Write a reproducibility manifest for one V1 case.
%
% The manifest records:
%   - V1 VERSION
%   - UTC creation time
%   - MATLAB release/version
%   - installed toolbox versions
%   - platform
%   - case / epoch metadata
%   - raster dimensions, GSD, bounds and CRS
%   - SHA-256 checksums for case config, rasters and input CSV files
%   - configured random seeds
%   - Git commit when available
%
% Output:
%   cases/<caseName>/output/00_manifest/
%       manifest.json
%       manifest.txt
%
% NOTE:
%   Hashing multi-GB rasters can take several minutes.

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

trustedCSV = fullfile( ...
    caseRoot,'input','trusted_correspondences.csv');

sourceCSV = fullfile( ...
    caseRoot,'input','source_points.csv');

metadataCSV = fullfile( ...
    caseRoot,'input','case_metadata.csv');

versionFile = fullfile(v1Root,'VERSION');

assert(isfile(configFile),'Missing case config.');
assert(isfile(trustedCSV),'Missing trusted correspondences.');
assert(isfile(sourceCSV),'Missing source points.');
assert(isfile(metadataCSV),'Missing case metadata.');
assert(isfile(versionFile),'Missing VERSION file.');

clear cfg;
run(configFile);

v1_prepare_case(caseName);

f1 = char(string(cfg.epoch1.raster));
f2 = char(string(cfg.epoch2.raster));

info1 = georasterinfo(f1);
info2 = georasterinfo(f2);

R1 = info1.RasterReference;
R2 = info2.RasterReference;

Meta = readtable(metadataCSV,'TextType','string');

V = ver;

Toolboxes = repmat(struct('name','','version',''),numel(V),1);

for i = 1:numel(V)
    Toolboxes(i).name = V(i).Name;
    Toolboxes(i).version = V(i).Version;
end

Manifest = struct;

Manifest.schema = 'V1_manifest_1';
Manifest.v1_version = strtrim(fileread(versionFile));
Manifest.created_utc = char(datetime('now','TimeZone','UTC', ...
    'Format','yyyy-MM-dd''T''HH:mm:ssXXX'));

Manifest.matlab = struct;
Manifest.matlab.version = version;
Manifest.matlab.release = version('-release');
Manifest.matlab.computer = computer;
Manifest.matlab.toolboxes = Toolboxes;

Manifest.case = struct;
Manifest.case.name = caseName;
Manifest.case.epoch1_name = char(string(cfg.epoch1.name));
Manifest.case.epoch2_name = char(string(cfg.epoch2.name));
Manifest.case.expected_crs = char(string(cfg.expected_crs));
Manifest.case.dt_days = Meta.dtDays(1);
Manifest.case.dt_years = Meta.dtYears(1);

Manifest.epoch1_raster = raster_record(f1,info1,R1);
Manifest.epoch2_raster = raster_record(f2,info2,R2);

fprintf('\nComputing SHA-256 checksums...\n');
fprintf('This may take several minutes for large rasters.\n\n');

Manifest.files = struct;

Manifest.files.case_config = file_record(configFile);
Manifest.files.trusted_correspondences = file_record(trustedCSV);
Manifest.files.source_points = file_record(sourceCSV);
Manifest.files.case_metadata = file_record(metadataCSV);
Manifest.files.epoch1_raster = file_record(f1);
Manifest.files.epoch2_raster = file_record(f2);

Manifest.random_seeds = collect_random_seeds(cfg);
Manifest.git_commit = git_commit(v1Root);

outRoot = fullfile(caseRoot,'output','00_manifest');

if ~isfolder(outRoot)
    mkdir(outRoot);
end

jsonFile = fullfile(outRoot,'manifest.json');
textFile = fullfile(outRoot,'manifest.txt');

jsonText = jsonencode(Manifest,'PrettyPrint',true);

fid = fopen(jsonFile,'w');
assert(fid~=-1,'Could not write manifest.json.');
cleanup1 = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonText);
clear cleanup1;

fid = fopen(textFile,'w');
assert(fid~=-1,'Could not write manifest.txt.');
cleanup2 = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid,'V1 REPRODUCIBILITY MANIFEST\n');
fprintf(fid,'===========================\n\n');
fprintf(fid,'Version:        %s\n',Manifest.v1_version);
fprintf(fid,'Created UTC:    %s\n',Manifest.created_utc);
fprintf(fid,'Case:           %s\n',Manifest.case.name);
fprintf(fid,'Epoch pair:     %s -> %s\n', ...
    Manifest.case.epoch1_name,Manifest.case.epoch2_name);
fprintf(fid,'Interval:       %.0f days = %.6f yr\n', ...
    Manifest.case.dt_days,Manifest.case.dt_years);
fprintf(fid,'CRS:            %s\n',Manifest.case.expected_crs);
fprintf(fid,'MATLAB release: R%s\n',Manifest.matlab.release);
fprintf(fid,'MATLAB version: %s\n',Manifest.matlab.version);
fprintf(fid,'Git commit:     %s\n',Manifest.git_commit);

fprintf(fid,'\nEpoch 1 raster\n');
fprintf(fid,'--------------\n');
write_raster_text(fid,Manifest.epoch1_raster);

fprintf(fid,'\nEpoch 2 raster\n');
fprintf(fid,'--------------\n');
write_raster_text(fid,Manifest.epoch2_raster);

fprintf(fid,'\nSHA-256\n');
fprintf(fid,'-------\n');
fprintf(fid,'case_config.m:                %s\n', ...
    Manifest.files.case_config.sha256);
fprintf(fid,'trusted_correspondences.csv:  %s\n', ...
    Manifest.files.trusted_correspondences.sha256);
fprintf(fid,'source_points.csv:            %s\n', ...
    Manifest.files.source_points.sha256);
fprintf(fid,'case_metadata.csv:            %s\n', ...
    Manifest.files.case_metadata.sha256);
fprintf(fid,'epoch1 raster:                %s\n', ...
    Manifest.files.epoch1_raster.sha256);
fprintf(fid,'epoch2 raster:                %s\n', ...
    Manifest.files.epoch2_raster.sha256);

fprintf(fid,'\nRandom seeds\n');
fprintf(fid,'------------\n');

seedNames = fieldnames(Manifest.random_seeds);

for i = 1:numel(seedNames)
    fprintf(fid,'%s: %s\n',seedNames{i}, ...
        string(Manifest.random_seeds.(seedNames{i})));
end

clear cleanup2;

fprintf('\nManifest written:\n%s\n',jsonFile);
fprintf('%s\n',textFile);

end

%% ============================================================
% LOCAL FUNCTIONS
% ============================================================

function R = raster_record(filename,info,ref)

d = dir(filename);

R = struct;
R.path = filename;
R.bytes = d.bytes;
R.modified = d.date;
R.rows = ref.RasterSize(1);
R.cols = ref.RasterSize(2);
R.pixel_size_x_m = ref.CellExtentInWorldX;
R.pixel_size_y_m = ref.CellExtentInWorldY;
R.x_world_limits = ref.XWorldLimits;
R.y_world_limits = ref.YWorldLimits;
R.crs_name = char(string(info.CoordinateReferenceSystem.Name));
R.length_unit = char(string(info.CoordinateReferenceSystem.LengthUnit));

end

function F = file_record(filename)

d = dir(filename);

F = struct;
F.path = filename;
F.bytes = d.bytes;
F.modified = d.date;
F.sha256 = sha256_file(filename);

end

function S = collect_random_seeds(cfg)

S = struct;

if isfield(cfg,'strain') && isfield(cfg.strain,'bootstrap_rng_seed')
    S.stage7_bootstrap = cfg.strain.bootstrap_rng_seed;
end

if isfield(cfg,'robustness') && isfield(cfg.robustness,'mc_rng_seed')
    S.stage8_monte_carlo = cfg.robustness.mc_rng_seed;
end

end

function commit = git_commit(root)

commit = 'not_available';

cmd = sprintf('git -C "%s" rev-parse HEAD',root);

[status,out] = system(cmd);

if status==0
    out = strtrim(out);

    if ~isempty(regexp(out,'^[0-9a-fA-F]{40}$','once'))
        commit = out;
    end
end

end

function h = sha256_file(filename)

if ispc

    cmd = sprintf('certutil -hashfile "%s" SHA256',filename);

elseif isunix

    cmd = sprintf('sha256sum "%s"',filename);

else

    error('No SHA-256 command configured for this operating system.');
end

[status,out] = system(cmd);

assert(status==0, ...
    'SHA-256 command failed for: %s',filename);

tokens = regexp(out,'(?i)\b[0-9a-f]{64}\b','match');

assert(~isempty(tokens), ...
    'Could not parse SHA-256 output for: %s',filename);

h = lower(tokens{1});

end

function write_raster_text(fid,R)

fprintf(fid,'Path:       %s\n',R.path);
fprintf(fid,'Bytes:      %.0f\n',R.bytes);
fprintf(fid,'Rows x cols:%d x %d\n',R.rows,R.cols);
fprintf(fid,'Pixel size: %.9f x %.9f m\n', ...
    R.pixel_size_x_m,R.pixel_size_y_m);
fprintf(fid,'X limits:   %.6f %.6f\n',R.x_world_limits);
fprintf(fid,'Y limits:   %.6f %.6f\n',R.y_world_limits);
fprintf(fid,'CRS:        %s\n',R.crs_name);
fprintf(fid,'Unit:       %s\n',R.length_unit);

end
