function v1_stage5_field_qc(caseName)
% v1_stage5_field_qc
%
% Generic V1 scientific-analysis Stage 5:
% finalized correspondence field -> displacement/velocity master field + QC.
%
% Reads:
%   cases/<caseName>/case_config.m
%   cases/<caseName>/input/case_metadata.csv
%   cases/<caseName>/output/04_finalized_correspondences/final_correspondences.csv
%   Epoch-1 raster from case_config.m
%
% Writes:
%   cases/<caseName>/output/05_field_qc/
%
% IMPORTANT:
%   - No matching is performed here.
%   - validation_only is never read.
%   - Local IDW residuals are diagnostics only, NOT rejection criteria.
%
% MATLAB R2024a. No Statistics Toolbox required.

if nargin < 1 || strlength(string(caseName)) == 0
    error('Provide a case name, e.g. v1_stage5_field_qc("Glacier_2025_2026").');
end

caseName = char(string(caseName));

%% ============================================================
% 1. LOCATE V1 PROJECT + CASE
% ============================================================

thisFile = mfilename('fullpath');
analysisDir = fileparts(thisFile);
srcDir = fileparts(analysisDir);
v1Root = fileparts(srcDir);

caseRoot = fullfile(v1Root,'cases',caseName);
configFile = fullfile(caseRoot,'case_config.m');

metadataCSV = fullfile( ...
    caseRoot, ...
    'input', ...
    'case_metadata.csv');

finalCSV = fullfile( ...
    caseRoot, ...
    'output', ...
    '04_finalized_correspondences', ...
    'final_correspondences.csv');

outRoot = fullfile( ...
    caseRoot, ...
    'output', ...
    '05_field_qc');

assert(isfolder(caseRoot), ...
    'Case folder not found: %s',caseRoot);

assert(isfile(configFile), ...
    'Case config not found: %s',configFile);

assert(isfile(metadataCSV), ...
    'Case metadata not found: %s',metadataCSV);

assert(isfile(finalCSV), ...
    'Missing finalized correspondence field. Run v1_run_stage4 first: %s',finalCSV);

if ~isfolder(outRoot)
    mkdir(outRoot);
end

clear cfg;
run(configFile);

assert(exist('cfg','var')==1 && isstruct(cfg), ...
    'case_config.m must create a struct named cfg.');

assert(strcmp(char(string(cfg.case_name)),caseName), ...
    'cfg.case_name does not match requested case name.');

%% ============================================================
% 2. LOAD METADATA + FINAL CORRESPONDENCES
% ============================================================

Meta = readtable(metadataCSV,'TextType','string');
Final = readtable(finalCSV,'TextType','string');

assert(height(Meta)==1, ...
    'case_metadata.csv must contain exactly one row.');

assert(ismember('dtDays',Meta.Properties.VariableNames) && ...
       ismember('dtYears',Meta.Properties.VariableNames), ...
    'case_metadata.csv must contain dtDays and dtYears.');

dtDays = Meta.dtDays(1);
dtYears = Meta.dtYears(1);

assert(isfinite(dtYears) && dtYears>0, ...
    'Invalid dtYears in case_metadata.csv.');

requiredFinal = { ...
    'Point', ...
    'Epoch1_X', ...
    'Epoch1_Y', ...
    'Epoch2_X', ...
    'Epoch2_Y', ...
    'Provenance'};

assert(all(ismember(requiredFinal,Final.Properties.VariableNames)), ...
    'final_correspondences.csv has an unexpected schema.');

assert(height(Final)>=3, ...
    'At least 3 finalized correspondences are required.');

assert(numel(unique(Final.Point))==height(Final), ...
    'Final Point IDs are not unique.');

Point = Final.Point;
Epoch1_X = Final.Epoch1_X;
Epoch1_Y = Final.Epoch1_Y;
Epoch2_X = Final.Epoch2_X;
Epoch2_Y = Final.Epoch2_Y;
Provenance = string(Final.Provenance);

n = height(Final);

%% ============================================================
% 3. CASE + ANALYSIS SETTINGS
% ============================================================

epoch1Name = char(string(cfg.epoch1.name));
epoch2Name = char(string(cfg.epoch2.name));
f1 = char(string(cfg.epoch1.raster));

assert(isfile(f1), ...
    'Missing Epoch-1 raster: %s',f1);

kLocal = cfg.analysis.local_qc_neighbors;
localIDWPower = cfg.analysis.local_idw_power;
closeThreshold_m = cfg.analysis.close_pair_threshold_m;
displayGSD = cfg.analysis.display_gsd_m;
margin_m = cfg.analysis.map_margin_m;

kUse = min(kLocal,n-1);

assert(kUse>=1, ...
    'Not enough correspondences for local-neighbor QC.');

%% ============================================================
% 4. DISPLACEMENT / VELOCITY
% ============================================================

dE_m = Epoch2_X-Epoch1_X;
dN_m = Epoch2_Y-Epoch1_Y;

Displacement_m = hypot(dE_m,dN_m);

vE_m_per_year = dE_m/dtYears;
vN_m_per_year = dN_m/dtYears;

Speed_m_per_year = Displacement_m/dtYears;

% Direction measured clockwise from North: 0=N, 90=E.
Direction_EofN_deg = mod(atan2d(dE_m,dN_m),360);

%% ============================================================
% 5. GLOBAL FLOW DIRECTION + FLOW-ALIGNED COMPONENTS
% ============================================================

theta = deg2rad(Direction_EofN_deg);

meanSin = mean(sin(theta));
meanCos = mean(cos(theta));

MeanFlowDirection_EofN_deg = mod(atan2d(meanSin,meanCos),360);
DirectionConcentration_R = hypot(meanSin,meanCos);

flowTheta = deg2rad(MeanFlowDirection_EofN_deg);

% Unit vector along mean flow in East/North.
eAlong = [sin(flowTheta), cos(flowTheta)];

% Positive cross-flow is 90 deg clockwise/right of mean flow.
eCross = [cos(flowTheta), -sin(flowTheta)];

vAlong_m_per_year = ...
    vE_m_per_year*eAlong(1) + ...
    vN_m_per_year*eAlong(2);

vCross_m_per_year = ...
    vE_m_per_year*eCross(1) + ...
    vN_m_per_year*eCross(2);

%% ============================================================
% 6. LOCAL QC: NEAREST NEIGHBOR + KNN-IDW
%
% Diagnostics ONLY. High residual is not automatic rejection.
% ============================================================

XY = [Epoch1_X Epoch1_Y];

D = inf(n,n);

for i = 1:n
    for j = i+1:n

        dij = hypot( ...
            XY(i,1)-XY(j,1), ...
            XY(i,2)-XY(j,2));

        D(i,j) = dij;
        D(j,i) = dij;
    end
end

[NearestSourceDistance_m,nearestIdx] = min(D,[],2);
NearestPoint = Point(nearestIdx);

NearestVectorDifference_m = hypot( ...
    dE_m-dE_m(nearestIdx), ...
    dN_m-dN_m(nearestIdx));

LocalPred_dE_m = nan(n,1);
LocalPred_dN_m = nan(n,1);

for i = 1:n

    [ds,ord] = sort(D(i,:),'ascend');

    ids = ord(1:kUse);
    ds = ds(1:kUse);

    w = 1./(ds.^localIDWPower);
    w = w/sum(w);

    LocalPred_dE_m(i) = sum(w'.*dE_m(ids));
    LocalPred_dN_m(i) = sum(w'.*dN_m(ids));
end

LocalIDWResidual_m = hypot( ...
    dE_m-LocalPred_dE_m, ...
    dN_m-LocalPred_dN_m);

%% ============================================================
% 7. CLOSE SOURCE PAIRS
% ============================================================

PairPoint1 = [];
PairPoint2 = [];
PairSourceDistance_m = [];
PairVectorDifference_m = [];

for i = 1:n-1
    for j = i+1:n

        dij = hypot( ...
            Epoch1_X(i)-Epoch1_X(j), ...
            Epoch1_Y(i)-Epoch1_Y(j));

        if dij < closeThreshold_m

            PairPoint1(end+1,1) = Point(i); %#ok<AGROW>
            PairPoint2(end+1,1) = Point(j); %#ok<AGROW>
            PairSourceDistance_m(end+1,1) = dij; %#ok<AGROW>

            PairVectorDifference_m(end+1,1) = hypot( ...
                dE_m(i)-dE_m(j), ...
                dN_m(i)-dN_m(j)); %#ok<AGROW>
        end
    end
end

ClosePairs = table( ...
    PairPoint1, ...
    PairPoint2, ...
    PairSourceDistance_m, ...
    PairVectorDifference_m);

%% ============================================================
% 8. DELAUNAY COVERAGE DIAGNOSTIC
% ============================================================

DT = delaunayTriangulation(Epoch1_X,Epoch1_Y);

assert(~isempty(DT.ConnectivityList), ...
    ['Finalized source points are degenerate for Delaunay triangulation. ' ...
     'Check spatial coverage.']);

E = edges(DT);

EdgePoint1 = Point(E(:,1));
EdgePoint2 = Point(E(:,2));

EdgeLength_m = hypot( ...
    Epoch1_X(E(:,1))-Epoch1_X(E(:,2)), ...
    Epoch1_Y(E(:,1))-Epoch1_Y(E(:,2)));

DelaunayEdges = table( ...
    EdgePoint1, ...
    EdgePoint2, ...
    EdgeLength_m);

DelaunayEdges = sortrows( ...
    DelaunayEdges, ...
    'EdgeLength_m', ...
    'descend');

%% ============================================================
% 9. MASTER TABLE
% ============================================================

Status = repmat("trusted",n,1);

SelectionMode = repmat("",n,1);

if ismember('SelectionMode',Final.Properties.VariableNames)
    SelectionMode = string(Final.SelectionMode);
end

Master = table( ...
    Point, ...
    Epoch1_X,Epoch1_Y, ...
    Epoch2_X,Epoch2_Y, ...
    dE_m,dN_m, ...
    Displacement_m, ...
    vE_m_per_year, ...
    vN_m_per_year, ...
    Speed_m_per_year, ...
    Direction_EofN_deg, ...
    vAlong_m_per_year, ...
    vCross_m_per_year, ...
    NearestPoint, ...
    NearestSourceDistance_m, ...
    NearestVectorDifference_m, ...
    LocalPred_dE_m, ...
    LocalPred_dN_m, ...
    LocalIDWResidual_m, ...
    Provenance, ...
    SelectionMode, ...
    Status);

masterCSV = fullfile( ...
    outRoot, ...
    'master_correspondence_velocity_qc.csv');

closeCSV = fullfile( ...
    outRoot, ...
    'close_source_pairs.csv');

edgesCSV = fullfile( ...
    outRoot, ...
    'delaunay_edges_sorted_longest_first.csv');

writetable(Master,masterCSV);
writetable(ClosePairs,closeCSV);
writetable(DelaunayEdges,edgesCSV);

%% ============================================================
% 10. CONSOLE SUMMARY
% ============================================================

fprintf('\n============================================================\n');
fprintf(' V1 STAGE 5 - MASTER FIELD QC\n');
fprintf('============================================================\n');

fprintf('Case:            %s\n',caseName);
fprintf('Epoch pair:      %s -> %s\n',epoch1Name,epoch2Name);
fprintf('Trusted vectors: %d\n',n);
fprintf('Time interval:   %.0f days = %.6f yr\n',dtDays,dtYears);

fprintf('\nSpeed [m/yr]:\n');
fprintf('  min:    %.2f\n',min(Speed_m_per_year));
fprintf('  p25:    %.2f\n',simple_percentile(Speed_m_per_year,25));
fprintf('  median: %.2f\n',median(Speed_m_per_year));
fprintf('  mean:   %.2f\n',mean(Speed_m_per_year));
fprintf('  p75:    %.2f\n',simple_percentile(Speed_m_per_year,75));
fprintf('  max:    %.2f\n',max(Speed_m_per_year));

fprintf('\nDirection:\n');
fprintf('  circular mean: %.3f deg E of N\n', ...
    MeanFlowDirection_EofN_deg);
fprintf('  concentration R: %.6f\n', ...
    DirectionConcentration_R);

fprintf('\nSource nearest-neighbor spacing [m]:\n');
fprintf('  min:    %.2f\n',min(NearestSourceDistance_m));
fprintf('  median: %.2f\n',median(NearestSourceDistance_m));
fprintf('  max:    %.2f\n',max(NearestSourceDistance_m));

fprintf('\nClose source pairs < %.1f m: %d\n', ...
    closeThreshold_m,height(ClosePairs));

if ~isempty(ClosePairs)
    disp(ClosePairs);
end

fprintf('\nTOP 10 local KNN-IDW residuals\n');
fprintf('(inspection priority only; NOT automatic rejection):\n');

[~,ordResidual] = sort(LocalIDWResidual_m,'descend');
ordResidual = ordResidual(1:min(10,n));

ResidualReview = Master( ...
    ordResidual, ...
    {'Point','dE_m','dN_m','Speed_m_per_year', ...
     'Direction_EofN_deg','NearestPoint', ...
     'NearestSourceDistance_m','LocalIDWResidual_m'});

disp(ResidualReview);

fprintf('\nTop 10 longest Delaunay edges [coverage diagnostic]:\n');
disp(DelaunayEdges(1:min(10,height(DelaunayEdges)),:));

%% ============================================================
% 11. DISPLAY IMAGE PATCH
% ============================================================

info1 = georasterinfo(f1);
R1 = info1.RasterReference;

xmin = min(Epoch1_X)-margin_m;
xmax = max(Epoch1_X)+margin_m;
ymin = min(Epoch1_Y)-margin_m;
ymax = max(Epoch1_Y)+margin_m;

cx = (xmin+xmax)/2;
cy = (ymin+ymax)/2;

halfWidth_m = max(xmax-xmin,ymax-ymin)/2;

[I1,xVec,yVec] = sample_world_patch_axes( ...
    f1,R1,cx,cy,halfWidth_m,displayGSD);

Irgb = repmat(I1,[1 1 3]);

%% ============================================================
% 12. FIGURE 1 - INTERVAL DISPLACEMENT FIELD
% ============================================================

f = figure('Color','w','Position',[80 80 1050 900]);

imagesc(xVec,yVec,I1);
set(gca,'YDir','normal');
axis image;
colormap(gray(256));
hold on;

quiver( ...
    Epoch1_X,Epoch1_Y, ...
    dE_m,dN_m, ...
    0, ...
    'LineWidth',1.4, ...
    'MaxHeadSize',0.5);

scatter(Epoch1_X,Epoch1_Y,30,'filled');

for i = 1:n
    text( ...
        Epoch1_X(i)+1.0, ...
        Epoch1_Y(i)+1.0, ...
        sprintf('P%d',Point(i)), ...
        'FontSize',7);
end

xlabel('Easting (m)');
ylabel('Northing (m)');

title(sprintf( ...
    '%d trusted horizontal displacement vectors - %.0f day interval', ...
    n,dtDays));

xlim([xmin xmax]);
ylim([ymin ymax]);

exportgraphics( ...
    f, ...
    fullfile(outRoot,'01_displacement_vectors.png'), ...
    'Resolution',220);

%% ============================================================
% 13. FIGURE 2 - SPEED MAP
% ============================================================

f = figure('Color','w','Position',[100 100 1050 900]);

image(xVec,yVec,Irgb);
set(gca,'YDir','normal');
axis image;
hold on;

scatter( ...
    Epoch1_X,Epoch1_Y, ...
    80, ...
    Speed_m_per_year, ...
    'filled', ...
    'MarkerEdgeColor','k', ...
    'LineWidth',0.7);

colormap(gca,turbo(256));

cmin = floor(min(Speed_m_per_year));
cmax = ceil(max(Speed_m_per_year));

if cmax<=cmin
    cmax = cmin+1;
end

caxis([cmin cmax]);

cb = colorbar;
cb.Label.String = 'Speed (m/yr)';

for i = 1:n
    text( ...
        Epoch1_X(i)+1.0, ...
        Epoch1_Y(i)+1.0, ...
        sprintf('P%d',Point(i)), ...
        'FontSize',7);
end

xlabel('Easting (m)');
ylabel('Northing (m)');
title(sprintf('%d trusted horizontal speeds',n));

xlim([xmin xmax]);
ylim([ymin ymax]);

exportgraphics( ...
    f, ...
    fullfile(outRoot,'02_speed_map.png'), ...
    'Resolution',220);

%% ============================================================
% 14. FIGURE 3 - LOCAL CONSISTENCY RESIDUAL
% ============================================================

f = figure('Color','w','Position',[120 120 1050 900]);

image(xVec,yVec,Irgb);
set(gca,'YDir','normal');
axis image;
hold on;

scatter( ...
    Epoch1_X,Epoch1_Y, ...
    80, ...
    LocalIDWResidual_m, ...
    'filled', ...
    'MarkerEdgeColor','k', ...
    'LineWidth',0.7);

colormap(gca,turbo(256));

resMax = max(LocalIDWResidual_m);

if resMax<=0
    resMax = 1;
end

caxis([0 ceil(resMax)]);

cb = colorbar;
cb.Label.String = sprintf( ...
    '%d-neighbor IDW displacement residual (m)',kUse);

for i = 1:n
    text( ...
        Epoch1_X(i)+1.0, ...
        Epoch1_Y(i)+1.0, ...
        sprintf('P%d',Point(i)), ...
        'FontSize',7);
end

xlabel('Easting (m)');
ylabel('Northing (m)');

title({ ...
    'Local vector-consistency diagnostic', ...
    'QC only - high residual does not automatically mean an error'});

xlim([xmin xmax]);
ylim([ymin ymax]);

exportgraphics( ...
    f, ...
    fullfile(outRoot,'03_local_IDW_residual_map.png'), ...
    'Resolution',220);

%% ============================================================
% 15. FIGURE 4 - SPATIAL COVERAGE / DELAUNAY
% ============================================================

f = figure('Color','w','Position',[140 140 1050 900]);

imagesc(xVec,yVec,I1);
set(gca,'YDir','normal');
axis image;
colormap(gca,gray(256));
hold on;

triplot( ...
    DT.ConnectivityList, ...
    Epoch1_X,Epoch1_Y, ...
    'LineWidth',0.7);

scatter(Epoch1_X,Epoch1_Y,35,'filled');

for i = 1:n
    text( ...
        Epoch1_X(i)+1.0, ...
        Epoch1_Y(i)+1.0, ...
        sprintf('P%d',Point(i)), ...
        'FontSize',7);
end

xlabel('Easting (m)');
ylabel('Northing (m)');
title(sprintf('%d-point spatial coverage - Delaunay triangulation',n));

xlim([xmin xmax]);
ylim([ymin ymax]);

exportgraphics( ...
    f, ...
    fullfile(outRoot,'04_spatial_coverage_delaunay.png'), ...
    'Resolution',220);

%% ============================================================
% 16. FIGURE 5 - SPEED VS EASTING
% ============================================================

f = figure('Color','w','Position',[160 160 900 650]);

scatter(Epoch1_X,Speed_m_per_year,60,'filled');
hold on;

for i = 1:n
    text( ...
        Epoch1_X(i)+0.7, ...
        Speed_m_per_year(i)+0.15, ...
        sprintf('P%d',Point(i)), ...
        'FontSize',7);
end

xlabel(sprintf('%s Easting (m)',epoch1Name));
ylabel('Speed (m/yr)');
title('Trusted horizontal speed vs Easting');
grid on;

exportgraphics( ...
    f, ...
    fullfile(outRoot,'05_speed_vs_easting.png'), ...
    'Resolution',220);

%% ============================================================
% 17. SAVE MAT
% ============================================================

matOut = fullfile( ...
    outRoot, ...
    'field_qc.mat');

save(matOut, ...
    'cfg', ...
    'caseName', ...
    'Final', ...
    'Master', ...
    'ClosePairs', ...
    'DelaunayEdges', ...
    'dtDays', ...
    'dtYears', ...
    'MeanFlowDirection_EofN_deg', ...
    'DirectionConcentration_R', ...
    'eAlong', ...
    'eCross', ...
    'kUse', ...
    'localIDWPower');

fprintf('\nSaved master CSV:\n%s\n',masterCSV);
fprintf('\nSaved close-pair CSV:\n%s\n',closeCSV);
fprintf('\nSaved Delaunay-edge CSV:\n%s\n',edgesCSV);
fprintf('\nSaved MAT:\n%s\n',matOut);

fprintf('\n============================================================\n');
fprintf(' V1 STAGE 5 COMPLETE\n');
fprintf('============================================================\n');

end

%% ============================================================
% LOCAL FUNCTIONS
% ============================================================

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
    error('Non-finite image samples encountered.');
end

patch = mat2gray(patch);

end

function q = simple_percentile(x,p)
% Linear percentile interpolation without Statistics Toolbox.

x = sort(x(:));

n = numel(x);

if n==0
    q = NaN;
    return
end

if n==1
    q = x;
    return
end

pos = 1 + (p/100)*(n-1);

lo = floor(pos);
hi = ceil(pos);

if lo==hi
    q = x(lo);
else
    a = pos-lo;
    q = (1-a)*x(lo) + a*x(hi);
end

end
