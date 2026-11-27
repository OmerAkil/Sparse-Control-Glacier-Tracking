function [gridXY,fittedEN,hull,gridSpacing_m,defaultSpacing] = v1_sample_flow_grid(model,gridSpacing_m)
% Evaluate the saved Stage 6 velocity fit inside the accepted control hull.

E = model.FlowTable.Epoch1_X;
N = model.FlowTable.Epoch1_Y;

% Centre the grid and hull at the fitted model origin.
dE = E-model.E0;
dN = N-model.N0;
hull = convhull(dE,dN);
defaultSpacing = max(max(E)-min(E),max(N)-min(N))/12;

if isempty(gridSpacing_m)
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
gridXY = [gridE+model.E0,gridN+model.N0];
end
