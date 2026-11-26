function [Irgb,xVec,yVec,xLimits,yLimits] = v1_flow_map_background(cfg,Epoch1_X,Epoch1_Y)
% Sample the Epoch-1 orthomosaic over the control footprint and map margin.

f1 = char(string(cfg.epoch1.raster));
assert(isfile(f1),'Missing Epoch-1 raster: %s',f1);

displayGSD = cfg.analysis.display_gsd_m;
margin_m = cfg.analysis.map_margin_m;

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

xLimits = [xmin xmax];
yLimits = [ymin ymax];

end

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
