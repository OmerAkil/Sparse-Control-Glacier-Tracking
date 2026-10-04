function Review = v1_progressive_review_current(caseName)
% v1_progressive_review_current
%
% GUI-only human review for the ONE progressive point currently marked
% awaiting_review.
%
% This is the progressive equivalent of the frozen V1 Stage-3 review
% semantics:
%   overview -> choose beam/fallback -> precise graphical click ->
%   accept manual click / snap nearest retained child / redo / change beam /
%   NO MATCH / DEFER.
%
% IMPORTANT
%   - No Command Window decision input is used.
%   - Only a HUMAN-ACCEPTED correspondence is appended to working_trusted.
%   - Proposals/refined candidates never become trusted automatically.
%   - NO MATCH is resolved without entering the trusted set.
%   - DEFER remains unresolved and is revisited only after never-reviewed
%     source points have had a first pass.
%   - No validation_only / withheld Epoch-2 truth is read.
%
% After the decision, the function cheaply recomputes support and reports
% which point would be selected NEXT. It does NOT image-match that point.

if nargin < 1 || strlength(string(caseName))==0
    error('Provide a case name.');
end

caseName = char(string(caseName));

%% ============================================================
% 1. LOCATE CASE + PROGRESSIVE STATE
% ============================================================

thisFile = mfilename('fullpath');
matchingDir = fileparts(thisFile);
srcDir = fileparts(matchingDir);
v1Root = fileparts(srcDir);

caseRoot = fullfile(v1Root,'cases',caseName);
configFile = fullfile(caseRoot,'case_config.m');
metadataCSV = fullfile(caseRoot,'input','case_metadata.csv');

outRoot = fullfile(caseRoot,'output','01_progressive_matching');
pointsRoot = fullfile(outRoot,'point_results');

workingTrustedCSV = fullfile(outRoot,'working_trusted.csv');
sourceStatusCSV = fullfile(outRoot,'source_status.csv');
progressionLogCSV = fullfile(outRoot,'progression_log.csv');
stateMat = fullfile(outRoot,'progressive_state.mat');

assert(isfolder(outRoot), ...
    'Progressive session is not initialized.');

assert(isfile(configFile),'Missing case_config.m.');
assert(isfile(metadataCSV),'Missing case_metadata.csv.');
assert(isfile(workingTrustedCSV),'Missing working_trusted.csv.');
assert(isfile(sourceStatusCSV),'Missing source_status.csv.');
assert(isfile(progressionLogCSV),'Missing progression_log.csv.');
assert(isfile(stateMat),'Missing progressive_state.mat.');

cfg = struct(); %#ok<NASGU>
run(configFile);

tmp = load(stateMat,'state');
state = tmp.state;

assert(strcmp(string(state.currentPointStatus),"awaiting_review"), ...
    'No progressive point is currently awaiting review.');

label = double(state.currentPoint);
iteration = double(state.iteration);

pointDir = fullfile( ...
    pointsRoot, ...
    sprintf('iteration_%03d_P%02d',iteration,label));

packetMat = fullfile(pointDir,'candidate_packet.mat');

assert(isfile(packetMat), ...
    'Candidate packet is missing: %s',packetMat);

P = load(packetMat,'packet');
packet = P.packet;

if isfield(packet,'SelectionPool')
    selectionPool = string(packet.SelectionPool);
else
    % Backward compatibility for packets prepared before this field existed.
    selectionPool = "remaining";
end

allowDefer = selectionPool=="remaining";

assert(packet.Point==label, ...
    'Progressive state and candidate packet Point IDs differ.');

assert(strcmp(string(packet.Status),"awaiting_review"), ...
    'Candidate packet is not awaiting review.');

%% ============================================================
% 2. REVIEW STATE
% ============================================================

SourceRow = packet.SourceRow;
SourceP = [double(SourceRow.Epoch1_X),double(SourceRow.Epoch1_Y)];

PredictedTarget = packet.Stage1.PredictedTarget;
PredictedDisp = packet.Stage1.PredictedDisp;

child = packet.Stage2.ChildrenWorld;
beamCenters = packet.Stage2.BeamCentersWorld;

nVisualClusters = packet.Stage2.Parameters.nVisualClusters;
fallbackBeam = packet.Stage2.Parameters.fallbackBeam;

assert(nVisualClusters==3 && fallbackBeam==4, ...
    ['Progressive review currently expects 3 visual beams plus ' ...
     'one IDW fallback beam.']);

%% ============================================================
% 3. TIME + RASTERS
% ============================================================

Meta = readtable(metadataCSV,'TextType','string');

assert(height(Meta)==1 && ...
       all(ismember({'dtYears','dtDays'},Meta.Properties.VariableNames)), ...
    'case_metadata.csv has an unexpected schema.');

dtYears = double(Meta.dtYears(1));
dtDays = double(Meta.dtDays(1));

f1 = char(string(cfg.epoch1.raster));
f2 = char(string(cfg.epoch2.raster));

epoch1Name = char(string(cfg.epoch1.name));
epoch2Name = char(string(cfg.epoch2.name));

info1 = georasterinfo(f1);
info2 = georasterinfo(f2);

R1 = info1.RasterReference;
R2 = info2.RasterReference;

displayGSD = cfg.review.display_gsd_m;
sourceHalfWidth_m = cfg.review.source_half_width_m;
overviewHalfWidth_m = cfg.review.overview_half_width_m;
beamHalfWidth_m = cfg.review.beam_half_width_m;
childDistanceWarning_m = cfg.review.child_distance_warning_m;

%% ============================================================
% 4. OVERVIEW
% ============================================================

fprintf('\n============================================================\n');
fprintf(' V1.2 PROGRESSIVE HUMAN REVIEW - P%02d\n',label);
fprintf('============================================================\n');
fprintf('Iteration:              %d\n',iteration);
fprintf('Trusted before review:  %d\n',packet.TrustedCountBefore);
fprintf('Support D1/D2/D3:       %.2f / %.2f / %.2f m\n', ...
    packet.SupportSelected.D1_m, ...
    packet.SupportSelected.D2_m, ...
    packet.SupportSelected.D3_m);
fprintf('Predicted displacement: dE %+0.2f m, dN %+0.2f m\n', ...
    PredictedDisp(1),PredictedDisp(2));
fprintf('Time interval:          %.0f days = %.6f yr\n', ...
    dtDays,dtYears);

f = figure( ...
    'Name',sprintf('Progressive P%02d overview',label), ...
    'Color','w', ...
    'Units','normalized', ...
    'Position',[0.03 0.06 0.94 0.86]);

tl = tiledlayout(f,2,3, ...
    'TileSpacing','compact', ...
    'Padding','compact');

ax = nexttile(tl,1);

show_world_patch( ...
    ax,f1,R1, ...
    SourceP(1),SourceP(2), ...
    sourceHalfWidth_m,displayGSD);

hold(ax,'on');

plot(ax, ...
    SourceP(1),SourceP(2), ...
    'r+','MarkerSize',14,'LineWidth',2);

title(ax,sprintf('P%02d %s source',label,epoch1Name));

ax = nexttile(tl,2);

show_world_patch( ...
    ax,f2,R2, ...
    PredictedTarget(1),PredictedTarget(2), ...
    overviewHalfWidth_m,displayGSD);

hold(ax,'on');

plot(ax, ...
    PredictedTarget(1),PredictedTarget(2), ...
    'mx','MarkerSize',12,'LineWidth',2);

plot_all_beam_children(ax,child,fallbackBeam);

title(ax,sprintf('%s overview - all retained children',epoch2Name));

for beam = 1:fallbackBeam

    ax = nexttile(tl,beam+2);

    center = beamCenters(beam,:);

    if any(~isfinite(center))
        center = PredictedTarget;
    end

    show_world_patch( ...
        ax,f2,R2, ...
        center(1),center(2), ...
        beamHalfWidth_m,displayGSD);

    hold(ax,'on');

    plot(ax, ...
        PredictedTarget(1),PredictedTarget(2), ...
        'mx','MarkerSize',10,'LineWidth',1.5);

    plot_beam_children(ax,child,beam);

    if beam<=nVisualClusters
        title(ax,sprintf('%s beam %d',epoch2Name,beam));
    else
        title(ax,sprintf('%s IDW fallback',epoch2Name));
    end
end

sgtitle(tl, ...
    sprintf(['P%02d progressive review | trusted before = %d | ' ...
             'red +=source; magenta x=IDW prediction'], ...
             label,packet.TrustedCountBefore));

overviewPNG = fullfile(pointDir,sprintf('P%02d_review_overview.png',label));
exportgraphics(f,overviewPNG,'Resolution',180);

%% ============================================================
% 5. GUI-ONLY REVIEW
% ============================================================

Status = "unreviewed";
ChosenBeam = NaN;
SelectionMode = "";

Accepted_Epoch2_X = NaN;
Accepted_Epoch2_Y = NaN;

NearestChild_X = NaN;
NearestChild_Y = NaN;
NearestChildDistance_m = NaN;

pointDone = false;

while ~pointDone

    beamChoice = choose_beam_gui(label,epoch2Name,allowDefer);

    if isempty(beamChoice)
        beamChoice = 9;
    end

    if beamChoice==0
        Status = "no_match";
        SelectionMode = "no_match";
        pointDone = true;
        break
    end

    if beamChoice==9
        Status = "deferred";
        SelectionMode = "deferred";
        pointDone = true;
        break
    end

    beam = beamChoice;
    center = beamCenters(beam,:);

    if any(~isfinite(center))
        center = PredictedTarget;
    end

    zf = figure( ...
        'Name',sprintf('Progressive P%02d beam %d',label,beam), ...
        'Color','w', ...
        'Units','normalized', ...
        'Position',[0.08 0.18 0.84 0.64]);

    ztl = tiledlayout(zf,1,2, ...
        'TileSpacing','compact', ...
        'Padding','compact');

    axS = nexttile(ztl,1);

    show_world_patch( ...
        axS,f1,R1, ...
        SourceP(1),SourceP(2), ...
        sourceHalfWidth_m,displayGSD);

    hold(axS,'on');

    plot(axS, ...
        SourceP(1),SourceP(2), ...
        'r+','MarkerSize',16,'LineWidth',2);

    title(axS,sprintf('P%02d %s source',label,epoch1Name));

    axT = nexttile(ztl,2);

    show_world_patch( ...
        axT,f2,R2, ...
        center(1),center(2), ...
        beamHalfWidth_m,displayGSD);

    hold(axT,'on');

    plot(axT, ...
        PredictedTarget(1),PredictedTarget(2), ...
        'mx','MarkerSize',11,'LineWidth',1.5);

    plot_beam_children(axT,child,beam);

    if beam<=nVisualClusters
        title(axT,sprintf('P%02d %s beam %d - CLICK MATCH', ...
            label,epoch2Name,beam));
    else
        title(axT,sprintf('P%02d %s fallback - CLICK MATCH', ...
            label,epoch2Name));
    end

    sgtitle(ztl, ...
        sprintf('Click the visually corresponding %s point.',epoch2Name));

    redoClick = true;
    changeBeam = false;

    while redoClick

        redoClick = false;

        figure(zf);
        axes(axT); %#ok<LAXES>

        [xc,yc] = ginput(1);

        if isempty(xc)
            changeBeam = true;
            break
        end

        xl = xlim(axT);
        yl = ylim(axT);

        if xc<min(xl) || xc>max(xl) || ...
           yc<min(yl) || yc>max(yl)
            redoClick = true;
            continue
        end

        beamRows = child(:,3)==beam;
        beamChild = child(beamRows,:);

        if isempty(beamChild)
            nearestDist = NaN;
            nearestXY = [NaN NaN];
        else
            d = hypot( ...
                beamChild(:,1)-xc, ...
                beamChild(:,2)-yc);

            [nearestDist,idx] = min(d);
            nearestXY = beamChild(idx,1:2);
        end

        plot(axT,xc,yc,'go','MarkerSize',12,'LineWidth',2);

        if all(isfinite(nearestXY))
            plot(axT, ...
                nearestXY(1),nearestXY(2), ...
                'cs','MarkerSize',10,'LineWidth',2);
        end

        action = choose_action_gui( ...
            label,beam,nearestDist,all(isfinite(nearestXY)), ...
            childDistanceWarning_m);

        switch action

            case 'a'
                Status = "accepted";
                ChosenBeam = beam;
                SelectionMode = "manual_click";
                Accepted_Epoch2_X = xc;
                Accepted_Epoch2_Y = yc;
                NearestChild_X = nearestXY(1);
                NearestChild_Y = nearestXY(2);
                NearestChildDistance_m = nearestDist;
                pointDone = true;

            case 'c'
                if ~all(isfinite(nearestXY))
                    redoClick = true;
                else
                    Status = "accepted";
                    ChosenBeam = beam;
                    SelectionMode = "nearest_child";
                    Accepted_Epoch2_X = nearestXY(1);
                    Accepted_Epoch2_Y = nearestXY(2);
                    NearestChild_X = nearestXY(1);
                    NearestChild_Y = nearestXY(2);
                    NearestChildDistance_m = nearestDist;
                    pointDone = true;
                end

            case 'r'
                redoClick = true;

            case 'b'
                changeBeam = true;

            case 'n'
                Status = "no_match";
                SelectionMode = "no_match";
                pointDone = true;
        end
    end

    if isvalid(zf)
        close(zf);
    end

    if changeBeam
        continue
    end
end

if isvalid(f)
    close(f);
end

%% ============================================================
% 6. BUILD REVIEW RECORD
% ============================================================

if Status=="accepted"

    dE_m = Accepted_Epoch2_X-SourceP(1);
    dN_m = Accepted_Epoch2_Y-SourceP(2);

    Displacement_m = hypot(dE_m,dN_m);
    Speed_m_per_year = Displacement_m/dtYears;

else

    dE_m = NaN;
    dN_m = NaN;
    Displacement_m = NaN;
    Speed_m_per_year = NaN;
end

Review = table( ...
    label, ...
    iteration, ...
    SourceP(1), ...
    SourceP(2), ...
    Status, ...
    ChosenBeam, ...
    SelectionMode, ...
    Accepted_Epoch2_X, ...
    Accepted_Epoch2_Y, ...
    NearestChild_X, ...
    NearestChild_Y, ...
    NearestChildDistance_m, ...
    dE_m, ...
    dN_m, ...
    Displacement_m, ...
    Speed_m_per_year, ...
    'VariableNames',{ ...
        'Point','Iteration', ...
        'Epoch1_X','Epoch1_Y', ...
        'Status','ChosenBeam','SelectionMode', ...
        'Accepted_Epoch2_X','Accepted_Epoch2_Y', ...
        'NearestChild_X','NearestChild_Y','NearestChildDistance_m', ...
        'dE_m','dN_m','Displacement_m','Speed_m_per_year'});

reviewCSV = fullfile(pointDir,'review_decision.csv');
atomic_writetable(Review,reviewCSV);

%% ============================================================
% 7. COMMIT DECISION TO PROGRESSIVE STATE
% ============================================================

WorkingTrusted = readtable(workingTrustedCSV,'TextType','string');
SourceStatus = readtable(sourceStatusCSV,'TextType','string');
Log = readtable(progressionLogCSV,'TextType','string');

idxStatus = find(double(SourceStatus.Point)==label,1);

assert(~isempty(idxStatus), ...
    'Current point is missing from source_status.csv.');

assert(string(SourceStatus.Status(idxStatus))=="awaiting_review", ...
    'Current source status is not awaiting_review.');

trustedBefore = height(WorkingTrusted);
trustedAfter = trustedBefore;

if Status=="accepted"

    assert(~any(double(WorkingTrusted.Point)==label), ...
        'P%02d already exists in working_trusted.csv.',label);

    NewTrusted = table( ...
        label, ...
        SourceP(1), ...
        SourceP(2), ...
        Accepted_Epoch2_X, ...
        Accepted_Epoch2_Y, ...
        "progressive_human_accept", ...
        iteration, ...
        'VariableNames',{ ...
            'Point','Epoch1_X','Epoch1_Y','Epoch2_X','Epoch2_Y', ...
            'Provenance','AcceptedIteration'});

    WorkingTrusted = [WorkingTrusted; NewTrusted];
    trustedAfter = height(WorkingTrusted);

    SourceStatus.Status(idxStatus) = "accepted";
    SourceStatus.Decision(idxStatus) = "accepted";
    SourceStatus.Accepted_Epoch2_X(idxStatus) = Accepted_Epoch2_X;
    SourceStatus.Accepted_Epoch2_Y(idxStatus) = Accepted_Epoch2_Y;

elseif Status=="no_match"

    SourceStatus.Status(idxStatus) = "no_match";
    SourceStatus.Decision(idxStatus) = "no_match";

elseif Status=="deferred"

    SourceStatus.Status(idxStatus) = "deferred";
    SourceStatus.Decision(idxStatus) = "deferred";

else

    error('Unexpected review Status: %s',Status);
end

% Append audit event.
newLogRow = table( ...
    iteration, ...
    label, ...
    Status, ...
    trustedBefore, ...
    trustedAfter, ...
    packet.SupportSelected.SupportRank, ...
    packet.SupportSelected.D1_m, ...
    packet.SupportSelected.D2_m, ...
    packet.SupportSelected.D3_m, ...
    packet.SupportSelected.EffectiveIDWN, ...
    packet.SupportSelected.DominantIDWWeight, ...
    packet.SupportSelected.InsideTrustedHull, ...
    PredictedDisp(1), ...
    PredictedDisp(2), ...
    Accepted_Epoch2_X, ...
    Accepted_Epoch2_Y, ...
    SelectionMode, ...
    'VariableNames',Log.Properties.VariableNames);

Log = [Log; newLogRow]; %#ok<AGROW>

% Packet becomes immutable review provenance for this iteration.
packet.Status = Status;
packet.Review = Review;
packet.TrustedCountAfter = trustedAfter;
packet.Reviewed = string(datetime('now'));

atomic_save_packet(packetMat,packet);

% Commit CSVs only after the review packet itself is safely stored.
atomic_writetable(WorkingTrusted,workingTrustedCSV);
atomic_writetable(SourceStatus,sourceStatusCSV);
atomic_writetable(Log,progressionLogCSV);

% Clear current point in the state.
state.currentPoint = NaN;
state.currentPointStatus = "none";

remainingMask = string(SourceStatus.Status)=="remaining";
deferredMask = string(SourceStatus.Status)=="deferred";

if any(remainingMask) || any(deferredMask)
    state.sessionStatus = "ready";
else
    state.sessionStatus = "complete";
end

state.updated = string(datetime('now'));
atomic_save_state(stateMat,state);

%% ============================================================
% 8. REPORT NEXT SUPPORT STATE - NO IMAGE MATCHING
% ============================================================

fprintf('\n============================================================\n');
fprintf(' V1.2 PROGRESSIVE REVIEW COMMITTED\n');
fprintf('============================================================\n');
fprintf('P%02d decision:          %s\n',label,upper(char(Status)));
fprintf('Trusted before:         %d\n',trustedBefore);
fprintf('Trusted after:          %d\n',trustedAfter);

if Status=="accepted"
    fprintf('Accepted %s:        %.3f , %.3f\n', ...
        epoch2Name,Accepted_Epoch2_X,Accepted_Epoch2_Y);
    fprintf('Annualized speed:       %.2f m/yr\n',Speed_m_per_year);
end

if state.sessionStatus=="complete"

    fprintf('\nAll source points are resolved.\n');

else

    % First-pass remaining points have priority over deferred points.
    remainingMask = string(SourceStatus.Status)=="remaining";
    deferredMask = string(SourceStatus.Status)=="deferred";

    if any(remainingMask)
        previewMask = remainingMask;
        poolName = "remaining";
    else
        previewMask = deferredMask;
        poolName = "deferred_revisit";
    end

    Remaining = SourceStatus(previewMask, ...
        {'Point','Epoch1_X','Epoch1_Y'});

    UpdatedSupport = v1_compute_source_support( ...
        cfg,WorkingTrusted,Remaining);

    [nextPoint,Ranked] = v1_select_next_source(UpdatedSupport);

    fprintf('\nNext selection pool:    %s\n',char(poolName));
    fprintf('NEXT proposed source:   P%02d\n',nextPoint);
    fprintf('Updated support:        D1 %.2f | D2 %.2f | D3 %.2f m\n', ...
        Ranked.D1_m(1),Ranked.D2_m(1),Ranked.D3_m(1));

    nextCSV = fullfile(pointDir,'support_ranking_after_review.csv');
    atomic_writetable(Ranked,nextCSV);

    fprintf(['No matching was run for P%02d yet. ' ...
             'Only lightweight support was updated.\n'],nextPoint);
end

fprintf('============================================================\n');

end

%% ============================================================
% GUI HELPERS
% ============================================================

function beamChoice = choose_beam_gui(label,epoch2Name,allowDefer)

if allowDefer
    options = { ...
        'Beam 1', ...
        'Beam 2', ...
        'Beam 3', ...
        'IDW fallback', ...
        'NO MATCH', ...
        'DEFER / review later'};

    map = [1 2 3 4 0 9];
    cancelString = 'Defer';
else
    options = { ...
        'Beam 1', ...
        'Beam 2', ...
        'Beam 3', ...
        'IDW fallback', ...
        'NO MATCH'};

    map = [1 2 3 4 0];
    cancelString = 'Back';
end

prompt = { ...
    sprintf('P%02d: choose the %s target region to inspect.',label,epoch2Name), ...
    'Only a human-accepted coordinate will enter the trusted set.'};

if ~allowDefer
    prompt{end+1} = ...
        'This point is being revisited after the first pass; resolve as ACCEPT or NO MATCH.';
end

[idx,ok] = listdlg( ...
    'ListString',options, ...
    'SelectionMode','single', ...
    'InitialValue',1, ...
    'ListSize',[390 195], ...
    'PromptString',prompt, ...
    'Name',sprintf('Progressive Review - P%02d',label), ...
    'OKString','Continue', ...
    'CancelString',cancelString);

if ~ok || isempty(idx)
    if allowDefer
        beamChoice = 9;
    else
        beamChoice = [];
    end
    return
end

beamChoice = map(idx);

end

function action = choose_action_gui( ...
    label,beam,nearestDist,hasNearestChild,warningDistance)

if hasNearestChild
    nearestText = sprintf( ...
        'Snap to nearest retained child (%.2f m away)',nearestDist);
else
    nearestText = 'Snap to nearest retained child (none available)';
end

warningLine = '';

if hasNearestChild && nearestDist>warningDistance
    warningLine = sprintf( ...
        'WARNING: click is %.2f m from the nearest retained child.', ...
        nearestDist);
end

options = { ...
    'Accept manual click', ...
    nearestText, ...
    'Redo click in this region', ...
    'Choose a different region', ...
    'NO MATCH'};

prompt = { ...
    sprintf('P%02d, region %d: choose what to do with this click.', ...
        label,beam), ...
    'The accepted coordinate becomes a new trusted control.'};

if strlength(string(warningLine))>0
    prompt{end+1} = warningLine; %#ok<AGROW>
end

[idx,ok] = listdlg( ...
    'ListString',options, ...
    'SelectionMode','single', ...
    'InitialValue',1, ...
    'ListSize',[450 185], ...
    'PromptString',prompt, ...
    'Name',sprintf('Confirm Progressive Review - P%02d',label), ...
    'OKString','Apply', ...
    'CancelString','Back');

if ~ok || isempty(idx)
    action = 'b';
    return
end

map = {'a','c','r','b','n'};
action = map{idx};

end

%% ============================================================
% FILE / DISPLAY HELPERS
% ============================================================

function atomic_writetable(T,finalPath)

[parentDir,baseName,ext] = fileparts(finalPath);

assert(isfolder(parentDir), ...
    'Atomic-write folder does not exist: %s',parentDir);

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

function atomic_save_packet(finalPath,packet)

[parentDir,baseName,ext] = fileparts(finalPath);
tmpPath = fullfile( ...
    parentDir, ...
    sprintf('.%s_tmp_%s%s', ...
        baseName,char(java.util.UUID.randomUUID),ext));

cleanupObj = onCleanup(@() cleanup_temp(tmpPath)); %#ok<NASGU>

save(tmpPath,'packet');

[ok,msg] = movefile(tmpPath,finalPath,'f');

assert(ok, ...
    'Atomic MAT replacement failed for %s: %s',finalPath,msg);

clear cleanupObj;

end

function atomic_save_state(finalPath,state)

[parentDir,baseName,ext] = fileparts(finalPath);
tmpPath = fullfile( ...
    parentDir, ...
    sprintf('.%s_tmp_%s%s', ...
        baseName,char(java.util.UUID.randomUUID),ext));

cleanupObj = onCleanup(@() cleanup_temp(tmpPath)); %#ok<NASGU>

save(tmpPath,'state');

[ok,msg] = movefile(tmpPath,finalPath,'f');

assert(ok, ...
    'Atomic state replacement failed for %s: %s',finalPath,msg);

clear cleanupObj;

end

function cleanup_temp(tmpPath)

if isfile(tmpPath)
    delete(tmpPath);
end

end

function show_world_patch(ax,filename,R,cx,cy,halfWidth_m,outGSD)

[patch,xVec,yVec] = sample_world_patch_axes( ...
    filename,R,cx,cy,halfWidth_m,outGSD);

imagesc(ax,xVec,yVec,patch);

set(ax,'YDir','normal');
axis(ax,'image');
colormap(ax,gray(256));

xlim(ax,[xVec(1) xVec(end)]);
ylim(ax,[yVec(end) yVec(1)]);

xlabel(ax,'Easting (m)');
ylabel(ax,'Northing (m)');

end

function [patch,xVec,yVec] = sample_world_patch_axes( ...
    filename,R,cx,cy,halfWidth_m,outGSD)

halfPix = round(halfWidth_m/outGSD);

xVec = cx + (-halfPix:halfPix)*outGSD;
yVec = cy + (halfPix:-1:-halfPix)*outGSD;

[XW,YW] = meshgrid(xVec,yVec);
[XI,YI] = worldToIntrinsic(R,XW,YW);

pad = 3;

c1 = max(1,floor(min(XI(:)))-pad);
c2 = min(R.RasterSize(2),ceil(max(XI(:)))+pad);

r1 = max(1,floor(min(YI(:)))-pad);
r2 = min(R.RasterSize(1),ceil(max(YI(:)))+pad);

I = imread(filename,'PixelRegion',{[r1 r2],[c1 c2]});

if ndims(I)==2
    grayI = double(I);
else
    nBands = min(3,size(I,3));
    grayI = mean(double(I(:,:,1:nBands)),3);
end

xLocal = XI-c1+1;
yLocal = YI-r1+1;

patch = interp2(grayI,xLocal,yLocal,'linear',NaN);

if any(~isfinite(patch(:)))
    error('Non-finite samples encountered while sampling review patch.');
end

patch = mat2gray(patch);

end

function plot_all_beam_children(ax,child,fallbackBeam)

if isempty(child)
    return
end

markers = {'o','s','^','d'};

for beam = 1:fallbackBeam

    idx = child(:,3)==beam;

    if any(idx)
        markerIdx = min(beam,numel(markers));

        plot(ax, ...
            child(idx,1),child(idx,2), ...
            markers{markerIdx}, ...
            'MarkerSize',4,'LineWidth',0.8);
    end
end

end

function plot_beam_children(ax,child,beam)

if isempty(child)
    return
end

idx = child(:,3)==beam;

if ~any(idx)
    return
end

plot(ax, ...
    child(idx,1),child(idx,2), ...
    'c.','MarkerSize',8);

end
