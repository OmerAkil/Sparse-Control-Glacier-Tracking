function Result = v1_stage2_single_point(cfg,SourceRow,Stage1Result,rasterState)
% v1_stage2_single_point
%
% Single-source-point implementation of the frozen V1 Stage-2
% parent-preserving refinement.
%
% This function preserves the V1.0.0 Stage-2 mathematics. Exactly ONE
% source point is processed per call.
%
% Inputs
%   cfg           case_config struct
%   SourceRow     one-row table: Point, Epoch1_X, Epoch1_Y
%   Stage1Result  struct returned by v1_stage1_single_point
%   rasterState   optional struct containing f1,f2,R1,R2
%
% Output
%   Result        complete Stage-2 state for one point
%
% No Epoch-2 truth is read.
%
% MATLAB R2024a + Image Processing Toolbox.

if nargin < 3
    error('v1_stage2_single_point requires cfg, SourceRow, and Stage1Result.');
end

if nargin < 4 || isempty(rasterState)
    rasterState = make_raster_state(cfg);
end

requiredSource = {'Point','Epoch1_X','Epoch1_Y'};

assert(istable(SourceRow) && height(SourceRow)==1, ...
    'SourceRow must be a one-row MATLAB table.');

assert(all(ismember(requiredSource,SourceRow.Properties.VariableNames)), ...
    'SourceRow has an invalid schema.');

pointLabel = normalize_point_ids(SourceRow.Point,'source');

assert(Stage1Result.Point==pointLabel, ...
    'SourceRow Point does not match Stage1Result.Point.');

SourceP = [SourceRow.Epoch1_X,SourceRow.Epoch1_Y];

H = Stage1Result.Hypotheses;
Ctab = Stage1Result.ClusterTable;

PredictedDisp = Stage1Result.PredictedDisp;
PredictedTarget = Stage1Result.PredictedTarget;

Xpred = PredictedTarget(1);
Ypred = PredictedTarget(2);

f1 = rasterState.f1;
f2 = rasterState.f2;
R1 = rasterState.R1;
R2 = rasterState.R2;

%% Frozen V1 Stage-2 parameters.

nVisualClusters = cfg.stage2.n_visual_clusters;

localRadius_m = cfg.stage2.local_radius_m;
candidateStep_m = cfg.stage2.candidate_step_m;

workingGSD = cfg.stage2.working_gsd_m;
context_m = cfg.stage2.context_m;

partialFraction = cfg.stage2.partial_fraction;
truncDistance_m = cfg.stage2.trunc_distance_m;
orientationWeight_m = cfg.stage2.orientation_weight_m;
smoothSigma_m = cfg.stage2.smooth_sigma_m;

topKPerParentPerMethod = cfg.stage2.top_k_per_parent_per_method;
parentNMS_m = cfg.stage2.parent_nms_m;

halfWpx = round((context_m/2)/workingGSD);
W = 2*halfWpx+1;

sigmaPix = smoothSigma_m/workingGSD;
truncPix = truncDistance_m/workingGSD;
orientWeightPix = orientationWeight_m/workingGSD;

%% Select top fused visual clusters.

parents = zeros(0,4);
% columns: dE, dN, beamRank, isFallback

beamCentersOff = nan(nVisualClusters+1,2);

if ~isempty(Ctab)

    [~,ord] = sort(Ctab.FusedRank,'ascend');

    nKeep = min(nVisualClusters,numel(ord));

    for q = 1:nKeep

        b = ord(q);

        members = Ctab.MemberIndices{b};

        thisParents = H(members,1:2);

        parents = [ ...
            parents; ...
            thisParents, ...
            repmat(q,size(thisParents,1),1), ...
            zeros(size(thisParents,1),1) ...
        ]; %#ok<AGROW>

        beamCentersOff(q,:) = spatial_medoid(thisParents);
    end
end

fallbackBeam = nVisualClusters+1;

parents = [ ...
    parents; ...
    0 0 fallbackBeam 1 ...
];

beamCentersOff(fallbackBeam,:) = [0 0];

parents = collapse_parents_by_beam(parents);

ParentCount = size(parents,1);

BeamCentersOffset = beamCentersOff;
BeamCentersWorld = [ ...
    Xpred + beamCentersOff(:,1), ...
    Ypred + beamCentersOff(:,2) ...
];

%% Source structural representation.

A = sample_world_patch( ...
    f1,R1,SourceP(1),SourceP(2), ...
    halfWpx*workingGSD,workingGSD);

A0 = mat2gray(A);

if sigmaPix > 0
    A0 = imgaussfilt(A0,sigmaPix);
end

[Ax,Ay] = imgradientxy(A0,'sobel');

Ag = hypot(Ax,Ay);
Atheta = atan2d(Ay,Ax);

EA = edge(A0,'Canny');

[edgeR,edgeC] = find(EA);

sourceCenter = halfWpx+1;

dR = edgeR-sourceCenter;
dC = edgeC-sourceCenter;

sourceTheta = Atheta(sub2ind(size(Atheta),edgeR,edgeC));

nSourceEdges = numel(edgeR);
keepForward = max(1,ceil(partialFraction*nSourceEdges));

%% Build union scoring grid.

localSets = cell(size(parents,1),1);
unionXY = zeros(0,2);

for j = 1:size(parents,1)

    localSets{j} = build_local_candidates( ...
        parents(j,1:2), ...
        localRadius_m, ...
        candidateStep_m);

    unionXY = [ ...
        unionXY; ...
        localSets{j} ...
    ]; %#ok<AGROW>
end

unionXY = unique(round(unionXY,6),'rows','stable');

maxAbsCandidate = max(abs(unionXY(:)));

targetHalfPix = ceil( ...
    (maxAbsCandidate + context_m/2 + 0.2)/workingGSD);

targetHalf_m = targetHalfPix*workingGSD;

B = sample_world_patch( ...
    f2,R2,Xpred,Ypred,targetHalf_m,workingGSD);

B0 = mat2gray(B);

if sigmaPix > 0
    B0 = imgaussfilt(B0,sigmaPix);
end

[Bx,By] = imgradientxy(B0,'sobel');

Bg = hypot(Bx,By);
Btheta = atan2d(By,Bx);

EB = edge(B0,'Canny');

if any(EB(:))
    [Dtarget,nearestTargetIdx] = bwdist(EB);
else
    Dtarget = [];
    nearestTargetIdx = [];
end

targetCenterRow = round((size(B0,1)+1)/2);
targetCenterCol = round((size(B0,2)+1)/2);

%% Score union once.

XC = normxcorr2(Ag,Bg);
XCvalid = XC(W:size(Bg,1),W:size(Bg,2));

gradScoresUnion = nan(size(unionXY,1),1);
orientScoresUnion = nan(size(unionXY,1),1);

for c = 1:size(unionXY,1)

    dE = unionXY(c,1);
    dN = unionXY(c,2);

    dxPix = round(dE/workingGSD);
    dyRowPix = round(-dN/workingGSD);

    centerRow = targetCenterRow+dyRowPix;
    centerCol = targetCenterCol+dxPix;

    % Gradient NCC.
    topRow = centerRow-halfWpx;
    topCol = centerCol-halfWpx;

    if topRow >= 1 && topCol >= 1 && ...
       topRow <= size(XCvalid,1) && ...
       topCol <= size(XCvalid,2)

        gradScoresUnion(c) = XCvalid(topRow,topCol);
    end

    % Oriented partial Chamfer.
    if nSourceEdges >= 10 && ~isempty(Dtarget)

        rr = centerRow+dR;
        cc = centerCol+dC;

        inside = ...
            rr >= 1 & rr <= size(Dtarget,1) & ...
            cc >= 1 & cc <= size(Dtarget,2);

        if all(inside)

            lin = sub2ind(size(Dtarget),rr,cc);

            distVals = min(Dtarget(lin),truncPix);
            nearestLin = nearestTargetIdx(lin);
            targetTheta = Btheta(nearestLin);

            dTheta = abs( ...
                mod(targetTheta-sourceTheta+90,180)-90);

            penalty = min( ...
                distVals + orientWeightPix*(dTheta/90), ...
                truncPix);

            sortedPenalty = sort(penalty,'ascend');

            cost = mean(sortedPenalty(1:keepForward));

            orientScoresUnion(c) = ...
                1-cost/truncPix;
        end
    end
end

%% Extract top children per parent and method.

child = zeros(0,7);

for j = 1:size(parents,1)

    localXY = localSets{j};

    [tf,loc] = ismember( ...
        round(localXY,6), ...
        round(unionXY,6), ...
        'rows');

    assert(all(tf), ...
        'Local candidates missing from union grid.');

    topG = extract_distinct_candidates( ...
        localXY, ...
        gradScoresUnion(loc), ...
        topKPerParentPerMethod, ...
        parentNMS_m);

    topO = extract_distinct_candidates( ...
        localXY, ...
        orientScoresUnion(loc), ...
        topKPerParentPerMethod, ...
        parentNMS_m);

    for k = 1:size(topG,1)

        child(end+1,:) = [ ...
            topG(k,1), ...
            topG(k,2), ...
            parents(j,3), ...
            j, ...
            1, ...
            k, ...
            topG(k,3) ...
        ]; %#ok<AGROW>
    end

    for k = 1:size(topO,1)

        child(end+1,:) = [ ...
            topO(k,1), ...
            topO(k,2), ...
            parents(j,3), ...
            j, ...
            2, ...
            k, ...
            topO(k,3) ...
        ]; %#ok<AGROW>
    end
end

if isempty(child)

    childWorld = zeros(0,7);
    UniqueChildCount = 0;

else

    childWorld = child;

    childWorld(:,1) = Xpred + child(:,1);
    childWorld(:,2) = Ypred + child(:,2);

    UniqueChildCount = size( ...
        unique(round(child(:,1:2),6),'rows'), ...
        1);
end

ChildCountBeam1 = nnz(child(:,3)==1);
ChildCountBeam2 = nnz(child(:,3)==2);
ChildCountBeam3 = nnz(child(:,3)==3);
ChildCountFallback = nnz(child(:,3)==fallbackBeam);

%% Return complete one-point state.

Result = struct();

Result.Point = pointLabel;
Result.SourceXY = SourceP;

Result.PredictedDisp = PredictedDisp;
Result.PredictedTarget = PredictedTarget;

Result.Parents = parents;
Result.ParentCount = ParentCount;

Result.Children = child;
Result.ChildrenWorld = childWorld;

Result.BeamCentersOffset = BeamCentersOffset;
Result.BeamCentersWorld = BeamCentersWorld;

Result.UniqueChildCount = UniqueChildCount;
Result.ChildCountBeam1 = ChildCountBeam1;
Result.ChildCountBeam2 = ChildCountBeam2;
Result.ChildCountBeam3 = ChildCountBeam3;
Result.ChildCountFallback = ChildCountFallback;

Result.Parameters = struct( ...
    'nVisualClusters',nVisualClusters, ...
    'fallbackBeam',fallbackBeam, ...
    'localRadius_m',localRadius_m, ...
    'candidateStep_m',candidateStep_m, ...
    'workingGSD',workingGSD, ...
    'context_m',context_m, ...
    'topKPerParentPerMethod',topKPerParentPerMethod);

end

function state = make_raster_state(cfg)

f1 = char(string(cfg.epoch1.raster));
f2 = char(string(cfg.epoch2.raster));

assert(isfile(f1),'Missing Epoch 1 raster: %s',f1);
assert(isfile(f2),'Missing Epoch 2 raster: %s',f2);

info1 = georasterinfo(f1);
info2 = georasterinfo(f2);

state = struct();
state.f1 = f1;
state.f2 = f2;
state.R1 = info1.RasterReference;
state.R2 = info2.RasterReference;

end

function XY = build_local_candidates(anchor,radius_m,step_m)

offsets = -radius_m:step_m:radius_m;

[DX,DY] = meshgrid(offsets,offsets);

XY = [ ...
    anchor(1)+DX(:), ...
    anchor(2)+DY(:) ...
];

XY = unique(round(XY,6),'rows','stable');

end

function patch = sample_world_patch(filename,R,cx,cy,halfWidth_m,outGSD)

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
    gray = double(I);
else
    nBands = min(3,size(I,3));
    gray = mean(double(I(:,:,1:nBands)),3);
end

xLocal = XI-c1+1;
yLocal = YI-r1+1;

patch = interp2(gray,xLocal,yLocal,'linear',NaN);

if any(~isfinite(patch(:)))
    error('Non-finite samples encountered.');
end

end

function top = extract_distinct_candidates(candidateXY,scores,K,nmsRadius_m)

top = zeros(0,3);

valid = isfinite(scores);

if ~any(valid)
    return
end

tmp = scores;
tmp(~valid) = -Inf;

[~,order] = sort(tmp,'descend');

chosenXY = zeros(0,2);

for q = 1:numel(order)

    idx = order(q);

    if ~isfinite(tmp(idx))
        break
    end

    xy = candidateXY(idx,:);

    if isempty(chosenXY)
        keep = true;
    else
        d = hypot( ...
            xy(1)-chosenXY(:,1), ...
            xy(2)-chosenXY(:,2));

        keep = all(d >= nmsRadius_m);
    end

    if keep

        top(end+1,:) = [xy tmp(idx)]; %#ok<AGROW>
        chosenXY(end+1,:) = xy; %#ok<AGROW>

        if size(top,1) >= K
            break
        end
    end
end

end

function parentsOut = collapse_parents_by_beam(parentsIn)

if isempty(parentsIn)
    parentsOut = parentsIn;
    return
end

key = [ ...
    round(parentsIn(:,1:2),6), ...
    parentsIn(:,3) ...
];

[~,ia] = unique(key,'rows','stable');

parentsOut = parentsIn(ia,:);

end

function m = spatial_medoid(XY)

if isempty(XY)
    m = [NaN NaN];
    return
end

if size(XY,1)==1
    m = XY(1,:);
    return
end

sumD = zeros(size(XY,1),1);

for i = 1:size(XY,1)
    sumD(i) = sum(hypot( ...
        XY(:,1)-XY(i,1), ...
        XY(:,2)-XY(i,2)));
end

[~,idx] = min(sumD);

m = XY(idx,:);

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

assert(all(ids > 0 & ids == floor(ids)), ...
    '%s Point IDs must be positive integers.',label);

end
