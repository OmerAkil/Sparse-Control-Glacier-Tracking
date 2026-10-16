function state = v1_progressive_initialize(caseName)
% v1_progressive_initialize
%
% Initialize a progressive matching session for one V1.2 case.
%
% This function:
%   - copies the immutable initial trusted set into working_trusted.csv
%   - copies source points into source_status.csv with Status="remaining"
%   - creates an empty progression_log.csv
%   - creates progressive_state.mat
%
% It does NOT run image matching and does NOT alter the input CSV files.
%
% Output root:
%   cases/<case>/output/01_progressive_matching/

if nargin < 1 || strlength(string(caseName))==0
    error('Provide a case name.');
end

caseName = char(string(caseName));

thisFile = mfilename('fullpath');
matchingDir = fileparts(thisFile);
srcDir = fileparts(matchingDir);
v1Root = fileparts(srcDir);

caseRoot = fullfile(v1Root,'cases',caseName);
configFile = fullfile(caseRoot,'case_config.m');

trustedCSV = fullfile(caseRoot,'input','trusted_correspondences.csv');
sourceCSV = fullfile(caseRoot,'input','source_points.csv');

outRoot = fullfile(caseRoot,'output','01_progressive_matching');
pointsRoot = fullfile(outRoot,'point_results');

workingTrustedCSV = fullfile(outRoot,'working_trusted.csv');
sourceStatusCSV = fullfile(outRoot,'source_status.csv');
progressionLogCSV = fullfile(outRoot,'progression_log.csv');
stateMat = fullfile(outRoot,'progressive_state.mat');

assert(isfolder(caseRoot),'Case folder not found: %s',caseRoot);
assert(isfile(configFile),'Missing case_config.m.');
assert(isfile(trustedCSV),'Missing trusted_correspondences.csv.');
assert(isfile(sourceCSV),'Missing source_points.csv.');

assert(~isfolder(outRoot), ...
    ['A progressive session already exists for this case:\n%s\n' ...
     'Do not overwrite it. Resume the existing session instead.'], ...
    outRoot);

cfg = struct(); %#ok<NASGU>
run(configFile);

Trusted = readtable(trustedCSV,'TextType','string');
Source = readtable(sourceCSV,'TextType','string');

requiredTrusted = { ...
    'Point','Epoch1_X','Epoch1_Y','Epoch2_X','Epoch2_Y'};
requiredSource = {'Point','Epoch1_X','Epoch1_Y'};

assert(all(ismember(requiredTrusted,Trusted.Properties.VariableNames)), ...
    'trusted_correspondences.csv has an invalid schema.');

assert(all(ismember(requiredSource,Source.Properties.VariableNames)), ...
    'source_points.csv has an invalid schema.');

trustedIDs = normalize_point_ids(Trusted.Point,'trusted');
sourceIDs = normalize_point_ids(Source.Point,'source');

assert(numel(unique(trustedIDs))==height(Trusted), ...
    'Trusted IDs must be unique.');
assert(numel(unique(sourceIDs))==height(Source), ...
    'Source IDs must be unique.');
assert(isempty(intersect(trustedIDs,sourceIDs)), ...
    'Trusted and source IDs must not overlap.');

% Internally normalize Point IDs to numeric values. Input files remain
% untouched.
Trusted.Point = trustedIDs;
Source.Point = sourceIDs;

mkdir(outRoot);
mkdir(pointsRoot);

% Working trusted set starts as an exact coordinate copy of the immutable
% initial trusted set.
WorkingTrusted = Trusted;
WorkingTrusted.Provenance = repmat("initial_trusted",height(Trusted),1);
WorkingTrusted.AcceptedIteration = zeros(height(Trusted),1);

writetable(WorkingTrusted,workingTrustedCSV);

% Source state.
SourceStatus = Source;
SourceStatus.Status = repmat("remaining",height(Source),1);
SourceStatus.ProcessIteration = nan(height(Source),1);
SourceStatus.Decision = repmat("",height(Source),1);
SourceStatus.Accepted_Epoch2_X = nan(height(Source),1);
SourceStatus.Accepted_Epoch2_Y = nan(height(Source),1);

writetable(SourceStatus,sourceStatusCSV);

% Empty audit/progression log.
ProgressionLog = table( ...
    zeros(0,1), ...                  % Iteration
    zeros(0,1), ...                  % Point
    strings(0,1), ...                % Event
    zeros(0,1), ...                  % TrustedCountBefore
    zeros(0,1), ...                  % TrustedCountAfter
    nan(0,1), ...                    % SupportRank
    nan(0,1), ...                    % D1_m
    nan(0,1), ...                    % D2_m
    nan(0,1), ...                    % D3_m
    nan(0,1), ...                    % EffectiveIDWN
    nan(0,1), ...                    % DominantIDWWeight
    false(0,1), ...                  % InsideTrustedHull
    nan(0,1), ...                    % Predicted_dE_m
    nan(0,1), ...                    % Predicted_dN_m
    nan(0,1), ...                    % Accepted_Epoch2_X
    nan(0,1), ...                    % Accepted_Epoch2_Y
    strings(0,1), ...                % SelectionMode
    'VariableNames',{ ...
        'Iteration','Point','Event', ...
        'TrustedCountBefore','TrustedCountAfter', ...
        'SupportRank','D1_m','D2_m','D3_m', ...
        'EffectiveIDWN','DominantIDWWeight','InsideTrustedHull', ...
        'Predicted_dE_m','Predicted_dN_m', ...
        'Accepted_Epoch2_X','Accepted_Epoch2_Y','SelectionMode'});

writetable(ProgressionLog,progressionLogCSV);

state = struct();
state.version = '1.2.1-beta';
state.caseName = caseName;
state.iteration = 0;
state.initialTrustedCount = height(Trusted);
state.initialSourceCount = height(Source);
state.currentPoint = NaN;
state.currentPointStatus = "none";
state.sessionStatus = "ready";
state.created = string(datetime('now'));
state.updated = state.created;

save(stateMat,'state');

fprintf('\n============================================================\n');
fprintf(' V1.2 PROGRESSIVE SESSION INITIALIZED\n');
fprintf('============================================================\n');
fprintf('Case:             %s\n',caseName);
fprintf('Initial trusted:  %d\n',height(Trusted));
fprintf('Source points:    %d\n',height(Source));
fprintf('Working root:\n%s\n',outRoot);
fprintf('============================================================\n');

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
