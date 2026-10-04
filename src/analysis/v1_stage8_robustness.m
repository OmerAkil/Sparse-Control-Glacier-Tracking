function v1_stage8_robustness(caseName)
% v1_stage8_robustness
%
% Generic V1 robustness / sensitivity analysis.
%
% PURPOSE
%   Test whether the fitted global affine velocity/strain conclusions depend
%   strongly on:
%     1) any single trusted correspondence (leave-one-out), or
%     2) plausible bounded coordinate-localization uncertainty.
%
% Reads:
%   cases/<caseName>/case_config.m
%   cases/<caseName>/input/case_metadata.csv
%   cases/<caseName>/output/04_finalized_correspondences/final_correspondences.csv
%
% Writes:
%   cases/<caseName>/output/08_robustness/
%
% TEST A - LEAVE ONE OUT
%   Refit the COMPLETE analysis once per omitted point.
%   Mean-flow direction and flow-aligned axes are recomputed each time.
%
% TEST B - BOUNDED COORDINATE PERTURBATION
%   Each Epoch-1 and Epoch-2 point is independently perturbed within a
%   circular disk. Radius is sampled uniformly in disk area:
%       r = R*sqrt(U)
%
% IMPORTANT
%   Monte-Carlo ranges are sensitivity intervals under the specified
%   perturbation model. They are NOT formal measurement-confidence
%   intervals.
%
% MATLAB R2024a. No Statistics Toolbox required.

if nargin < 1 || strlength(string(caseName)) == 0
    error('Provide a case name, e.g. v1_stage8_robustness("Glacier_2025_2026").');
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
    '08_robustness');

assert(isfolder(caseRoot), ...
    'Case folder not found: %s',caseRoot);

assert(isfile(configFile), ...
    'Case config not found: %s',configFile);

assert(isfile(metadataCSV), ...
    'Case metadata not found: %s',metadataCSV);

assert(isfile(finalCSV), ...
    'Missing finalized correspondences. Run v1_run_stage4 first: %s',finalCSV);

if ~isfolder(outRoot)
    mkdir(outRoot);
end

clear cfg;
run(configFile);

assert(exist('cfg','var')==1 && isstruct(cfg), ...
    'case_config.m must create a struct named cfg.');

assert(strcmp(char(string(cfg.case_name)),caseName), ...
    'cfg.case_name does not match requested case name.');

assert(isfield(cfg,'robustness') && ...
       isfield(cfg.robustness,'mc_realizations') && ...
       isfield(cfg.robustness,'mc_rng_seed') && ...
       isfield(cfg.robustness,'localization_radius_m'), ...
    ['Stage-8 robustness settings are missing from case_config.m. ' ...
     'Run v1_patch_config_stage8 first.']);

%% ============================================================
% 2. LOAD FINAL CORRESPONDENCES + TIME INTERVAL
% ============================================================

Meta = readtable(metadataCSV,'TextType','string');
Final = readtable(finalCSV,'TextType','string');

assert(height(Meta)==1, ...
    'case_metadata.csv must contain exactly one row.');

assert(ismember('dtYears',Meta.Properties.VariableNames), ...
    'case_metadata.csv is missing dtYears.');

dtYears = Meta.dtYears(1);

assert(isfinite(dtYears) && dtYears>0, ...
    'Invalid dtYears in case_metadata.csv.');

requiredFinal = { ...
    'Point', ...
    'Epoch1_X', ...
    'Epoch1_Y', ...
    'Epoch2_X', ...
    'Epoch2_Y'};

assert(all(ismember(requiredFinal,Final.Properties.VariableNames)), ...
    'final_correspondences.csv has an unexpected schema.');

labels = Final.Point;

coords = [ ...
    Final.Epoch1_X, ...
    Final.Epoch1_Y, ...
    Final.Epoch2_X, ...
    Final.Epoch2_Y ...
];

n = size(coords,1);

assert(n>=5, ...
    'At least 5 correspondences are required for useful robustness analysis.');

%% ============================================================
% 3. SETTINGS
% ============================================================

nMC = cfg.robustness.mc_realizations;
rngSeed = cfg.robustness.mc_rng_seed;
localizationRadius_m = cfg.robustness.localization_radius_m;

assert(nMC>=100 && mod(nMC,1)==0, ...
    'mc_realizations must be an integer >= 100.');

assert(isfinite(localizationRadius_m) && localizationRadius_m>0, ...
    'localization_radius_m must be > 0.');

%% ============================================================
% 4. BASELINE METRICS
% ============================================================

base = compute_metrics(coords,dtYears);

metricNames = [ ...
    "meanFlowDeg"
    "Rdir"
    "du_dx"
    "du_dy"
    "dv_dx"
    "dv_dy"
    "eps_xx"
    "eps_yy"
    "eps_xy"
    "engineering_shear"
    "divergence"
    "principal_min"
    "principal_max"
    "max_shear"
    "rotation_rad_per_year"
    "rotation_deg_per_year"
    "R2_u"
    "RMSE_u"
];

baseVec = metrics_to_vector(base);

%% ============================================================
% 5. LEAVE-ONE-OUT FULL-PIPELINE INFLUENCE
% ============================================================

LOO = nan(n,numel(baseVec));

for i = 1:n

    keep = true(n,1);
    keep(i) = false;

    LOO(i,:) = metrics_to_vector( ...
        compute_metrics(coords(keep,:),dtYears)).';
end

LOODelta = LOO-baseVec.';
maxAbsLOODelta = max(abs(LOODelta),[],1);

LOOTable = array2table( ...
    LOO, ...
    'VariableNames',cellstr(metricNames));

LOOTable = addvars( ...
    LOOTable, ...
    labels, ...
    'Before',1, ...
    'NewVariableNames','OmittedPoint');

looCSV = fullfile( ...
    outRoot, ...
    'leave_one_out_metrics.csv');

writetable(LOOTable,looCSV);

%% ============================================================
% 6. BOUNDED COORDINATE-PERTURBATION SENSITIVITY
% ============================================================

rng(rngSeed);

MC = nan(nMC,numel(baseVec));

for b = 1:nMC

    C = coords;

    % Epoch 1 and Epoch 2 independently perturbed for every point.
    for epoch = 1:2

        ang = 2*pi*rand(n,1);
        rad = localizationRadius_m*sqrt(rand(n,1));

        dE = rad.*cos(ang);
        dN = rad.*sin(ang);

        if epoch==1
            C(:,1) = C(:,1)+dE;
            C(:,2) = C(:,2)+dN;
        else
            C(:,3) = C(:,3)+dE;
            C(:,4) = C(:,4)+dN;
        end
    end

    MC(b,:) = metrics_to_vector( ...
        compute_metrics(C,dtYears)).';
end

MCLow = nan(1,size(MC,2));
MCHigh = nan(1,size(MC,2));
MCMedian = nan(1,size(MC,2));

for j = 1:size(MC,2)

    MCLow(j) = simple_percentile(MC(:,j),2.5);
    MCHigh(j) = simple_percentile(MC(:,j),97.5);
    MCMedian(j) = simple_percentile(MC(:,j),50);
end

SensitivityTable = table( ...
    metricNames, ...
    baseVec, ...
    MCMedian.', ...
    MCLow.', ...
    MCHigh.', ...
    maxAbsLOODelta.', ...
    'VariableNames',{ ...
        'Metric', ...
        'Baseline', ...
        'MC_Median', ...
        'MC_2p5', ...
        'MC_97p5', ...
        'MaxAbsLeaveOneOutChange'});

sensCSV = fullfile( ...
    outRoot, ...
    'robustness_summary.csv');

writetable(SensitivityTable,sensCSV);

%% ============================================================
% 7. CONSOLE SUMMARY
% ============================================================

fprintf('\n============================================================\n');
fprintf(' V1 STAGE 8 - ROBUSTNESS / SENSITIVITY\n');
fprintf('============================================================\n');

fprintf('Case:    %s\n',caseName);
fprintf('Vectors: %d\n',n);

fprintf('\nBaseline:\n');
fprintf('  mean flow direction = %.3f deg E of N\n',base.meanFlowDeg);
fprintf('  du/dx = %+.6f yr^-1  (%+.3f m/yr per 100 m)\n', ...
    base.du_dx,100*base.du_dx);
fprintf('  du/dy = %+.6f yr^-1  (%+.3f m/yr per 100 m)\n', ...
    base.du_dy,100*base.du_dy);
fprintf('  eps_xy = %+.6f yr^-1\n',base.eps_xy);
fprintf('  divergence = %+.6f yr^-1\n',base.divergence);
fprintf('  principal min = %+.6f yr^-1\n',base.principal_min);
fprintf('  principal max = %+.6f yr^-1\n',base.principal_max);
fprintf('  rotation = %+.3f deg/yr\n',base.rotation_deg_per_year);

fprintf('\nLEAVE-ONE-OUT full-pipeline sensitivity:\n');

print_loo( ...
    'mean flow direction [deg]', ...
    base.meanFlowDeg, ...
    LOO(:,1), ...
    labels);

print_loo( ...
    'du/dx [yr^-1]', ...
    base.du_dx, ...
    LOO(:,3), ...
    labels);

print_loo( ...
    'du/dy [yr^-1]', ...
    base.du_dy, ...
    LOO(:,4), ...
    labels);

print_loo( ...
    'divergence [yr^-1]', ...
    base.divergence, ...
    LOO(:,11), ...
    labels);

print_loo( ...
    'principal min [yr^-1]', ...
    base.principal_min, ...
    LOO(:,12), ...
    labels);

print_loo( ...
    'principal max [yr^-1]', ...
    base.principal_max, ...
    LOO(:,13), ...
    labels);

print_loo( ...
    'rotation [deg/yr]', ...
    base.rotation_deg_per_year, ...
    LOO(:,16), ...
    labels);

fprintf('\nCOORDINATE-PERTURBATION SENSITIVITY:\n');
fprintf('  %d Monte-Carlo realizations\n',nMC);
fprintf('  each Epoch-1 and Epoch-2 point independently perturbed\n');
fprintf('  within a %.2f m radius disk\n\n',localizationRadius_m);

print_mc('mean flow direction [deg]',1,baseVec,MCLow,MCHigh);
print_mc('du/dx [yr^-1]',3,baseVec,MCLow,MCHigh);
print_mc('du/dy [yr^-1]',4,baseVec,MCLow,MCHigh);
print_mc('eps_xy [yr^-1]',9,baseVec,MCLow,MCHigh);
print_mc('divergence [yr^-1]',11,baseVec,MCLow,MCHigh);
print_mc('principal min [yr^-1]',12,baseVec,MCLow,MCHigh);
print_mc('principal max [yr^-1]',13,baseVec,MCLow,MCHigh);
print_mc('rotation [deg/yr]',16,baseVec,MCLow,MCHigh);

fprintf('\nSIGN / ORDER STABILITY:\n');

fprintf('  du/dx positive in all MC runs: %s\n', ...
    tfstr(all(MC(:,3)>0)));

fprintf('  du/dy positive in all MC runs: %s\n', ...
    tfstr(all(MC(:,4)>0)));

fprintf(['  cross-flow gradient larger than along-flow gradient ' ...
         'in all MC runs: %s\n'], ...
    tfstr(all(abs(MC(:,4)) > abs(MC(:,3)))));

fprintf('  principal compression negative in all MC runs: %s\n', ...
    tfstr(all(MC(:,12)<0)));

fprintf('  principal extension positive in all MC runs: %s\n', ...
    tfstr(all(MC(:,13)>0)));

fprintf('  rotation positive in all MC runs: %s\n', ...
    tfstr(all(MC(:,16)>0)));

fprintf('\nInterpretation note:\n');
fprintf(['  MC ranges are sensitivity intervals under the configured bounded ' ...
         'coordinate-perturbation model, not formal confidence intervals.\n']);

%% ============================================================
% 8. FIGURE 1 - LEAVE-ONE-OUT GRADIENT INFLUENCE
% ============================================================

f = figure('Color','w','Position',[80 80 1000 700]);

tiledlayout(f,2,1,'TileSpacing','compact','Padding','compact');

ax = nexttile;
scatter(ax,labels,100*LOO(:,3),55,'filled');
hold(ax,'on');
yline(ax,100*base.du_dx,'k--','LineWidth',1.5);
xlabel(ax,'Omitted point');
ylabel(ax,'du/dx (% yr^{-1})');
title(ax,'Leave-one-out influence on along-flow gradient');
grid(ax,'on');

ax = nexttile;
scatter(ax,labels,100*LOO(:,4),55,'filled');
hold(ax,'on');
yline(ax,100*base.du_dy,'k--','LineWidth',1.5);
xlabel(ax,'Omitted point');
ylabel(ax,'du/dy (% yr^{-1})');
title(ax,'Leave-one-out influence on cross-flow gradient');
grid(ax,'on');

exportgraphics( ...
    f, ...
    fullfile(outRoot,'01_leave_one_out_gradient_influence.png'), ...
    'Resolution',220);

%% ============================================================
% 9. FIGURE 2 - MONTE-CARLO GRADIENT SENSITIVITY
% ============================================================

f = figure('Color','w','Position',[100 100 950 700]);

scatter(100*MC(:,3),100*MC(:,4),8,'filled');
hold on;

plot( ...
    100*base.du_dx, ...
    100*base.du_dy, ...
    'kp', ...
    'MarkerSize',15, ...
    'MarkerFaceColor','y');

xlabel('du/dx (% yr^{-1})');
ylabel('du/dy (% yr^{-1})');

title(sprintf( ...
    'Coordinate sensitivity - %.2f m bounded perturbation', ...
    localizationRadius_m));

grid on;

exportgraphics( ...
    f, ...
    fullfile(outRoot,'02_MC_gradient_sensitivity.png'), ...
    'Resolution',220);

%% ============================================================
% 10. FIGURE 3 - PRINCIPAL STRAIN SENSITIVITY
% ============================================================

f = figure('Color','w','Position',[120 120 950 700]);

scatter(100*MC(:,12),100*MC(:,13),8,'filled');
hold on;

plot( ...
    100*base.principal_min, ...
    100*base.principal_max, ...
    'kp', ...
    'MarkerSize',15, ...
    'MarkerFaceColor','y');

xline(0,'k--');
yline(0,'k--');

xlabel('Principal compression (% yr^{-1})');
ylabel('Principal extension (% yr^{-1})');

title('Principal-strain sensitivity to bounded coordinate perturbations');

grid on;

exportgraphics( ...
    f, ...
    fullfile(outRoot,'03_MC_principal_strain_sensitivity.png'), ...
    'Resolution',220);

%% ============================================================
% 11. FIGURE 4 - ROBUSTNESS INTERVAL SUMMARY
%
% Explicit column-vector coercion prevents the historical MATLAB
% row/column implicit-expansion plotting bug.
% ============================================================

selectedIdx = [3 4 9 11 12 13];

names = { ...
    'du/dx', ...
    'du/dy', ...
    '\epsilon_{xy}', ...
    'divergence', ...
    '\epsilon_{min}', ...
    '\epsilon_{max}'};

est = 100*baseVec(selectedIdx);
lo = 100*MCLow(selectedIdx);
hi = 100*MCHigh(selectedIdx);

est = est(:);
lo = lo(:);
hi = hi(:);

lowerErr = est-lo;
upperErr = hi-est;

f = figure('Color','w','Position',[140 140 1000 650]);

errorbar( ...
    (1:numel(est)).', ...
    est, ...
    lowerErr, ...
    upperErr, ...
    'o', ...
    'LineWidth',1.6, ...
    'MarkerSize',8);

xticks(1:numel(est));
xticklabels(names);

ylabel('Rate (% yr^{-1})');

title(sprintf( ...
    'Sensitivity interval under %.2f m bounded coordinate perturbations', ...
    localizationRadius_m));

grid on;
yline(0,'k--');

exportgraphics( ...
    f, ...
    fullfile(outRoot,'04_coordinate_uncertainty_intervals.png'), ...
    'Resolution',220);

%% ============================================================
% 12. SAVE MAT
% ============================================================

matOut = fullfile( ...
    outRoot, ...
    'robustness_sensitivity.mat');

save(matOut, ...
    'cfg', ...
    'caseName', ...
    'labels', ...
    'coords', ...
    'dtYears', ...
    'base', ...
    'metricNames', ...
    'baseVec', ...
    'LOO', ...
    'LOODelta', ...
    'MC', ...
    'MCLow','MCHigh','MCMedian', ...
    'localizationRadius_m', ...
    'nMC','rngSeed', ...
    'LOOTable', ...
    'SensitivityTable');

fprintf('\nSaved LOO table:\n%s\n',looCSV);
fprintf('\nSaved robustness summary:\n%s\n',sensCSV);
fprintf('\nSaved MAT:\n%s\n',matOut);

fprintf('\n============================================================\n');
fprintf(' V1 STAGE 8 COMPLETE\n');
fprintf('============================================================\n');

end

%% ============================================================
% LOCAL FUNCTIONS
% ============================================================

function m = compute_metrics(C,dtYears)
% C columns: Epoch1_X Epoch1_Y Epoch2_X Epoch2_Y

X1 = C(:,1);
Y1 = C(:,2);
X2 = C(:,3);
Y2 = C(:,4);

dE = X2-X1;
dN = Y2-Y1;

vE = dE/dtYears;
vN = dN/dtYears;

dir = mod(atan2d(dE,dN),360);

th = deg2rad(dir);

ms = mean(sin(th));
mc = mean(cos(th));

meanFlowDeg = mod(atan2d(ms,mc),360);
Rdir = hypot(ms,mc);

ft = deg2rad(meanFlowDeg);

eAlong = [sin(ft); cos(ft)];
eCross = [cos(ft); -sin(ft)];

Q = [eAlong eCross];

E0 = mean(X1);
N0 = mean(Y1);

dPos = [ ...
    X1-E0, ...
    Y1-N0 ...
];

x = dPos*eAlong;
y = dPos*eCross;

Vel = [vE vN];

u = Vel*eAlong;
v = Vel*eCross;

A = [ones(size(x)) x y];

assert(rank(A)==3, ...
    'Rank-deficient affine fit encountered during robustness analysis.');

beta = A\u;
gamma = A\v;

uFit = A*beta;

SSTu = sum((u-mean(u)).^2);

if SSTu>0
    R2_u = 1-sum((u-uFit).^2)/SSTu;
else
    R2_u = NaN;
end

RMSE_u = sqrt(mean((u-uFit).^2));

L = [ ...
    beta(2), beta(3); ...
    gamma(2), gamma(3) ...
];

D = 0.5*(L+L.');

ev = sort(eig(D),'ascend');

L_EN = Q*L*Q.';

omegaRad = ...
    0.5*(L_EN(2,1)-L_EN(1,2));

m.meanFlowDeg = meanFlowDeg;
m.Rdir = Rdir;

m.du_dx = L(1,1);
m.du_dy = L(1,2);
m.dv_dx = L(2,1);
m.dv_dy = L(2,2);

m.eps_xx = D(1,1);
m.eps_yy = D(2,2);
m.eps_xy = D(1,2);
m.engineering_shear = 2*D(1,2);

m.divergence = trace(D);

m.principal_min = ev(1);
m.principal_max = ev(2);
m.max_shear = ev(2)-ev(1);

m.rotation_rad_per_year = omegaRad;
m.rotation_deg_per_year = rad2deg(omegaRad);

m.R2_u = R2_u;
m.RMSE_u = RMSE_u;

end

function v = metrics_to_vector(m)

v = [ ...
    m.meanFlowDeg
    m.Rdir
    m.du_dx
    m.du_dy
    m.dv_dx
    m.dv_dy
    m.eps_xx
    m.eps_yy
    m.eps_xy
    m.engineering_shear
    m.divergence
    m.principal_min
    m.principal_max
    m.max_shear
    m.rotation_rad_per_year
    m.rotation_deg_per_year
    m.R2_u
    m.RMSE_u
];

end

function print_loo(name,baseline,vals,labels)

[mn,~] = min(vals);
[mx,~] = max(vals);

delta = abs(vals-baseline);

[maxDelta,id] = max(delta);

fprintf('  %s\n',name);
fprintf('    baseline: %.6f\n',baseline);
fprintf('    LOO range: [%.6f, %.6f]\n',mn,mx);
fprintf('    largest change: %.6f when omitting P%d\n', ...
    maxDelta,labels(id));

end

function print_mc(name,idx,baseVec,lo,hi)

fprintf('  %s\n',name);
fprintf('    baseline: %.6f\n',baseVec(idx));
fprintf('    sensitivity 95%% range: [%.6f, %.6f]\n', ...
    lo(idx),hi(idx));

end

function s = tfstr(tf)

if tf
    s = 'YES';
else
    s = 'NO';
end

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
