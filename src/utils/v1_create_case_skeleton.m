function v1_create_case_skeleton(caseName)
% v1_create_case_skeleton
%
% Create a clean empty Sparse-Control Glacier Tracking case.
%
% The GUI fills raster paths, acquisition dates, and CRS after creation.
% The user then imports trusted_correspondences.csv and source_points.csv.
%
% The configuration schema written here matches the v1.2.0-beta
% progressive matching and analysis backend.

if nargin < 1 || strlength(string(caseName))==0
    error('Provide a new case name.');
end

caseName = char(string(caseName));

assert(~contains(caseName,filesep), ...
    'caseName must be a folder name, not a path.');

thisFile = mfilename('fullpath');
utilsDir = fileparts(thisFile);
srcDir = fileparts(utilsDir);
v1Root = fileparts(srcDir);

caseRoot = fullfile(v1Root,'cases',caseName);

assert(~isfolder(caseRoot), ...
    'Case already exists: %s',caseRoot);

mkdir(caseRoot);
mkdir(fullfile(caseRoot,'input'));
mkdir(fullfile(caseRoot,'output'));

fid = fopen(fullfile(caseRoot,'case_config.m'),'w');
assert(fid~=-1,'Could not create case_config.m.');
cleanupObj = onCleanup(@() safe_fclose(fid)); %#ok<NASGU>

fprintf(fid,'%% case_config.m\n');
fprintf(fid,'%% Case-specific configuration for Sparse-Control Glacier Tracking.\n\n');
fprintf(fid,'cfg = struct();\n\n');

fprintf(fid,'cfg.v1_version = ''1.2.0-beta'';\n');
fprintf(fid,'cfg.case_name = ''%s'';\n\n',caseName);

fprintf(fid,'cfg.epoch1 = struct();\n');
fprintf(fid,'cfg.epoch1.name = ''EPOCH1'';\n');
fprintf(fid,'cfg.epoch1.raster = ''REPLACE_WITH_ABSOLUTE_RASTER_PATH'';\n\n');

fprintf(fid,'cfg.epoch2 = struct();\n');
fprintf(fid,'cfg.epoch2.name = ''EPOCH2'';\n');
fprintf(fid,'cfg.epoch2.raster = ''REPLACE_WITH_ABSOLUTE_RASTER_PATH'';\n\n');

fprintf(fid,'cfg.expected_crs = ''EPSG:REPLACE'';\n\n');

fprintf(fid,'%% ============================================================\n');
fprintf(fid,'%% Stage 1 - coarse structural proposal generation\n');
fprintf(fid,'%% ============================================================\n\n');
fprintf(fid,'cfg.stage1 = struct();\n');
fprintf(fid,'cfg.stage1.idw_power = 3.0;\n');
fprintf(fid,'cfg.stage1.coarse_gsd_m = 0.20;\n');
fprintf(fid,'cfg.stage1.context_scales_m = [8 12 16];\n');
fprintf(fid,'cfg.stage1.candidate_step_m = 0.40;\n');
fprintf(fid,'cfg.stage1.search_radius_m = 15.0;\n');
fprintf(fid,'cfg.stage1.top_k_per_stream = 10;\n');
fprintf(fid,'cfg.stage1.nms_radius_m = 1.20;\n');
fprintf(fid,'cfg.stage1.partial_fraction = 0.70;\n');
fprintf(fid,'cfg.stage1.trunc_distance_m = 1.00;\n');
fprintf(fid,'cfg.stage1.orientation_weight_m = 0.40;\n');
fprintf(fid,'cfg.stage1.smooth_sigma_m = 0.20;\n');
fprintf(fid,'cfg.stage1.cluster_radius_m = 1.60;\n');
fprintf(fid,'cfg.stage1.rrf_k = 5;\n\n');

fprintf(fid,'%% ============================================================\n');
fprintf(fid,'%% Stage 2 - parent-preserving local refinement\n');
fprintf(fid,'%% ============================================================\n\n');
fprintf(fid,'cfg.stage2 = struct();\n');
fprintf(fid,'cfg.stage2.n_visual_clusters = 3;\n');
fprintf(fid,'cfg.stage2.local_radius_m = 1.80;\n');
fprintf(fid,'cfg.stage2.candidate_step_m = 0.20;\n');
fprintf(fid,'cfg.stage2.working_gsd_m = 0.10;\n');
fprintf(fid,'cfg.stage2.context_m = 4.80;\n');
fprintf(fid,'cfg.stage2.partial_fraction = 0.70;\n');
fprintf(fid,'cfg.stage2.trunc_distance_m = 0.60;\n');
fprintf(fid,'cfg.stage2.orientation_weight_m = 0.25;\n');
fprintf(fid,'cfg.stage2.smooth_sigma_m = 0.10;\n');
fprintf(fid,'cfg.stage2.top_k_per_parent_per_method = 10;\n');
fprintf(fid,'cfg.stage2.parent_nms_m = 0.40;\n\n');

fprintf(fid,'%% ============================================================\n');
fprintf(fid,'%% Human review display parameters\n');
fprintf(fid,'%% ============================================================\n\n');
fprintf(fid,'cfg.review = struct();\n');
fprintf(fid,'cfg.review.display_gsd_m = 0.04;\n');
fprintf(fid,'cfg.review.source_half_width_m = 6.0;\n');
fprintf(fid,'cfg.review.overview_half_width_m = 18.0;\n');
fprintf(fid,'cfg.review.beam_half_width_m = 6.0;\n');
fprintf(fid,'cfg.review.child_distance_warning_m = 0.80;\n\n');

fprintf(fid,'%% ============================================================\n');
fprintf(fid,'%% Scientific analysis defaults\n');
fprintf(fid,'%% ============================================================\n\n');
fprintf(fid,'cfg.analysis = struct();\n');
fprintf(fid,'cfg.analysis.local_qc_neighbors = 5;\n');
fprintf(fid,'cfg.analysis.local_idw_power = 2;\n');
fprintf(fid,'cfg.analysis.close_pair_threshold_m = 5.0;\n');
fprintf(fid,'cfg.analysis.display_gsd_m = 0.20;\n');
fprintf(fid,'cfg.analysis.map_margin_m = 18.0;\n\n');

fprintf(fid,'cfg.strain = struct();\n');
fprintf(fid,'cfg.strain.bootstrap_resamples = 5000;\n');
fprintf(fid,'cfg.strain.bootstrap_rng_seed = 1;\n\n');

fprintf(fid,'cfg.robustness = struct();\n');
fprintf(fid,'cfg.robustness.mc_realizations = 5000;\n');
fprintf(fid,'cfg.robustness.mc_rng_seed = 2;\n');
fprintf(fid,'cfg.robustness.localization_radius_m = 0.20;\n');

fclose(fid);
clear cleanupObj;

Trusted = table( ...
    zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1), ...
    'VariableNames',{'Point','Epoch1_X','Epoch1_Y','Epoch2_X','Epoch2_Y'});

writetable(Trusted, ...
    fullfile(caseRoot,'input','trusted_correspondences.csv'));

Source = table( ...
    zeros(0,1),zeros(0,1),zeros(0,1), ...
    'VariableNames',{'Point','Epoch1_X','Epoch1_Y'});

writetable(Source, ...
    fullfile(caseRoot,'input','source_points.csv'));

Meta = table( ...
    NaN,NaN, ...
    'VariableNames',{'dtDays','dtYears'});

writetable(Meta, ...
    fullfile(caseRoot,'input','case_metadata.csv'));

fprintf('\nCreated new case skeleton:\n%s\n',caseRoot);

end

function safe_fclose(fid)
% Close an open file only if the identifier is still valid.
try
    if isnumeric(fid) && isscalar(fid) && fid >= 0
        name = fopen(fid);
        if ~isempty(name)
            fclose(fid);
        end
    end
catch
    % Cleanup must never mask the original error.
end
end
