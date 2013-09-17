function ImportPLX(epochGroup, plxFile, bits, plxRawFile, expFile, varargin)
    % Import Plexon data into an existing PL-DA-PS PDS EpochGroup
    %
    %    ImportPLX(epochGroup, plxFile, plxRawFile, expFile)
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
    derivationParameters.expFileContents = expTxt;
    
    derivationParameters = struct2map(derivationParameters);
    
    disp('Calculating PLX-PDS unique number mapping...');
    epochCache.uniqueNumber = java.util.HashMap();
    epochCache.truncatedUniqueNumber = java.util.HashMap();
    epochs = epochGroup.getEpochsUnsorted();
    for i = 1:length(epochs)
        if(mod(i,5) == 0)
            disp(['    Epoch ' num2str(i) ' of ' num2str(length(epochs))]);
        end
        
        epoch = epochs(i);
        epochUniqueNumber = epoch.getOwnerProperty('uniqueNumber');
        if(~isempty(epochUniqueNumber))
            epochUniqueNumber = epochUniqueNumber.getIntegerData()';
        end
        
        epochCache.uniqueNumber.put(num2str(epochUniqueNumber), epoch);
        epochCache.truncatedUniqueNumber.put(num2str(mod(epochUniqueNumber,256)),...
            epoch);
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
        error('ovation:import:plx:epoch_boundary',...
            'Epoch boundary events and unique_number values are not paired');
    end
    
    tic;
    for i = 1:length(plx.unique_number)
        if(mod(i,5) == 0)
            disp(['    Epoch ' num2str(i) ' of ' num2str(length(plx.unique_number)) ' (' num2str(toc()/5) ' s/epoch)']);
            tic();
        end
        
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
        insertSpikeDerivedResponses(epoch,...
            plx,...
            start_time,...
            end_time,...
            derivationParameters,...
            drSuffix);
        
        % Add bit events to Epoch
        insertEvents(epoch, plx, bitsMap, start_time, end_time, drSuffix);
        
        % Inter-epoch spikes are end_time to next strobe_time (if present)
        % else end
        if(~isempty(epoch.getNextEpoch()))
            next = epoch.getNextEpoch();
            if(strfind(next.getProtocolID(), 'intertrial'))
                if(i == length(start_times))
                    inter_trial_end = [];
                else
                    inter_trial_end = start_times(i+1);
                end
                
                insertSpikeDerivedResponses(next,...
                    plx,...
                    end_time,...
                    inter_trial_end,...
                    derivationParameters,...
                    drSuffix);
            end
            
            % Add bit events to inter-trial Epoch
            insertEvents(next, plx, bitsMap, start_time, end_time, drSuffix);
        end
        
        
    end
    
    disp('Attaching .plx file...');
    epochGroup.addResource('com.plexon.plx', plxRawFile);
    
    disp('Attaching .exp file...');
    epochGroup.addResource('com.plexon.exp', expFile);
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
                epoch.getStartTime().plusMillis(1000 * epochEventTimestamps(e)));
        end
    end
end

function insertSpikeDerivedResponses(epoch, plx, start_time, end_time, derivationParameters, drSuffix)
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
            derivedResponseName = ['spikeTimes_channel_' ...
                num2str(c-1) '_unit_' num2str(u-1)];
            
            j = 1;
            drNameCandidate = [derivedResponseName '-' ...
                drSuffix '-' num2str(j)];
            while(~isempty(epoch.getMyDerivedResponse(drNameCandidate)))
                j = j+1;
                drNameCandidate = [derivedResponseName '-'...
                    drSuffix '-' num2str(j)];
            end
            
            derivedResponseName = drNameCandidate;
            
            if(~isempty(spike_times))
                epoch.insertDerivedResponse(derivedResponseName,...
                    NumericData(spike_times'),...
                    's',... %times in seconds
                    derivationParameters,...
                    {'time from epoch start'}...
                    );
            end
            
            
            % Insert spike wave forms
            derivedResponseName = ['spikeWaveforms_channel_'...
                num2str(c-1) '_unit_' num2str(u-1)];
            
            waveformData = plx.spike_waves{c,u}(spike_idx,:);
            
            if(~isempty(waveformData))
                data = NumericData(reshape(waveformData, 1, ...
                    numel(waveformData)),...
                    size(waveformData));
                
                j = 1;
                drNameCandidate = [derivedResponseName '-' ...
                    drSuffix '-' num2str(j)];
                while(~isempty(epoch.getMyDerivedResponse(drNameCandidate)))
                    j = j+1;
                    drNameCandidate = [derivedResponseName '-'...
                        drSuffix '-' num2str(j)];
                end
                
                derivedResponseName = drNameCandidate;
                
                epoch.insertDerivedResponse(derivedResponseName,...
                    data,...
                    'mV',... % TODO confirm units
                    derivationParameters,...
                    {'spikes','waveform'}... % TODO dimension labels?
                    );
            end
            
        end
    end
end