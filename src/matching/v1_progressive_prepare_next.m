function packet = v1_progressive_prepare_next(caseName)
% v1_progressive_prepare_next
%
% Select and match exactly ONE source point using the CURRENT working
% trusted set.
%
% Workflow:
%   1) load current working trusted set
%   2) rank remaining/deferred source points by lightweight support
%   3) select best-supported point
%   4) run single-point Stage 1
%   5) run single-point Stage 2
%   6) save an immutable candidate packet and mark point awaiting_review
%
% IMPORTANT:
%   - This function does NOT perform human review.
%   - It does NOT promote the point into the trusted set.
%   - It refuses to prepare another point while one is awaiting review.

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

outRoot = fullfile(caseRoot,'output','01_progressive_matching');
pointsRoot = fullfile(outRoot,'point_results');

workingTrustedCSV = fullfile(outRoot,'working_trusted.csv');
sourceStatusCSV = fullfile(outRoot,'source_status.csv');
progressionLogCSV = fullfile(outRoot,'progression_log.csv');
stateMat = fullfile(outRoot,'progressive_state.mat');

assert(isfolder(outRoot), ...
    'Progressive session not initialized. Run v1_progressive_initialize first.');

assert(isfile(configFile),'Missing case_config.m.');
assert(isfile(workingTrustedCSV),'Missing working_trusted.csv.');
assert(isfile(sourceStatusCSV),'Missing source_status.csv.');
assert(isfile(stateMat),'Missing progressive_state.mat.');

cfg = struct(); %#ok<NASGU>
run(configFile);

tmp = load(stateMat,'state');
state = tmp.state;

assert(strcmp(char(string(state.caseName)),caseName), ...
    'Progressive state belongs to a different case.');

assert(~strcmp(string(state.currentPointStatus),"awaiting_review"), ...
    ['A point is already awaiting human review: P%02d.\n' ...
     'Review/finalize that point before preparing another.'], ...
    state.currentPoint);

WorkingTrusted = readtable(workingTrustedCSV,'TextType','string');
SourceStatus = readtable(sourceStatusCSV,'TextType','string');

remainingMask = string(SourceStatus.Status)=="remaining";
deferredMask = string(SourceStatus.Status)=="deferred";

% A deferred point must not be immediately selected again. Complete the
% first pass through never-reviewed points first; only then revisit
% deferred points using the enlarged trusted network.
if any(remainingMask)
    eligible = remainingMask;
    selectionPool = "remaining";
elseif any(deferredMask)
    eligible = deferredMask;
    selectionPool = "deferred_revisit";
else
    error('No remaining/deferred source points are available.');
end

EligibleSources = SourceStatus(eligible, ...
    {'Point','Epoch1_X','Epoch1_Y'});

Support = v1_compute_source_support( ...
    cfg,WorkingTrusted,EligibleSources);

[nextPoint,Ranked] = v1_select_next_source(Support);

selectedRow = find(double(EligibleSources.Point)==nextPoint,1);
assert(~isempty(selectedRow),'Selected point not found in eligible sources.');

SourceRow = EligibleSources(selectedRow,:);

% Build raster state once for both single-point stages.
f1 = char(string(cfg.epoch1.raster));
f2 = char(string(cfg.epoch2.raster));

info1 = georasterinfo(f1);
info2 = georasterinfo(f2);

rasterState = struct( ...
    'f1',f1, ...
    'f2',f2, ...
    'R1',info1.RasterReference, ...
    'R2',info2.RasterReference);

fprintf('\n============================================================\n');
fprintf(' V1.2 PROGRESSIVE - PREPARE NEXT POINT\n');
fprintf('============================================================\n');
fprintf('Current trusted:  %d\n',height(WorkingTrusted));
fprintf('Selection pool:   %s\n',char(selectionPool));
fprintf('Eligible sources: %d\n',height(EligibleSources));
fprintf('Selected point:   P%02d\n',nextPoint);
fprintf('Support: D1 %.2f m | D2 %.2f m | D3 %.2f m\n', ...
    Ranked.D1_m(1),Ranked.D2_m(1),Ranked.D3_m(1));
fprintf('Running Stage 1 for P%02d only...\n',nextPoint);

Stage1Result = v1_stage1_single_point( ...
    cfg,WorkingTrusted,SourceRow,rasterState);

fprintf('Running Stage 2 for P%02d only...\n',nextPoint);

Stage2Result = v1_stage2_single_point( ...
    cfg,SourceRow,Stage1Result,rasterState);

iteration = state.iteration+1;

pointDir = fullfile( ...
    pointsRoot, ...
    sprintf('iteration_%03d_P%02d',iteration,nextPoint));

assert(~isfolder(pointDir), ...
    'Iteration output already exists: %s',pointDir);

mkdir(pointDir);

supportCSV = fullfile(pointDir,'support_ranking_before_matching.csv');
packetMat = fullfile(pointDir,'candidate_packet.mat');

writetable(Ranked,supportCSV);

packet = struct();
packet.iteration = iteration;
packet.Point = nextPoint;
packet.SourceRow = SourceRow;
packet.SupportSelected = Ranked(1,:);
packet.SupportRanking = Ranked;
packet.TrustedCountBefore = height(WorkingTrusted);
packet.Stage1 = Stage1Result;
packet.Stage2 = Stage2Result;
packet.Created = string(datetime('now'));
packet.Status = "awaiting_review";
packet.SelectionPool = selectionPool;

save(packetMat,'packet');

% Mark the selected source as awaiting review.
idxStatus = find(double(SourceStatus.Point)==nextPoint,1);
assert(~isempty(idxStatus),'Selected point missing from source_status.csv.');

SourceStatus.Status(idxStatus) = "awaiting_review";
SourceStatus.ProcessIteration(idxStatus) = iteration;

writetable(SourceStatus,sourceStatusCSV);

% Audit event.
Log = readtable(progressionLogCSV,'TextType','string');

newRow = table( ...
    iteration, ...
    nextPoint, ...
    "prepared_for_review", ...
    height(WorkingTrusted), ...
    height(WorkingTrusted), ...
    Ranked.SupportRank(1), ...
    Ranked.D1_m(1), ...
    Ranked.D2_m(1), ...
    Ranked.D3_m(1), ...
    Ranked.EffectiveIDWN(1), ...
    Ranked.DominantIDWWeight(1), ...
    Ranked.InsideTrustedHull(1), ...
    Stage1Result.PredictedDisp(1), ...
    Stage1Result.PredictedDisp(2), ...
    NaN, ...
    NaN, ...
    "", ...
    'VariableNames',Log.Properties.VariableNames);

Log = [Log; newRow]; %#ok<AGROW>
writetable(Log,progressionLogCSV);

state.iteration = iteration;
state.currentPoint = nextPoint;
state.currentPointStatus = "awaiting_review";
state.sessionStatus = "awaiting_review";
state.updated = string(datetime('now'));

save(stateMat,'state');

fprintf('\nCandidate packet saved:\n%s\n',packetMat);
fprintf('\nP%02d is now awaiting human review.\n',nextPoint);
fprintf('No other source point was image-matched.\n');
fprintf('============================================================\n');

end
