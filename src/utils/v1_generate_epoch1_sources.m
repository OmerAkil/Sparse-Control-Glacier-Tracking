function xy = v1_generate_epoch1_sources(earlier,laterRef,cfg,seedXY,seedShift)
% Propose source locations from distinctive, spatially separated Epoch-1 patches.

xy = zeros(0,2);
f = uifigure('Name','Generate source points from Epoch 1','WindowStyle','modal', ...
    'Position',[100 100 940 690],'Visible','off');
cleanup = onCleanup(@() delete(f(isgraphics(f)))); %#ok<NASGU>
layout = uigridlayout(f,[3 1]);
layout.RowHeight = {'1x',30,28};
ax = uiaxes(layout);
ax.Layout.Row = 1;
preview = v1_epoch1_source_preview(ax,earlier,laterRef,cfg,seedXY,seedShift);
title(ax,'Epoch 1 source proposals');
areaOutline = plot(ax,NaN,NaN,'-','Color',[1 0.7 0.20],'LineWidth',1.6);
markers = plot(ax,NaN,NaN,'o','Color',[0.03 0.18 0.25], ...
    'MarkerFaceColor',[0.12 0.85 0.97],'MarkerSize',7,'LineStyle','none');

controls = uigridlayout(layout,[1 6]);
controls.Layout.Row = 2;
controls.Padding = [0 0 0 0];
controls.ColumnWidth = {'fit',65,125,105,'1x',150};
uilabel(controls,'Text','Target point count');
countField = uieditfield(controls,'numeric','Value',12,'Limits',[1 Inf], ...
    'RoundFractionalValues','on','ValueChangedFcn',@(~,~) refreshPoints());
areaButton = uibutton(controls,'Text','Draw ice area','ButtonPushedFcn',@(~,~) drawIceArea());
clearButton = uibutton(controls,'Text','Clear area','Enable','off', ...
    'ButtonPushedFcn',@(~,~) setIceArea(zeros(0,2)));
useButton = uibutton(controls,'Text','Use generated points','Enable','off', ...
    'ButtonPushedFcn',@(~,~) usePoints());
useButton.Layout.Column = 6;
status = uilabel(layout);
status.Layout.Row = 3;

area = zeros(0,2);
proposed = zeros(0,2);
context_m = cfg.stage2.context_m;
scores = texture_scores(preview,context_m,seedXY);
refreshPoints();
f.Visible = 'on';
uiwait(f);

    function drawIceArea()
        status.Text = 'Click around the ice area. Double-click to finish or press Esc to cancel.';
        areaButton.Enable = 'off';
        useButton.Enable = 'off';
        roi = drawpolygon(ax,'Color',[1 0.7 0.20]);
        if ~isgraphics(f)
            return
        end
        areaButton.Enable = 'on';
        vertices = zeros(0,2);
        if isvalid(roi)
            vertices = roi.Position;
            delete(roi);
        end
        if size(vertices,1)>=3 && polyarea(vertices(:,1),vertices(:,2))>0
            setIceArea(vertices);
        else
            refreshPoints();
        end
    end

    function setIceArea(vertices)
        area = vertices;
        outline = [NaN NaN];
        if ~isempty(area)
            outline = [area;area(1,:)];
        end
        set(areaOutline,'XData',outline(:,1),'YData',outline(:,2));
        clearButton.Enable = ~isempty(area);
        refreshPoints();
    end

    function refreshPoints()
        proposed = spread_points(preview,scores,area,countField.Value,context_m);
        set(markers,'XData',proposed(:,1),'YData',proposed(:,2));
        useButton.Enable = ~isempty(proposed);
        if isempty(proposed)
            status.Text = 'No usable texture patches. Try a wider ice area.';
        else
            status.Text = sprintf('%d of %d proposed | Cyan points are proposals | Magenta crosses are trusted seeds', ...
                size(proposed,1),countField.Value);
        end
    end

    function usePoints()
        xy = proposed;
        uiresume(f);
    end
end

function scores = texture_scores(P,context_m,seedXY)
% Shi-Tomasi score from the smaller eigenvalue of the local gradient tensor.
east = P.Easting;
north = P.Northing(:);
step = P.StepYX_m;
imageSize = size(P.Gray);
scores = -inf(imageSize,'single');
halfTexture = max(1,round((context_m/2)./step));
% Check the source chip and the texture window, including its gradient stencil.
halfChip = max(ceil(P.SourceMargin_m./step),halfTexture+1);
if ~any(P.Valid,'all') || any(2*halfChip+1>imageSize)
    return
end

chipShape = 2*halfChip+1;
validCount = imboxfilt(single(P.Valid),chipShape,'Padding',0,'NormalizationFactor',1);
inside = east>=P.XBounds(1) & east<=P.XBounds(2) & ...
    north>=P.YBounds(1) & north<=P.YBounds(2);
eligible = inside & validCount>prod(chipShape)-0.5;
for i = 1:size(seedXY,1)
    eligible = eligible & hypot(east-seedXY(i,1),north-seedXY(i,2))>=context_m;
end
if ~any(eligible,'all')
    return
end

values = P.Gray(P.Valid);
low = min(values);
intensityRange = max(values)-low;
if intensityRange<=0
    return
end
I = zeros(imageSize,'single');
I(P.Valid) = single((values-low)/intensityRange);
[Gx,Gy] = imgradientxy(I,'sobel');
Gx = Gx/step(2);
Gy = Gy/step(1);
box = 2*halfTexture+1;
xx = imboxfilt(Gx.^2,box);
yy = imboxfilt(Gy.^2,box);
xy = imboxfilt(Gx.*Gy,box);
strength = 0.5*(xx+yy-hypot(xx-yy,2*xy));
scores(eligible) = strength(eligible);
end

function xy = spread_points(P,scores,area,targetCount,context_m)
% Look for a strong patch in each cell so dense texture cannot fill the list.
xy = zeros(0,2);
if ~isempty(area)
    [E,N] = meshgrid(P.Easting,P.Northing);
    scores(~inpolygon(E,N,area(:,1),area(:,2))) = -Inf;
end
peak = max(scores,[],'all');
if peak<=0
    return
end
% Suppress near-flat patches and weak responses relative to the chosen area.
scores(scores<max(1e-6,0.02*peak)) = -Inf;
hasFeature = isfinite(scores);
rows = find(any(hasFeature,2));
cols = find(any(hasFeature,1));
if isempty(rows)
    return
end

widthPixels = cols(end)-cols(1)+1;
heightPixels = rows(end)-rows(1)+1;
width_m = widthPixels*P.StepYX_m(2);
height_m = heightPixels*P.StepYX_m(1);
nCols = max(1,min([widthPixels,targetCount,round(sqrt(targetCount*width_m/height_m))]));
nRows = min(heightPixels,ceil(targetCount/nCols));
colEdges = floor(linspace(cols(1),cols(end)+1,nCols+1));
rowEdges = floor(linspace(rows(1),rows(end)+1,nRows+1));

cellPeaks = zeros(nCols*nRows,3);
n = 0;
for rowBand = 1:nRows
    r = rowEdges(rowBand):rowEdges(rowBand+1)-1;
    for colBand = 1:nCols
        c = colEdges(colBand):colEdges(colBand+1)-1;
        block = scores(r,c);
        [strength,index] = max(block(:));
        if isfinite(strength)
            [row,col] = ind2sub(size(block),index);
            n = n+1;
            cellPeaks(n,:) = [P.Easting(c(col)),P.Northing(r(row)),strength];
        end
    end
end
[~,order] = sort(cellPeaks(1:n,3),'descend');
minDistance = max(context_m/2,0.35*min(width_m/nCols,height_m/nRows));
for index = order.'
    point = cellPeaks(index,1:2);
    if all(hypot(xy(:,1)-point(1),xy(:,2)-point(2))>=minDistance)
        xy(end+1,:) = point; %#ok<AGROW>
        if size(xy,1)==targetCount
            break
        end
    end
end
end
