function v1_stage7_strain_rate(caseName)
% v1_stage7_strain_rate
%
% Generic V1 scientific-analysis Stage 7:
% flow-aligned affine velocity field -> 2-D horizontal strain-rate analysis.
%
% Reads:
%   cases/<caseName>/case_config.m
%   cases/<caseName>/output/06_flow_aligned_plane/flow_aligned_plane.mat
%   Epoch-1 raster from case_config.m
%
% Writes:
%   cases/<caseName>/output/07_strain_rate/
%
% COORDINATE CONVENTION
%   x_along : positive along circular-mean glacier-flow direction
%   y_cross : positive to the RIGHT of flow
%
% Because +y_cross is to the right of +x_along, the flow-aligned basis is
% left-handed in map space. This does not change the symmetric strain-rate
% tensor or principal strain rates. Rigid-body rotation/vorticity is
% therefore reported in the ordinary East/North map frame.
%
% IMPORTANT SCIENTIFIC LIMITATION
%   This is a first-order GLOBAL affine deformation estimate over the
%   spatial footprint of the trusted controls. Do not interpret it as a
%   dense local strain field at every crevasse.
%
% MATLAB R2024a. No Statistics Toolbox required.

if nargin < 1 || strlength(string(caseName)) == 0
    error('Provide a case name, e.g. v1_stage7_strain_rate("Glacier_2025_2026").');
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

stage6Mat = fullfile( ...
    caseRoot, ...
    'output', ...
    '06_flow_aligned_plane', ...
    'flow_aligned_plane.mat');

outRoot = fullfile( ...
    caseRoot, ...
    'output', ...
    '07_strain_rate');

assert(isfolder(caseRoot), ...
    'Case folder not found: %s',caseRoot);

assert(isfile(configFile), ...
    'Case config not found: %s',configFile);

assert(isfile(stage6Mat), ...
    'Missing Stage-6 MAT. Run v1_run_stage6 first: %s',stage6Mat);

if ~isfolder(outRoot)
    mkdir(outRoot);
end

clear cfg;
run(configFile);

assert(exist('cfg','var')==1 && isstruct(cfg), ...
    'case_config.m must create a struct named cfg.');

assert(strcmp(char(string(cfg.case_name)),caseName), ...
    'cfg.case_name does not match requested case name.');

assert(isfield(cfg,'strain') && ...
       isfield(cfg.strain,'bootstrap_resamples') && ...
       isfield(cfg.strain,'bootstrap_rng_seed'), ...
    ['Stage-7 strain settings are missing from case_config.m. ' ...
     'Run v1_patch_config_stage7 first.']);

%% ============================================================
% 2. LOAD STAGE-6 RESULTS
% ============================================================

S = load(stage6Mat, ...
    'FlowTable', ...
    'dtDays','dtYears', ...
    'meanFlowDeg', ...
    'Rdir', ...
    'E0','N0', ...
    'eAlong','eCross');

T = S.FlowTable;

dtDays = S.dtDays;
dtYears = S.dtYears;

meanFlowDeg = S.meanFlowDeg;
Rdir = S.Rdir;

E0 = S.E0;
N0 = S.N0;

eAlong = S.eAlong(:);
eCross = S.eCross(:);

requiredFlow = { ...
    'Point', ...
    'Epoch1_X', ...
    'Epoch1_Y', ...
    'x_along_m', ...
    'y_cross_m', ...
    'v_along_m_per_year', ...
    'v_cross_m_per_year'};

assert(all(ismember(requiredFlow,T.Properties.VariableNames)), ...
    'Stage-6 FlowTable has an unexpected schema.');

Point = T.Point;

x = T.x_along_m;
y = T.y_cross_m;

u = T.v_along_m_per_year;
v = T.v_cross_m_per_year;

Epoch1_X = T.Epoch1_X;
Epoch1_Y = T.Epoch1_Y;

n = height(T);

assert(n>=4, ...
    'At least 4 trusted vectors are required.');

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

nBoot = cfg.strain.bootstrap_resamples;
rngSeed = cfg.strain.bootstrap_rng_seed;

assert(nBoot>=100 && mod(nBoot,1)==0, ...
    'bootstrap_resamples must be an integer >= 100.');

%% ============================================================
% 4. FIT TWO VELOCITY PLANES
% ============================================================

A = [ ...
    ones(n,1), ...
    x, ...
    y ...
];

assert(rank(A)==3, ...
    ['Velocity-plane design matrix is rank deficient. ' ...
     'Check spatial distribution of controls.']);

beta = A\u;
gamma = A\v;

% u = beta0 + beta_x*x + beta_y*y
du_dx = beta(2);
du_dy = beta(3);

% v = gamma0 + gamma_x*x + gamma_y*y
dv_dx = gamma(2);
dv_dy = gamma(3);

% Velocity-gradient tensor in flow coordinates.
L = [ ...
    du_dx, du_dy; ...
    dv_dx, dv_dy ...
];

%% ============================================================
% 5. STRAIN-RATE + SPIN DECOMPOSITION
% ============================================================

D = 0.5*(L + L.');
W = 0.5*(L - L.');

eps_xx = D(1,1);
eps_yy = D(2,2);

eps_xy = D(1,2);
gamma_xy = 2*eps_xy;

% Horizontal areal strain rate.
divergence = trace(D);

% Principal strain rates and axes.
[Vprin,Eval] = eig(D);

eigVals = diag(Eval);
[eigVals,ord] = sort(eigVals,'ascend');
Vprin = Vprin(:,ord);

eps_min = eigVals(1);
eps_max = eigVals(2);

vMin = Vprin(:,1);
vMax = Vprin(:,2);

% Give eigenvectors a repeatable sign for plotting/reporting.
if vMax(1) < 0
    vMax = -vMax;
end

if vMin(1) < 0
    vMin = -vMin;
end

maxExtensionAngle_fromAlong_deg = ...
    atan2d(vMax(2),vMax(1));

maxShearRate = eps_max-eps_min;

%% ============================================================
% 6. PRINCIPAL AXES IN EAST/NORTH MAP COORDINATES
% ============================================================

% Q maps [along; cross] components into [East; North].
Q = [eAlong, eCross];

vMax_EN = Q*vMax;
vMin_EN = Q*vMin;

maxExtensionAzimuth_EofN_deg = ...
    mod(atan2d(vMax_EN(1),vMax_EN(2)),180);

minExtensionAzimuth_EofN_deg = ...
    mod(atan2d(vMin_EN(1),vMin_EN(2)),180);

%% ============================================================
% 7. RIGID-BODY ROTATION IN EAST/NORTH MAP FRAME
% ============================================================

L_EN = Q*L*Q.';

omega_EN_rad_per_year = ...
    0.5*(L_EN(2,1)-L_EN(1,2));

vorticity_EN_per_year = ...
    L_EN(2,1)-L_EN(1,2);

omega_EN_deg_per_year = ...
    rad2deg(omega_EN_rad_per_year);

%% ============================================================
% 8. FIT QUALITY
% ============================================================

uFit = A*beta;
vFit = A*gamma;

uResid = u-uFit;
vResid = v-vFit;

SSTu = sum((u-mean(u)).^2);
SSTv = sum((v-mean(v)).^2);

if SSTu>0
    R2_u = 1-sum(uResid.^2)/SSTu;
else
    R2_u = NaN;
end

if SSTv>0
    R2_v = 1-sum(vResid.^2)/SSTv;
else
    R2_v = NaN;
end

RMSE_u = sqrt(mean(uResid.^2));
RMSE_v = sqrt(mean(vResid.^2));

%% ============================================================
% 9. NONPARAMETRIC BOOTSTRAP UNCERTAINTY
%
% Flow-aligned axes remain FIXED to the Stage-6 mean-flow coordinate system.
% Trusted vectors are resampled with replacement.
% ============================================================

rng(rngSeed);

Boot = nan(nBoot,9);

% Columns:
%   1 du_dx
%   2 du_dy
%   3 dv_dx
%   4 dv_dy
%   5 eps_xy
%   6 divergence
%   7 eps_min
%   8 eps_max
%   9 map rotation [rad/yr]

nAccepted = 0;

for b = 1:nBoot

    ids = randi(n,n,1);

    Ab = A(ids,:);

    if rank(Ab)<3
        continue
    end

    beta_b = Ab\u(ids);
    gamma_b = Ab\v(ids);

    Lb = [ ...
        beta_b(2), beta_b(3); ...
        gamma_b(2), gamma_b(3) ...
    ];

    Db = 0.5*(Lb+Lb.');

    ev = sort(eig(Db),'ascend');

    Lb_EN = Q*Lb*Q.';

    omega_b = ...
        0.5*(Lb_EN(2,1)-Lb_EN(1,2));

    nAccepted = nAccepted+1;

    Boot(nAccepted,:) = [ ...
        Lb(1,1), ...
        Lb(1,2), ...
        Lb(2,1), ...
        Lb(2,2), ...
        Db(1,2), ...
        trace(Db), ...
        ev(1), ...
        ev(2), ...
        omega_b ...
    ];
end

Boot = Boot(1:nAccepted,:);

assert(nAccepted>0, ...
    'No valid bootstrap resamples were obtained.');

BootCI = nan(2,size(Boot,2));

for j = 1:size(Boot,2)
    BootCI(1,j) = simple_percentile(Boot(:,j),2.5);
    BootCI(2,j) = simple_percentile(Boot(:,j),97.5);
end

%% ============================================================
% 10. SUMMARY TABLES
% ============================================================

Metric = [ ...
    "du_dx_longitudinal_gradient"
    "du_dy_crossflow_gradient"
    "dv_dx"
    "dv_dy"
    "eps_xx_longitudinal_strain_rate"
    "eps_yy_transverse_normal_strain_rate"
    "eps_xy_tensor_shear_rate"
    "engineering_shear_rate"
    "horizontal_divergence"
    "principal_compression_rate"
    "principal_extension_rate"
    "maximum_shear_rate"
    "map_rotation_rate_rad_per_year"
    "map_rotation_rate_deg_per_year"
];

Value = [ ...
    du_dx
    du_dy
    dv_dx
    dv_dy
    eps_xx
    eps_yy
    eps_xy
    gamma_xy
    divergence
    eps_min
    eps_max
    maxShearRate
    omega_EN_rad_per_year
    omega_EN_deg_per_year
];

Unit = [ ...
    "yr^-1"
    "yr^-1"
    "yr^-1"
    "yr^-1"
    "yr^-1"
    "yr^-1"
    "yr^-1"
    "yr^-1"
    "yr^-1"
    "yr^-1"
    "yr^-1"
    "yr^-1"
    "rad/yr"
    "deg/yr"
];

SummaryTable = table(Metric,Value,Unit);

summaryCSV = fullfile( ...
    outRoot, ...
    'strain_rate_summary.csv');

writetable(SummaryTable,summaryCSV);

BootMetric = [ ...
    "du_dx"
    "du_dy"
    "dv_dx"
    "dv_dy"
    "eps_xy"
    "divergence"
    "principal_compression"
    "principal_extension"
    "map_rotation_rad_per_year"
];

BootstrapCI = table( ...
    BootMetric, ...
    BootCI(1,:).', ...
    BootCI(2,:).', ...
    'VariableNames',{ ...
        'Metric', ...
        'CI95_Low', ...
        'CI95_High'});

bootCSV = fullfile( ...
    outRoot, ...
    'bootstrap_95CI.csv');

writetable(BootstrapCI,bootCSV);

%% ============================================================
% 11. CONSOLE SUMMARY
% ============================================================

fprintf('\n============================================================\n');
fprintf(' V1 STAGE 7 - 2-D STRAIN-RATE ANALYSIS\n');
fprintf('============================================================\n');

fprintf('Case:       %s\n',caseName);
fprintf('Epoch pair: %s -> %s\n',epoch1Name,epoch2Name);
fprintf('Vectors:    %d\n',n);
fprintf('Interval:   %.0f days = %.6f yr\n',dtDays,dtYears);

fprintf('\nCoordinate system:\n');
fprintf('  mean flow direction = %.3f deg E of N\n',meanFlowDeg);
fprintf('  directional concentration R = %.6f\n',Rdir);
fprintf('  +y_cross points to flow-right\n');
fprintf('  flow-aligned basis is left-handed in map space\n');

fprintf('\nVelocity-gradient tensor L [yr^-1]:\n');
fprintf('  [ %+.6f   %+.6f ]\n',L(1,1),L(1,2));
fprintf('  [ %+.6f   %+.6f ]\n',L(2,1),L(2,2));

fprintf('\nStrain-rate tensor D [yr^-1]:\n');
fprintf('  [ %+.6f   %+.6f ]\n',D(1,1),D(1,2));
fprintf('  [ %+.6f   %+.6f ]\n',D(2,1),D(2,2));

fprintf('\nNormal + shear strain rates:\n');
fprintf('  longitudinal eps_xx = %+.6f yr^-1  (%+.2f %%/yr)\n', ...
    eps_xx,100*eps_xx);
fprintf('  transverse   eps_yy = %+.6f yr^-1  (%+.2f %%/yr)\n', ...
    eps_yy,100*eps_yy);
fprintf('  tensor shear eps_xy = %+.6f yr^-1\n',eps_xy);
fprintf('  engineering shear   = %+.6f yr^-1  (%+.2f %%/yr)\n', ...
    gamma_xy,100*gamma_xy);

fprintf('\nHorizontal divergence:\n');
fprintf('  %+.6f yr^-1  (%+.2f %%/yr)\n', ...
    divergence,100*divergence);

fprintf('\nPrincipal strain rates:\n');
fprintf('  maximum extension   = %+.6f yr^-1  (%+.2f %%/yr)\n', ...
    eps_max,100*eps_max);
fprintf('  maximum compression = %+.6f yr^-1  (%+.2f %%/yr)\n', ...
    eps_min,100*eps_min);
fprintf('  maximum shear rate  = %.6f yr^-1  (%.2f %%/yr)\n', ...
    maxShearRate,100*maxShearRate);

fprintf('\nPrincipal extension axis:\n');
fprintf('  %.2f deg from +x_along toward +y_cross\n', ...
    maxExtensionAngle_fromAlong_deg);
fprintf('  map azimuth = %.2f deg E of N (axis modulo 180 deg)\n', ...
    maxExtensionAzimuth_EofN_deg);

fprintf('\nPrincipal compression axis:\n');
fprintf('  map azimuth = %.2f deg E of N (axis modulo 180 deg)\n', ...
    minExtensionAzimuth_EofN_deg);

fprintf('\nRigid-body rotation in East/North map frame:\n');
fprintf('  omega = %+.6f rad/yr\n',omega_EN_rad_per_year);
fprintf('        = %+.3f deg/yr\n',omega_EN_deg_per_year);
fprintf('  map vorticity = %+.6f yr^-1\n',vorticity_EN_per_year);
fprintf('  positive map rotation = counter-clockwise\n');

fprintf('\nPlane fit quality:\n');
fprintf('  v_along: R^2 %.4f | RMSE %.3f m/yr\n',R2_u,RMSE_u);
fprintf('  v_cross: R^2 %.4f | RMSE %.3f m/yr\n',R2_v,RMSE_v);

fprintf('\nBootstrap 95%% intervals (%d accepted resamples):\n',nAccepted);
fprintf('  du/dx:        [%+.6f, %+.6f] yr^-1\n', ...
    BootCI(1,1),BootCI(2,1));
fprintf('  du/dy:        [%+.6f, %+.6f] yr^-1\n', ...
    BootCI(1,2),BootCI(2,2));
fprintf('  dv/dx:        [%+.6f, %+.6f] yr^-1\n', ...
    BootCI(1,3),BootCI(2,3));
fprintf('  dv/dy:        [%+.6f, %+.6f] yr^-1\n', ...
    BootCI(1,4),BootCI(2,4));
fprintf('  eps_xy:       [%+.6f, %+.6f] yr^-1\n', ...
    BootCI(1,5),BootCI(2,5));
fprintf('  divergence:   [%+.6f, %+.6f] yr^-1\n', ...
    BootCI(1,6),BootCI(2,6));
fprintf('  compression:  [%+.6f, %+.6f] yr^-1\n', ...
    BootCI(1,7),BootCI(2,7));
fprintf('  extension:    [%+.6f, %+.6f] yr^-1\n', ...
    BootCI(1,8),BootCI(2,8));
fprintf('  map rotation: [%+.6f, %+.6f] rad/yr\n', ...
    BootCI(1,9),BootCI(2,9));

fprintf('\nScientific scope:\n');
fprintf(['  These values describe the fitted GLOBAL first-order horizontal ' ...
         'velocity field over the control footprint.\n']);
fprintf(['  Horizontal divergence alone must not be interpreted as 3-D ' ...
         'volumetric strain or thickness change.\n']);

%% ============================================================
% 12. BACKGROUND IMAGE
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
% 13. FIGURE 1 - PRINCIPAL STRAIN AXES ON GLACIER
% ============================================================

f = figure('Color','w','Position',[80 80 1050 900]);

image(xVec,yVec,Irgb);
set(gca,'YDir','normal');
axis image;
hold on;

scatter(Epoch1_X,Epoch1_Y,25,'filled');

extentScale = max( ...
    max(Epoch1_X)-min(Epoch1_X), ...
    max(Epoch1_Y)-min(Epoch1_Y));

axisLength = max(10,0.28*extentScale);

plot( ...
    [E0-axisLength*vMax_EN(1), E0+axisLength*vMax_EN(1)], ...
    [N0-axisLength*vMax_EN(2), N0+axisLength*vMax_EN(2)], ...
    'r-', ...
    'LineWidth',3);

plot( ...
    [E0-axisLength*vMin_EN(1), E0+axisLength*vMin_EN(1)], ...
    [N0-axisLength*vMin_EN(2), N0+axisLength*vMin_EN(2)], ...
    'b-', ...
    'LineWidth',3);

plot(E0,N0,'kp','MarkerSize',13,'MarkerFaceColor','w');

text( ...
    E0+axisLength*vMax_EN(1), ...
    N0+axisLength*vMax_EN(2), ...
    sprintf('  max extension  %+0.3f yr^{-1}',eps_max), ...
    'FontWeight','bold', ...
    'Color','r', ...
    'BackgroundColor','w');

text( ...
    E0+axisLength*vMin_EN(1), ...
    N0+axisLength*vMin_EN(2), ...
    sprintf('  max compression  %+0.3f yr^{-1}',eps_min), ...
    'FontWeight','bold', ...
    'Color','b', ...
    'BackgroundColor','w');

xlabel('Easting (m)');
ylabel('Northing (m)');
title('Principal horizontal strain-rate axes');

xlim([xmin xmax]);
ylim([ymin ymax]);

exportgraphics( ...
    f, ...
    fullfile(outRoot,'01_principal_strain_axes_map.png'), ...
    'Resolution',220);

%% ============================================================
% 14. FIGURE 2 - UNIT CIRCLE -> ONE-YEAR PURE-STRAIN ELLIPSE
%
% Uses expm(D*1 yr). Rigid-body rotation is intentionally excluded.
% ============================================================

ang = linspace(0,2*pi,500);

circle = [ ...
    cos(ang); ...
    sin(ang) ...
];

Fstrain_1yr = expm(D);

ellipse = Fstrain_1yr*circle;

f = figure('Color','w','Position',[100 100 760 720]);

plot(circle(1,:),circle(2,:),'k--','LineWidth',1.5);
hold on;

plot(ellipse(1,:),ellipse(2,:),'r-','LineWidth',2.5);

axis equal;
grid on;

xlabel('x_{along}');
ylabel('y_{cross}');
title('One-year pure-strain deformation of a unit circle');

legend( ...
    'Initial unit circle', ...
    'After 1 yr from fitted strain-rate tensor', ...
    'Location','best');

scaleAxis = 1.15;

plot( ...
    [-scaleAxis*vMax(1),scaleAxis*vMax(1)], ...
    [-scaleAxis*vMax(2),scaleAxis*vMax(2)], ...
    'r:', ...
    'LineWidth',1.5);

plot( ...
    [-scaleAxis*vMin(1),scaleAxis*vMin(1)], ...
    [-scaleAxis*vMin(2),scaleAxis*vMin(2)], ...
    'b:', ...
    'LineWidth',1.5);

exportgraphics( ...
    f, ...
    fullfile(outRoot,'02_one_year_strain_ellipse.png'), ...
    'Resolution',220);

%% ============================================================
% 15. FIGURE 3 - STRAIN-RATE COMPONENT SUMMARY
% ============================================================

componentNames = categorical({ ...
    '\epsilon_{xx}', ...
    '\epsilon_{yy}', ...
    '\gamma_{xy}', ...
    'divergence', ...
    '\epsilon_{min}', ...
    '\epsilon_{max}'});

componentValues = [ ...
    eps_xx; ...
    eps_yy; ...
    gamma_xy; ...
    divergence; ...
    eps_min; ...
    eps_max ...
];

f = figure('Color','w','Position',[120 120 900 650]);

bar(componentNames,100*componentValues);

ylabel('Rate (% yr^{-1})');
title('Horizontal deformation-rate summary');

grid on;
yline(0,'k-');

exportgraphics( ...
    f, ...
    fullfile(outRoot,'03_strain_rate_components.png'), ...
    'Resolution',220);

%% ============================================================
% 16. FIGURE 4 - BOOTSTRAP 95% INTERVALS
% ============================================================

ciLabels = { ...
    'du/dx', ...
    'du/dy', ...
    'dv/dx', ...
    'dv/dy', ...
    '\epsilon_{xy}', ...
    'divergence', ...
    '\epsilon_{min}', ...
    '\epsilon_{max}'};

estimate = [ ...
    du_dx; ...
    du_dy; ...
    dv_dx; ...
    dv_dy; ...
    eps_xy; ...
    divergence; ...
    eps_min; ...
    eps_max ...
];

ciLo = BootCI(1,1:8).';
ciHi = BootCI(2,1:8).';

lowerErr = estimate-ciLo;
upperErr = ciHi-estimate;

% Force column vectors explicitly to prevent row/column implicit expansion.
estimate = estimate(:);
lowerErr = lowerErr(:);
upperErr = upperErr(:);

f = figure('Color','w','Position',[140 140 1000 650]);

errorbar( ...
    (1:numel(estimate)).', ...
    100*estimate, ...
    100*lowerErr, ...
    100*upperErr, ...
    'o', ...
    'LineWidth',1.5, ...
    'MarkerSize',7);

xticks(1:numel(estimate));
xticklabels(ciLabels);

ylabel('Rate (% yr^{-1})');

title(sprintf( ...
    'Bootstrap 95%% intervals - %d accepted resamples', ...
    nAccepted));

grid on;
yline(0,'k--');

exportgraphics( ...
    f, ...
    fullfile(outRoot,'04_bootstrap_95CI.png'), ...
    'Resolution',220);

%% ============================================================
% 17. SAVE MAT
% ============================================================

matOut = fullfile( ...
    outRoot, ...
    'strain_rate_analysis.mat');

save(matOut, ...
    'cfg', ...
    'caseName', ...
    'dtDays','dtYears', ...
    'L','D','W','L_EN', ...
    'beta','gamma', ...
    'eps_xx','eps_yy','eps_xy','gamma_xy', ...
    'divergence', ...
    'eps_min','eps_max','maxShearRate', ...
    'vMin','vMax', ...
    'vMin_EN','vMax_EN', ...
    'maxExtensionAngle_fromAlong_deg', ...
    'maxExtensionAzimuth_EofN_deg', ...
    'minExtensionAzimuth_EofN_deg', ...
    'omega_EN_rad_per_year', ...
    'omega_EN_deg_per_year', ...
    'vorticity_EN_per_year', ...
    'R2_u','RMSE_u','R2_v','RMSE_v', ...
    'BootCI','Boot', ...
    'nAccepted','nBoot','rngSeed', ...
    'SummaryTable','BootstrapCI');

fprintf('\nSaved strain-rate summary:\n%s\n',summaryCSV);
fprintf('\nSaved bootstrap CI table:\n%s\n',bootCSV);
fprintf('\nSaved MAT:\n%s\n',matOut);

fprintf('\n============================================================\n');
fprintf(' V1 STAGE 7 COMPLETE\n');
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
