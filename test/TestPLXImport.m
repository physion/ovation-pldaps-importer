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
            names = asarray(target.getResourceNames());
            found = false;
            for i = 1:length(names)
                if(strcmp(names(i), name))
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
            itr = self.epochGroup.getEpochs().iterator();
            while(itr.hasNext())
                epoch = itr.next();
                analysisRecords = asarray(epoch.getAnalysisRecords(epoch.getOwner()));
                
                for i = 1:length(analysisRecords)
                    if(~isempty(strfind(char(analysisRecords(i).getName()), 'channel_')))
                        actual = actual + 1;
                        break;
                    end
                end
            end
            
            self.verifyThat(actual, IsEqualTo(expected));
        end
        
        function testShouldAssignSpikeTimesToSpanningEpoch(self)
            % Spikes in plx.wave_ts should be assigned to the Epoch in which they occurred
            
            import ovation.*;
            import matlab.unittest.constraints.*;
            
            [maxChannels,maxUnits] = size(self.plx.wave_ts);
            
            start_times = self.plx.ts{7}(1:2:end);
            end_times = self.plx.ts{7}(2:2:end);
            for i = 1:size(self.plx.unique_number,1)
                epoch = findEpochByUniqueNumber(self.epochGroup,...
                    self.plx.unique_number(i,:),...
                    self.epochCache);
                
                if(isempty(epoch))
                    continue;
                end
                
                for c = 2:maxChannels % Row 1 is unsorted
                    for u = 2:maxUnits % Col 1 in unsorted
                        spikeTimes = self.plx.wave_ts{c,u};
                        
                        epochSpikeTimes = spikeTimes(spikeTimes >= start_times(i) & ...
                            spikeTimes < end_times(i)) - start_times(i);
                        if(i < size(self.plx.unique_number,1))
                            interEpochSpikeTimes = spikeTimes(spikeTimes >= end_times(i) & ...
                                spikeTimes < start_times(i+1)) - end_times(i);
                        else
                            interEpochSpikeTimes = [];
                        end
                        
                        analysisRecords = asarray(epoch.getAnalysisRecords(epoch.getOwner()));
                        
                        self.verifyThat(isempty(analysisRecords), IsEqualTo(isempty(epochSpikeTimes)));
                        
                        for d = 1:length(analysisRecords)
                            % assume there's only one DR
                            record = analysisRecords(d);
                            actualSpikeTimes = record.getOutputs().get('spike times');
                            self.verifyThat(nm2data(actualSpikeTimes).spike_time_from_epoch_start,...
                                IsEqualTo(epochSpikeTimes,...
                                'Within',...
                                AbsoluteTolerance(1e-6))); %nanosecond precision
                            
                            
                            self.verifyThat(min(actualSpikeTimes), IsGreaterThanOrEqualTo(0));
                            self.verifyThat(max(actualSpikeTimes), IsLessThan(epoch.getDuration()));
                        end
                        
                        if(~isempty(interEpochSpikeTimes))
                            interTrialEpoch = self.context.getObjectWithURI(epoch.getUserProperty(epoch.getOwner(), 'nextEpoch'));
                            if(~isempty(interTrialEpoch))
                                analysisRecords = asarray(interTrialEpoch.getAnalysisRecords(interTrialEpoch.getOwner()));
                                
                                for d = 1:length(analysisRecords)
                                    record = analysisRecords(d);
                                    actualSpikeTimes = record.getOutputs().get('spike times');
                                    self.verifyThat(nm2data(actualSpikeTimes).spike_time_from_epoch_start,...
                                        IsEqualTo(epochSpikeTimes,...
                                        'Within',...
                                        AbsoluteTolerance(1e-6))); %nanosecond precision
                                    
                                    self.verifyThat(min(actualSpikeTimes), IsGreaterThanOrEqualTo(0));
                                    self.verifyThat(max(actualSpikeTimes), IsLessThan(epoch.getEnd().minus(epoch.getStart()), 'Within', AbsoluteTolerance(0.001)));
                                end
                            end
                        end
                    end
                end
            end
            
        end
        
        
        function testShouldHaveSpikeWaveformsForEachUnit(self)
            % Spikes in plx.wave_ts should be assigned to the Epoch in which they occurred
            
            [maxChannels,maxUnits] = size(self.plx.wave_ts);
            
            start_times = self.plx.ts{7}(1:2:end);
            end_times = self.plx.ts{7}(2:2:end);
            for i = 1:size(self.plx.unique_number,1)
                epoch = findEpochByUniqueNumber(self.epochGroup,...
                    self.plx.unique_number(i,:),...
                    self.epochCache);
                
                if(isempty(epoch))
                    continue;
                end
                
                for c = 2:maxChannels % Row 1 is unsorted
                    for u = 2:maxUnits % Col 1 in unsorted
                        spikeTimes = self.plx.wave_ts{c,u};
                        
                        spike_idx = find(spikeTimes >= start_times(i) & ...
                            spikeTimes < end_times(i));
                        
                        % assume there's only one DR
                        drName = ['spikeWaveforms_channel_' num2str(c-1)...
                            '_unit_' num2str(u-1) '-'...
                            self.drNameSuffix '-1'];
                        
                        derivedResponses = epoch.getDerivedResponses(drName);
                        
                        assert(isempty(derivedResponses) == isempty(spike_idx));
                        
                        for d = 1:length(derivedResponses)
                            dr = derivedResponses(d);
                            
                            waveforms = reshape(dr.getFloatingPointData(), dr.getShape()');
                            
                            % Should have same number of waveforms as spike
                            % times
                            if(length(spike_idx) ~= size(waveforms,1))
                                keyboard
                            end
                            assertEqual(length(spike_idx), size(waveforms, 1));
                        end
                    end
                end
            end
            
        end
        
    end
end
