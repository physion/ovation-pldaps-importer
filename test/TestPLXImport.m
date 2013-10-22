classdef TestPLXImport < TestPldapsBase
    
    properties
        plx
        drNameSuffix
        epochCache
    end
    
    methods
        function self = TestPLXImport()
            import ovation.*;
            
            
            expModificationDate = org.joda.time.DateTime(java.io.File(self.plxFile).lastModified());
            self.drNameSuffix = [num2str(expModificationDate.getYear()) '-' ...
                num2str(expModificationDate.getMonthOfYear()) '-'...
                num2str(expModificationDate.getDayOfMonth())];
            
        end
        
        function localFixture(self)
            localFixture@TestPldapsBase(self);
            
            import ovation.*;
            
            plxStruct = load(self.plxFile);
            self.plx = plxStruct.plx;
            
            disp('Calculating PLX-PDS unique number mapping...');
            cache.uniqueNumber = java.util.HashMap();
            cache.truncatedUniqueNumber = java.util.HashMap();
            epochs = asarray(self.epochGroup.getEpochs());
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
                    
                    cache.uniqueNumber.put(num2str(uNum), epoch);
                    cache.truncatedUniqueNumber.put(num2str(mod(uNum,256)),...
                        epoch);
                end
            end
            
            self.epochCache = cache;
        end
        
        function assertFileResource(self, target, name)
            import ovation.*;
            
            [~,name,ext]=fileparts(name);
            name = [name ext];
            resources = asarray(target.getResources());
            found = false;
            for i = 1:length(resources)
                if(strcmp(char(resources(i).getFilename()), char(name)))
                    found = true;
                    break;
                end
            end
            
            self.assertTrue(found);
        end
        
    end
    
    methods(Test)
        
        % The PLX import should
        %  - import spike data to existing Epochs
        %    - with spike times t0 <= ts < end_trial
        %    - the same number of wave forms as spike times
        
        function testShouldAppendPLXFile(self)
            self.assertFileResource(self.epochGroup, self.plxRawFile);
        end
        
        function testShouldAppendEXPFile(self)
            self.assertFileResource(self.epochGroup, self.plxExpFile);
        end
        
        function testFindEpochGivesNullForNullEpochGroup(self)
            import matlab.unittest.constraints.*;
            self.assertThat(findEpochByUniqueNumber([], [1,2]),...
                IsEmpty());
        end
        
        function testGivesEmptyForNoMatchingEpochByUniqueNumber(self)
            import matlab.unittest.constraints.*;
            self.assertThat(findEpochByUniqueNumber(self.epochGroup, [1,2,3,4,5,6]),...
                IsEmpty());
        end
        
        function testFindsMatchingEpochFromUniqueNumber(self)
            import ovation.*;
            import matlab.unittest.constraints.*;
            
            for i = 1:size(self.plx.unique_number, 1)
                unum = self.plx.unique_number(i,:);
                
                epoch = findEpochByUniqueNumber(self.epochGroup, unum);
                if(isempty(epoch))
                    continue;
                end
                epochUnum = epoch.getUserProperty(epoch.getOwner(), 'uniqueNumber');
                uNum = zeros(1, epochUnum.size());
                for j = 1:length(uNum)
                    uNum(j) = epochUnum.get(j-1);
                end
                self.verifyThat(mod(uNum, 256), IsEqualTo(unum));
            end
        end
        
        function testImportsExpectedNumberOfEpochs(self)
            import ovation.*;
            import matlab.unittest.constraints.*;
            
            expected = size(self.plx.unique_number,1)*2 - 1;
            actual = 0;
            epochs = sort_epochs(asarray(self.epochGroup.getEpochs()));
            for i = 1:length(epochs)
                epoch = epochs{i};
                analysisRecords = asarray(epoch.getAnalysisRecords(epoch.getOwner()));
                
                for i = 1:length(analysisRecords)
                    if(~isempty(strfind(char(analysisRecords(i).getName()), 'channel_')))
                        actual = actual + 1;
                        break;
                    end
                end
            end
            
            if(~isempty(self.nTrials))
                self.verifyThat(actual, IsLessThanOrEqualTo(self.nTrials));
            else
                self.verifyThat(actual, IsLessThanOrEqualTo(expected));
            end
        end
        
        function testShouldAssignSpikeTimesToSpanningEpoch(self)
            % Spikes in plx.wave_ts should be assigned to the Epoch in which they occurred
            
            import ovation.*;
            import matlab.unittest.constraints.*;
            
            self.context.getRepository().clear();
            
            [maxChannels,maxUnits] = size(self.plx.wave_ts);
            
            self.context.getRepository().clear();
            
            start_times = self.plx.ts{7}(1:2:end);
            end_times = self.plx.ts{7}(2:2:end);
            
            
            foundSpikeTimes = false;
            foundInterEpochSpikeTimes = false;
            shouldFindInterEpochSpikeTimes = false;
            
            for i = 1:size(self.plx.unique_number,1)
                epoch = findEpochByUniqueNumber(self.epochGroup,...
                    self.plx.unique_number(i,:),...
                    self.epochCache);
                
                if(isempty(epoch))
                    continue;
                end
                
                nextUri = epoch.getUserProperty(epoch.getOwner(), 'nextEpoch');
                if(~isempty(nextUri))
                    interTrialEpoch = self.context.getObjectWithURI(nextUri);
                else
                    interTrialEpoch = [];
                end
                
                for c = 2:maxChannels % Row 1 is unsorted
                    for u = 2:maxUnits % Col 1 in unsorted
                        if(isempty(self.plx.wave_ts{c,u}))
                            continue;
                        end
                        
                        spikeTimes = self.plx.wave_ts{c,u};
                        
                        recordName = ['channel_' ...
                            num2str(c-1) '_unit_' num2str(u-1)];
                        
                        epochSpikeTimes = spikeTimes(spikeTimes >= start_times(i) & ...
                            spikeTimes < end_times(i)) - start_times(i);
                        
                        if(i < size(self.plx.unique_number,1))
                            interEpochSpikeTimes = spikeTimes(spikeTimes >= end_times(i) & ...
                                spikeTimes < start_times(i+1)) - end_times(i);
                            shouldFindInterEpochSpikeTimes = true;
                        else
                            interEpochSpikeTimes = [];
                        end
                        
                        analysisRecords = asarray(epoch.getAnalysisRecords(epoch.getOwner()));
                        
                        for d = 1:length(analysisRecords)
                            % assume there's only one DR
                            record = analysisRecords(d);
                            if(record.getName().startsWith(recordName))
                                
                                actualSpikeTimes = record.getOutputs().get('spike times');
                                if(~isempty(actualSpikeTimes))
                                    dataTimes = nm2data(actualSpikeTimes).spike_time_from_epoch_start;
                                    self.verifyThat(dataTimes,...
                                        IsEqualTo(epochSpikeTimes,...
                                        'Within',...
                                        AbsoluteTolerance(1e-6))); %nanosecond precision
                                    
                                    
                                    self.verifyThat(min(dataTimes), IsGreaterThanOrEqualTo(0));
                                    self.verifyThat(max(dataTimes), IsGreaterThanOrEqualTo(min(dataTimes)));
                                    
                                    % TODO: max(dateTimes) is longer than
                                    %  Epoch. Do PDS and PLX epoch
                                    %  boundaries not align?
                                    
                                    foundSpikeTimes = true;
                                end
                            end
                        end
                        
                        if(~isempty(interTrialEpoch))
                            
                            if(strfind(char(interTrialEpoch.getProtocol().getName()), 'Intertrial'))
                                d = org.joda.time.Interval(interTrialEpoch.getStart(), interTrialEpoch.getEnd()).toDurationMillis / 1000;
                                
                                interEpochSpikeTimes = spikeTimes(spikeTimes >= end_times(i) & ...
                                    spikeTimes < (end_times(i) + d)) - end_times(i);
                                shouldFindInterEpochSpikeTimes = true;
                            end
                            
                            %disp([char(interTrialEpoch.getStart().toString()) ' ' num2str(end_times(i)) ' ' num2str(end_times(i) + d)]);
                            
                            analysisRecords = asarray(interTrialEpoch.getAnalysisRecords(interTrialEpoch.getOwner()));
                            
                            for d = 1:length(analysisRecords)
                                record = analysisRecords(d);
                                if(record.getName().startsWith(recordName))
                                    actualSpikeTimes = record.getOutputs().get('spike times');
                                    if(~isempty(actualSpikeTimes))
                                        foundInterEpochSpikeTimes = true;
                                        
                                        self.verifyThat(nm2data(actualSpikeTimes).spike_time_from_epoch_start,...
                                            IsEqualTo(interEpochSpikeTimes,...
                                            'Within',...
                                            AbsoluteTolerance(1e-6))); %nanosecond precision
                                        
                                        self.verifyThat(min(nm2data(actualSpikeTimes).spike_time_from_epoch_start),...
                                            IsGreaterThanOrEqualTo(0));
                                        self.verifyThat(max(nm2data(actualSpikeTimes).spike_time_from_epoch_start),...
                                            IsLessThan((epoch.getEnd().getMillis() - epoch.getStart().getMillis())/1000));
                                        
                                    end
                                end
                            end
                        end
                    end
                end
            end
            
            self.verifyTrue(foundSpikeTimes, 'Found some spike times');
            self.verifyThat(foundInterEpochSpikeTimes, IsEqualTo(shouldFindInterEpochSpikeTimes), 'Found some inter-epoch spike times');
        end
        
        
        function testShouldHaveSpikeWaveformsForEachUnit(self)
            % Should have same number of waveforms as spikes
            
            import ovation.*;
            import matlab.unittest.constraints.*;
            
            [maxChannels,maxUnits] = size(self.plx.wave_ts);
            
            self.context.getRepository().clear();
            
            
            foundWaveforms = false;
            
            for i = 1:size(self.plx.unique_number,1)
                epoch = findEpochByUniqueNumber(self.epochGroup,...
                    self.plx.unique_number(i,:),...
                    self.epochCache);
                
                if(isempty(epoch))
                    continue;
                end
                
                for c = 2:maxChannels % Row 1 is unsorted
                    for u = 2:maxUnits % Col 1 in unsorted
                        if(isempty(self.plx.wave_ts{c,u}))
                            continue;
                        end
                        
                        recordName = ['channel_' ...
                            num2str(c-1) '_unit_' num2str(u-1)];
                        
                        analysisRecords = asarray(epoch.getAnalysisRecords(epoch.getOwner()));
                        
                        for d = 1:length(analysisRecords)
                            % assume there's only one DR
                            record = analysisRecords(d);
                            if(record.getName().startsWith(recordName))
                                waveforms = record.getOutputs().get('spike waveforms');
                                spikeTimes = record.getOutputs().get('spike times');

                                if(~isempty(waveforms))
                                    self.verifyNotEmpty(spikeTimes);
                                    data = nm2data(waveforms);
                                    self.verifyThat(size(data.spike_waveforms,1),...
                                        IsEqualTo(size(nm2data(spikeTimes).spike_time_from_epoch_start, 1)));
                                    foundWaveforms = true;
                                end
                            end
                        end
                        
                        
                    end
                end
            end
            
            self.verifyTrue(foundWaveforms);
        end
    end
end
