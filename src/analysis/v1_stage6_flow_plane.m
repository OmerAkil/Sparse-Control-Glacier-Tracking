function v1_stage6_flow_plane(caseName)
% v1_stage6_flow_plane
%
% Generic V1 scientific-analysis Stage 6:
% master velocity field -> flow-aligned affine velocity-plane analysis.
%
% Reads:
%   cases/<caseName>/case_config.m
%   cases/<caseName>/output/05_field_qc/field_qc.mat
%   Epoch-1 raster from case_config.m
%
% Writes:
%   cases/<caseName>/output/06_flow_aligned_plane/
%
% PHYSICAL COORDINATE SYSTEM
%   x_along : positive in circular-mean flow direction
%   y_cross : positive 90 deg clockwise/right of mean flow direction
%
% PRIMARY MODEL
%   v_along = beta0 + beta_x*x_along + beta_y*y_cross
%
% SECONDARY MODEL
%   v_cross = gamma0 + gamma_x*x_along + gamma_y*y_cross
%
% IMPORTANT:
%   d(v_along)/d(y_cross) is a cross-glacier GRADIENT of forward speed.
%   It is not the same quantity as v_cross.
%
% MATLAB R2024a. No Statistics Toolbox required.

if nargin < 1 || strlength(string(caseName)) == 0
    error('Provide a case name, e.g. v1_stage6_flow_plane("Glacier_2025_2026").');
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

stage5Mat = fullfile( ...
    caseRoot, ...
    'output', ...
    '05_field_qc', ...
    'field_qc.mat');

outRoot = fullfile( ...
    caseRoot, ...
    'output', ...
    '06_flow_aligned_plane');

assert(isfolder(caseRoot), ...
    'Case folder not found: %s',caseRoot);

assert(isfile(configFile), ...
    'Case config not found: %s',configFile);

assert(isfile(stage5Mat), ...
    'Missing Stage-5 MAT. Run v1_run_stage5 first: %s',stage5Mat);

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
% 2. LOAD MASTER VELOCITY FIELD
% ============================================================

S = load(stage5Mat, ...
    'Master', ...
    'dtDays', ...
    'dtYears');

M = S.Master;
dtDays = S.dtDays;
dtYears = S.dtYears;

requiredMaster = { ...
    'Point', ...
    'Epoch1_X', ...
    'Epoch1_Y', ...
    'vE_m_per_year', ...
    'vN_m_per_year', ...
    'Speed_m_per_year', ...
    'Direction_EofN_deg'};

assert(all(ismember(requiredMaster,M.Properties.VariableNames)), ...
    'Stage-5 Master table has an unexpected schema.');

Point = M.Point;

Epoch1_X = M.Epoch1_X;
Epoch1_Y = M.Epoch1_Y;

vE = M.vE_m_per_year;
vN = M.vN_m_per_year;

Speed = M.Speed_m_per_year;
Direction = M.Direction_EofN_deg;

n = height(M);

assert(n>=4, ...
    'At least 4 trusted vectors are required for a 3-parameter plane fit.');

%% ============================================================
% 3. CASE SETTINGS
% ============================================================

epoch1Name = char(string(cfg.epoch1.name));
epoch2Name = char(string(cfg.epoch2.name));
f1 = char(string(cfg.epoch1.raster));

assert(isfile(f1), ...
    'Missing Epoch-1 raster: %s',f1);

displayGSD = cfg.analysis.display_gsd_m;
margin_m = cfg.analysis.map_margin_m;

%% ============================================================
% 4. CIRCULAR-MEAN FLOW DIRECTION
% ============================================================

theta = deg2rad(Direction);

meanSin = mean(sin(theta));
meanCos = mean(cos(theta));

meanFlowDeg = mod(atan2d(meanSin,meanCos),360);
Rdir = hypot(meanSin,meanCos);

flowTheta = deg2rad(meanFlowDeg);

% Direction is measured clockwise from North.
eAlong = [ ...
    sin(flowTheta), ...
    cos(flowTheta) ...
];

% Positive cross-flow is 90 deg clockwise/right of mean flow.
eCross = [ ...
    cos(flowTheta), ...
   -sin(flowTheta) ...
];

%% ============================================================
% 5. FLOW-ALIGNED SOURCE COORDINATES
% ============================================================

E0 = mean(Epoch1_X);
N0 = mean(Epoch1_Y);

dEpos = Epoch1_X-E0;
dNpos = Epoch1_Y-N0;

x_along_m = ...
    dEpos*eAlong(1) + ...
    dNpos*eAlong(2);

y_cross_m = ...
    dEpos*eCross(1) + ...
    dNpos*eCross(2);

%% ============================================================
% 6. FLOW-ALIGNED VELOCITY COMPONENTS
% ============================================================

v_along = ...
    vE*eAlong(1) + ...
    vN*eAlong(2);

v_cross = ...
    vE*eCross(1) + ...
    vN*eCross(2);

%% ============================================================
% 7. PRIMARY OLS PLANE: v_along
% ============================================================

A = [ ...
    ones(n,1), ...
    x_along_m, ...
    y_cross_m ...
];

assert(rank(A)==3, ...
    ['Flow-plane design matrix is rank deficient. ' ...
     'Check spatial distribution of finalized controls.']);

beta = A\v_along;

vAlong_fit = A*beta;
vAlong_resid = v_along-vAlong_fit;

SSE = sum(vAlong_resid.^2);
SST = sum((v_along-mean(v_along)).^2);

if SST>0
    R2_along = 1-SSE/SST;
else
    R2_along = NaN;
end

RMSE_along = sqrt(mean(vAlong_resid.^2));

df = n-size(A,2);

assert(df>0, ...
    'Not enough degrees of freedom for coefficient uncertainty.');

sigma2 = SSE/df;

covBeta = sigma2*pinv(A'*A);
seBeta = sqrt(diag(covBeta));

% 95% normal approximation, matching the validated historical workflow.
ci95Low = beta-1.96*seBeta;
ci95High = beta+1.96*seBeta;

beta0 = beta(1);
beta_x = beta(2);
beta_y = beta(3);

gradAlong_per100 = beta_x*100;
gradCross_per100 = beta_y*100;

gradientMagnitude_per100 = hypot(beta_x,beta_y)*100;

if abs(beta_x)>0
    crossToAlongGradientRatio = abs(beta_y/beta_x);
else
    crossToAlongGradientRatio = Inf;
end

%% ============================================================
% 8. SECONDARY OLS PLANE: v_cross
% ============================================================

gamma = A\v_cross;

vCross_fit = A*gamma;
vCross_resid = v_cross-vCross_fit;

SSEcross = sum(vCross_resid.^2);
SSTcross = sum((v_cross-mean(v_cross)).^2);

if SSTcross>0
    R2_cross = 1-SSEcross/SSTcross;
else
    R2_cross = NaN;
end

RMSE_cross = sqrt(mean(vCross_resid.^2));

%% ============================================================
% 9. RESULT TABLE
% ============================================================

FlowTable = table( ...
    Point, ...
    Epoch1_X,Epoch1_Y, ...
    x_along_m, ...
    y_cross_m, ...
    vE,vN, ...
    Speed, ...
    Direction, ...
    v_along, ...
    v_cross, ...
    vAlong_fit, ...
    vAlong_resid, ...
    vCross_fit, ...
    vCross_resid, ...
    'VariableNames',{ ...
        'Point', ...
        'Epoch1_X', ...
        'Epoch1_Y', ...
        'x_along_m', ...
        'y_cross_m', ...
        'vE_m_per_year', ...
        'vN_m_per_year', ...
        'Speed_m_per_year', ...
        'Direction_EofN_deg', ...
        'v_along_m_per_year', ...
        'v_cross_m_per_year', ...
        'v_along_fit_m_per_year', ...
        'v_along_residual_m_per_year', ...
        'v_cross_fit_m_per_year', ...
        'v_cross_residual_m_per_year'});

csvOut = fullfile( ...
    outRoot, ...
    'flow_aligned_plane_results.csv');

writetable(FlowTable,csvOut);

%% ============================================================
% 10. CONSOLE SUMMARY
% ============================================================

fprintf('\n============================================================\n');
fprintf(' V1 STAGE 6 - FLOW-ALIGNED VELOCITY PLANE\n');
fprintf('============================================================\n');

fprintf('Case:       %s\n',caseName);
fprintf('Epoch pair: %s -> %s\n',epoch1Name,epoch2Name);
fprintf('Vectors:    %d\n',n);
fprintf('Interval:   %.0f days = %.6f yr\n',dtDays,dtYears);

fprintf('\nMean flow direction:\n');
fprintf('  %.3f deg E of N\n',meanFlowDeg);
fprintf('  directional concentration R = %.6f\n',Rdir);

fprintf('\nCoordinate origin (source-point centroid):\n');
fprintf('  E0 = %.3f m\n',E0);
fprintf('  N0 = %.3f m\n',N0);

fprintf('\nPRIMARY PLANE\n');
fprintf('  v_along = beta0 + beta_x*x_along + beta_y*y_cross\n\n');

fprintf('  beta0 = %.4f m/yr\n',beta0);
fprintf('  beta_x = %.6f (m/yr)/m\n',beta_x);
fprintf('  beta_y = %.6f (m/yr)/m\n',beta_y);

fprintf('\nEquivalent gradients:\n');
fprintf('  along-flow gradient  = %+.3f m/yr per 100 m\n', ...
    gradAlong_per100);
fprintf('  cross-flow gradient  = %+.3f m/yr per 100 m\n', ...
    gradCross_per100);
fprintf('  gradient magnitude   = %.3f m/yr per 100 m\n', ...
    gradientMagnitude_per100);
fprintf('  |cross/along| slope ratio = %.3f\n', ...
    crossToAlongGradientRatio);

fprintf('\nModel fit:\n');
fprintf('  R^2  = %.4f\n',R2_along);
fprintf('  RMSE = %.3f m/yr\n',RMSE_along);

fprintf('\nApproximate 95%% coefficient intervals:\n');
fprintf('  beta0: [%.4f, %.4f]\n',ci95Low(1),ci95High(1));
fprintf('  beta_x: [%.6f, %.6f]\n',ci95Low(2),ci95High(2));
fprintf('  beta_y: [%.6f, %.6f]\n',ci95Low(3),ci95High(3));

fprintf('\nCross-flow velocity component:\n');
fprintf('  median v_cross   = %.3f m/yr\n',median(v_cross));
fprintf('  mean   v_cross   = %.3f m/yr\n',mean(v_cross));
fprintf('  median |v_cross| = %.3f m/yr\n',median(abs(v_cross)));

fprintf('\nSECONDARY v_cross PLANE:\n');
fprintf('  gamma0 = %.4f m/yr\n',gamma(1));
fprintf('  gamma_x = %.6f (m/yr)/m\n',gamma(2));
fprintf('  gamma_y = %.6f (m/yr)/m\n',gamma(3));
fprintf('  R^2 = %.4f\n',R2_cross);
fprintf('  RMSE = %.3f m/yr\n',RMSE_cross);

%% ============================================================
% 11. BACKGROUND IMAGE FOR MAP FIGURES
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
% 12. FIGURE 1 - FLOW-ALIGNED AXES
% ============================================================

f = figure('Color','w','Position',[80 80 1050 900]);

image(xVec,yVec,Irgb);
set(gca,'YDir','normal');
axis image;
hold on;

scatter(Epoch1_X,Epoch1_Y,35,'filled');

extentScale = max( ...
    max(Epoch1_X)-min(Epoch1_X), ...
    max(Epoch1_Y)-min(Epoch1_Y));

axisLength = max(10,0.25*extentScale);

quiver( ...
    E0,N0, ...
    axisLength*eAlong(1), ...
    axisLength*eAlong(2), ...
    0, ...
    'LineWidth',2.5, ...
    'MaxHeadSize',0.6);

quiver( ...
    E0,N0, ...
    axisLength*eCross(1), ...
    axisLength*eCross(2), ...
    0, ...
    'LineWidth',2.5, ...
    'MaxHeadSize',0.6);

text( ...
    E0+axisLength*eAlong(1), ...
    N0+axisLength*eAlong(2), ...
    '  +x_{along}', ...
    'FontWeight','bold', ...
    'FontSize',11, ...
    'BackgroundColor','w');

text( ...
    E0+axisLength*eCross(1), ...
    N0+axisLength*eCross(2), ...
    '  +y_{cross}', ...
    'FontWeight','bold', ...
    'FontSize',11, ...
    'BackgroundColor','w');

plot(E0,N0,'kp','MarkerSize',12,'MarkerFaceColor','w');

xlabel('Easting (m)');
ylabel('Northing (m)');

title(sprintf( ...
    'Flow-aligned coordinates - mean flow %.2f deg E of N', ...
    meanFlowDeg));

xlim([xmin xmax]);
ylim([ymin ymax]);

exportgraphics( ...
    f, ...
    fullfile(outRoot,'01_flow_aligned_axes.png'), ...
    'Resolution',220);

%% ============================================================
% 13. FIGURE 2 - 3D v_along PLANE
% ============================================================

f = figure('Color','w','Position',[100 100 1000 800]);

scatter3( ...
    x_along_m, ...
    y_cross_m, ...
    v_along, ...
    70, ...
    v_along, ...
    'filled');

hold on;

xg = linspace(min(x_along_m),max(x_along_m),35);
yg = linspace(min(y_cross_m),max(y_cross_m),35);

[XG,YG] = meshgrid(xg,yg);

ZG = ...
    beta0 + ...
    beta_x*XG + ...
    beta_y*YG;

surf( ...
    XG,YG,ZG, ...
    'FaceAlpha',0.35, ...
    'EdgeColor','none');

for i = 1:n
    text( ...
        x_along_m(i), ...
        y_cross_m(i), ...
        v_along(i)+0.25, ...
        sprintf('P%d',Point(i)), ...
        'FontSize',7);
end

xlabel('x_{along} (m)');
ylabel('y_{cross} (m)');
zlabel('v_{along} (m/yr)');

title(sprintf( ...
    'Along-flow velocity plane, R^2 = %.3f', ...
    R2_along));

grid on;
view(42,28);
colorbar;

exportgraphics( ...
    f, ...
    fullfile(outRoot,'02_v_along_plane_3D.png'), ...
    'Resolution',220);

%% ============================================================
% 14. FIGURE 3 - PLANE RESIDUAL MAP
% ============================================================

f = figure('Color','w','Position',[120 120 1050 900]);

image(xVec,yVec,Irgb);
set(gca,'YDir','normal');
axis image;
hold on;

scatter( ...
    Epoch1_X,Epoch1_Y, ...
    90, ...
    vAlong_resid, ...
    'filled', ...
    'MarkerEdgeColor','k', ...
    'LineWidth',0.7);

maxAbsResid = max(abs(vAlong_resid));

if maxAbsResid==0
    maxAbsResid = 1;
end

colormap(gca,turbo(256));
caxis([-maxAbsResid maxAbsResid]);

cb = colorbar;
cb.Label.String = 'v_{along} plane residual (m/yr)';

for i = 1:n
    text( ...
        Epoch1_X(i)+1.0, ...
        Epoch1_Y(i)+1.0, ...
        sprintf('P%d',Point(i)), ...
        'FontSize',7, ...
        'Color','k', ...
        'BackgroundColor','w', ...
        'Margin',0.5);
end

xlabel('Easting (m)');
ylabel('Northing (m)');
title('Along-flow velocity plane residuals');

xlim([xmin xmax]);
ylim([ymin ymax]);

exportgraphics( ...
    f, ...
    fullfile(outRoot,'03_v_along_plane_residual_map.png'), ...
    'Resolution',220);

%% ============================================================
% 15. FIGURE 4 - OBSERVED VS FITTED
% ============================================================

f = figure('Color','w','Position',[140 140 760 700]);

scatter(vAlong_fit,v_along,70,'filled');
hold on;

lo = min([vAlong_fit;v_along]);
hi = max([vAlong_fit;v_along]);

plot([lo hi],[lo hi],'k--','LineWidth',1.5);

for i = 1:n
    text( ...
        vAlong_fit(i)+0.10, ...
        v_along(i)+0.10, ...
        sprintf('P%d',Point(i)), ...
        'FontSize',7);
end

xlabel('Fitted v_{along} (m/yr)');
ylabel('Observed v_{along} (m/yr)');

title(sprintf( ...
    'Observed vs fitted along-flow velocity - R^2 %.3f, RMSE %.2f m/yr', ...
    R2_along,RMSE_along));

grid on;
axis equal;
xlim([lo hi]);
ylim([lo hi]);

exportgraphics( ...
    f, ...
    fullfile(outRoot,'04_observed_vs_fitted_v_along.png'), ...
    'Resolution',220);

%% ============================================================
% 16. FIGURE 5 - PARTIAL ALONG-FLOW GRADIENT
% ============================================================

partialAlong = v_along-beta_y*y_cross_m;

f = figure('Color','w','Position',[160 160 850 650]);

scatter(x_along_m,partialAlong,65,'filled');
hold on;

xx = linspace(min(x_along_m),max(x_along_m),100);

plot( ...
    xx, ...
    beta0+beta_x*xx, ...
    'k-', ...
    'LineWidth',1.8);

for i = 1:n
    text( ...
        x_along_m(i)+1.0, ...
        partialAlong(i)+0.08, ...
        sprintf('P%d',Point(i)), ...
        'FontSize',7);
end

xlabel('x_{along} (m)');
ylabel('v_{along} - \beta_y y_{cross} (m/yr)');

title(sprintf( ...
    'Partial along-flow gradient = %+.2f m/yr per 100 m', ...
    gradAlong_per100));

grid on;

exportgraphics( ...
    f, ...
    fullfile(outRoot,'05_partial_along_flow_gradient.png'), ...
    'Resolution',220);

%% ============================================================
% 17. FIGURE 6 - PARTIAL CROSS-FLOW GRADIENT
% ============================================================

partialCross = v_along-beta_x*x_along_m;

f = figure('Color','w','Position',[180 180 850 650]);

scatter(y_cross_m,partialCross,65,'filled');
hold on;

yy = linspace(min(y_cross_m),max(y_cross_m),100);

plot( ...
    yy, ...
    beta0+beta_y*yy, ...
    'k-', ...
    'LineWidth',1.8);

for i = 1:n
    text( ...
        y_cross_m(i)+1.0, ...
        partialCross(i)+0.08, ...
        sprintf('P%d',Point(i)), ...
        'FontSize',7);
end

xlabel('y_{cross} (m)');
ylabel('v_{along} - \beta_x x_{along} (m/yr)');

title(sprintf( ...
    'Partial cross-flow gradient = %+.2f m/yr per 100 m', ...
    gradCross_per100));

grid on;

exportgraphics( ...
    f, ...
    fullfile(outRoot,'06_partial_cross_flow_gradient.png'), ...
    'Resolution',220);

%% ============================================================
% 18. SAVE MODEL
% ============================================================

matOut = fullfile( ...
    outRoot, ...
    'flow_aligned_plane.mat');

save(matOut, ...
    'cfg', ...
    'caseName', ...
    'FlowTable', ...
    'dtDays','dtYears', ...
    'meanFlowDeg', ...
    'Rdir', ...
    'E0','N0', ...
    'eAlong','eCross', ...
    'beta', ...
    'seBeta', ...
    'ci95Low','ci95High', ...
    'R2_along', ...
    'RMSE_along', ...
    'gamma', ...
    'R2_cross', ...
    'RMSE_cross', ...
    'gradAlong_per100', ...
    'gradCross_per100', ...
    'gradientMagnitude_per100', ...
    'crossToAlongGradientRatio');

fprintf('\nSaved flow table:\n%s\n',csvOut);
fprintf('\nSaved model MAT:\n%s\n',matOut);

fprintf('\n============================================================\n');
fprintf(' V1 STAGE 6 COMPLETE\n');
fprintf('============================================================\n');

end

%% ============================================================
% LOCAL FUNCTION
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
