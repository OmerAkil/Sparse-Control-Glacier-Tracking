function [xy,dropped] = v1_pick_epoch1_sources(earlier,laterRef,cfg,seedXY,seedShift)
% Collect source coordinates on an Epoch-1-only preview.
% The later raster bounds and seed shifts only determine the pickable area.

f = figure('Name','Pick sources from Epoch 1','Color','w', ...
    'Units','normalized','Position',[0.10 0.10 0.80 0.80]);
cleanup = onCleanup(@() delete(f(isgraphics(f)))); %#ok<NASGU>
ax = axes('Parent',f);
P = v1_epoch1_source_preview(ax,earlier,laterRef,cfg,seedXY,seedShift);
title(ax,{'Epoch 1 | Pick 20–30 features across the outlined area', ...
    'Magenta crosses mark existing seeds. Backspace undoes a pick. Enter finishes.'});
[x,y] = getpts(ax);
xy = [x(:),y(:)];
picked = size(xy,1);
inside = xy(:,1)>=P.XBounds(1) & xy(:,1)<=P.XBounds(2) & ...
    xy(:,2)>=P.YBounds(1) & xy(:,2)<=P.YBounds(2);
xy = xy(inside,:);

if ~isempty(xy)
    c = round((xy(:,1)-P.Easting(1))/(P.Easting(2)-P.Easting(1)))+1;
    r = round((xy(:,2)-P.Northing(1))/(P.Northing(2)-P.Northing(1)))+1;
    onPreview = r>=1 & r<=numel(P.Northing) & c>=1 & c<=numel(P.Easting);
    xy = xy(onPreview,:);
    pixel = sub2ind(size(P.Valid),r(onPreview),c(onPreview));
    xy = xy(P.Valid(pixel),:);
end

% Keep distinct picks at the native raster scale, in the order they were made.
distanceTolerance = min(earlier.Ref.CellExtentInWorldX,earlier.Ref.CellExtentInWorldY);
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
