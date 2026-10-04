function info = v1_progressive_ensure_final_schema(caseName)
% v1_progressive_ensure_final_schema
%
% Ensure the V1.2 progressive final correspondence CSV is compatible with
% the frozen V1 Stage-5 scientific-analysis backend.
%
% Stage 5 REQUIRES these fields:
%   Point
%   Epoch1_X
%   Epoch1_Y
%   Epoch2_X
%   Epoch2_Y
%   Provenance
%
% It also carries SelectionMode forward when present. For compatibility
% and auditability, V1.2 writes the following 9-column schema:
%
%   Point
%   Epoch1_X
%   Epoch1_Y
%   Epoch2_X
%   Epoch2_Y
%   Provenance
%   SelectionMode
%   ChosenBeam
%   NearestChildDistance_m
%
% This function repairs either:
%   - the original 5-column progressive CSV, or
%   - the intermediate 8-column CSV that omitted Provenance.
%
% Accepted coordinates are NEVER changed.

if nargin < 1 || strlength(string(caseName))==0
    error('Provide a case name.');
end

caseName = char(string(caseName));

%% Paths
thisFile = mfilename('fullpath');
matchingDir = fileparts(thisFile);
srcDir = fileparts(matchingDir);
v1Root = fileparts(srcDir);

caseRoot = fullfile(v1Root,'cases',caseName);
outputRoot = fullfile(caseRoot,'output');

progressiveRoot = fullfile(outputRoot,'01_progressive_matching');
workingCSV = fullfile(progressiveRoot,'working_trusted.csv');
pointsRoot = fullfile(progressiveRoot,'point_results');

finalRoot = fullfile(outputRoot,'04_finalized_correspondences');
finalCSV = fullfile(finalRoot,'final_correspondences.csv');

backup5 = fullfile( ...
    finalRoot,'final_correspondences_pre_schema_repair.csv');

backup8 = fullfile( ...
    finalRoot,'final_correspondences_pre_provenance_repair.csv');

manifestMat = fullfile( ...
    finalRoot,'progressive_finalization_manifest.mat');

assert(isfile(finalCSV),'Missing progressive final_correspondences.csv.');
assert(isfile(workingCSV),'Missing progressive working_trusted.csv.');
assert(isfile(manifestMat),'Missing progressive finalization manifest.');

M = load(manifestMat,'manifest');

assert(isfield(M,'manifest') && ...
       string(M.manifest.mode)=="progressive", ...
    'Active finalization manifest is not progressive.');

required = { ...
    'Point', ...
    'Epoch1_X', ...
    'Epoch1_Y', ...
    'Epoch2_X', ...
    'Epoch2_Y', ...
    'Provenance', ...
    'SelectionMode', ...
    'ChosenBeam', ...
    'NearestChildDistance_m'};

core = required(1:5);

F = readtable(finalCSV,'TextType','string');

info = struct();
info.caseName = caseName;
info.finalCSV = finalCSV;
info.repaired = false;
info.rowCount = height(F);

if isequal(F.Properties.VariableNames,required)
    fprintf('\nProgressive final correspondence schema already Stage-5 compatible.\n');
    return
end

assert(all(ismember(core,F.Properties.VariableNames)), ...
    ['final_correspondences.csv is not a recognized progressive schema ' ...
     'and cannot be repaired safely.']);

W = readtable(workingCSV,'TextType','string');

requiredWorking = [core,{'Provenance','AcceptedIteration'}];

assert(all(ismember(requiredWorking,W.Properties.VariableNames)), ...
    'working_trusted.csv has an unexpected schema.');

W.Point = normalize_point_ids(W.Point);

%% Rebuild exact downstream interface from authoritative progressive state

Point = W.Point;
Epoch1_X = double(W.Epoch1_X);
Epoch1_Y = double(W.Epoch1_Y);
Epoch2_X = double(W.Epoch2_X);
Epoch2_Y = double(W.Epoch2_Y);

Provenance = string(W.Provenance);

n = height(W);

SelectionMode = strings(n,1);
ChosenBeam = nan(n,1);
NearestChildDistance_m = nan(n,1);

for i = 1:n

    provenance = Provenance(i);
    id = Point(i);

    if provenance=="initial_trusted"

        SelectionMode(i) = "initial_trusted";

    elseif provenance=="progressive_human_accept"

        iter = double(W.AcceptedIteration(i));

        assert(isfinite(iter) && iter>=1 && iter==floor(iter), ...
            'Accepted progressive P%02d has invalid AcceptedIteration.',id);

        reviewCSV = fullfile( ...
            pointsRoot, ...
            sprintf('iteration_%03d_P%02d',iter,id), ...
            'review_decision.csv');

        assert(isfile(reviewCSV), ...
            'Missing review_decision.csv for accepted P%02d.',id);

        R = readtable(reviewCSV,'TextType','string');

        assert(height(R)==1, ...
            'Expected one review row for accepted P%02d.',id);

        rid = normalize_point_ids(R.Point);

        assert(rid==id && string(R.Status)=="accepted", ...
            'Review provenance mismatch for accepted P%02d.',id);

        % Hard guard: schema repair must not alter scientific coordinates.
        assert(abs(double(R.Epoch1_X)-Epoch1_X(i))<=1e-9 && ...
               abs(double(R.Epoch1_Y)-Epoch1_Y(i))<=1e-9 && ...
               abs(double(R.Accepted_Epoch2_X)-Epoch2_X(i))<=1e-9 && ...
               abs(double(R.Accepted_Epoch2_Y)-Epoch2_Y(i))<=1e-9, ...
            'Review coordinates do not match working trusted P%02d.',id);

        SelectionMode(i) = string(R.SelectionMode);
        ChosenBeam(i) = double(R.ChosenBeam);
        NearestChildDistance_m(i) = ...
            double(R.NearestChildDistance_m);

    else

        error('Unexpected progressive provenance for P%02d: %s', ...
            id,provenance);
    end
end

Compat = table( ...
    Point, ...
    Epoch1_X,Epoch1_Y, ...
    Epoch2_X,Epoch2_Y, ...
    Provenance, ...
    SelectionMode, ...
    ChosenBeam, ...
    NearestChildDistance_m);

Compat = sortrows(Compat,'Point');

%% Verify current finalized coordinates are preserved exactly

Fold = F(:,core);
Fold.Point = normalize_point_ids(Fold.Point);
Fold = sortrows(Fold,'Point');

assert(height(Fold)==height(Compat), ...
    'Finalized row count changed during schema repair.');

assert(isequal(Fold.Point,Compat.Point), ...
    'Point IDs changed during schema repair.');

A = [ ...
    double(Fold.Epoch1_X), ...
    double(Fold.Epoch1_Y), ...
    double(Fold.Epoch2_X), ...
    double(Fold.Epoch2_Y)];

B = [ ...
    Compat.Epoch1_X, ...
    Compat.Epoch1_Y, ...
    Compat.Epoch2_X, ...
    Compat.Epoch2_Y];

assert(max(abs(A(:)-B(:)))<=1e-9, ...
    'Coordinate values changed during schema repair.');

%% Back up current interface state before replacement

if width(F)==5 && ~isfile(backup5)
    copyfile(finalCSV,backup5);
elseif width(F)==8 && ~isfile(backup8)
    copyfile(finalCSV,backup8);
end

atomic_writetable(Compat,finalCSV);

%% Update manifest

manifest = M.manifest;
manifest.downstreamSchema = "V1_stage5_compatible_9col";
manifest.schemaRepairedAt = string(datetime('now'));
manifest.finalCorrespondenceCount = height(Compat);

save(manifestMat,'manifest');

%% Final read-back validation against actual Stage-5 requirement

Check = readtable(finalCSV,'TextType','string');

assert(isequal(Check.Properties.VariableNames,required), ...
    'Schema repair write-back validation failed.');

stage5Required = { ...
    'Point','Epoch1_X','Epoch1_Y','Epoch2_X','Epoch2_Y','Provenance'};

assert(all(ismember(stage5Required,Check.Properties.VariableNames)), ...
    'Stage-5 required fields are still missing after repair.');

info.repaired = true;
info.rowCount = height(Check);

fprintf('\n============================================================\n');
fprintf(' V1.2 PROGRESSIVE FINAL SCHEMA REPAIRED\n');
fprintf('============================================================\n');
fprintf('Rows preserved:               %d\n',height(Check));
fprintf('Coordinates changed:          NO\n');
fprintf('Provenance restored:          YES\n');
fprintf('Final downstream columns:     %d\n',width(Check));
fprintf('Stage-5 required schema:      PASS\n');
fprintf('\nRepaired final CSV:\n%s\n',finalCSV);

if isfile(backup8)
    fprintf('\nBackup of previous 8-column CSV:\n%s\n',backup8);
elseif isfile(backup5)
    fprintf('\nBackup of previous 5-column CSV:\n%s\n',backup5);
end

fprintf('============================================================\n');

end

function ids = normalize_point_ids(v)

if isnumeric(v)
    ids = double(v(:));
else
    s = upper(strtrim(string(v)));
    s = regexprep(s,'^P','');
    ids = str2double(s(:));
end

assert(all(isfinite(ids)) && ...
       all(ids>0 & ids==floor(ids)), ...
    'Point IDs must be positive integers or P-prefixed positive integers.');

end

function atomic_writetable(T,finalPath)

[parentDir,baseName,ext] = fileparts(finalPath);

tmpPath = fullfile( ...
    parentDir, ...
    sprintf('.%s_tmp_%s%s', ...
        baseName,char(java.util.UUID.randomUUID),ext));

cleanupObj = onCleanup(@() cleanup_temp(tmpPath)); %#ok<NASGU>

writetable(T,tmpPath);

[ok,msg] = movefile(tmpPath,finalPath,'f');

assert(ok, ...
    'Atomic CSV replacement failed for %s: %s',finalPath,msg);

clear cleanupObj;

end

function cleanup_temp(tmpPath)

if isfile(tmpPath)
    delete(tmpPath);
end

end
