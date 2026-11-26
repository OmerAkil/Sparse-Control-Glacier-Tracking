function summaryCSV = v1_write_velocity_summary(outRoot,Master,dtDays)
% Export a compact, rounded copy of the accepted Stage 5 velocities.

Summary = Master(:,{ ...
    'Point','Epoch1_X','Epoch1_Y', ...
    'dE_m','dN_m','Displacement_m', ...
    'vE_m_per_year','vN_m_per_year','Speed_m_per_year', ...
    'Direction_EofN_deg','LocalIDWResidual_m'});

Summary.Properties.VariableNames = { ...
    'Point','Epoch1_Easting_m','Epoch1_Northing_m', ...
    'East_Displacement_m','North_Displacement_m','Displacement_Distance_m', ...
    'East_Velocity_m_per_year','North_Velocity_m_per_year','Speed_m_per_year', ...
    'Direction_deg_clockwise_from_grid_north','Local_IDW_Residual_m'};

Summary{:,2:end} = round(Summary{:,2:end},2);
direction = mod(Summary.Direction_deg_clockwise_from_grid_north,360);
direction(Master.Displacement_m==0) = NaN;
Summary.Direction_deg_clockwise_from_grid_north = direction;
Summary.Interval_days = repmat(dtDays,height(Summary),1);

summaryCSV = fullfile(outRoot,'velocity_summary.csv');
tmpCSV = [tempname(outRoot) '.csv'];
cleanup = onCleanup(@() delete_if_present(tmpCSV)); %#ok<NASGU>

writetable(Summary,tmpCSV);
[ok,msg] = movefile(tmpCSV,summaryCSV,'f');
assert(ok,'Could not save the velocity summary to %s: %s',summaryCSV,msg);

end

function delete_if_present(file)
if isfile(file)
    delete(file);
end
end
