function epochGroup = ImportPldapsPDS(container,...
        animalSource,...
        protocol,...
        interTrialProtocol,...
        pdsfile,...
        timezone,...
        ntrials)
    % Import PL-DA-PS PDS structural data into an Ovation Experiment
    %
    %    epochGroup = ImportPladpsPDS(experiment, animal, pdsfile, timezone)
    %      context: context with which to find the experiment
    %
    %      experiment: ovation.Experiment or ovation.EpochGroup object. A
    %      new EpochGroup for this PDS data will be added to the given
    %      experiment.
    %
    %      animal: ovation.Source. The Source for the newly added
    %      EpochGroup.
    %
    %      pdsfile: path to .PDS file
    %
    %      timezone: name of the time zone (e.g. 'America/New_York') where
    %      the experiment was performed
    
    % TODO OTHER PARAMETERS DOCS
    
    import ovation.*;
    
    narginchk(6,7);
    if(nargin < 7)
        ntrials = [];
    end
    
    
    pdsFileStruct = load('-mat', pdsfile);
    pds = pdsFileStruct.PDS;
    displayVariables = pdsFileStruct.dv;
    
    [~, trialFunction, ~] = fileparts(pdsfile);
    
    
    % External devices
    % TODO more devices?
    devices.psychToolbox.version = '3.0.8';
    devices.psychToolbox.matlab_version = 'R2009a 32bit';
    devices.datapixx.manufacturer = 'VPixx Technologies';
    devices.monitor.model = 'LH 1080p';
    devices.monitor.manufacturer = 'LG';
    devices.monitor.resolution.width = 1920;
    devices.monitor.resolution.height = 1080;
    devices.eye_tracker.model = 'Eye Trac 6000';
    devices.eye_tracker.manufacturer = 'ASL';
    devices.eye_tracker.timer = 'Microsoft Windows';
    
    if(java.lang.String(class(container)).endsWith('Experiment'))
        if(isempty(container.getEquipmentSetup()))
            container.setEquipmentSetupFromMap(struct2map(devices));
        end
    elseif(isempty(container.getExperiment().getEquipmentSetup()))
        container.getExperiment().setEquipmentSetupFromMap(struct2map(devices));
    end
    
    % generate the start and end times for each epoch, from the unique_number and
    % timezone
    
    if(ischar(timezone))
        timezone = org.joda.time.DateTimeZone.forID(timezone);
    end
    
    firstEpochIdx = pds.datapixxstarttime == min(pds.datapixxstarttime);
    firstEpochStart = uniqueNumberToDateTime(pds.unique_number(firstEpochIdx,:),...
        timezone.getID());
    
    %% Insert one epochGroup per PDS file
    epochGroup = container.insertEpochGroup(trialFunction,...
        firstEpochStart,...
        protocol,... % No EpochGroup-level protocol
        [],... % No EpochGroup-level protocol parameters
        []... % No EpochGroup-level device parameters
        );
    
    % Convert DV paired cells to a struct
    displayVariables.bits = cell2struct(displayVariables.bits(:,2)',...
        num2cell(strcat('bit_', num2str(cell2mat(displayVariables.bits(:,1)))), 2)',...
        2);
    
    insertEpochs(epochGroup,...
        protocol,...
        animalSource,...
        interTrialProtocol,...
        pds,...
        displayVariables,...
        ntrials);
    
end

function insertEpochs(epochGroup, protocol, animalSource, interTrialProtocol, pds, parameters, ntrials)
    import ovation.*;
    
    if(isempty(ntrials))
        ntrials = size(pds.unique_number,1);
    end
    
    disp('Importing Epochs...');
    previousEpoch = [];
    tic;
    for n=1:ntrials
        nTrialProgress = 1;
        if(mod(n,nTrialProgress) == 0 && n > 1)
            elapsedTime = toc;
            
            disp(['    ' num2str(n) ' of ' num2str(ntrials) ' (' num2str(elapsedTime/nTrialProgress) ' s/epoch)...']);
            tic();
        end
        
        
        dataPixxZero = min(pds.datapixxstarttime);
        dataPixxStart = pds.datapixxstarttime(n) - dataPixxZero;
        dataPixxEnd = pds.datapixxstoptime(n) - dataPixxZero;
        
        
        
        protocol_parameters = parameters.params;
        protocol_parameters.target1_XY_deg_visual_angle = pds.targ1XY(n);
        if(isfield(pds, 'targ2XY'))
            protocol_parameters.target2_XY_deg_visual_angle = pds.targ2XY(n);
        end
        if(isfield(pds, 'coherence'))
            protocol_parameters.coherence = pds.coherence(n);
        end
        if(isfield(pds, 'fp2XY'))
            protocol_parameters.fp2_XY_deg_visual_angle = pds.fp2XY(n);
        end
        if(isfield(pds, 'inRF'))
            protocol_parameters.inReceptiveField = pds.inRF(n);
        end
        
        deviceParameters = rmfield(parameters, 'params');
        sources = java.util.HashMap();
        sources.put('monkey', animalSource);
        
        
        if(n > 1) % Assumes first Epoch is not an inter-trial
            if(dataPixxStart > (pds.datapixxstoptime(n-1) - dataPixxZero))
                % Inserting inter-trial Epoch
                interEpochDataPixxStart = pds.datapixxstoptime(n-1) - dataPixxZero;
                interEpochDataPixxStop = dataPixxStart;
                
                interEpoch = epochGroup.insertEpoch(sources,...
                    [],... % No output sources
                    epochGroup.getStart().plusMillis(dataPixxStart * 1000),...
                    epochGroup.getStart().plusMillis(dataPixxEnd * 1000),...
                    interTrialProtocol,...
                    struct2map(protocol_parameters),...
                    struct2map(deviceParameters)); %TODO deviceParameters do not match EquipmentSetup
                
                
                interEpoch.addProperty('dataPixxStart_seconds', interEpochDataPixxStart);
                interEpoch.addProperty('dataPixxStop_seconds', interEpochDataPixxStop);
                
                if(epoch.getProtocolParameters().size() == 0)
                    disp('Crap!');
                end
                %if(~isempty(previousEpoch))
                %    interEpoch.setPreviousEpoch(previousEpoch);
                %end
                
                previousEpoch = interEpoch;
            end
        end
        
        
        epoch = epochGroup.insertEpoch(sources,...
            [],... % No output sources
            epochGroup.getStart().plusMillis(dataPixxStart * 1000),...
            epochGroup.getStart().plusMillis(dataPixxEnd * 1000),...
            protocol,...
            struct2map(protocol_parameters),...
            struct2map(deviceParameters)); %TODO deviceParameters do not match EquipmentSetup
        
        epoch.addProperty('dataPixxStart_seconds', pds.datapixxstarttime(n));
        epoch.addProperty('dataPixxStop_seconds', pds.datapixxstoptime(n));
        epoch.addProperty('uniqueNumber', int32(pds.unique_number(n,:)));
        epoch.addProperty('uniqueNumberString', num2str(pds.unique_number(n,:)));
        epoch.addProperty('trialNumber', pds.trialnumber(n));
        
        epoch.addProperty('goodTrial', pds.goodtrial(n)); %TODO is this a measurement?
        
        if(epoch.getProtocolParameters().size() == 0)
                    disp('Crap!');
        end
                
        % Next/Prev Epoch not supported in Ovation 2.0 yet
        if(~isempty(previousEpoch))
            epoch.addProperty('previousEpoch', previousEpoch.getURI());
            previousEpoch.addProperty('nextEpoch', epoch.getURI());
        end
        previousEpoch = epoch;
        
        insertEyePositionMeasurement(epoch, 'monkey', pds.eyepos{n}, protocol);
        
        
        %TODO make these a CSV
        % These are more like DerivedResponses...
        if(isfield(pds, 'chooseRF'))
            epoch.addProperty('chooseRF', pds.chooseRF(n));
        end
        if(isfield(pds, 'timeOfChoice'))
            epoch.addProperty('timeOfChoice', pds.timechoice(n));
        end
        if(isfield(pds, 'timeOfReward'))
            epoch.addProperty('timeOfReward', pds.timereward(n));
        end
        if(isfield(pds, 'timeBrokeFixation'))
            epoch.addProperty('timeBrokeFixation', pds.timebrokefix(n));
        end
        if(isfield(pds, 'correct'))
            if(pds.correct(n))
                epoch.addTag('correct');
            end
        end
        
        addTimelineAnnotations(epoch, pds, n);
        
    end
end

function addTimelineAnnotations(epoch, pds, n)
    
    if(isnan(pds.fp1off(n)))
        fp1offTime = epoch.getEnd();
    else
        fp1offTime = epoch.getEnd().plusSeconds(pds.fp1off(n));
    end
    % Add timeline annotations for trial structure events.
    % NaN indicates a missing value. For non-point envents (e.g.
    % fixationPoint1), with a missing end, we use the Epoch endTime as
    % the annotation end.
    
    epoch.addTimelineAnnotation('fixation point 1 on',...
        'fixationPoint1',...
        epoch.getStart().plusSeconds(pds.fp1on(n)),...
        fp1offTime);
    epoch.addTimelineAnnotation('fixation point 1 entered',...
        'fixationPoint1',...
        epoch.getStart().plusSeconds(pds.fp1entered(n)));
    
    if(pds.timebrokefix(n) > 0)
        epoch.addTimelineAnnotation('time broke fixation',...
            'fixation',...
            epoch.getStart().plusSeconds(pds.timebrokefix(n)));
    end
    
    
    epoch.addTimelineAnnotation('fixation point 2 off',...
        'fixationPoint2',...
        epoch.getStart().plusSeconds(pds.fp2off(n)));
    
    if(isnan(pds.targoff(n)))
        epoch.addTimelineAnnotation('target on',...
            'target',...
            epoch.getStart().plusSeconds(pds.targon(n)),...
            epoch.getEnd());
    else
        epoch.addTimelineAnnotation('target on',...
            'target',...
            epoch.getStart().plusSeconds(pds.targon(n)),...
            epoch.getStart().plusSeconds(pds.targoff(n)));
    end
    if(isfield(pds, 'dotson') && ~isnan(pds.dotson(n)))
        if(isnan(pds.dotsoff(n)))
            epoch.addTimelineAnnotation('dots on',...
                'dots',...
                epoch.getStart().plusSeconds(pds.dotson(n)),...
                epoch.getEnd());
        else
            epoch.addTimelineAnnotation('dots on',...
                'dots',...
                epoch.getStart().plusSeconds(pds.dotson(n)),...
                epoch.getStart().plusSeconds(pds.dotsoff(n)));
        end
    end
    if(isfield(pds, 'timechoice') && ~isnan(pds.timechoice(n)))
        epoch.addTimelineAnnotation('time of choice',...
            'choice',...
            epoch.getStart().plusSeconds(pds.timechoice(n)));
    end
    if(isfield(pds, 'timereward') && ~isnan(pds.timereward(n)))
        epoch.addTimelineAnnotation('time of reward',...
            'reward',...
            epoch.getStart().plusSeconds(pds.timereward(n)));
    end
end

function insertEyePositionMeasurement(epoch, sourceName, eye_position_data, protocol)
    import ovation.*;
    import us.physion.ovation.values.NumericData;
    
    
    % eye_position_data(:,3) are sample times in seconds. We estimate a
    % single sample rate for eye position data by taking the reciprocal of
    % the median inter-sample difference.
    sampling_rate = 1 / median(diff(eye_position_data(:,3)));
    
    
    % NOTE 
    data = NumericData();
    
    data.addData('position_x',...
        eye_position_data(:,1)',...
        'Degrees of visual angle',...
        sampling_rate,...
        'Hz');
    
    data.addData('position_y',...
        eye_position_data(:,2)',...
        'Degrees of visual angle',...
        sampling_rate,...
        'Hz');
    
    data.addData('time',...
        eye_position_data(:,3)',...
        's',...
        1,...
        '');
    
    
    m = epoch.insertNumericMeasurement('Eye position',...
        array2set({sourceName}),...
        array2set({'eye_tracker'}),...
        data);
    
    inputData = java.util.HashMap();
    inputData.put('Eye position', m);
    
    state = epoch.addAnalysisRecord('State measurements',...
        inputData,...
        protocol,...
        struct2map(struct())... % TODO parameters
        );
    
    state.addNumericOutput('eye state',...
        NumericData().addData('state', eye_position_data(:,4)', '', sampling_rate, 'Hz'));
    
    % Ditto for columns 5, and 6
    % Units? Labels? ...
    
end
