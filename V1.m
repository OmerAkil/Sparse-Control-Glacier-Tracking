function V1
% V1 - Sparse-Control Glacier Tracking v1.2.1-beta GUI.
% Place V1.m in the repository root and run: V1

v1Root = fileparts(mfilename('fullpath'));
assert(isfolder(fullfile(v1Root,'src')), ...
    'Place V1.m directly in the repository root.');
addpath(genpath(fullfile(v1Root,'src')));

assert(exist('v1_prepare_case','file')==2,'v1_prepare_case.m not found.');
assert(exist('v1_create_case_skeleton','file')==2,'v1_create_case_skeleton.m not found.');

S = struct('caseName',"",'caseRoot',"", ...
    'epoch1Raster',"",'epoch2Raster',"", ...
    'epoch1Info',[],'epoch2Info',[], ...
    'expectedCRS',"",'epoch1Date',NaT,'epoch2Date',NaT);

fig = uifigure('Name','Sparse-Control Glacier Tracking - v1.2.1-beta', ...
    'Position',[100 80 1040 720]);
main = uigridlayout(fig,[2 1]);
main.RowHeight = {58,'1x'};
main.Padding = [0 0 0 0];

head = uigridlayout(main,[1 3]);
head.Layout.Row = 1;
head.ColumnWidth = {'1x','fit','fit'};
head.Padding = [18 10 18 8];
uilabel(head,'Text','Sparse-Control Glacier Tracking', ...
    'FontSize',20,'FontWeight','bold');
uilabel(head,'Text','v1.2.1-beta');
uibutton(head,'push','Text','Home','ButtonPushedFcn',@(~,~) showHome());

content = uipanel(main,'BorderType','none');
content.Layout.Row = 2;
showHome();

    function clearPage()
        if ~isempty(content.Children), delete(content.Children); end
    end

    function showHome()
        clearPage();
        g = uigridlayout(content,[6 3]);
        g.RowHeight = {60,45,35,70,70,'1x'};
        g.ColumnWidth = {'1x',320,'1x'};
        g.Padding = [30 40 30 30];
        a = uilabel(g,'Text','Sparse-Control Glacier Tracking', ...
            'FontSize',28,'FontWeight','bold','HorizontalAlignment','center');
        a.Layout.Row=1; a.Layout.Column=[1 3];
        a = uilabel(g,'Text','Human-validated sparse horizontal-displacement workflow', ...
            'FontSize',15,'HorizontalAlignment','center');
        a.Layout.Row=2; a.Layout.Column=[1 3];
        a = uilabel(g,'Text','Progressive human-validated sparse-control workflow.', ...
            'HorizontalAlignment','center');
        a.Layout.Row=3; a.Layout.Column=[1 3];
        b = uibutton(g,'push','Text','New Project','FontSize',17, ...
            'ButtonPushedFcn',@(~,~) showNewProject());
        b.Layout.Row=4; b.Layout.Column=2;
        b = uibutton(g,'push','Text','Open Project','FontSize',17, ...
            'ButtonPushedFcn',@(~,~) openProject());
        b.Layout.Row=5; b.Layout.Column=2;
    end

    function showNewProject()
        clearPage();
        S.caseName=""; S.caseRoot=""; S.epoch1Raster=""; S.epoch2Raster="";
        S.epoch1Info=[]; S.epoch2Info=[]; S.expectedCRS="";

        g = uigridlayout(content,[9 4]);
        g.RowHeight = {40,34,34,34,34,34,110,45,'1x'};
        g.ColumnWidth = {155,'1x',120,20};
        g.Padding = [28 22 28 24]; g.RowSpacing=10;

        a=uilabel(g,'Text','New Project','FontSize',22,'FontWeight','bold');
        a.Layout.Row=1; a.Layout.Column=[1 4];

        a=uilabel(g,'Text','Project name:','FontWeight','bold','HorizontalAlignment','right');
        a.Layout.Row=2; a.Layout.Column=1;
        nameEdit=uieditfield(g,'text','Placeholder','e.g. Glacier_2025_2026', ...
            'ValueChangedFcn',@(~,~) refresh());
        nameEdit.Layout.Row=2; nameEdit.Layout.Column=[2 3];

        a=uilabel(g,'Text','Earlier image:','FontWeight','bold','HorizontalAlignment','right');
        a.Layout.Row=3; a.Layout.Column=1;
        e1=uieditfield(g,'text','Editable','off'); e1.Layout.Row=3; e1.Layout.Column=2;
        b=uibutton(g,'push','Text','Browse...','ButtonPushedFcn',@(~,~) chooseRaster(1));
        b.Layout.Row=3; b.Layout.Column=3;

        a=uilabel(g,'Text','Later image:','FontWeight','bold','HorizontalAlignment','right');
        a.Layout.Row=4; a.Layout.Column=1;
        e2=uieditfield(g,'text','Editable','off'); e2.Layout.Row=4; e2.Layout.Column=2;
        b=uibutton(g,'push','Text','Browse...','ButtonPushedFcn',@(~,~) chooseRaster(2));
        b.Layout.Row=4; b.Layout.Column=3;

        a=uilabel(g,'Text','Earlier date:','FontWeight','bold','HorizontalAlignment','right');
        a.Layout.Row=5; a.Layout.Column=1;
        d1=uidatepicker(g,'DisplayFormat','yyyy-MM-dd','Value',datetime('today')-calyears(1), ...
            'ValueChangedFcn',@(~,~) refresh());
        d1.Layout.Row=5; d1.Layout.Column=2;

        a=uilabel(g,'Text','Later date:','FontWeight','bold','HorizontalAlignment','right');
        a.Layout.Row=6; a.Layout.Column=1;
        d2=uidatepicker(g,'DisplayFormat','yyyy-MM-dd','Value',datetime('today'), ...
            'ValueChangedFcn',@(~,~) refresh());
        d2.Layout.Row=6; d2.Layout.Column=2;

        crsLbl=uilabel(g,'Text','CRS: waiting for rasters','FontWeight','bold');
        crsLbl.Layout.Row=5; crsLbl.Layout.Column=3;
        intLbl=uilabel(g,'Text','Interval: --'); intLbl.Layout.Row=6; intLbl.Layout.Column=3;
        summary=uitextarea(g,'Editable','off','Value',{'Choose both GeoTIFFs.'});
        summary.Layout.Row=7; summary.Layout.Column=[1 3];
        createBtn=uibutton(g,'push','Text','Create Project','FontSize',15,'Enable','off', ...
            'ButtonPushedFcn',@(~,~) createProject());
        createBtn.Layout.Row=8; createBtn.Layout.Column=[2 3];
        refresh();

        function chooseRaster(which)
            [f,p]=uigetfile({'*.tif;*.tiff','GeoTIFF files (*.tif, *.tiff)'},'Select GeoTIFF');
            if isequal(f,0), return; end
            fp=fullfile(p,f);
            try
                I=inspectRaster(fp);
                if which==1
                    S.epoch1Raster=string(fp); S.epoch1Info=I; e1.Value=fp;
                else
                    S.epoch2Raster=string(fp); S.epoch2Info=I; e2.Value=fp;
                end
                refresh();
            catch ME
                uialert(fig,ME.message,'Raster rejected');
            end
        end

        function refresh()
            intervalOK = d2.Value>d1.Value;
            if intervalOK
                dd=days(d2.Value-d1.Value);
                intLbl.Text=sprintf('Interval: %.0f d (%.6f yr)',dd,dd/365);
            else
                intLbl.Text='Interval: invalid';
            end
            nameOK=~isempty(regexp(strtrim(nameEdit.Value),'^[A-Za-z0-9_-]+$','once'));
            pairOK=false; lines=strings(0,1);
            if strlength(S.epoch1Raster)>0, lines(end+1)=rasterLine("Earlier",S.epoch1Info); end %#ok<AGROW>
            if strlength(S.epoch2Raster)>0, lines(end+1)=rasterLine("Later",S.epoch2Info); end %#ok<AGROW>
            if strlength(S.epoch1Raster)>0 && strlength(S.epoch2Raster)>0
                try
                    [epsgText,overlapText]=validatePair(S.epoch1Info,S.epoch2Info);
                    S.expectedCRS=string(epsgText); crsLbl.Text=['CRS: ' epsgText];
                    lines(end+1)=string(overlapText); pairOK=true; %#ok<AGROW>
                catch ME
                    S.expectedCRS=""; crsLbl.Text='CRS: validation failed';
                    lines(end+1)="ERROR: "+string(ME.message); %#ok<AGROW>
                end
            end
            if isempty(lines), lines="Choose both GeoTIFFs."; end
            summary.Value=cellstr(lines);
            if nameOK && intervalOK && pairOK, createBtn.Enable='on'; else, createBtn.Enable='off'; end
        end

        function createProject()
            caseName=strtrim(string(nameEdit.Value));
            caseRoot=fullfile(v1Root,'cases',char(caseName));
            if isfolder(caseRoot)
                uialert(fig,'A project with this name already exists. Use Open Project.','Project exists'); return;
            end
            try
                [epsgText,~]=validatePair(S.epoch1Info,S.epoch2Info);
                dtDays=days(d2.Value-d1.Value);
                evalc('v1_create_case_skeleton(char(caseName));');
                cfgFile=fullfile(caseRoot,'case_config.m');
                patchConfig(cfgFile,caseName,S.epoch1Raster,S.epoch2Raster,d1.Value,d2.Value,string(epsgText));
                Meta=table(dtDays,dtDays/365,'VariableNames',{'dtDays','dtYears'});
                writetable(Meta,fullfile(caseRoot,'input','case_metadata.csv'));
                S.caseName=caseName; S.caseRoot=string(caseRoot); S.expectedCRS=string(epsgText);
                S.epoch1Date=d1.Value; S.epoch2Date=d2.Value;
                showWorkspace();
            catch ME
                uialert(fig,ME.message,'Project creation failed');
            end
        end
    end

    function showResults()
        % Results dashboard for completed Stages 5-8.
        % This page reads existing scientific outputs only. It does not
        % recompute or modify any correspondence or analysis result.

        stage5Mat=fullfile( ...
            char(S.caseRoot),'output','05_field_qc','field_qc.mat');
        stage6Mat=fullfile( ...
            char(S.caseRoot),'output','06_flow_aligned_plane','flow_aligned_plane.mat');
        stage7Mat=fullfile( ...
            char(S.caseRoot),'output','07_strain_rate','strain_rate_analysis.mat');
        stage8Mat=fullfile( ...
            char(S.caseRoot),'output','08_robustness','robustness_sensitivity.mat');

        assert(isfile(stage5Mat) && isfile(stage6Mat) && ...
               isfile(stage7Mat) && isfile(stage8Mat), ...
            'Scientific analysis must be complete before opening Results.');

        A5=load(stage5Mat);
        A6=load(stage6Mat);
        A7=load(stage7Mat);
        A8=load(stage8Mat);

        clearPage();

        outer=uigridlayout(content,[3 1]);
        outer.RowHeight={46,'1x',40};
        outer.Padding=[18 12 18 12];
        outer.RowSpacing=8;

        top=uigridlayout(outer,[1 4]);
        top.Layout.Row=1;
        top.ColumnWidth={'1x','fit','fit','fit'};
        top.Padding=[0 0 0 0];

        a=uilabel(top, ...
            'Text',sprintf('%s - Scientific Results',char(S.caseName)), ...
            'FontSize',21,'FontWeight','bold');
        a.Layout.Column=1;

        b=uibutton(top,'push','Text','Project Workspace', ...
            'ButtonPushedFcn',@(~,~) showWorkspace());
        b.Layout.Column=2;

        b=uibutton(top,'push','Text','Open Output Folder', ...
            'ButtonPushedFcn',@(~,~) openFolder(fullfile(char(S.caseRoot),'output')));
        b.Layout.Column=3;

        b=uibutton(top,'push','Text','Home', ...
            'ButtonPushedFcn',@(~,~) showHome());
        b.Layout.Column=4;

        tabs=uitabgroup(outer);
        tabs.Layout.Row=2;

        % ====================================================
        % OVERVIEW / FIELD QC
        % ====================================================
        t=uitab(tabs,'Title','Velocity / QC');

        speed=A5.Master.Speed_m_per_year;
        localResidual=A5.Master.LocalIDWResidual_m;

        metrics={ ...
            'Final vectors',sprintf('%d',height(A5.Master)); ...
            'Interval',sprintf('%.0f days = %.6f yr',A5.dtDays,A5.dtYears); ...
            'Speed median',sprintf('%.2f m/yr',median(speed)); ...
            'Speed mean',sprintf('%.2f m/yr',mean(speed)); ...
            'Speed range',sprintf('%.2f - %.2f m/yr',min(speed),max(speed)); ...
            'Mean flow direction',sprintf('%.3f deg E of N',A5.MeanFlowDirection_EofN_deg); ...
            'Direction concentration R',sprintf('%.6f',A5.DirectionConcentration_R); ...
            'Median local QC residual',sprintf('%.3f m',median(localResidual)); ...
            'Maximum local QC residual',sprintf('%.3f m',max(localResidual))};

        figures={ ...
            'Displacement vectors','01_displacement_vectors.png'; ...
            'Speed map','02_speed_map.png'; ...
            'Local IDW residual map','03_local_IDW_residual_map.png'; ...
            'Spatial coverage / Delaunay','04_spatial_coverage_delaunay.png'; ...
            'Speed vs Easting','05_speed_vs_easting.png'};

        buildResultTab(t,metrics, ...
            fullfile(char(S.caseRoot),'output','05_field_qc'),figures);

        % ====================================================
        % FLOW-ALIGNED PLANE
        % ====================================================
        t=uitab(tabs,'Title','Flow Plane');

        vcross=A6.FlowTable.v_cross_m_per_year;

        metrics={ ...
            'Mean flow direction',sprintf('%.3f deg E of N',A6.meanFlowDeg); ...
            'Direction concentration R',sprintf('%.6f',A6.Rdir); ...
            'Along-flow intercept beta0',sprintf('%.3f m/yr',A6.beta(1)); ...
            'd(v_along)/d(x_along)',sprintf('%+.3f m/yr per 100 m',A6.gradAlong_per100); ...
            'd(v_along)/d(y_cross)',sprintf('%+.3f m/yr per 100 m',A6.gradCross_per100); ...
            'Gradient magnitude',sprintf('%.3f m/yr per 100 m',A6.gradientMagnitude_per100); ...
            '|cross/along| slope ratio',sprintf('%.3f',A6.crossToAlongGradientRatio); ...
            'Along-plane R^2',sprintf('%.4f',A6.R2_along); ...
            'Along-plane RMSE',sprintf('%.3f m/yr',A6.RMSE_along); ...
            'Median v_cross',sprintf('%+.3f m/yr',median(vcross)); ...
            'Median |v_cross|',sprintf('%.3f m/yr',median(abs(vcross))); ...
            'Cross-plane R^2',sprintf('%.4f',A6.R2_cross)};

        figures={ ...
            'Flow-aligned axes','01_flow_aligned_axes.png'; ...
            '3-D v_along plane','02_v_along_plane_3D.png'; ...
            'v_along residual map','03_v_along_plane_residual_map.png'; ...
            'Observed vs fitted v_along','04_observed_vs_fitted_v_along.png'; ...
            'Partial along-flow gradient','05_partial_along_flow_gradient.png'; ...
            'Partial cross-flow gradient','06_partial_cross_flow_gradient.png'};

        buildResultTab(t,metrics, ...
            fullfile(char(S.caseRoot),'output','06_flow_aligned_plane'),figures);

        % ====================================================
        % STRAIN RATE
        % ====================================================
        t=uitab(tabs,'Title','Strain Rate');

        metrics={ ...
            'Longitudinal strain eps_xx',sprintf('%+.2f %%/yr',100*A7.eps_xx); ...
            'Transverse strain eps_yy',sprintf('%+.2f %%/yr',100*A7.eps_yy); ...
            'Tensor shear eps_xy',sprintf('%+.4f yr^-1',A7.eps_xy); ...
            'Engineering shear',sprintf('%+.2f %%/yr',100*A7.gamma_xy); ...
            'Horizontal divergence',sprintf('%+.2f %%/yr',100*A7.divergence); ...
            'Principal extension',sprintf('%+.2f %%/yr',100*A7.eps_max); ...
            'Principal compression',sprintf('%+.2f %%/yr',100*A7.eps_min); ...
            'Maximum shear rate',sprintf('%.2f %%/yr',100*A7.maxShearRate); ...
            'Extension-axis azimuth',sprintf('%.2f deg E of N',A7.maxExtensionAzimuth_EofN_deg); ...
            'Map rotation',sprintf('%+.3f deg/yr',A7.omega_EN_deg_per_year); ...
            'v_along fit R^2 / RMSE',sprintf('%.4f / %.3f m/yr',A7.R2_u,A7.RMSE_u); ...
            'Bootstrap resamples accepted',sprintf('%d',A7.nAccepted)};

        figures={ ...
            'Principal strain axes map','01_principal_strain_axes_map.png'; ...
            'One-year strain ellipse','02_one_year_strain_ellipse.png'; ...
            'Strain-rate components','03_strain_rate_components.png'; ...
            'Bootstrap 95% intervals','04_bootstrap_95CI.png'};

        buildResultTab(t,metrics, ...
            fullfile(char(S.caseRoot),'output','07_strain_rate'),figures);

        % ====================================================
        % ROBUSTNESS
        % ====================================================
        t=uitab(tabs,'Title','Robustness');

        names=string(A8.metricNames);
        idxDuDx=find(names=="du_dx",1);
        idxDuDy=find(names=="du_dy",1);
        idxDiv=find(names=="divergence",1);
        idxPMin=find(names=="principal_min",1);
        idxPMax=find(names=="principal_max",1);
        idxRot=find(names=="rotation_deg_per_year",1);

        metrics={ ...
            'Monte-Carlo realizations',sprintf('%d',A8.nMC); ...
            'Localization perturbation radius',sprintf('%.2f m',A8.localizationRadius_m); ...
            'du/dx MC 95% sensitivity',intervalText(A8.MCLow(idxDuDx),A8.MCHigh(idxDuDx),'yr^-1'); ...
            'du/dy MC 95% sensitivity',intervalText(A8.MCLow(idxDuDy),A8.MCHigh(idxDuDy),'yr^-1'); ...
            'Divergence MC 95% sensitivity',intervalText(A8.MCLow(idxDiv),A8.MCHigh(idxDiv),'yr^-1'); ...
            'Compression MC 95% sensitivity',intervalText(A8.MCLow(idxPMin),A8.MCHigh(idxPMin),'yr^-1'); ...
            'Extension MC 95% sensitivity',intervalText(A8.MCLow(idxPMax),A8.MCHigh(idxPMax),'yr^-1'); ...
            'Rotation MC 95% sensitivity',intervalText(A8.MCLow(idxRot),A8.MCHigh(idxRot),'deg/yr'); ...
            'du/dx positive in all MC',tfText(all(A8.MC(:,idxDuDx)>0)); ...
            'du/dy positive in all MC',tfText(all(A8.MC(:,idxDuDy)>0)); ...
            'Compression negative in all MC',tfText(all(A8.MC(:,idxPMin)<0)); ...
            'Extension positive in all MC',tfText(all(A8.MC(:,idxPMax)>0))};

        figures={ ...
            'Leave-one-out influence','01_leave_one_out_gradient_influence.png'; ...
            'MC gradient sensitivity','02_MC_gradient_sensitivity.png'; ...
            'MC principal strain sensitivity','03_MC_principal_strain_sensitivity.png'; ...
            'Coordinate uncertainty intervals','04_coordinate_uncertainty_intervals.png'};

        buildResultTab(t,metrics, ...
            fullfile(char(S.caseRoot),'output','08_robustness'),figures);

        note=uilabel(outer, ...
            'Text',['Scope: values describe the finalized sparse horizontal-displacement field over the project AOI. ' ...
                    'Annualized velocities are interval-average values; strain results are first-order 2-D horizontal estimates.'], ...
            'WordWrap','on');
        note.Layout.Row=3;
    end

    function buildResultTab(tab,metrics,resultDir,figures)
        g=uigridlayout(tab,[1 2]);
        g.ColumnWidth={360,'1x'};
        g.Padding=[12 12 12 12];
        g.ColumnSpacing=14;

        left=uigridlayout(g,[3 1]);
        left.Layout.Column=1;
        left.RowHeight={28,'1x',38};
        left.Padding=[0 0 0 0];

        a=uilabel(left,'Text','Key metrics','FontSize',16,'FontWeight','bold');
        a.Layout.Row=1;

        tbl=uitable(left, ...
            'Data',metrics, ...
            'ColumnName',{'Metric','Value'}, ...
            'ColumnEditable',[false false], ...
            'RowName',[]);
        tbl.Layout.Row=2;
        tbl.ColumnWidth={205,130};

        b=uibutton(left,'push','Text','Open this stage output folder', ...
            'ButtonPushedFcn',@(~,~) openFolder(resultDir));
        b.Layout.Row=3;

        right=uigridlayout(g,[3 1]);
        right.Layout.Column=2;
        right.RowHeight={28,34,'1x'};
        right.Padding=[0 0 0 0];

        a=uilabel(right,'Text','Figures','FontSize',16,'FontWeight','bold');
        a.Layout.Row=1;

        labels=figures(:,1);
        files=figures(:,2);

        dd=uidropdown(right,'Items',labels,'Value',labels{1});
        dd.Layout.Row=2;

        img=uiimage(right, ...
            'ScaleMethod','fit', ...
            'ImageSource',fullfile(resultDir,files{1}));
        img.Layout.Row=3;

        dd.ValueChangedFcn=@(~,~) updatePreview();

        function updatePreview()
            idx=find(strcmp(labels,dd.Value),1);

            if isempty(idx)
                return
            end

            fp=fullfile(resultDir,files{idx});

            if isfile(fp)
                img.ImageSource=fp;
            else
                uialert(fig, ...
                    ['Figure file not found:' newline fp], ...
                    'Missing result figure');
            end
        end
    end

    function openFolder(folderPath)
        assert(isfolder(folderPath), ...
            'Folder not found: %s',folderPath);

        if ispc
            winopen(folderPath);
        elseif ismac
            system(sprintf('open "%s"',folderPath));
        else
            system(sprintf('xdg-open "%s" &',folderPath));
        end
    end

    function s = intervalText(lo,hi,unitText)
        s=sprintf('[%+.6f, %+.6f] %s',lo,hi,unitText);
    end

    function s = tfText(tf)
        if tf
            s='YES';
        else
            s='NO';
        end
    end

    function openProject()
        casesRoot=fullfile(v1Root,'cases'); if ~isfolder(casesRoot), mkdir(casesRoot); end
        p=uigetdir(casesRoot,'Select existing V1 case folder'); if isequal(p,0), return; end
        cfgFile=fullfile(p,'case_config.m');
        if ~isfile(cfgFile), uialert(fig,'Selected folder has no case_config.m.','Not a V1 project'); return; end
        try
            cfgLocal=readConfig(cfgFile);
            S.caseRoot=string(p); S.caseName=string(cfgLocal.case_name);
            S.epoch1Raster=string(cfgLocal.epoch1.raster); S.epoch2Raster=string(cfgLocal.epoch2.raster);
            S.expectedCRS=string(cfgLocal.expected_crs);
            S.epoch1Info=inspectRaster(char(S.epoch1Raster)); S.epoch2Info=inspectRaster(char(S.epoch2Raster));
            if isfield(cfgLocal.epoch1,'date'), S.epoch1Date=datetime(string(cfgLocal.epoch1.date)); else, S.epoch1Date=NaT; end
            if isfield(cfgLocal.epoch2,'date'), S.epoch2Date=datetime(string(cfgLocal.epoch2.date)); else, S.epoch2Date=NaT; end
            showWorkspace();
        catch ME
            uialert(fig,ME.message,'Open Project failed');
        end
    end

    function showWorkspace()
        clearPage();
        g=uigridlayout(content,[14 4]);
        g.RowHeight={42,28,28,28,22,75,75,38,48,48,48,48,220,'1x'};
        g.ColumnWidth={190,'1x',150,20}; g.Padding=[28 22 28 24]; g.RowSpacing=8;
        a=uilabel(g,'Text',char(S.caseName),'FontSize',22,'FontWeight','bold'); a.Layout.Row=1; a.Layout.Column=[1 4];
        addRowLabel(g,2,'Earlier raster:'); x=uieditfield(g,'text','Editable','off','Value',char(S.epoch1Raster)); x.Layout.Row=2; x.Layout.Column=[2 3];
        addRowLabel(g,3,'Later raster:'); x=uieditfield(g,'text','Editable','off','Value',char(S.epoch2Raster)); x.Layout.Row=3; x.Layout.Column=[2 3];
        addRowLabel(g,4,'CRS / interval:'); a=uilabel(g,'Text',metadataLine()); a.Layout.Row=4; a.Layout.Column=[2 3];
        a=uilabel(g,'Text','Import control data','FontSize',15,'FontWeight','bold'); a.Layout.Row=5; a.Layout.Column=[1 3];

        tp=uipanel(g,'Title','Initial trusted correspondences'); tp.Layout.Row=6; tp.Layout.Column=[1 3];
        tg=uigridlayout(tp,[2 3]); tg.RowHeight={30,22}; tg.ColumnWidth={'1x',130,130};
        tStatus=uilabel(tg,'Text','Not loaded'); tStatus.Layout.Row=1; tStatus.Layout.Column=1;
        b=uibutton(tg,'push','Text','Import CSV...','ButtonPushedFcn',@(~,~) importCSV('trusted')); b.Layout.Row=1; b.Layout.Column=2;
        tOpen=uibutton(tg,'push','Text','Open current','Enable','off','ButtonPushedFcn',@(~,~) openCSV('trusted')); tOpen.Layout.Row=1; tOpen.Layout.Column=3;
        a=uilabel(tg,'Text','Required: Point, Epoch1_X, Epoch1_Y, Epoch2_X, Epoch2_Y'); a.Layout.Row=2; a.Layout.Column=[1 3];

        sp=uipanel(g,'Title','Source points'); sp.Layout.Row=7; sp.Layout.Column=[1 3];
        sg=uigridlayout(sp,[2 3]); sg.RowHeight={30,22}; sg.ColumnWidth={'1x',130,130};
        sStatus=uilabel(sg,'Text','Not loaded'); sStatus.Layout.Row=1; sStatus.Layout.Column=1;
        b=uibutton(sg,'push','Text','Import CSV...','ButtonPushedFcn',@(~,~) importCSV('source')); b.Layout.Row=1; b.Layout.Column=2;
        sOpen=uibutton(sg,'push','Text','Open current','Enable','off','ButtonPushedFcn',@(~,~) openCSV('source')); sOpen.Layout.Row=1; sOpen.Layout.Column=3;
        a=uilabel(sg,'Text','Required: Point, Epoch1_X, Epoch1_Y'); a.Layout.Row=2; a.Layout.Column=[1 3];

        b=uibutton(g,'push','Text','Revalidate Project','ButtonPushedFcn',@(~,~) refreshInputs(true)); b.Layout.Row=8; b.Layout.Column=2;

        progressiveBtn=uibutton(g,'push', ...
            'Text','Start Progressive Matching', ...
            'FontSize',15, ...
            'FontWeight','bold', ...
            'Enable','off', ...
            'ButtonPushedFcn',@(~,~) runProgressive());
        progressiveBtn.Layout.Row=9;
        progressiveBtn.Layout.Column=[2 3];

        finalizeBtn=uibutton(g,'push', ...
            'Text','Finalize Progressive Correspondences', ...
            'FontSize',15, ...
            'FontWeight','bold', ...
            'Enable','off', ...
            'ButtonPushedFcn',@(~,~) runFinalize());
        finalizeBtn.Layout.Row=10;
        finalizeBtn.Layout.Column=[2 3];

        analysisBtn=uibutton(g,'push', ...
            'Text','Run Scientific Analysis', ...
            'FontSize',15, ...
            'FontWeight','bold', ...
            'Enable','off', ...
            'ButtonPushedFcn',@(~,~) runAnalysis());
        analysisBtn.Layout.Row=11;
        analysisBtn.Layout.Column=[2 3];

        resultsBtn=uibutton(g,'push', ...
            'Text','View Results', ...
            'FontSize',15, ...
            'FontWeight','bold', ...
            'Enable','off', ...
            'ButtonPushedFcn',@(~,~) showResults());
        resultsBtn.Layout.Row=12;
        resultsBtn.Layout.Column=[2 3];

        statusBox=uitextarea(g,'Editable','off','Value',{'Checking project inputs...'});
        statusBox.Layout.Row=13;
        statusBox.Layout.Column=[1 3];

        refreshInputs(false);

        function importCSV(kind)
            [f,p]=uigetfile({'*.csv','CSV files (*.csv)'},['Import ' kind ' CSV']); if isequal(f,0), return; end
            src=fullfile(p,f);
            try
                T=readtable(src,'TextType','string');
                if strcmp(kind,'trusted'), validateTrusted(T,S.epoch1Info,S.epoch2Info); dst=fullfile(char(S.caseRoot),'input','trusted_correspondences.csv');
                else, validateSource(T,S.epoch1Info); dst=fullfile(char(S.caseRoot),'input','source_points.csv'); end
                copyIfDifferent(src,dst); refreshInputs(true);
            catch ME
                uialert(fig,ME.message,'CSV rejected');
            end
        end

        function refreshInputs(showAlert)
            lines=strings(0,1);
            tv=false;
            sv=false;

            tf=fullfile(char(S.caseRoot),'input','trusted_correspondences.csv');
            sf=fullfile(char(S.caseRoot),'input','source_points.csv');

            progressiveBtn.Enable='off';
            progressiveBtn.Text='Start Progressive Matching';

            finalizeBtn.Enable='off';
            finalizeBtn.Text='Finalize Progressive Correspondences';

            analysisBtn.Enable='off';
            analysisBtn.Text='Run Scientific Analysis';

            resultsBtn.Enable='off';
            resultsBtn.Text='View Results';

            try
                if isfile(tf)
                    T=readtable(tf,'TextType','string');
                    if height(T)>0
                        validateTrusted(T,S.epoch1Info,S.epoch2Info);
                        tv=true;
                        tStatus.Text=sprintf('%d initial trusted controls loaded',height(T));
                        tOpen.Enable='on';
                    end
                end
            catch ME
                tStatus.Text='Invalid trusted CSV';
                tOpen.Enable='on';
                lines(end+1)="Trusted CSV: "+string(ME.message); %#ok<AGROW>
            end

            try
                if isfile(sf)
                    T=readtable(sf,'TextType','string');
                    if height(T)>0
                        validateSource(T,S.epoch1Info);
                        sv=true;
                        sStatus.Text=sprintf('%d source points loaded',height(T));
                        sOpen.Enable='on';
                    end
                end
            catch ME
                sStatus.Text='Invalid source CSV';
                sOpen.Enable='on';
                lines(end+1)="Source CSV: "+string(ME.message); %#ok<AGROW>
            end

            if tv && sv
                Tt=readtable(tf,'TextType','string');
                Ts=readtable(sf,'TextType','string');

                trustedIDs=normalize_gui_point_ids(Tt.Point);
                sourceIDs=normalize_gui_point_ids(Ts.Point);

                common=intersect(trustedIDs,sourceIDs);

                if ~isempty(common)
                    sv=false;
                    lines(end+1)="Point IDs occur in both files: "+ ...
                        strjoin("P"+compose("%02d",common),", "); %#ok<AGROW>
                end
            end

            if tv && sv
                try
                    evalc('v1_prepare_case(char(S.caseName));');
                    lines(end+1)="PREPARE PASSED"; %#ok<AGROW>
                    lines(end+1)="MODE: progressive human-validated propagation."; %#ok<AGROW>

                    progRoot=fullfile( ...
                        char(S.caseRoot),'output','01_progressive_matching');

                    stateMat=fullfile(progRoot,'progressive_state.mat');
                    workingCSV=fullfile(progRoot,'working_trusted.csv');
                    sourceStatusCSV=fullfile(progRoot,'source_status.csv');

                    if ~isfolder(progRoot)
                        lines(end+1)=sprintf( ...
                            "READY - %d initial trusted controls, %d source points.", ...
                            height(Tt),height(Ts)); %#ok<AGROW>
                        lines(end+1)="NEXT STEP: start progressive matching."; %#ok<AGROW>

                        progressiveBtn.Text='Start Progressive Matching';
                        progressiveBtn.Enable='on';

                    elseif isfile(stateMat) && isfile(workingCSV) && isfile(sourceStatusCSV)

                        St=load(stateMat,'state');
                        ps=St.state;

                        W=readtable(workingCSV,'TextType','string');
                        SS=readtable(sourceStatusCSV,'TextType','string');

                        ss=string(SS.Status);

                        nAccepted=nnz(ss=="accepted");
                        nNoMatch=nnz(ss=="no_match");
                        nDeferred=nnz(ss=="deferred");
                        nRemaining=nnz(ss=="remaining");
                        nAwaiting=nnz(ss=="awaiting_review");

                        lines(end+1)=sprintf( ...
                            "PROGRESSIVE SESSION - iteration %d.", ...
                            double(ps.iteration)); %#ok<AGROW>

                        lines(end+1)=sprintf( ...
                            "Trusted: %d initial -> %d current | accepted new: %d.", ...
                            double(ps.initialTrustedCount),height(W),nAccepted); %#ok<AGROW>

                        lines(end+1)=sprintf( ...
                            "Sources: %d remaining | %d deferred | %d no match | %d awaiting review.", ...
                            nRemaining,nDeferred,nNoMatch,nAwaiting); %#ok<AGROW>

                        if string(ps.sessionStatus)=="complete"
                            lines(end+1)="PROGRESSIVE MATCHING COMPLETE."; %#ok<AGROW>

                            progressiveBtn.Text='Progressive Matching Complete';
                            progressiveBtn.Enable='off';

                            finalRoot=fullfile( ...
                                char(S.caseRoot),'output','04_finalized_correspondences');

                            finalCSV=fullfile(finalRoot,'final_correspondences.csv');
                            progressiveManifest=fullfile( ...
                                finalRoot,'progressive_finalization_manifest.mat');

                            if isfile(finalCSV) && isfile(progressiveManifest)

                                F=readtable(finalCSV,'TextType','string');

                                lines(end+1)=sprintf( ...
                                    "PROGRESSIVE FINALIZATION COMPLETE - %d authoritative correspondences.", ...
                                    height(F)); %#ok<AGROW>

                                finalizeBtn.Text='Progressive Finalization Complete';
                                finalizeBtn.Enable='off';

                                stage5Mat=fullfile( ...
                                    char(S.caseRoot),'output','05_field_qc','field_qc.mat');
                                stage6Mat=fullfile( ...
                                    char(S.caseRoot),'output','06_flow_aligned_plane','flow_aligned_plane.mat');
                                stage7Mat=fullfile( ...
                                    char(S.caseRoot),'output','07_strain_rate','strain_rate_analysis.mat');
                                stage8Mat=fullfile( ...
                                    char(S.caseRoot),'output','08_robustness','robustness_sensitivity.mat');

                                done=[isfile(stage5Mat),isfile(stage6Mat), ...
                                      isfile(stage7Mat),isfile(stage8Mat)];

                                if all(done)
                                    lines(end+1)="SCIENTIFIC ANALYSIS COMPLETE - Stages 5-8 available."; %#ok<AGROW>
                                    lines(end+1)="NEXT STEP: inspect progressive results."; %#ok<AGROW>

                                    analysisBtn.Text='Analysis Complete';
                                    analysisBtn.Enable='off';

                                    resultsBtn.Text='View Results';
                                    resultsBtn.Enable='on';

                                elseif any(done)
                                    lines(end+1)=sprintf( ...
                                        "SCIENTIFIC ANALYSIS IN PROGRESS - %d/4 stages complete.", ...
                                        nnz(done)); %#ok<AGROW>
                                    lines(end+1)="NEXT STEP: resume scientific analysis."; %#ok<AGROW>

                                    analysisBtn.Text='Resume Scientific Analysis';
                                    analysisBtn.Enable='on';

                                else
                                    lines(end+1)="NEXT STEP: run scientific analysis on progressive field."; %#ok<AGROW>

                                    analysisBtn.Text='Run Scientific Analysis';
                                    analysisBtn.Enable='on';
                                end

                            else
                                lines(end+1)="NEXT STEP: progressive finalization."; %#ok<AGROW>

                                finalizeBtn.Text='Finalize Progressive Correspondences';
                                finalizeBtn.Enable='on';
                            end

                        elseif string(ps.currentPointStatus)=="awaiting_review"
                            lines(end+1)=sprintf( ...
                                "P%02d is awaiting human review.", ...
                                double(ps.currentPoint)); %#ok<AGROW>
                            lines(end+1)="NEXT STEP: resume progressive matching."; %#ok<AGROW>

                            progressiveBtn.Text='Resume Progressive Matching';
                            progressiveBtn.Enable='on';

                        else
                            lines(end+1)="Session is safely paused/ready."; %#ok<AGROW>
                            lines(end+1)="NEXT STEP: resume progressive matching."; %#ok<AGROW>

                            progressiveBtn.Text='Resume Progressive Matching';
                            progressiveBtn.Enable='on';
                        end

                    else
                        lines(end+1)="PROGRESSIVE SESSION ERROR: state files are incomplete."; %#ok<AGROW>
                        progressiveBtn.Text='Progressive State Error';
                        progressiveBtn.Enable='off';
                    end

                catch ME
                    lines(end+1)="PREPARE / PROGRESSIVE STATE FAILED: "+string(ME.message); %#ok<AGROW>

                    if showAlert
                        uialert(fig,ME.message,'Project validation failed');
                    end
                end
            else
                if ~tv
                    lines(end+1)="Import a valid trusted-correspondence CSV."; %#ok<AGROW>
                end
                if ~sv
                    lines(end+1)="Import a valid source-point CSV."; %#ok<AGROW>
                end
            end

            statusBox.Value=cellstr(lines);
        end

        function runProgressive()
            progRoot=fullfile( ...
                char(S.caseRoot),'output','01_progressive_matching');

            if isfolder(progRoot)
                actionText='Resume';
                confirmText=sprintf([ ...
                    'Resume progressive matching for %s?\n\n' ...
                    'The saved working trusted set and source-state will be used.'], ...
                    char(S.caseName));
            else
                actionText='Start';
                confirmText=sprintf([ ...
                    'Start progressive matching for %s?\n\n' ...
                    'Only human-accepted source correspondences will be added ' ...
                    'to the working trusted set.'], ...
                    char(S.caseName));
            end

            choice=uiconfirm(fig, ...
                confirmText, ...
                'Progressive Matching', ...
                'Options',{actionText,'Cancel'}, ...
                'DefaultOption',1, ...
                'CancelOption',2);

            if ~strcmp(choice,actionText)
                return
            end

            progressiveBtn.Enable='off';
            statusBox.Value=[statusBox.Value; {'PROGRESSIVE MATCHING SESSION ACTIVE...'}];
            drawnow;

            try
                summary=v1_progressive_run_session(char(S.caseName));

                refreshInputs(false);

                if string(summary.sessionStatus)=="complete"
                    uialert(fig, ...
                        sprintf([ ...
                            'Progressive matching is complete.\n\n' ...
                            'Initial trusted: %d\n' ...
                            'Accepted new: %d\n' ...
                            'No match: %d\n' ...
                            'Current trusted: %d\n\n' ...
                            'The next workflow step is progressive finalization.'], ...
                            summary.initialTrusted, ...
                            summary.acceptedNew, ...
                            summary.noMatch, ...
                            summary.currentTrusted), ...
                        'Progressive matching complete', ...
                        'Icon','success');
                else
                    uialert(fig, ...
                        sprintf([ ...
                            'Progressive session paused safely.\n\n' ...
                            'Current trusted: %d\n' ...
                            'Accepted new: %d\n' ...
                            'Remaining: %d\n' ...
                            'Deferred: %d'], ...
                            summary.currentTrusted, ...
                            summary.acceptedNew, ...
                            summary.remaining, ...
                            summary.deferred), ...
                        'Progressive matching paused', ...
                        'Icon','info');
                end

            catch ME
                refreshInputs(false);

                uialert(fig, ...
                    ME.message, ...
                    'Progressive matching failed');
            end
        end

        function runFinalize()
            progRoot=fullfile( ...
                char(S.caseRoot),'output','01_progressive_matching');

            stateMat=fullfile(progRoot,'progressive_state.mat');
            sourceStatusCSV=fullfile(progRoot,'source_status.csv');

            assert(isfile(stateMat) && isfile(sourceStatusCSV), ...
                'Progressive session state is missing.');

            St=load(stateMat,'state');
            ps=St.state;

            assert(string(ps.sessionStatus)=="complete", ...
                'Progressive matching must be complete before finalization.');

            SS=readtable(sourceStatusCSV,'TextType','string');
            st=string(SS.Status);

            assert(all(st=="accepted" | st=="no_match"), ...
                'All source points must be accepted or NO MATCH before finalization.');

            nAccepted=nnz(st=="accepted");
            nNoMatch=nnz(st=="no_match");

            finalRoot=fullfile( ...
                char(S.caseRoot),'output','04_finalized_correspondences');

            finalCSV=fullfile(finalRoot,'final_correspondences.csv');
            manifestMat=fullfile( ...
                finalRoot,'progressive_finalization_manifest.mat');

            if isfile(finalCSV) && isfile(manifestMat)
                refreshInputs(false);
                uialert(fig, ...
                    'The progressive authoritative correspondence field already exists.', ...
                    'Already finalized', ...
                    'Icon','info');
                return
            end

            choice=uiconfirm(fig, ...
                sprintf([ ...
                    'Finalize the progressive correspondence field for %s?\n\n' ...
                    'Initial trusted: %d\n' ...
                    'Human-accepted new: %d\n' ...
                    'NO MATCH excluded: %d\n\n' ...
                    'Any pre-existing Stage 4-8 outputs in this case ' ...
                    'will be archived before the finalized progressive field is written.'], ...
                    char(S.caseName), ...
                    double(ps.initialTrustedCount), ...
                    nAccepted,nNoMatch), ...
                'Progressive Finalization', ...
                'Options',{'Finalize','Cancel'}, ...
                'DefaultOption',1, ...
                'CancelOption',2);

            if ~strcmp(choice,'Finalize')
                return
            end

            finalizeBtn.Enable='off';
            statusBox.Value=[statusBox.Value; {'PROGRESSIVE FINALIZATION STARTED...'}];
            drawnow;

            dlg=uiprogressdlg(fig, ...
                'Title','Progressive Finalization', ...
                'Message','Verifying progressive state and isolating old downstream outputs...', ...
                'Indeterminate','on', ...
                'Cancelable','off');

            cleanupDlg=onCleanup(@() close_progress(dlg)); %#ok<NASGU>

            try
                summary=v1_progressive_finalize(char(S.caseName));

                assert(isfile(summary.finalCSV), ...
                    'Progressive finalization did not create final_correspondences.csv.');

                close_progress(dlg);
                clear cleanupDlg;

                refreshInputs(false);

                if strlength(summary.archiveRoot)>0
                    archiveText=sprintf( ...
                        '\n\nPre-existing Stage 4-8 outputs were archived at:\n%s', ...
                        char(summary.archiveRoot));
                else
                    archiveText='';
                end

                uialert(fig, ...
                    sprintf([ ...
                        'Progressive finalization complete.\n\n' ...
                        '%d initial trusted + %d accepted new = %d authoritative correspondences.\n' ...
                        '%d NO MATCH points excluded.%s\n\n' ...
                        'The next workflow stage is scientific analysis.'], ...
                        summary.initialTrusted, ...
                        summary.acceptedNew, ...
                        summary.finalCount, ...
                        summary.noMatch, ...
                        archiveText), ...
                    'Progressive finalization complete', ...
                    'Icon','success');

            catch ME
                close_progress(dlg);
                clear cleanupDlg;

                refreshInputs(false);

                uialert(fig, ...
                    ME.message, ...
                    'Progressive finalization failed');
            end
        end

        function runAnalysis()
            finalCSV=fullfile( ...
                char(S.caseRoot),'output','04_finalized_correspondences', ...
                'final_correspondences.csv');

            assert(isfile(finalCSV), ...
                'Finalized correspondences are required before scientific analysis.');

            progressiveManifest=fullfile( ...
                char(S.caseRoot),'output','04_finalized_correspondences', ...
                'progressive_finalization_manifest.mat');

            assert(isfile(progressiveManifest), ...
                ['The active finalized field is not marked as progressive. ' ...
                 'Run Progressive Finalization first.']);

            % V1.2 compatibility guard: the first progressive finalizer
            % wrote only the five coordinate columns, while the frozen
            % scientific backend expects the established eight-column
            % Stage-4 interface. Repair metadata only; coordinates remain
            % unchanged.
            schemaInfo=v1_progressive_ensure_final_schema(char(S.caseName));

            if schemaInfo.repaired
                statusBox.Value=[statusBox.Value; ...
                    {'Progressive final CSV upgraded to Stage-5-compatible schema.'}];
                drawnow;
            end

            F=readtable(finalCSV,'TextType','string');

            choice=uiconfirm(fig, ...
                sprintf(['Run the scientific analysis for %s?\n\n' ...
                         'Authoritative correspondences: %d\n\n' ...
                         'This runs:\n' ...
                         'Stage 5 - field QC and velocity field\n' ...
                         'Stage 6 - flow-aligned velocity plane\n' ...
                         'Stage 7 - strain-rate analysis\n' ...
                         'Stage 8 - robustness / sensitivity'], ...
                         char(S.caseName),height(F)), ...
                'Run Scientific Analysis', ...
                'Options',{'Run Analysis','Cancel'}, ...
                'DefaultOption',1, ...
                'CancelOption',2);

            if ~strcmp(choice,'Run Analysis')
                return
            end

            stage5Mat=fullfile( ...
                char(S.caseRoot),'output','05_field_qc','field_qc.mat');
            stage6Mat=fullfile( ...
                char(S.caseRoot),'output','06_flow_aligned_plane','flow_aligned_plane.mat');
            stage7Mat=fullfile( ...
                char(S.caseRoot),'output','07_strain_rate','strain_rate_analysis.mat');
            stage8Mat=fullfile( ...
                char(S.caseRoot),'output','08_robustness','robustness_sensitivity.mat');

            analysisBtn.Enable='off';
            statusBox.Value=[statusBox.Value; {'SCIENTIFIC ANALYSIS STARTED...'}];
            drawnow;

            dlg=uiprogressdlg(fig, ...
                'Title','Scientific Analysis', ...
                'Message','Preparing analysis...', ...
                'Indeterminate','on', ...
                'Cancelable','off');

            cleanupDlg=onCleanup(@() close_progress(dlg)); %#ok<NASGU>

            try
                if ~isfile(stage5Mat)
                    dlg.Message='Stage 5/8 - field QC and velocity field...';
                    drawnow;
                    v1_stage5_field_qc(char(S.caseName));
                end

                if ~isfile(stage6Mat)
                    dlg.Message='Stage 6/8 - flow-aligned velocity plane...';
                    drawnow;
                    v1_stage6_flow_plane(char(S.caseName));
                end

                if ~isfile(stage7Mat)
                    dlg.Message='Stage 7/8 - strain-rate analysis (bootstrap may take time)...';
                    drawnow;
                    v1_stage7_strain_rate(char(S.caseName));
                end

                if ~isfile(stage8Mat)
                    dlg.Message='Stage 8/8 - robustness / sensitivity (Monte Carlo may take time)...';
                    drawnow;
                    v1_stage8_robustness(char(S.caseName));
                end

                assert(isfile(stage5Mat) && isfile(stage6Mat) && ...
                       isfile(stage7Mat) && isfile(stage8Mat), ...
                    'Scientific analysis did not produce all expected Stage 5-8 outputs.');

                close_progress(dlg);
                clear cleanupDlg;

                refreshInputs(false);

                uialert(fig, ...
                    ['Scientific analysis is complete.' newline newline ...
                     'Stage 5: field QC / velocity field' newline ...
                     'Stage 6: flow-aligned velocity plane' newline ...
                     'Stage 7: strain-rate analysis' newline ...
                     'Stage 8: robustness / sensitivity' newline newline ...
                     'The next step is to inspect and summarize the scientific results.'], ...
                    'Analysis complete', ...
                    'Icon','success');

            catch ME
                close_progress(dlg);
                clear cleanupDlg;

                refreshInputs(false);

                uialert(fig, ...
                    ME.message, ...
                    'Scientific analysis failed');
            end
        end

        function close_progress(dlg)
            if ~isempty(dlg) && isvalid(dlg)
                close(dlg);
            end
        end

        function openCSV(kind)
            if strcmp(kind,'trusted'), p=fullfile(char(S.caseRoot),'input','trusted_correspondences.csv'); else, p=fullfile(char(S.caseRoot),'input','source_points.csv'); end
            if isfile(p), open(p); end
        end
    end

    function ids=normalize_gui_point_ids(v)
        if isnumeric(v)
            ids=double(v(:));
        else
            s=upper(strtrim(string(v)));
            s=regexprep(s,'^P','');
            ids=str2double(s(:));
        end
        assert(all(isfinite(ids)), ...
            'Point IDs must be numeric or P-prefixed numeric labels.');
    end

    function addRowLabel(g,row,textValue)
        a=uilabel(g,'Text',textValue,'FontWeight','bold','HorizontalAlignment','right'); a.Layout.Row=row; a.Layout.Column=1;
    end

    function I=inspectRaster(path)
        assert(isfile(path),'Raster not found: %s',path);
        info=georasterinfo(path); crs=info.CoordinateReferenceSystem;
        assert(~isempty(crs),'Raster has no readable CRS.');
        assert(isa(crs,'projcrs'),'Raster must use a projected CRS.');
        assert(contains(lower(string(crs.LengthUnit)),'met'),'Raster CRS must use metres.');
        R=info.RasterReference;
        I=struct('Info',info,'CRS',crs,'Ref',R,'File',string(path));
    end

    function [epsgText,overlapText]=validatePair(A,B)
        assert(isequal(A.CRS,B.CRS),'Earlier and later rasters use different CRS definitions.');
        epsg=inferEPSG(A.CRS); assert(isequal(A.CRS,projcrs(epsg)),'Raster CRS did not verify against inferred EPSG:%d.',epsg);
        R1=A.Ref; R2=B.Ref;
        xmin=max(R1.XWorldLimits(1),R2.XWorldLimits(1)); xmax=min(R1.XWorldLimits(2),R2.XWorldLimits(2));
        ymin=max(R1.YWorldLimits(1),R2.YWorldLimits(1)); ymax=min(R1.YWorldLimits(2),R2.YWorldLimits(2));
        assert(xmax>xmin && ymax>ymin,'The two rasters have no common overlap.');
        epsgText=sprintf('EPSG:%d',epsg);
        overlapText=sprintf('Common overlap: X %.3f-%.3f m | Y %.3f-%.3f m',xmin,xmax,ymin,ymax);
    end

    function epsg=inferEPSG(crs)
        name=char(string(crs.Name));
        tok=regexp(name,'WGS\s*84\s*/\s*UTM\s*zone\s*(\d{1,2})([NS])','tokens','once','ignorecase');
        if ~isempty(tok)
            z=str2double(tok{1}); h=upper(tok{2});
            if strcmp(h,'N'), epsg=32600+z; else, epsg=32700+z; end
            return
        end
        for z=1:60
            if isequal(crs,projcrs(32600+z)), epsg=32600+z; return; end
            if isequal(crs,projcrs(32700+z)), epsg=32700+z; return; end
        end
        error('Could not auto-detect EPSG for CRS "%s". v1.2.1-beta currently auto-recognizes WGS 84 UTM projected CRS.',name);
    end

    function line=rasterLine(label,I)
        R=I.Ref; line=sprintf('%s: %d x %d | %.5f x %.5f m/px | %s',char(label),R.RasterSize(1),R.RasterSize(2),R.CellExtentInWorldX,R.CellExtentInWorldY,char(string(I.CRS.Name)));
    end

    function patchConfig(file,caseName,r1,r2,d1,d2,epsgText)
        txt=fileread(file);
        % Store raster paths with forward slashes. MATLAB on Windows
        % accepts them and this avoids backslash escaping issues in
        % generated case_config.m files.
        r1cfg=string(strrep(char(r1),'\','/'));
        r2cfg=string(strrep(char(r2),'\','/'));

        txt=replaceAssign(txt,'cfg.case_name',caseName);
        txt=replaceAssign(txt,'cfg.epoch1.name',string(datestr(d1,'yyyy-mm-dd')));
        txt=replaceAssign(txt,'cfg.epoch1.raster',r1cfg);
        txt=replaceAssign(txt,'cfg.epoch2.name',string(datestr(d2,'yyyy-mm-dd')));
        txt=replaceAssign(txt,'cfg.epoch2.raster',r2cfg);
        txt=replaceAssign(txt,'cfg.expected_crs',epsgText);
        txt=sprintf('%s\n\n%% Acquisition dates written by V1 GUI.\n%s\n%s\n',strtrim(txt),assignLine('cfg.epoch1.date',string(datestr(d1,'yyyy-mm-dd'))),assignLine('cfg.epoch2.date',string(datestr(d2,'yyyy-mm-dd'))));
        writeText(file,txt);
    end

    function txt=replaceAssign(txt,varName,value)
        % Do NOT use regexprep with a Windows path as the replacement
        % string. Backslashes in replacement text are interpreted by the
        % regexp engine and can be lost. Locate the assignment with regexp,
        % then splice the literal replacement text into the file.
        pat=[regexptranslate('escape',varName) '\s*=\s*''[^'']*''\s*;'];
        [i1,i2]=regexp(txt,pat,'start','end','once');
        assert(~isempty(i1),'Could not find %s in case_config.m.',varName);
        replacement=assignLine(varName,value);
        txt=[txt(1:i1-1) replacement txt(i2+1:end)];
    end

    function s=assignLine(varName,value)
        v=strrep(char(string(value)),'''',''''''); s=sprintf('%s = ''%s'';',varName,v);
    end

    function cfgOut=readConfig(file)
        % V1 is a function with nested callbacks, so MATLAB uses a static
        % workspace. Calling CLEAR and then RUN here makes case_config.m
        % try to introduce cfg dynamically, which raises:
        %   "Attempt to add 'cfg' to a static workspace."
        %
        % Predeclare cfg instead. The config script then assigns into an
        % already-known variable in this workspace.
        cfg = struct;
        run(file);
        assert(isstruct(cfg) && ~isempty(fieldnames(cfg)), ...
            'case_config.m did not create a valid cfg struct.');
        cfgOut = cfg;
    end

    function validateTrusted(T,A,B)
        req={'Point','Epoch1_X','Epoch1_Y','Epoch2_X','Epoch2_Y'};
        assert(all(ismember(req,T.Properties.VariableNames)),'Trusted CSV must contain Point, Epoch1_X, Epoch1_Y, Epoch2_X, Epoch2_Y.');
        assert(height(T)>=3,'At least 3 trusted correspondences are required.');
        ids=string(T.Point); assert(all(strlength(ids)>0),'Trusted CSV has blank Point IDs.'); assert(numel(unique(ids))==height(T),'Trusted Point IDs are not unique.');
        x1=numcol(T,'Epoch1_X'); y1=numcol(T,'Epoch1_Y'); x2=numcol(T,'Epoch2_X'); y2=numcol(T,'Epoch2_Y');
        assert(all(isfinite([x1;y1;x2;y2])),'Trusted CSV contains non-finite coordinates.');
        inside(x1,y1,A.Ref,ids,'trusted epoch-1'); inside(x2,y2,B.Ref,ids,'trusted epoch-2');
    end

    function validateSource(T,A)
        req={'Point','Epoch1_X','Epoch1_Y'};
        assert(all(ismember(req,T.Properties.VariableNames)),'Source CSV must contain Point, Epoch1_X, Epoch1_Y.');
        assert(height(T)>=1,'Source CSV contains no points.');
        ids=string(T.Point); assert(all(strlength(ids)>0),'Source CSV has blank Point IDs.'); assert(numel(unique(ids))==height(T),'Source Point IDs are not unique.');
        x=numcol(T,'Epoch1_X'); y=numcol(T,'Epoch1_Y'); assert(all(isfinite([x;y])),'Source CSV contains non-finite coordinates.'); inside(x,y,A.Ref,ids,'source epoch-1');
    end

    function x=numcol(T,name)
        v=T.(name); if isnumeric(v), x=double(v); else, x=str2double(string(v)); end; x=x(:);
    end

    function inside(x,y,R,ids,label)
        ok=x>=R.XWorldLimits(1) & x<=R.XWorldLimits(2) & y>=R.YWorldLimits(1) & y<=R.YWorldLimits(2);
        if ~all(ok)
            bad=ids(~ok); n=min(8,numel(bad)); txt=strjoin(bad(1:n),', '); if numel(bad)>n, txt=txt+', ...'; end
            error('%s coordinates outside raster extent for Point ID(s): %s',label,txt);
        end
    end

    function copyIfDifferent(src,dst)
        if strcmpi(char(java.io.File(src).getCanonicalPath()),char(java.io.File(dst).getCanonicalPath())), return; end
        [ok,msg]=copyfile(src,dst,'f'); assert(ok,'Could not copy CSV: %s',msg);
    end

    function line=metadataLine()
        mf=fullfile(char(S.caseRoot),'input','case_metadata.csv'); it='interval unavailable';
        try
            M=readtable(mf); if height(M)==1 && isfinite(M.dtDays(1)) && isfinite(M.dtYears(1)), it=sprintf('%.0f days = %.6f yr',M.dtDays(1),M.dtYears(1)); end
        catch
        end
        line=sprintf('%s | %s',char(S.expectedCRS),it);
    end

    function writeText(file,txt)
        fid=fopen(file,'w'); assert(fid~=-1,'Could not write %s',file); c=onCleanup(@() fclose(fid)); %#ok<NASGU>
        fprintf(fid,'%s',txt);
    end
end
