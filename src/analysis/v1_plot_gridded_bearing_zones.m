function pngPath = v1_plot_gridded_bearing_zones(caseRoot,gridSpacing_m)
% Map fitted bearings and the nearest groups identified from measured vectors.
% Optional gridSpacing_m sets the East/North spacing in map metres.

if nargin < 2
    gridSpacing_m = [];
end
outRoot = fullfile(caseRoot,'output','06_flow_aligned_plane');
modelPath = fullfile(outRoot,'flow_aligned_plane.mat');
configFile = fullfile(caseRoot,'case_config.m');

assert(isfile(modelPath),'Run Stage 6 before generating bearing zones: %s',modelPath);
assert(isfile(configFile),'Case config not found: %s',configFile);

model = load(modelPath,'FlowTable','E0','N0','eAlong','eCross','beta','gamma','dtDays');
[gridXY,fittedEN,hull,gridSpacing_m,defaultSpacing] = v1_sample_flow_grid(model,gridSpacing_m);
T = model.FlowTable;
E = T.Epoch1_X;
N = T.Epoch1_Y;
measuredEN = [T.vE_m_per_year,T.vN_m_per_year];
R = v1_flow_direction_groups(measuredEN);
k = R.SelectedK;
groups = R.Groups(R.Groups.K==k & isfinite(R.Groups.Circular_mean_deg_from_grid_north),:);
meanBearings = groups.Circular_mean_deg_from_grid_north;
groupColors = v1_flow_group_colors();

fittedSpeed = hypot(fittedEN(:,1),fittedEN(:,2));
defined = isfinite(fittedSpeed) & fittedSpeed>0;
gridXY = gridXY(defined,:);
fittedBearing = atan2d(fittedEN(defined,1),fittedEN(defined,2));

% Center the bearing scale on the measured circular mean across all matches.
% Use grid north as the reference if the circular mean is undefined.
reference = R.Groups.Circular_mean_deg_from_grid_north(R.Groups.K==1);
if isempty(reference) || ~isfinite(reference)
    reference = 0;
end
bearingOffset = mod(fittedBearing-reference+180,360)-180;
bearingLimit = max([abs(bearingOffset);1]);

run(configFile);
[Irgb,xVec,yVec,xLimits,yLimits] = v1_flow_map_background(cfg,E,N);

f = figure('Visible','off','Color','w','Position',[80 80 1500 780]);
cleanup = onCleanup(@() close(f)); %#ok<NASGU>
layout = tiledlayout(f,1,2,'TileSpacing','compact','Padding','compact');
bearingAx = nexttile(layout);
zoneAx = nexttile(layout);
for ax = [bearingAx zoneAx]
    image(ax,xVec,yVec,Irgb);
    set(ax,'YDir','normal');
    axis(ax,'image');
    xlim(ax,xLimits);
    ylim(ax,yLimits);
    hold(ax,'on');
    xlabel(ax,'Easting (m)');
    ylabel(ax,'Northing (m)');
    ax.XAxis.Exponent = 0;
    ax.YAxis.Exponent = 0;
    plot(ax,E(hull),N(hull),'--','Color',[0.1 0.1 0.1],'LineWidth',1.2);
end

title(bearingAx,sprintf('Fitted bearing | reference %.1f deg from grid north',reference));
colormap(bearingAx,parula(64));
clim(bearingAx,[-bearingLimit bearingLimit]);
bearingBar = colorbar(bearingAx,'southoutside');
bearingBar.Label.String = 'Bearing offset from reference (deg)';
if ~isempty(gridXY)
    scatter(bearingAx,gridXY(:,1),gridXY(:,2),45,bearingOffset,'s','filled', ...
        'MarkerEdgeColor',[0.15 0.15 0.15]);
end

arrowScale = 0.8*defaultSpacing/max([R.Speed_m_per_year(R.Usable);eps]);
draw_measurements(bearingAx,E(R.Usable),N(R.Usable), ...
    arrowScale*measuredEN(R.Usable,:),[1 1 1]);

if isempty(groups)
    title(zoneAx,'No defined group bearing');
    draw_measurements(zoneAx,E(R.Usable),N(R.Usable), ...
        arrowScale*measuredEN(R.Usable,:),[1 1 1]);
else
    % Use circular distance from each fitted bearing to each measured mean.
    angularDistance = abs(mod(fittedBearing-meanBearings.'+180,360)-180);
    [~,nearest] = min(angularDistance,[],2);
    colors = groupColors(groups.Group,:);
    if ~isempty(gridXY)
        scatter(zoneAx,gridXY(:,1),gridXY(:,2),45,colors(nearest,:),'s','filled', ...
            'MarkerEdgeColor',[0.15 0.15 0.15]);
    end

    markers = gobjects(height(groups),1);
    for g = 1:height(groups)
        members = R.Membership(:,k)==groups.Group(g);
        draw_measurements(zoneAx,E(members),N(members), ...
            arrowScale*measuredEN(members,:),colors(g,:));
        markers(g) = scatter(zoneAx,NaN,NaN,45,colors(g,:),'s','filled', ...
            'MarkerEdgeColor',[0.15 0.15 0.15]);
    end
    labels = compose('G%d | %.1f deg | %.1f m/yr | n=%d', ...
        groups.Group,meanBearings,groups.Median_speed_m_per_year,groups.Count);
    key = legend(zoneAx,markers,cellstr(labels),'Location','southoutside', ...
        'Orientation','horizontal','FontSize',9);
    key.Title.String = 'Measured groups: mean bearing, median speed, and count';

    if k==1
        title(zoneAx,'Fitted bearing zones | one-group baseline');
    else
        title(zoneAx,sprintf('Fitted bearing zones | k = %d | CH %.1f', ...
            k,R.Candidates.CH_score(k)));
    end
end

title(layout,'Fitted glacier bearings and zones from measured groups');
notes = sprintf(['%.0f-day interval | %.3g m grid | Squares: fitted samples ' ...
    '| Arrows: measured velocities | Dashed line: control hull'],model.dtDays,gridSpacing_m);
if isempty(gridXY)
    notes = {notes; 'No fitted grid samples have a defined bearing at this spacing.'};
end
layout.Subtitle.String = notes;

pngPath = fullfile(outRoot,'08_gridded_velocity_bearing_zones.png');
exportgraphics(f,pngPath,'Resolution',220);
end

function draw_measurements(ax,E,N,delta,color)
if isempty(E)
    return
end
quiver(ax,E,N,delta(:,1),delta(:,2),0, ...
    'Color',[0.08 0.09 0.12],'LineWidth',3.0,'MaxHeadSize',0.55);
quiver(ax,E,N,delta(:,1),delta(:,2),0, ...
    'Color',color,'LineWidth',1.6,'MaxHeadSize',0.55);
scatter(ax,E,N,25,color,'filled','MarkerEdgeColor',[0.08 0.09 0.12]);
end
