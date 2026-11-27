function [xy,dropped] = v1_pick_epoch1_sources(earlier,laterRef,cfg,seedXY,seedShift)
% Collect source coordinates on an Epoch-1-only preview.
% The later raster bounds and seed shifts only determine the pickable area.

R = earlier.Ref;
overlapX = [max(R.XWorldLimits(1),laterRef.XWorldLimits(1)), ...
    min(R.XWorldLimits(2),laterRef.XWorldLimits(2))];
overlapY = [max(R.YWorldLimits(1),laterRef.YWorldLimits(1)), ...
    min(R.YWorldLimits(2),laterRef.YWorldLimits(2))];
assert(diff(overlapX)>0 && diff(overlapY)>0,'The rasters have no common map overlap.');

% Leave room for the source and target chips used by matching and review.
coarseHalf = max(cfg.stage1.context_scales_m(:))/2;
fineHalf = cfg.stage2.context_m/2;
workingPadding = max([cfg.stage1.coarse_gsd_m,cfg.stage2.working_gsd_m,cfg.review.display_gsd_m]);
sourceMargin = max([coarseHalf,fineHalf,cfg.review.source_half_width_m]) + ...
    max([workingPadding,R.CellExtentInWorldX,R.CellExtentInWorldY]);
search = cfg.stage1.search_radius_m;
targetMargin = max([search+coarseHalf,search+cfg.stage2.local_radius_m+fineHalf, ...
    cfg.review.overview_half_width_m,search+cfg.review.beam_half_width_m]) + ...
    max([workingPadding,laterRef.CellExtentInWorldX,laterRef.CellExtentInWorldY]);

% IDW predicts a weighted average of seed shifts. Use their component range
% to keep an initial search chip inside the later raster's rectangular extent.
xBounds = [max([overlapX(1),R.XWorldLimits(1)+sourceMargin, ...
    laterRef.XWorldLimits(1)+targetMargin-min(seedShift(:,1))]), ...
    min([overlapX(2),R.XWorldLimits(2)-sourceMargin, ...
    laterRef.XWorldLimits(2)-targetMargin-max(seedShift(:,1))])];
yBounds = [max([overlapY(1),R.YWorldLimits(1)+sourceMargin, ...
    laterRef.YWorldLimits(1)+targetMargin-min(seedShift(:,2))]), ...
    min([overlapY(2),R.YWorldLimits(2)-sourceMargin, ...
    laterRef.YWorldLimits(2)-targetMargin-max(seedShift(:,2))])];
assert(diff(xBounds)>0 && diff(yBounds)>0, ...
    'The overlap is too narrow for the configured search windows and seed shifts.');

[colLimits,rowLimits] = worldToIntrinsic(R,overlapX,overlapY);
first = max([1 1],ceil([min(rowLimits),min(colLimits)]));
last = min(R.RasterSize,floor([max(rowLimits),max(colLimits)]));
stride = max(1,ceil(max(last-first+1)/2048));
rows = first(1):stride:last(1);
cols = first(2):stride:last(2);
assert(numel(rows)>=2 && numel(cols)>=2,'The overlap is too small to display.');
I = imread(char(earlier.File),'PixelRegion',{[rows(1) stride rows(end)], ...
    [cols(1) stride cols(end)]});
I = double(I(:,:,1:min(3,size(I,3))));
valid = all(isfinite(I),3);
missing = earlier.Info.MissingDataIndicator;
if isscalar(missing) && isfinite(missing)
    valid = valid & ~all(I==missing,3);
end
gray = mean(I,3);
gray(~valid) = NaN;

[xLimits,yLimits] = intrinsicToWorld(R,cols([1 end]),rows([1 end]));
f = figure('Name','Pick sources from Epoch 1','Color','w', ...
    'Units','normalized','Position',[0.10 0.10 0.80 0.80]);
cleanup = onCleanup(@() delete(f(isgraphics(f)))); %#ok<NASGU>
ax = axes('Parent',f);
imagesc(ax,xLimits,yLimits,gray,'AlphaData',valid);
set(ax,'YDir','normal','Color',[0.12 0.12 0.12]);
axis(ax,'image');
xlim(ax,sort(xLimits));
ylim(ax,sort(yLimits));
colormap(ax,bone(256));
hold(ax,'on');
rectangle(ax,'Position',[xBounds(1),yBounds(1),diff(xBounds),diff(yBounds)], ...
    'LineStyle','--','EdgeColor',[0.98 0.80 0.24],'LineWidth',1.5);
plot(ax,seedXY(:,1),seedXY(:,2),'m+','MarkerSize',9,'LineWidth',1.4);
xlabel(ax,'Easting (m)');
ylabel(ax,'Northing (m)');
title(ax,{'Epoch 1 | Pick 20–30 features across the outlined area', ...
    'Magenta crosses mark existing seeds. Backspace undoes a pick. Enter finishes.'});
[x,y] = getpts(ax);
xy = [x(:),y(:)];
picked = size(xy,1);
inside = xy(:,1)>=xBounds(1) & xy(:,1)<=xBounds(2) & ...
    xy(:,2)>=yBounds(1) & xy(:,2)<=yBounds(2);
xy = xy(inside,:);

if ~isempty(xy)
    [col,row] = worldToIntrinsic(R,xy(:,1),xy(:,2));
    c = round((col-cols(1))/stride)+1;
    r = round((row-rows(1))/stride)+1;
    onPreview = r>=1 & r<=numel(rows) & c>=1 & c<=numel(cols);
    xy = xy(onPreview,:);
    pixel = sub2ind(size(valid),r(onPreview),c(onPreview));
    xy = xy(valid(pixel),:);
end

% Keep distinct picks at the native raster scale, in the order they were made.
distanceTolerance = min(R.CellExtentInWorldX,R.CellExtentInWorldY);
keep = false(size(xy,1),1);
occupied = seedXY;
for i = 1:size(xy,1)
    if all(hypot(occupied(:,1)-xy(i,1),occupied(:,2)-xy(i,2))>distanceTolerance)
        keep(i) = true;
        occupied(end+1,:) = xy(i,:); %#ok<AGROW>
    end
end
xy = xy(keep,:);
dropped = picked-size(xy,1);
end
