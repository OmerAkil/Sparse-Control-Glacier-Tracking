function pngPath = v1_plot_gridded_flow(caseName,gridSpacing_m)
% Compare measured velocities with the saved Stage 6 affine fit on a grid.
% Optional gridSpacing_m sets the equal East/North spacing in map metres.

analysisDir = fileparts(mfilename('fullpath'));
v1Root = fileparts(fileparts(analysisDir));
caseRoot = fullfile(v1Root,'cases',char(string(caseName)));
outRoot = fullfile(caseRoot,'output','06_flow_aligned_plane');
modelPath = fullfile(outRoot,'flow_aligned_plane.mat');
configFile = fullfile(caseRoot,'case_config.m');

assert(isfile(modelPath),'Run Stage 6 before generating the velocity map: %s',modelPath);
assert(isfile(configFile),'Case config not found: %s',configFile);

model = load(modelPath,'FlowTable','E0','N0','eAlong','eCross','beta','gamma','dtDays');
T = model.FlowTable;
E = T.Epoch1_X;
N = T.Epoch1_Y;
vE = T.vE_m_per_year;
vN = T.vN_m_per_year;

% Centre the grid and hull at the fitted model origin.
dE = E-model.E0;
dN = N-model.N0;
hull = convhull(dE,dN);
defaultSpacing = max(max(E)-min(E),max(N)-min(N))/12;

if nargin < 2
    gridSpacing_m = defaultSpacing;
end
validateattributes(gridSpacing_m,{'numeric'},{'real','finite','scalar','positive'});

firstCell = ceil([min(dE) min(dN)]/gridSpacing_m);
lastCell = floor([max(dE) max(dN)]/gridSpacing_m);
assert(prod(lastCell-firstCell+1) <= 10000, ...
    'Grid spacing creates more than 10,000 candidate positions. Use a larger spacing.');

[gridE,gridN] = meshgrid( ...
    (firstCell(1):lastCell(1))*gridSpacing_m, ...
    (firstCell(2):lastCell(2))*gridSpacing_m);
gridE = gridE(:);
gridN = gridN(:);
inside = inpolygon(gridE,gridN,dE(hull),dN(hull));
gridE = gridE(inside);
gridN = gridN(inside);

% Evaluate both fitted components, then rotate velocities back to East/North.
basis = [model.eAlong; model.eCross];
design = [ones(numel(gridE),1), [gridE gridN]*basis.'];
fittedEN = (design*[model.beta model.gamma])*basis;
gridE = gridE+model.E0;
gridN = gridN+model.N0;

run(configFile);
[Irgb,xVec,yVec,xLimits,yLimits] = v1_flow_map_background(cfg,E,N);

% Share one arrow scale across panels. Keep the longest arrows shorter
% than a grid spacing, including when the optional spacing is very coarse.
maxSpeed = max([hypot(vE,vN); hypot(fittedEN(:,1),fittedEN(:,2))]);
referenceLength = 0.65*min(defaultSpacing,gridSpacing_m);
arrowScale = 0;
if maxSpeed > 0
    arrowScale = referenceLength/maxSpeed;
end

% Zero is a common reference for comparing annualized speeds on either map.
speedLimit = maxSpeed;
if speedLimit == 0
    speedLimit = 1;
end
speedColors = parula(64);

f = figure('Visible','off','Color','w','Position',[80 80 1500 780]);
cleanupFigure = onCleanup(@() close(f)); %#ok<NASGU>
layout = tiledlayout(f,1,2,'TileSpacing','compact','Padding','compact');

observed = nexttile(layout);
modeled = nexttile(layout);
for ax = [observed modeled]
    image(ax,xVec,yVec,Irgb);
    set(ax,'YDir','normal');
    axis(ax,'image');
    xlim(ax,xLimits);
    ylim(ax,yLimits);
    hold(ax,'on');
    colormap(ax,speedColors);
    clim(ax,[0 speedLimit]);
    xlabel(ax,'Easting (m)');
    ylabel(ax,'Northing (m)');
end

hullColor = [0.13 0.16 0.20];
plot(observed,E(hull),N(hull),'--','Color',hullColor,'LineWidth',1.2);
hullLine = plot(modeled,E(hull),N(hull),'--','Color',hullColor,'LineWidth',1.2);

draw_arrows(observed,[E N],[vE vN],arrowScale,speedColors,speedLimit);
draw_arrows(modeled,[gridE gridN],fittedEN,arrowScale,speedColors,speedLimit);

scatter(observed,E,N,22,'w','filled','MarkerEdgeColor','k');
sourceMarkers = scatter(modeled,E,N,22,'w','filled','MarkerEdgeColor','k');
key = legend(modeled,[sourceMarkers hullLine], ...
    {'Accepted source locations','Control convex hull'},'Orientation','horizontal');
key.Layout.Tile = 'south';

speedBar = colorbar(modeled);
speedBar.Layout.Tile = 'east';
speedBar.Label.String = 'Speed (m/yr)';

title(observed,sprintf('Measured velocities (%d matches)',height(T)));
title(modeled,sprintf('Fitted velocities (%.3g m grid)',gridSpacing_m));
title(layout,'Annualized horizontal glacier velocity');
if maxSpeed > 0
    layout.Subtitle.String = sprintf( ...
        '%.0f-day interval | A %.3g m arrow represents %.3g m/yr in both panels', ...
        model.dtDays,referenceLength,maxSpeed);
else
    layout.Subtitle.String = sprintf( ...
        '%.0f-day interval | Fitted and measured speeds are zero',model.dtDays);
end

pngPath = fullfile(outRoot,'07_gridded_velocity_speed_map.png');
exportgraphics(f,pngPath,'Resolution',220);

end

function draw_arrows(ax,positions,velocity,arrowScale,speedColors,speedLimit)
% Match the shared colorbar. Quiver assigns one color to each series.
speed = hypot(velocity(:,1),velocity(:,2));
nColors = size(speedColors,1);
colorIndex = min(nColors,1+floor((speed/speedLimit)*nColors));
deltas = arrowScale*velocity;

for color = unique(colorIndex).'
    keep = colorIndex==color;
    E = positions(keep,1);
    N = positions(keep,2);
    dE = deltas(keep,1);
    dN = deltas(keep,2);

    % Use the same series geometry for the outline and colored arrow.
    quiver(ax,E,N,dE,dN,0, ...
        'Color',[0.05 0.09 0.12],'LineWidth',2.9,'MaxHeadSize',0.55);
    quiver(ax,E,N,dE,dN,0, ...
        'Color',speedColors(color,:),'LineWidth',1.6,'MaxHeadSize',0.55);
end
end
