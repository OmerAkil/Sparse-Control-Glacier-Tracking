function summary = v1_progressive_run_session(caseName)
% v1_progressive_run_session
%
% Interactive controller for V1.2 progressive propagation.
%
% It repeatedly performs:
%   current trusted set
%       -> lightweight support ranking
%       -> select ONE source point
%       -> Stage 1 for that point only
%       -> Stage 2 for that point only
%       -> GUI human review
%       -> if ACCEPT: append to working trusted set
%       -> update lightweight support only
%       -> ask whether to continue
%
% No Command Window decision input is used.
%
% The controller is resumable:
%   - if a point is already awaiting_review, it opens that review
%   - if session is ready, it prepares the next point
%   - if session is complete, it reports completion
%
% DEFER policy:
%   - first pass through "remaining" points: DEFER is allowed
%   - after all never-reviewed points are resolved, deferred points are
%     revisited using the enlarged trusted network
%   - during deferred revisit, the point must be resolved as ACCEPT or
%     NO MATCH; a second defer cannot improve support because there are no
%     unreviewed points left to grow the network.

if nargin < 1 || strlength(string(caseName))==0
    error('Provide a case name.');
end

caseName = char(string(caseName));

thisFile = mfilename('fullpath');
matchingDir = fileparts(thisFile);
srcDir = fileparts(matchingDir);
v1Root = fileparts(srcDir);

caseRoot = fullfile(v1Root,'cases',caseName);
progressiveRoot = fullfile( ...
    caseRoot,'output','01_progressive_matching');

stateMat = fullfile(progressiveRoot,'progressive_state.mat');
workingTrustedCSV = fullfile(progressiveRoot,'working_trusted.csv');
sourceStatusCSV = fullfile(progressiveRoot,'source_status.csv');

% Initialize only if no progressive session exists.
if ~isfolder(progressiveRoot)
    v1_progressive_initialize(caseName);
end

assert(isfile(stateMat), ...
    'Progressive session exists but progressive_state.mat is missing.');

keepRunning = true;

while keepRunning

    S = load(stateMat,'state');
    state = S.state;

    if string(state.sessionStatus)=="complete"
        break
    end

    % --------------------------------------------------------
    % Prepare exactly one point if none is awaiting review.
    % --------------------------------------------------------
    if string(state.currentPointStatus)~="awaiting_review"
        v1_progressive_prepare_next(caseName);

        S = load(stateMat,'state');
        state = S.state;
    end

    assert(string(state.currentPointStatus)=="awaiting_review", ...
        'Progressive controller expected a point awaiting review.');

    currentPoint = double(state.currentPoint);

    % --------------------------------------------------------
    % Human review and state commit.
    % --------------------------------------------------------
    Review = v1_progressive_review_current(caseName);

    decision = string(Review.Status(1));

    % --------------------------------------------------------
    % Refresh state after commit.
    % --------------------------------------------------------
    S = load(stateMat,'state');
    state = S.state;

    if string(state.sessionStatus)=="complete"
        break
    end

    WorkingTrusted = readtable(workingTrustedCSV,'TextType','string');
    SourceStatus = readtable(sourceStatusCSV,'TextType','string');

    nAccepted = nnz(string(SourceStatus.Status)=="accepted");
    nNoMatch = nnz(string(SourceStatus.Status)=="no_match");
    nDeferred = nnz(string(SourceStatus.Status)=="deferred");
    nRemaining = nnz(string(SourceStatus.Status)=="remaining");

    message = sprintf([ ...
        'P%02d: %s\n\n' ...
        'Current trusted controls: %d\n' ...
        'Accepted new: %d\n' ...
        'No match: %d\n' ...
        'Deferred: %d\n' ...
        'Never reviewed: %d\n\n' ...
        'Continue to the next best-supported source point?'], ...
        currentPoint,upper(char(decision)), ...
        height(WorkingTrusted), ...
        nAccepted,nNoMatch,nDeferred,nRemaining);

    choice = questdlg( ...
        message, ...
        'Progressive Matching', ...
        'Continue','Pause','Continue');

    if isempty(choice) || strcmp(choice,'Pause')
        keepRunning = false;
    end
end

% ------------------------------------------------------------
% Final summary
% ------------------------------------------------------------

S = load(stateMat,'state');
state = S.state;

WorkingTrusted = readtable(workingTrustedCSV,'TextType','string');
SourceStatus = readtable(sourceStatusCSV,'TextType','string');

nAccepted = nnz(string(SourceStatus.Status)=="accepted");
nNoMatch = nnz(string(SourceStatus.Status)=="no_match");
nDeferred = nnz(string(SourceStatus.Status)=="deferred");
nRemaining = nnz(string(SourceStatus.Status)=="remaining");
nAwaiting = nnz(string(SourceStatus.Status)=="awaiting_review");

summary = struct();
summary.caseName = caseName;
summary.sessionStatus = string(state.sessionStatus);
summary.iterations = double(state.iteration);
summary.initialTrusted = double(state.initialTrustedCount);
summary.currentTrusted = height(WorkingTrusted);
summary.acceptedNew = nAccepted;
summary.noMatch = nNoMatch;
summary.deferred = nDeferred;
summary.remaining = nRemaining;
summary.awaitingReview = nAwaiting;

fprintf('\n============================================================\n');
fprintf(' V1.2 PROGRESSIVE SESSION STATUS\n');
fprintf('============================================================\n');
fprintf('Case:               %s\n',caseName);
fprintf('Session status:     %s\n',upper(char(summary.sessionStatus)));
fprintf('Iterations:         %d\n',summary.iterations);
fprintf('Initial trusted:    %d\n',summary.initialTrusted);
fprintf('Current trusted:    %d\n',summary.currentTrusted);
fprintf('Accepted new:       %d\n',summary.acceptedNew);
fprintf('No match:           %d\n',summary.noMatch);
fprintf('Deferred:           %d\n',summary.deferred);
fprintf('Remaining:          %d\n',summary.remaining);
fprintf('Awaiting review:    %d\n',summary.awaitingReview);

if summary.sessionStatus=="complete"
    fprintf('\nPROGRESSIVE MATCHING COMPLETE.\n');
else
    fprintf('\nSession paused safely and can be resumed later.\n');
end

fprintf('============================================================\n');

end
