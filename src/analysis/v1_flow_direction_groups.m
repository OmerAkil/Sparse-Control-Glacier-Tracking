function R = v1_flow_direction_groups(velocityEN,options,displacementError_m_per_year)
% Compare one, two and three directional groups in measured velocities.
% Input is an N-by-2 matrix with east and north components in m/year.
% Groups are fitted to unit directions. Summary speeds use the input vectors.
% Pass cfg.analysis to override the automatic separation and group count.
% The optional displacement-error bound uses the same units as velocityEN.

if nargin < 2
    options = struct;
end
if nargin < 3
    displacementError_m_per_year = [];
end
manualSeparation = isfield(options,'flow_direction_min_separation_deg');
if manualSeparation
    minSeparation_deg = options.flow_direction_min_separation_deg;
    validateattributes(minSeparation_deg,{'numeric'},{'real','finite','scalar','>=',0,'<=',180}, ...
        mfilename,'flow_direction_min_separation_deg');
end
validateattributes(velocityEN,{'numeric'},{'real','2d','ncols',2});
velocityEN = double(velocityEN);
speed = hypot(velocityEN(:,1),velocityEN(:,2));
usable = isfinite(speed) & speed>0;
bearing = NaN(size(speed));

% Collapse floating-point differences between otherwise identical bearings.
bearing(usable) = mod(round(atan2d(velocityEN(usable,1),velocityEN(usable,2)),10),360);
unit = [sind(bearing(usable)),cosd(bearing(usable))];
velocity = velocityEN(usable,:);
usedSpeed = speed(usable);
usedBearing = bearing(usable);
n = nnz(usable);

minGroupCount = max(3,ceil(0.10*n));
if isfield(options,'flow_direction_min_group_count')
    minGroupCount = options.flow_direction_min_group_count;
    validateattributes(minGroupCount,{'numeric'},{'real','finite','scalar','integer','positive'}, ...
        mfilename,'flow_direction_min_group_count');
end

bearingError_deg = zeros(n,1);
separationFloor_deg = 5; % Keep a minimum angle when localization information is missing.
if ~manualSeparation && ~isempty(displacementError_m_per_year)
    validateattributes(displacementError_m_per_year,{'numeric'},{'real','finite','scalar','nonnegative'}, ...
        mfilename,'displacementError_m_per_year');
    ratio = displacementError_m_per_year./usedSpeed;
    bearingError_deg = asind(min(ratio,1));
    % A displacement comparable to its error bound has no reliable bearing.
    bearingError_deg(ratio>=1) = 180;
    separationFloor_deg = 0;
end

K = (1:3).';
CH_score = NaN(3,1);
Smallest_group_count = NaN(3,1);
Min_bearing_separation_deg = NaN(3,1);
Limiting_pair_separation_deg = NaN(3,1);
Required_separation_deg = NaN(3,1);
membership = NaN(numel(speed),3);
groupRows = zeros(0,10);

for k = 1:3
    [group,centers,CH_score(k)] = fit_partition(unit,k);
    if isempty(group)
        continue
    end

    meanBearing = mod(atan2d(centers(:,1),centers(:,2)),360);
    meanBearing(hypot(centers(:,1),centers(:,2))<=sqrt(eps)) = NaN;
    [meanBearing,order] = sort(meanBearing);
    groupIndex = zeros(k,1);
    groupIndex(order) = (1:k).';
    group = groupIndex(group);
    membership(usable,k) = group;
    Smallest_group_count(k) = min(accumarray(group,1,[k 1]));

    halfWidths = NaN(k,1);
    for g = 1:k
        inGroup = group==g;
        meanVelocity = mean(velocity(inGroup,:),1);
        deviation = abs(mod(usedBearing(inGroup)-meanBearing(g)+180,360)-180);
        halfWidths(g) = max(deviation+bearingError_deg(inGroup));
        s = usedSpeed(inGroup);
        groupRows(end+1,:) = [k,g,nnz(inGroup),meanBearing(g),max(deviation), ...
            median(s),min(s),max(s),meanVelocity]; %#ok<AGROW>
    end

    if k>1 && all(isfinite(meanBearing))
        pairs = nchoosek(1:k,2);
        a = pairs(:,1);
        b = pairs(:,2);
        gaps = abs(mod(meanBearing(a)-meanBearing(b)+180,360)-180);
        required = max(separationFloor_deg,halfWidths(a)+halfWidths(b));
        if manualSeparation
            required(:) = minSeparation_deg;
        end
        [~,limiting] = min(gaps-required);
        Min_bearing_separation_deg(k) = min(gaps);
        Limiting_pair_separation_deg(k) = gaps(limiting);
        Required_separation_deg(k) = required(limiting);
    end
end

Best_CH_split = false(3,1);
tested = find(~isnan(CH_score));
if ~isempty(tested)
    Best_CH_split(tested) = CH_score(tested)==max(CH_score(tested));
end

% Count preferences only when both candidate splits can be compared.
Leave_one_out_wins = NaN(3,1);
Leave_one_out_comparisons = NaN(3,1);
if numel(tested)==2
    wins = zeros(2,1);
    compared = 0;
    for i = 1:n
        keep = (1:n).'~=i;
        [~,~,score2] = fit_partition(unit(keep,:),2);
        [~,~,score3] = fit_partition(unit(keep,:),3);
        if ~isnan(score2) && ~isnan(score3)
            compared = compared+1;
            wins = wins + [score2>score3; score3>score2];
        end
    end
    Leave_one_out_wins(2:3) = wins;
    Leave_one_out_comparisons(2:3) = compared;
end

% CH ranks admissible splits. Retain the one-direction baseline otherwise.
Split_eligible = ~isnan(CH_score) & Limiting_pair_separation_deg>=Required_separation_deg ...
    & Smallest_group_count>=minGroupCount;
eligible = find(Split_eligible);
selectedK = 1;
if ~isempty(eligible)
    % Candidate rows are ordered by k, so ties favor the smaller split.
    [~,best] = max(CH_score(eligible));
    selectedK = K(eligible(best));
end
Selected = (K==selectedK) & n>0;
Required_group_count = repmat(minGroupCount,size(K));

R = struct;
R.SelectedK = selectedK;
R.Speed_m_per_year = speed;
R.Bearing_deg_from_grid_north = bearing;
R.Usable = usable;
R.Membership = membership;
R.Candidates = table(K,CH_score,Smallest_group_count,Min_bearing_separation_deg, ...
    Best_CH_split,Leave_one_out_wins,Leave_one_out_comparisons, ...
    Required_separation_deg,Required_group_count,Split_eligible,Selected,Limiting_pair_separation_deg);
R.Groups = array2table(groupRows,'VariableNames',{ ...
    'K','Group','Count','Circular_mean_deg_from_grid_north','Max_bearing_deviation_deg', ...
    'Median_speed_m_per_year','Min_speed_m_per_year','Max_speed_m_per_year', ...
    'Mean_east_velocity_m_per_year','Mean_north_velocity_m_per_year'});
end

function [labels,centers,score] = fit_partition(unit,k)
% Deterministic multi-start k-means on the two unit-direction components.
n = size(unit,1);
labels = [];
centers = [];
score = NaN;
if n==0 || (k>1 && n<=k)
    return
end
if k==1
    labels = ones(n,1);
    centers = mean(unit,1);
    return
end

directions = unique(unit,'rows');
nDistinct = size(directions,1);
if nDistinct<k
    return
end

starts = unique(round(linspace(1,nDistinct,min(16,nDistinct))));
bestWithin = Inf;
for start = starts
    trialCenters = zeros(k,2);
    trialCenters(1,:) = directions(start,:);
    nearest = Inf(nDistinct,1);
    for g = 2:k
        nearest = min(nearest,sum((directions-trialCenters(g-1,:)).^2,2));
        [~,farthest] = max(nearest);
        trialCenters(g,:) = directions(farthest,:);
    end

    trialLabels = zeros(n,1);
    for iteration = 1:100
        distance = zeros(n,k);
        for g = 1:k
            distance(:,g) = sum((unit-trialCenters(g,:)).^2,2);
        end
        [~,next] = min(distance,[],2);
        if isequal(next,trialLabels)
            break
        end
        trialLabels = next;
        if numel(unique(trialLabels))<k
            break
        end
        for g = 1:k
            trialCenters(g,:) = mean(unit(trialLabels==g,:),1);
        end
    end

    if numel(unique(trialLabels))<k
        continue
    end
    within = sum((unit-trialCenters(trialLabels,:)).^2,'all');
    if within<bestWithin
        bestWithin = within;
        labels = trialLabels;
        centers = trialCenters;
    end
end

if ~isempty(labels)
    count = accumarray(labels,1,[k 1]);
    between = sum(count.*sum((centers-mean(unit,1)).^2,2));
    if between>0
        if bestWithin<=n*eps^2
            score = Inf;
        else
            score = (between/(k-1))/(bestWithin/(n-k));
        end
    end
end
end
