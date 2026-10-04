function Report = v1_check_dependencies()
% v1_check_dependencies
%
% Checks the software dependencies used by V1.
%
% Validated environment:
%   MATLAB R2024a
%   Image Processing Toolbox
%   Mapping Toolbox
%
% Statistics and Machine Learning Toolbox is not required.

fprintf('\n============================================================\n');
fprintf(' V1 DEPENDENCY CHECK\n');
fprintf('============================================================\n');

matlabVersion = version;
matlabRelease = version('-release');

fprintf('MATLAB version: %s\n',matlabVersion);
fprintf('MATLAB release: %s\n',matlabRelease);

requiredFunctions = { ...
    'georasterinfo', ...
    'projcrs', ...
    'worldToIntrinsic', ...
    'normxcorr2', ...
    'mat2gray', ...
    'imgaussfilt', ...
    'imgradientxy', ...
    'edge', ...
    'bwdist', ...
    'interp2', ...
    'exportgraphics' ...
};

Function = string(requiredFunctions(:));
Available = false(numel(Function),1);
ResolvedPath = strings(numel(Function),1);

for i = 1:numel(Function)

    p = which(char(Function(i)));

    Available(i) = ~isempty(p);

    if Available(i)
        ResolvedPath(i) = string(p);
    end
end

FunctionTable = table(Function,Available,ResolvedPath);

fprintf('\nRequired functions:\n');
disp(FunctionTable(:,{'Function','Available'}));

assert(all(Available), ...
    'One or more required MATLAB functions are unavailable.');

v = ver;

toolboxNames = string({v.Name}).';
toolboxVersions = string({v.Version}).';

imageMask = contains(lower(toolboxNames),'image processing toolbox');
mapMask = contains(lower(toolboxNames),'mapping toolbox');

assert(any(imageMask), ...
    'Image Processing Toolbox was not found.');

assert(any(mapMask), ...
    'Mapping Toolbox was not found.');

fprintf('\nRequired toolboxes:\n');

fprintf('  Image Processing Toolbox: %s\n', ...
    toolboxVersions(find(imageMask,1)));

fprintf('  Mapping Toolbox:          %s\n', ...
    toolboxVersions(find(mapMask,1)));

if ~strcmpi(matlabRelease,'2024a')
    fprintf(['\nNOTE: V1 was validated under MATLAB R2024a. ' ...
             'Current release is R%s.\n'],matlabRelease);
end

fprintf('\nStatistics and Machine Learning Toolbox is not required.\n');

Report = struct;
Report.matlab_version = matlabVersion;
Report.matlab_release = matlabRelease;
Report.functions = FunctionTable;
Report.image_processing_version = toolboxVersions(find(imageMask,1));
Report.mapping_toolbox_version = toolboxVersions(find(mapMask,1));

fprintf('\n============================================================\n');
fprintf(' V1 DEPENDENCY CHECK PASSED\n');
fprintf('============================================================\n');

end
