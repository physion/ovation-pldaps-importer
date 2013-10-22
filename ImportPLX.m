function ImportPLX(epochGroup, plxFile, bits, plxRawFile, expFile, protocol, varargin)
    % Import Plexon data into an existing PL-DA-PS PDS EpochGroup
    %
    %    ImportPLX(epochGroup, plxFile, plxRawFile, expFile, protocol)
    %
    %      epochGroup: ovation.EpochGroup containing Epochs matching Plexon
    %      data.
    %
    %      plxFile: Path to a Matlab .mat file produced by plx2mat from a Plexon .plx
    %      file.
    %
    %      bits: bits field from the DV structure. Defines mapping from
    %      digital bit to event name.
    %
    %      plxRawFile: Path to .plx file from which plxFile was generated.
    %    
    %      expFile
    %
    %      prtocol: us.physion.ovation.domain.Protocol
    
    narginchk(5, 6);
    
    import ovation.*
    
    plxStruct = load('-mat', plxFile);
    plx = plxStruct.plx;
    
    expModificationDate = org.joda.time.DateTime(...
        java.io.File(plxRawFile).lastModified());
    
    drSuffix = [num2str(expModificationDate.getYear()) '-' ...
        num2str(expModificationDate.getMonthOfYear()) '-'...
        num2str(expModificationDate.getDayOfMonth())];
    
    lines = ovation.util.read_lines(expFile);
    expTxt = lines{1};
    for i = 2:length(lines)
        expTxt = sprintf('%s\n%s', expTxt, lines{i});
    end
    analysisParameters.expFileContents = expTxt;
    
    analysisParameters = struct2map(analysisParameters);
    
    disp('Calculating PLX-PDS unique number mapping...');
    epochCache.uniqueNumber = java.util.HashMap();
    epochCache.truncatedUniqueNumber = java.util.HashMap();
    epochs = asarray(epochGroup.getEpochs());
    for i = 1:length(epochs)
        if(mod(i,5) == 0)
            disp(['    Epoch ' num2str(i) ' of ' num2str(length(epochs))]);
        end
        
        epoch = epochs(i);
        epochUniqueNumber = epoch.getUserProperty(epoch.getOwner(), 'uniqueNumber');
        if(~isempty(epochUniqueNumber))
            uNum = zeros(1, epochUniqueNumber.size());
            for j = 1:length(uNum)
                uNum(j) = epochUniqueNumber.get(j-1);
            end
            
            epochCache.uniqueNumber.put(num2str(uNum), epoch);
            epochCache.truncatedUniqueNumber.put(num2str(mod(uNum,256)),...
                epoch);
        end
    end
    
    % Create a bit => event name map
    TRIAL_BOUNDARY_BIT = 7;
    bitsMap = java.util.HashMap();
    for i = 1:size(bits,1)
        if(i == TRIAL_BOUNDARY_BIT)
            continue;
        end
        bitsMap.put(bits{i,1}, bits{i,2});
    end
    
    disp('Importing PLX data...');
    
    % NB: Currently ignoring spikes before first epoch start
    end_times = plx.ts{7}(2:2:end);
    start_times = plx.ts{7}(1:2:end);
    if(numel(end_times) ~= numel(start_times))
        error('ovation:import:plx:epoch_boundary',...
            'Bit 7 events do not form Epoch boundary pairs');
    end
    if(abs(numel(end_times) - size(plx.unique_number, 1)) > 1)
        warning('ovation:import:plx:epoch_boundary',...
            'SHOULD BE ERROR: Epoch boundary events and unique_number values are not paired');
    end
    
    tic;
    for i = 1:length(plx.unique_number)
        
        
        % Find epoch
        epoch = findEpochByUniqueNumber(epochGroup,...
            plx.unique_number(i,:),...
            epochCache);
        if(isempty(epoch))
            warning('ovation:import:plx:unique_number',...
               'Unable to align PLX data: PLX data contains a unique number not present in the epoch group');
            continue;
        end
        
        % Epoch spikes are strobe_time to end_time
        
        % Add Epoch spike times and waveforms
        start_time = start_times(i);
        end_time = end_times(i);
        insertSpikeAnalysisRecord(epoch,...
            plx,...
            start_time,...
            end_time,...
            analysisParameters,...
            drSuffix,...
            protocol);
        
        % Add bit events to Epoch
        insertEvents(epoch, plx, bitsMap, start_time, end_time, drSuffix);
        
        % Inter-epoch spikes are end_time to next strobe_time (if present)
        nextEpoch = next_epoch(epoch);
        if(~isempty(nextEpoch))
            if(strfind(char(nextEpoch.getProtocol().getName()), 'Intertrial'))
                inter_trial_end = end_time + epoch_duration_s(nextEpoch);
                
                %disp([char(nextEpoch.getStart().toString()) ' ' num2str(end_time) ' ' num2str(inter_trial_end)]);
                
                insertSpikeAnalysisRecord(nextEpoch,...
                    plx,...
                    end_time,...
                    inter_trial_end,...
                    analysisParameters,...
                    drSuffix,...
                    protocol);
            end
            
            % Add bit events to inter-trial Epoch
            insertEvents(nextEpoch, plx, bitsMap, start_time, end_time, drSuffix);
        end
        
        nTrialProgress = 1;
        if(mod(i,nTrialProgress) == 0)
            disp(['    Epoch ' num2str(i) ' of ' num2str(length(plx.unique_number)) ' (' num2str(toc()/5) ' s/epoch)']);
            tic();
        end
    end
    
    disp('Attaching .plx file...');
    f = java.io.File(plxRawFile);
    if(~f.isAbsolute())
        f = java.io.File(fullfile(pwd(), plxRawFile));
    end
    
    epochGroup.addResource('Plexon PLX', f.toURI().toURL(), 'application/x-plexon-plx');
    
    disp('Attaching .exp file...');
    f = java.io.File(expFile);
    if(~f.isAbsolute())
        f = java.io.File(fullfile(pwd(), expFile));
    end
    epochGroup.addResource('Plexon EXP', f.toURI().toURL(), 'application/x-plexon-exp');
end

function d = epoch_duration_s(epoch)
    interval = org.joda.time.Interval(epoch.getStart(), epoch.getEnd());
    d = interval.toDurationMillis() / 1000;
end

function insertEvents(epoch, plx, bitsMap, start_time, end_time, drSuffix)
    
    bits = bitsMap.keySet.toArray;
    for i = 1:length(bits)
        bitNumber = bits(i);
        
        eventTimestamps = plx.ts{bitNumber};
        
        % Find events in this Epoch
        if(isempty(end_time))
            event_idx = eventTimestamps >= start_time;
        else
            event_idx = eventTimestamps >= start_time & eventTimestamps < end_time;
        end
        
        
        epochEventTimestamps = eventTimestamps(event_idx) - start_time;
        for e = 1:length(epochEventTimestamps)
            epoch.addTimelineAnnotation([char(bitsMap.get(bitNumber)) '-' drSuffix],...
                bitsMap.get(bitNumber),...
                epoch.getStart().plusMillis(1000 * epochEventTimestamps(e)));
        end
    end
end

function insertSpikeAnalysisRecord(epoch, plx, start_time, end_time, derivationParameters, drSuffix, protocol)
    import ovation.*
    
    [maxChannels,maxUnits] = size(plx.wave_ts);
    
    % First channel (row) is unsorted
    for c = 2:maxChannels
        % First unit (column) is unsorted
        for u = 2:maxUnits
            if(isempty(plx.wave_ts{c,u}))
                continue;
            end
            
            % Find spikes in this Epoch
            if(isempty(end_time))
                spike_idx = plx.wave_ts{c,u} >= start_time;
            else 
                spike_idx = plx.wave_ts{c,u} >= start_time & plx.wave_ts{c,u} < end_time;
            end
            
            % Calculate relative spike times
            spike_times = plx.wave_ts{c,u}(spike_idx) - start_time;
            
            
            % Insert spike times
            recordName = ['channel_' ...
                num2str(c-1) '_unit_' num2str(u-1)];
            
            j = 1;
            drNameCandidate = [recordName '-' ...
                drSuffix '-' num2str(j)];
            while(has_analysis_record(epoch, drNameCandidate))
                j = j+1;
                drNameCandidate = [recordName '-'...
                    drSuffix '-' num2str(j)];
            end
            
            recordName = drNameCandidate;
            
            
            analysisRecord = epoch.addAnalysisRecord(recordName,...
                namedMap(epoch.getMeasurements(), false),...
                protocol,...
                derivationParameters);
            
            % Spike times
            if(~isempty(spike_times))
                nd = us.physion.ovation.values.NumericData();
                nd.addData('spike_time_from_epoch_start',...
                    spike_times,...
                    's',...
                    0,...
                    'n/a');
                
                analysisRecord.addNumericOutput('spike times',...
                    nd);
            end
            
            
            % Spike waveforms
            waveformData = plx.spike_waves{c,u}(spike_idx,:);
            
            if(~isempty(waveformData))
                samplingRate = 1; % TODO: sampling rate?
                
                nd = us.physion.ovation.values.NumericData();
                nd.addData('spike_waveforms',...
                    waveformData,...
                    {'spikes','waveform'},...
                    'mV',...
                    [0, samplingRate],...
                    {'n/a', 'Hz'});
                
                analysisRecord.addNumericOutput('spike waveforms',...
                    nd);
            end
            
        end
    end
end

function result = has_analysis_record(epoch, recordName)
    import ovation.*;
    
    result = false;
    analysisRecords = asarray(epoch.getAnalysisRecords(epoch.getOwner()));
    for i = 1:length(analysisRecords)
        if(analysisRecords(i).getName().equals(recordName))
            result = true;
            return;
        end
    end
end

function n = next_epoch(epoch)
    nextUri = epoch.getUserProperty(epoch.getOwner(), 'nextEpoch');
    if(~isempty(nextUri))
        n = epoch.getDataContext().getObjectWithURI(nextUri);
    else
        n = [];
    end
end
