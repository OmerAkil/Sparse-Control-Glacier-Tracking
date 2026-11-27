function pngPath = v1_plot_flow_direction_groups(caseRoot)
% Plot the selected bearing groups from the full-precision Stage 5 vectors.

outRoot = fullfile(caseRoot,'output','05_field_qc');
stage5Mat = fullfile(outRoot,'field_qc.mat');
assert(isfile(stage5Mat),'Stage 5 results are missing from %s.',outRoot);
S = load(stage5Mat,'Master','dtDays');
T = S.Master;
velocity = [T.vE_m_per_year,T.vN_m_per_year];
E = T.Epoch1_X;
N = T.Epoch1_Y;
R = v1_flow_direction_groups(velocity);

% Use the same map background as the gridded-velocity figure. A map of
% measured locations is still possible when the raster cannot be sampled.
Irgb = [];
span = max([max(E)-min(E),max(N)-min(N),1]);
margin = 0.08*span;
xLimits = [min(E)-margin,max(E)+margin];
yLimits = [min(N)-margin,max(N)+margin];
try
    run(fullfile(caseRoot,'case_config.m'));
    [Irgb,xVec,yVec,xLimits,yLimits] = v1_flow_map_background(cfg,E,N);
catch ME
    warning('v1:FlowDirectionBackground','Orthomosaic unavailable for direction comparison. %s',ME.message);
end

% Candidate rows are ordered by k, so the first winner breaks ties toward smaller k.
k = find(R.Candidates.Best_CH_split,1,'first');
if isempty(k)
    k = 1;
end
groups = R.Groups(R.Groups.K==k,:);
membership = R.Membership(:,k);

f = figure('Visible','off','Color','w','Position',[60 60 1200 680]);
cleanup = onCleanup(@() close(f)); %#ok<NASGU>
layout = tiledlayout(f,1,2,'TileSpacing','compact','Padding','compact');
title(layout,'Measured glacier velocity groups by bearing');
measurements = sprintf('%.0f-day interval | %d of %d accepted vectors have a bearing', ...
    S.dtDays,nnz(R.Usable),height(T));
notes = 'Legend shows mean bearing, median speed, and count. Diamonds show mean velocities in their group colors.';
if any(~R.Usable)
    notes = [notes ' Gray crosses show unassigned vectors.'];
end
layout.Subtitle.String = {measurements;notes};

groupColors = [0.00 0.46 0.70; 0.86 0.45 0.06; 0.66 0.22 0.54];
mapArrowLength = 0.055*max([diff(xLimits),diff(yLimits)]);
arrowScale = mapArrowLength/max([R.Speed_m_per_year(R.Usable);eps]);
v = [0 0;velocity(R.Usable,:)];
center = (min(v,[],1)+max(v,[],1))/2;
halfSpan = 0.56*max([max(v,[],1)-min(v,[],1),eps]);

velocityAx = nexttile(layout,1);
hold(velocityAx,'on');
box(velocityAx,'on');
grid(velocityAx,'on');
axis(velocityAx,'equal');
xlim(velocityAx,center(1)+[-halfSpan halfSpan]);
ylim(velocityAx,center(2)+[-halfSpan halfSpan]);
xline(velocityAx,0,':','Color',[0.55 0.55 0.55]);
yline(velocityAx,0,':','Color',[0.55 0.55 0.55]);
xlabel(velocityAx,'East velocity (m/yr)');
ylabel(velocityAx,'North velocity (m/yr)');

mapAx = nexttile(layout,2);
if isempty(Irgb)
    title(mapAx,'Accepted match locations (no orthomosaic)');
else
    image(mapAx,xVec,yVec,Irgb);
    title(mapAx,'Accepted match locations');
end
set(mapAx,'YDir','normal');
axis(mapAx,'image');
xlim(mapAx,xLimits);
ylim(mapAx,yLimits);
hold(mapAx,'on');
box(mapAx,'on');
mapAx.XAxis.Exponent = 0;
mapAx.YAxis.Exponent = 0;
xlabel(mapAx,'Easting (m)');
ylabel(mapAx,'Northing (m)');

unassigned = ~R.Usable;
if any(unassigned)
    plot(mapAx,E(unassigned),N(unassigned),'x','Color',[0.45 0.45 0.45]);
    onVelocityPlot = unassigned & all(isfinite(velocity),2);
    plot(velocityAx,velocity(onVelocityPlot,1),velocity(onVelocityPlot,2), ...
        'x','Color',[0.45 0.45 0.45]);
end

points = gobjects(height(groups),1);
for g = 1:height(groups)
    inGroup = membership==g;
    color = groupColors(g,:);
    points(g) = scatter(velocityAx,velocity(inGroup,1),velocity(inGroup,2), ...
        42,color,'filled','MarkerEdgeColor',[0.15 0.15 0.15]);
    u = arrowScale*velocity(inGroup,:);
    quiver(mapAx,E(inGroup),N(inGroup),u(:,1),u(:,2),0, ...
        'Color',[0.08 0.09 0.12],'LineWidth',2.7,'MaxHeadSize',0.55);
    quiver(mapAx,E(inGroup),N(inGroup),u(:,1),u(:,2),0, ...
        'Color',color,'LineWidth',1.5,'MaxHeadSize',0.55);
    scatter(mapAx,E(inGroup),N(inGroup),24,color,'filled', ...
        'MarkerEdgeColor',[0.08 0.09 0.12]);
end

if isempty(groups)
    title(velocityAx,'No usable bearings');
else
    scatter(velocityAx,groups.Mean_east_velocity_m_per_year, ...
        groups.Mean_north_velocity_m_per_year,85,groupColors(groups.Group,:),'d','filled', ...
        'MarkerEdgeColor',[0.15 0.15 0.15],'LineWidth',1.2);
    description = compose('G%d  %.1f deg | %.1f m/yr | n=%d',groups.Group, ...
        groups.Circular_mean_deg_from_grid_north,groups.Median_speed_m_per_year,groups.Count);
    legend(velocityAx,points,cellstr(description),'Location','southoutside','FontSize',9);
    if k==1
        title(velocityAx,'k = 1 | Single-direction baseline');
    else
        title(velocityAx,sprintf('k = %d | CH %.1f',k,R.Candidates.CH_score(k)));
    end
end

Candidates = R.Candidates;
Candidates.CH_score = round(Candidates.CH_score,2);
Candidates.Min_bearing_separation_deg = round(Candidates.Min_bearing_separation_deg,2);
writetable(Candidates,fullfile(outRoot,'flow_direction_candidates.csv'));

Groups = R.Groups;
Groups{:,4:end} = round(Groups{:,4:end},2);
Groups.Circular_mean_deg_from_grid_north = mod(Groups.Circular_mean_deg_from_grid_north,360);
writetable(Groups,fullfile(outRoot,'flow_direction_groups.csv'));

Membership = table(T.Point,round(E,2),round(N,2),round(R.Speed_m_per_year,2), ...
    mod(round(R.Bearing_deg_from_grid_north,2),360), ...
    R.Membership(:,1),R.Membership(:,2),R.Membership(:,3),'VariableNames',{ ...
    'Point','Epoch1_Easting_m','Epoch1_Northing_m','Speed_m_per_year', ...
    'Bearing_deg_from_grid_north','Group_k1','Group_k2','Group_k3'});
writetable(Membership,fullfile(outRoot,'flow_direction_membership.csv'));

pngPath = fullfile(outRoot,'06_dominant_flow_directions.png');
exportgraphics(f,pngPath,'Resolution',220);
end
