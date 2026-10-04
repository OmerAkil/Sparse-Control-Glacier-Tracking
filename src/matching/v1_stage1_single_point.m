function Result = v1_stage1_single_point(cfg,TrustedTable,SourceRow,rasterState)
% v1_stage1_single_point
%
% Single-source-point implementation of the frozen V1 Stage-1 matcher.
%
% This function intentionally preserves the Stage-1 mathematics and
% parameters used by V1.0.0. The only architectural change is that exactly
% ONE source point is processed per call.
%
% Inputs
%   cfg          case_config struct
%   TrustedTable table with:
%                  Point, Epoch1_X, Epoch1_Y, Epoch2_X, Epoch2_Y
%   SourceRow    one-row table with:
%                  Point, Epoch1_X, Epoch1_Y
%   rasterState  optional struct containing f1,f2,R1,R2
%
% Output
%   Result       struct containing the complete Stage-1 state for one point
%
% No Epoch-2 truth is read. validation_only is never used.
%
% MATLAB R2024a + Image Processing Toolbox.

if nargin < 3
    error('v1_stage1_single_point requires cfg, TrustedTable, and SourceRow.');
end

if nargin < 4 || isempty(rasterState)
    rasterState = make_raster_state(cfg);
end

requiredTrusted = { ...
    'Point','Epoch1_X','Epoch1_Y','Epoch2_X','Epoch2_Y'};

requiredSource = { ...
    'Point','Epoch1_X','Epoch1_Y'};

assert(istable(TrustedTable), ...
    'TrustedTable must be a MATLAB table.');

assert(istable(SourceRow) && height(SourceRow)==1, ...
    'SourceRow must be a one-row MATLAB table.');

assert(all(ismember(requiredTrusted,TrustedTable.Properties.VariableNames)), ...
    'TrustedTable has an invalid schema.');

assert(all(ismember(requiredSource,SourceRow.Properties.VariableNames)), ...
    'SourceRow has an invalid schema.');

assert(height(TrustedTable) >= 3, ...
    'At least 3 trusted correspondences are required.');

TrustedLabels = normalize_point_ids(TrustedTable.Point,'trusted');
pointLabel = normalize_point_ids(SourceRow.Point,'source');

assert(numel(unique(TrustedLabels)) == height(TrustedTable), ...
    'Trusted point IDs must be unique.');

assert(isempty(intersect(TrustedLabels,pointLabel)), ...
    'Trusted and source-only point IDs must not overlap.');

TrustedP = [ ...
    TrustedTable.Epoch1_X, ...
    TrustedTable.Epoch1_Y, ...
    TrustedTable.Epoch2_X, ...
    TrustedTable.Epoch2_Y];

SourceP = [SourceRow.Epoch1_X,SourceRow.Epoch1_Y];

TrustedDisp = [ ...
    TrustedP(:,3)-TrustedP(:,1), ...
    TrustedP(:,4)-TrustedP(:,2)];

f1 = rasterState.f1;
f2 = rasterState.f2;
R1 = rasterState.R1;
R2 = rasterState.R2;

%% Frozen V1 Stage-1 parameters.

idwPower = cfg.stage1.idw_power;

coarseGSD = cfg.stage1.coarse_gsd_m;
contextScales_m = cfg.stage1.context_scales_m;

candidateStep_m = cfg.stage1.candidate_step_m;
requestedSearchRadius_m = cfg.stage1.search_radius_m;

topKPerStream = cfg.stage1.top_k_per_stream;
nmsRadius_m = cfg.stage1.nms_radius_m;

partialFraction = cfg.stage1.partial_fraction;
truncDistance_m = cfg.stage1.trunc_distance_m;
orientationWeight_m = cfg.stage1.orientation_weight_m;
smoothSigma_m = cfg.stage1.smooth_sigma_m;

clusterRadius_m = cfg.stage1.cluster_radius_m;
rrfK = cfg.stage1.rrf_k;

candidateStep_px = max(1,round(candidateStep_m/coarseGSD));
candidateStep_m_actual = candidateStep_px*coarseGSD;

searchRadius_px_raw = floor(requestedSearchRadius_m/coarseGSD);
searchRadius_px = ...
    floor(searchRadius_px_raw/candidateStep_px)*candidateStep_px;

searchRadius_m = searchRadius_px*coarseGSD;

shiftVec = ...
    -searchRadius_px:candidateStep_px:searchRadius_px;

truncPix = truncDistance_m/coarseGSD;
orientWeightPix = orientationWeight_m/coarseGSD;
sigmaPix = smoothSigma_m/coarseGSD;

%% IDW prior from the CURRENT trusted set.

Xtr = TrustedP(:,1);
Ytr = TrustedP(:,2);

dEtr = TrustedDisp(:,1);
dNtr = TrustedDisp(:,2);

dist = hypot( ...
    Xtr-SourceP(1), ...
    Ytr-SourceP(2));

[NearestTrustedSeed_m,idxNear] = min(dist);
NearestTrustedSeedPoint = TrustedLabels(idxNear);

distSafe = max(dist,1e-6);

w = 1./(distSafe.^idwPower);
w = w/sum(w);

pred_dE = sum(w.*dEtr);
pred_dN = sum(w.*dNtr);

Xpred = SourceP(1)+pred_dE;
Ypred = SourceP(2)+pred_dN;

PredictedDisp = [pred_dE pred_dN];
PredictedTarget = [Xpred Ypred];

%% Six structural streams around the predicted target.
%
% H columns:
% [dE_from_prediction, dN_from_prediction, streamID, streamRank, score]

H = zeros(0,5);
streamID = 0;

for s = 1:numel(contextScales_m)

    requestedContext_m = contextScales_m(s);

    halfContext_px = ...
        round((requestedContext_m/2)/coarseGSD);

    W = 2*halfContext_px+1;

    sourceHalf_m = halfContext_px*coarseGSD;
    targetHalf_m = sourceHalf_m+searchRadius_m;

    A = sample_world_patch( ...
        f1,R1,SourceP(1),SourceP(2),sourceHalf_m,coarseGSD);

    B = sample_world_patch( ...
        f2,R2,Xpred,Ypred,targetHalf_m,coarseGSD);

    A0 = mat2gray(A);
    B0 = mat2gray(B);

    if sigmaPix > 0
        A0 = imgaussfilt(A0,sigmaPix);
        B0 = imgaussfilt(B0,sigmaPix);
    end

    [Ax,Ay] = imgradientxy(A0,'sobel');
    [Bx,By] = imgradientxy(B0,'sobel');

    Ag = hypot(Ax,Ay);
    Bg = hypot(Bx,By);

    Atheta = atan2d(Ay,Ax);
    Btheta = atan2d(By,Bx);

    EA = edge(A0,'Canny');
    EB = edge(B0,'Canny');

    [edgeR,edgeC] = find(EA);
    nSourceEdges = numel(edgeR);

    scoreMaps = cell(1,2);

    % Gradient NCC.
    C = normxcorr2(Ag,Bg);

    Cvalid = C(W:size(Bg,1),W:size(Bg,2));

    candidateIndices = ...
        1:candidateStep_px:size(Cvalid,1);

    scoreMaps{1} = ...
        Cvalid(candidateIndices,candidateIndices);

    % Oriented partial Chamfer.
    if nSourceEdges < 10 || ~any(EB(:))

        scoreMaps{2} = ...
            nan(numel(shiftVec));

    else

        [Dtarget,nearestEdgeIdx] = bwdist(EB);

        sourceCenter = halfContext_px+1;
        targetCenter = ...
            searchRadius_px+halfContext_px+1;

        dR = edgeR-sourceCenter;
        dC = edgeC-sourceCenter;

        sourceTheta = ...
            Atheta(sub2ind(size(Atheta),edgeR,edgeC));

        orientedScore = ...
            nan(numel(shiftVec),numel(shiftVec));

        keepN = ...
            max(1,ceil(partialFraction*nSourceEdges));

        for iy = 1:numel(shiftVec)

            dy = shiftVec(iy);
            rr = targetCenter+dR+dy;

            for ix = 1:numel(shiftVec)

                dx = shiftVec(ix);
                cc = targetCenter+dC+dx;

                lin = sub2ind(size(Dtarget),rr,cc);

                distVals = ...
                    min(Dtarget(lin),truncPix);

                nearestLin = nearestEdgeIdx(lin);

                targetTheta = Btheta(nearestLin);

                dTheta = abs( ...
                    mod(targetTheta-sourceTheta+90,180)-90);

                orientPenalty = ...
                    orientWeightPix*(dTheta/90);

                combinedPenalty = min( ...
                    distVals+orientPenalty, ...
                    truncPix);

                sortedCombined = ...
                    sort(combinedPenalty,'ascend');

                orientedCost = ...
                    mean(sortedCombined(1:keepN));

                orientedScore(iy,ix) = ...
                    1-orientedCost/truncPix;
            end
        end

        scoreMaps{2} = orientedScore;
    end

    % Retain top hypotheses.
    for m = 1:2

        streamID = streamID+1;

        top = extract_distinct_top_candidates( ...
            scoreMaps{m}, ...
            shiftVec, ...
            coarseGSD, ...
            topKPerStream, ...
            nmsRadius_m);

        if ~isempty(top)

            n = size(top,1);

            H = [
                H
                top(:,1:2), ...
                repmat(streamID,n,1), ...
                (1:n)', ...
                top(:,3)
            ]; %#ok<AGROW>
        end
    end
end

%% Cluster + fused ranking.

labels = cluster_hypotheses(H,clusterRadius_m);
Ctab = summarize_clusters(H,labels);

if ~isempty(Ctab)

    nC = height(Ctab);

    consensusRank = Ctab.ConsensusRank;
    priorDistance = nan(nC,1);

    for b = 1:nC

        members = Ctab.MemberIndices{b};

        priorDistance(b) = min( ...
            hypot(H(members,1),H(members,2)));
    end

    priorRank = ascending_rank(priorDistance);

    fusedScore = ...
        1./(rrfK+consensusRank) + ...
        1./(rrfK+priorRank);

    fusedRank = descending_rank(fusedScore);

    Ctab.PriorDistance_m = priorDistance;
    Ctab.PriorRank = priorRank;
    Ctab.FusedScore = fusedScore;
    Ctab.FusedRank = fusedRank;
end

%% Return complete one-point state.

Result = struct();

Result.Point = pointLabel;
Result.SourceXY = SourceP;

Result.TrustedP = TrustedP;
Result.TrustedLabels = TrustedLabels;
Result.TrustedCount = height(TrustedTable);

Result.PredictedDisp = PredictedDisp;
Result.PredictedTarget = PredictedTarget;

Result.NearestTrustedSeedPoint = NearestTrustedSeedPoint;
Result.NearestTrustedSeed_m = NearestTrustedSeed_m;

Result.IDWWeights = w;
Result.IDWDistances_m = dist;

Result.Hypotheses = H;
Result.ClusterTable = Ctab;

Result.Parameters = struct( ...
    'idwPower',idwPower, ...
    'rrfK',rrfK, ...
    'coarseGSD',coarseGSD, ...
    'contextScales_m',contextScales_m, ...
    'candidateStep_m_actual',candidateStep_m_actual, ...
    'searchRadius_m',searchRadius_m, ...
    'clusterRadius_m',clusterRadius_m);

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

assert(strcmp(class(state.R1),class(state.R2)), ...
    'Epoch raster reference types differ.');

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

function top = extract_distinct_top_candidates( ...
    Smap,shiftVec,gsd,K,nmsRadius_m)

top = zeros(0,3);

valid = isfinite(Smap);

if ~any(valid(:))
    return
end

tmp = Smap;
tmp(~valid) = -Inf;

[~,order] = sort(tmp(:),'descend');

chosen = zeros(0,2);

for q = 1:numel(order)

    idx = order(q);

    if ~isfinite(tmp(idx))
        break
    end

    [iy,ix] = ind2sub(size(tmp),idx);

    dE = shiftVec(ix)*gsd;
    dN = -shiftVec(iy)*gsd;

    xy = [dE dN];

    if isempty(chosen)
        keep = true;
    else
        d = hypot(xy(1)-chosen(:,1),xy(2)-chosen(:,2));
        keep = all(d >= nmsRadius_m);
    end

    if keep

        top(end+1,:) = [dE dN tmp(idx)]; %#ok<AGROW>
        chosen(end+1,:) = xy; %#ok<AGROW>

        if size(top,1) >= K
            break
        end
    end
end

end

function labels = cluster_hypotheses(H,radius_m)

n = size(H,1);
labels = zeros(n,1);

if n==0
    return
end

clusterID = 0;

for i = 1:n

    if labels(i)~=0
        continue
    end

    clusterID = clusterID+1;
    labels(i) = clusterID;

    queue = i;

    while ~isempty(queue)

        current = queue(1);
        queue(1) = [];

        d = hypot( ...
            H(:,1)-H(current,1), ...
            H(:,2)-H(current,2));

        nbr = find(d <= radius_m & labels==0);

        if ~isempty(nbr)
            labels(nbr) = clusterID;
            queue = [queue; nbr]; %#ok<AGROW>
        end
    end
end

end

function C = summarize_clusters(H,labels)

ids = unique(labels(labels>0));

if isempty(ids)
    C = table();
    return
end

nC = numel(ids);

ClusterID = nan(nC,1);
DistinctStreams = nan(nC,1);
VoteCount = nan(nC,1);
ReciprocalRankSupport = nan(nC,1);
BestMemberRank = nan(nC,1);
Compactness_m = nan(nC,1);
MemberIndices = cell(nC,1);

for k = 1:nC

    idx = find(labels==ids(k));

    X = H(idx,1);
    Y = H(idx,2);
    streams = H(idx,3);
    ranks = H(idx,4);

    n = numel(idx);

    if n==1
        medoidLocal = 1;
    else
        sumD = zeros(n,1);

        for j = 1:n
            sumD(j) = sum(hypot(X-X(j),Y-Y(j)));
        end

        [~,medoidLocal] = min(sumD);
    end

    ae = X(medoidLocal);
    an = Y(medoidLocal);

    ClusterID(k) = ids(k);
    DistinctStreams(k) = numel(unique(streams));
    VoteCount(k) = n;
    ReciprocalRankSupport(k) = sum(1./ranks);
    BestMemberRank(k) = min(ranks);
    Compactness_m(k) = median(hypot(X-ae,Y-an));
    MemberIndices{k} = idx;
end

C = table( ...
    ClusterID, ...
    DistinctStreams, ...
    VoteCount, ...
    ReciprocalRankSupport, ...
    BestMemberRank, ...
    Compactness_m, ...
    MemberIndices);

sortMatrix = [
    -C.DistinctStreams, ...
    -C.ReciprocalRankSupport, ...
     C.BestMemberRank, ...
     C.Compactness_m
];

[~,ord] = sortrows(sortMatrix,[1 2 3 4]);

C = C(ord,:);
C.ConsensusRank = (1:height(C))';

end

function r = ascending_rank(x)

r = nan(size(x));
valid = isfinite(x);

if ~any(valid)
    return
end

idx = find(valid);
vals = x(valid);

[~,ord] = sort(vals,'ascend');

r(idx(ord)) = (1:numel(ord))';

end

function r = descending_rank(x)

r = nan(size(x));
valid = isfinite(x);

if ~any(valid)
    return
end

idx = find(valid);
vals = x(valid);

[~,ord] = sort(vals,'descend');

r(idx(ord)) = (1:numel(ord))';

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
