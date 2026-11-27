function R = v1_case_flow_direction_groups(velocityEN,cfg,timing)
% Apply the same case settings to measured and gridded direction figures.

options = struct;
if isfield(cfg,'analysis')
    options = cfg.analysis;
end
displacementError_m_per_year = [];
if ~isfield(options,'flow_direction_min_separation_deg') && ...
        isfield(cfg,'robustness') && isfield(cfg.robustness,'localization_radius_m') && ...
        isfield(timing,'dtYears') && isfinite(timing.dtYears) && timing.dtYears>0
    radius = cfg.robustness.localization_radius_m;
    validateattributes(radius,{'numeric'},{'real','finite','scalar','positive'}, ...
        mfilename,'localization_radius_m');
    % The two position errors can point in opposite directions.
    displacementError_m_per_year = 2*radius/timing.dtYears;
end
R = v1_flow_direction_groups(velocityEN,options,displacementError_m_per_year);
end
