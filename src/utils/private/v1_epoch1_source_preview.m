function P = v1_epoch1_source_preview(ax,earlier,laterRef,cfg,seedXY,seedShift)
% Read the earlier image and show where the configured search windows fit.

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
fineSearchHalf = ceil((search+cfg.stage2.local_radius_m+fineHalf+0.20) / ...
    cfg.stage2.working_gsd_m)*cfg.stage2.working_gsd_m;
targetMargin = max([search+coarseHalf,fineSearchHalf, ...
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

P = struct('Gray',gray,'Valid',valid,'XBounds',xBounds,'YBounds',yBounds, ...
    'Easting',linspace(xLimits(1),xLimits(2),numel(cols)), ...
    'Northing',linspace(yLimits(1),yLimits(2),numel(rows)), ...
    'SourceMargin_m',sourceMargin, ...
    'StepYX_m',stride*[R.CellExtentInWorldY,R.CellExtentInWorldX]);
end
