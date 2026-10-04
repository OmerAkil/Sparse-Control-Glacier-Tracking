function summary = v1_progressive_finalize(caseName)
% v1_progressive_finalize
%
% Freeze a COMPLETE V1.2 progressive session into the authoritative
% downstream correspondence field.
%
% This function:
%   1) verifies that the progressive session is complete;
%   2) verifies working_trusted.csv against the immutable initial trusted
%      CSV and the committed source_status.csv decisions;
%   3) archives any pre-existing Stage 4-8 outputs so stale downstream
%      results cannot be mistaken for the newly finalized field;
%   4) writes:
%        output/04_finalized_correspondences/final_correspondences.csv
%      using ONLY the progressive working trusted field;
%   5) saves provenance and a progressive-finalization manifest.
%
% Initial input CSV files are never modified.
%
% The downstream CSV preserves the established frozen V1 Stage-5
% interface:
%   Point, Epoch1_X, Epoch1_Y, Epoch2_X, Epoch2_Y, Provenance,
%   SelectionMode, ChosenBeam, NearestChildDistance_m
%
% MATLAB R2024a.

if nargin < 1 || strlength(string(caseName))==0
    error('Provide a case name.');
end

caseName = char(string(caseName));

%% ============================================================
% 1. PATHS
% ============================================================

thisFile = mfilename('fullpath');
matchingDir = fileparts(thisFile);
srcDir = fileparts(matchingDir);
v1Root = fileparts(srcDir);

caseRoot = fullfile(v1Root,'cases',caseName);
inputRoot = fullfile(caseRoot,'input');
outputRoot = fullfile(caseRoot,'output');

initialTrustedCSV = fullfile(inputRoot,'trusted_correspondences.csv');

progressiveRoot = fullfile(outputRoot,'01_progressive_matching');
workingTrustedCSV = fullfile(progressiveRoot,'working_trusted.csv');
sourceStatusCSV = fullfile(progressiveRoot,'source_status.csv');
stateMat = fullfile(progressiveRoot,'progressive_state.mat');
progressionLogCSV = fullfile(progressiveRoot,'progression_log.csv');

finalRoot = fullfile(outputRoot,'04_finalized_correspondences');
finalCSV = fullfile(finalRoot,'final_correspondences.csv');
provenanceCSV = fullfile(finalRoot,'progressive_provenance.csv');
summaryCSV = fullfile(finalRoot,'progressive_finalization_summary.csv');
manifestMat = fullfile(finalRoot,'progressive_finalization_manifest.mat');

assert(isfile(initialTrustedCSV),'Missing immutable initial trusted CSV.');
assert(isfile(workingTrustedCSV),'Missing progressive working_trusted.csv.');
assert(isfile(sourceStatusCSV),'Missing progressive source_status.csv.');
assert(isfile(stateMat),'Missing progressive_state.mat.');
assert(isfile(progressionLogCSV),'Missing progression_log.csv.');

%% ============================================================
% 2. VERIFY SESSION COMPLETE
% ============================================================

S = load(stateMat,'state');
state = S.state;

assert(strcmp(string(state.caseName),string(caseName)), ...
    'Progressive state belongs to a different case.');

assert(string(state.sessionStatus)=="complete", ...
    'Progressive matching must be COMPLETE before finalization.');

Initial = readtable(initialTrustedCSV,'TextType','string');
Working = readtable(workingTrustedCSV,'TextType','string');
SourceStatus = readtable(sourceStatusCSV,'TextType','string');

requiredCore = {'Point','Epoch1_X','Epoch1_Y','Epoch2_X','Epoch2_Y'};

assert(all(ismember(requiredCore,Initial.Properties.VariableNames)), ...
    'Initial trusted CSV has an invalid schema.');

assert(all(ismember([requiredCore,{'Provenance','AcceptedIteration'}], ...
    Working.Properties.VariableNames)), ...
    'working_trusted.csv has an invalid schema.');

requiredSourceStatus = { ...
    'Point','Epoch1_X','Epoch1_Y','Status','Decision', ...
    'Accepted_Epoch2_X','Accepted_Epoch2_Y'};

assert(all(ismember(requiredSourceStatus, ...
    SourceStatus.Properties.VariableNames)), ...
    'source_status.csv has an invalid schema.');

Initial.Point = normalize_point_ids(Initial.Point,'initial trusted');
Working.Point = normalize_point_ids(Working.Point,'working trusted');
SourceStatus.Point = normalize_point_ids(SourceStatus.Point,'source status');

assert(numel(unique(Working.Point))==height(Working), ...
    'working_trusted.csv contains duplicate Point IDs.');

status = string(SourceStatus.Status);

assert(all(status=="accepted" | status=="no_match"), ...
    ['All source points must be resolved as accepted or no_match before ' ...
     'progressive finalization.']);

nAccepted = nnz(status=="accepted");
nNoMatch = nnz(status=="no_match");

expectedCount = height(Initial)+nAccepted;

assert(height(Working)==expectedCount, ...
    ['Working trusted count mismatch: expected %d initial+accepted rows, ' ...
     'found %d.'], ...
    expectedCount,height(Working));

%% ============================================================
% 3. DATA-INTEGRITY CHECKS
% ============================================================

% Immutable initial trusted coordinates must be present unchanged.
for i = 1:height(Initial)

    id = Initial.Point(i);
    j = find(Working.Point==id);

    assert(numel(j)==1, ...
        'Initial trusted P%02d is missing or duplicated in working trusted.',id);

    a = [ ...
        Initial.Epoch1_X(i),Initial.Epoch1_Y(i), ...
        Initial.Epoch2_X(i),Initial.Epoch2_Y(i)];

    b = [ ...
        Working.Epoch1_X(j),Working.Epoch1_Y(j), ...
        Working.Epoch2_X(j),Working.Epoch2_Y(j)];

    assert(max(abs(double(a)-double(b)))<=1e-9, ...
        'Initial trusted P%02d changed during progressive propagation.',id);

    assert(string(Working.Provenance(j))=="initial_trusted", ...
        'Initial trusted P%02d has unexpected provenance.',id);
end

% Every accepted source must be present exactly once with the committed
% human-reviewed coordinate.
acceptedRows = find(status=="accepted");

for k = 1:numel(acceptedRows)

    i = acceptedRows(k);
    id = SourceStatus.Point(i);
    j = find(Working.Point==id);

    assert(numel(j)==1, ...
        'Accepted source P%02d is missing or duplicated in working trusted.',id);

    assert(abs(Working.Epoch1_X(j)-SourceStatus.Epoch1_X(i))<=1e-9 && ...
           abs(Working.Epoch1_Y(j)-SourceStatus.Epoch1_Y(i))<=1e-9, ...
        'Accepted source P%02d has inconsistent Epoch-1 coordinates.',id);

    assert(abs(Working.Epoch2_X(j)-SourceStatus.Accepted_Epoch2_X(i))<=1e-9 && ...
           abs(Working.Epoch2_Y(j)-SourceStatus.Accepted_Epoch2_Y(i))<=1e-9, ...
        'Accepted source P%02d has inconsistent accepted Epoch-2 coordinates.',id);

    assert(string(Working.Provenance(j))=="progressive_human_accept", ...
        'Accepted source P%02d has unexpected provenance.',id);
end

% NO MATCH points must never appear in the trusted field.
noMatchIDs = SourceStatus.Point(status=="no_match");

assert(isempty(intersect(Working.Point,noMatchIDs)), ...
    'One or more NO MATCH points incorrectly entered working_trusted.csv.');

%% ============================================================
% 4. ALREADY-FINALIZED GUARD
% ============================================================

if isfile(manifestMat) && isfile(finalCSV)

    M = load(manifestMat,'manifest');

    assert(isfield(M,'manifest') && ...
           string(M.manifest.mode)=="progressive", ...
        'Existing finalization manifest is not a progressive manifest.');

    F = readtable(finalCSV,'TextType','string');

    requiredDownstream = { ...
        'Point','Epoch1_X','Epoch1_Y','Epoch2_X','Epoch2_Y', ...
        'Provenance','SelectionMode','ChosenBeam', ...
        'NearestChildDistance_m'};

    if ~isequal(F.Properties.VariableNames,requiredDownstream)
        error([ ...
            'Existing progressive final CSV uses the obsolete schema. ' ...
            'Run v1_progressive_ensure_final_schema(caseName) once, then retry.']);
    end

    summary = struct();
    summary.caseName = caseName;
    summary.initialTrusted = height(Initial);
    summary.acceptedNew = nAccepted;
    summary.noMatch = nNoMatch;
    summary.finalCount = height(F);
    summary.finalCSV = finalCSV;
    summary.archiveRoot = string(M.manifest.archiveRoot);
    summary.alreadyFinalized = true;

    fprintf('\n============================================================\n');
    fprintf(' V1.2 PROGRESSIVE FINALIZATION ALREADY COMPLETE\n');
    fprintf('============================================================\n');
    fprintf('Final correspondences: %d\n',height(F));
    fprintf('Final CSV:\n%s\n',finalCSV);
    fprintf('============================================================\n');

    return
end

%% ============================================================
% 5. ARCHIVE PRE-EXISTING DOWNSTREAM OUTPUTS
% ============================================================
%
% Stage 4-8 outputs may exist from an earlier finalization or analysis run.
% They are archived before writing the new authoritative correspondence
% field so stale downstream results cannot remain active.

downstreamDirs = { ...
    '04_finalized_correspondences', ...
    '05_field_qc', ...
    '06_flow_aligned_plane', ...
    '07_strain_rate', ...
    '08_robustness'};

existing = false(size(downstreamDirs));

for i = 1:numel(downstreamDirs)
    existing(i) = isfolder(fullfile(outputRoot,downstreamDirs{i}));
end

archiveRoot = "";

if any(existing)

    stamp = datestr(now,'yyyymmdd_HHMMSS');

    archiveRoot = fullfile( ...
        outputRoot, ...
        ['_archived_downstream_' stamp]);

    mkdir(archiveRoot);

    for i = 1:numel(downstreamDirs)

        if ~existing(i)
            continue
        end

        src = fullfile(outputRoot,downstreamDirs{i});
        dst = fullfile(archiveRoot,downstreamDirs{i});

        [ok,msg] = movefile(src,dst);

        assert(ok, ...
            'Failed to archive old downstream folder %s: %s',src,msg);
    end
end

%% ============================================================
% 6. WRITE AUTHORITATIVE PROGRESSIVE FIELD
% ============================================================

if ~isfolder(finalRoot)
    mkdir(finalRoot);
end

% Preserve the established V1 Stage-5 interface. The coordinate field is
% still authoritative; review metadata is carried only for compatibility
% and provenance.
Point = double(Working.Point);
Epoch1_X = double(Working.Epoch1_X);
Epoch1_Y = double(Working.Epoch1_Y);
Epoch2_X = double(Working.Epoch2_X);
Epoch2_Y = double(Working.Epoch2_Y);

Provenance = string(Working.Provenance);

SelectionMode = strings(height(Working),1);
ChosenBeam = nan(height(Working),1);
NearestChildDistance_m = nan(height(Working),1);

pointsRoot = fullfile(progressiveRoot,'point_results');

for i = 1:height(Working)

    provenance = string(Working.Provenance(i));
    id = Point(i);

    if provenance=="initial_trusted"

        SelectionMode(i) = "initial_trusted";

    elseif provenance=="progressive_human_accept"

        iter = double(Working.AcceptedIteration(i));

        reviewCSV = fullfile( ...
            pointsRoot, ...
            sprintf('iteration_%03d_P%02d',iter,id), ...
            'review_decision.csv');

        assert(isfile(reviewCSV), ...
            'Missing review_decision.csv for accepted P%02d.',id);

        R = readtable(reviewCSV,'TextType','string');

        assert(height(R)==1 && string(R.Status)=="accepted", ...
            'Invalid review provenance for accepted P%02d.',id);

        SelectionMode(i) = string(R.SelectionMode);
        ChosenBeam(i) = double(R.ChosenBeam);
        NearestChildDistance_m(i) = double(R.NearestChildDistance_m);

    else
        error('Unexpected provenance for P%02d: %s',id,provenance);
    end
end

Final = table( ...
    Point,Epoch1_X,Epoch1_Y,Epoch2_X,Epoch2_Y, ...
    Provenance,SelectionMode,ChosenBeam,NearestChildDistance_m);

Final = sortrows(Final,'Point');

atomic_writetable(Final,finalCSV);

Provenance = Working(:,{ ...
    'Point','Provenance','AcceptedIteration'});
Provenance = sortrows(Provenance,'Point');

atomic_writetable(Provenance,provenanceCSV);

Metric = [ ...
    "initial_trusted"
    "accepted_progressive"
    "no_match"
    "final_correspondences"
];

Value = [ ...
    height(Initial)
    nAccepted
    nNoMatch
    height(Final)
];

SummaryTable = table(Metric,Value);

atomic_writetable(SummaryTable,summaryCSV);

manifest = struct();
manifest.mode = "progressive";
manifest.caseName = string(caseName);
manifest.version = "1.2.0-beta";
manifest.finalizedAt = string(datetime('now'));
manifest.initialTrustedCount = height(Initial);
manifest.acceptedNewCount = nAccepted;
manifest.noMatchCount = nNoMatch;
manifest.finalCorrespondenceCount = height(Final);
manifest.finalCSV = string(finalCSV);
manifest.provenanceCSV = string(provenanceCSV);
manifest.progressionLogCSV = string(progressionLogCSV);
manifest.archiveRoot = string(archiveRoot);

save(manifestMat,'manifest');

% Update progressive state only after authoritative files exist.
state.finalized = true;
state.finalizedAt = manifest.finalizedAt;
state.finalCorrespondenceCount = height(Final);
state.finalCSV = string(finalCSV);
state.archiveRoot = string(archiveRoot);
state.updated = string(datetime('now'));

save(stateMat,'state');

%% ============================================================
% 7. SUMMARY
% ============================================================

summary = struct();
summary.caseName = caseName;
summary.initialTrusted = height(Initial);
summary.acceptedNew = nAccepted;
summary.noMatch = nNoMatch;
summary.finalCount = height(Final);
summary.finalCSV = finalCSV;
summary.archiveRoot = string(archiveRoot);
summary.alreadyFinalized = false;

fprintf('\n============================================================\n');
fprintf(' V1.2 PROGRESSIVE FINALIZATION COMPLETE\n');
fprintf('============================================================\n');
fprintf('Initial trusted:          %d\n',summary.initialTrusted);
fprintf('Accepted progressive:     %d\n',summary.acceptedNew);
fprintf('NO MATCH excluded:        %d\n',summary.noMatch);
fprintf('Final correspondences:    %d\n',summary.finalCount);

if strlength(summary.archiveRoot)>0
    fprintf('\nArchived pre-existing Stage 4-8 outputs:\n%s\n', ...
        char(summary.archiveRoot));
else
    fprintf('\nNo pre-existing Stage 4-8 outputs required archiving.\n');
end

fprintf('\nAuthoritative progressive CSV:\n%s\n',summary.finalCSV);
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

function atomic_writetable(T,finalPath)

[parentDir,baseName,ext] = fileparts(finalPath);

assert(isfolder(parentDir), ...
    'Output folder does not exist: %s',parentDir);

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
