classdef TestPDSImport < TestPldapsBase
    
    properties
        trialFunctionName
    end
    
    methods
        function self = TestPDSImport()
            
            import ovation.*;
            import org.joda.time.*;
           
            % N.B. these value should match those in runtestsuite
            [~,self.trialFunctionName,~] = fileparts(self.pdsFile);
            
        end
    end
    
    methods(Test)
        
        % EpochGroup
        %  - should have correct trial function name as group label
        %  - should have PDS start time (min unique number)
        %  - should have PDS start time + last datapixxendtime seconds
        %  - should have original plx file attached as Resource
        %  - should have PLX exp file attached as Resource
        % For each Epoch
        %  - should have trial function name as protocol ID
        %  - should have protocol parameters from dv, PDS
        %  - should have start and end time defined by datapixx
        %  - should have sequential time with prev/next 
        %  - should have next/pre
        %    - intertrial Epochs should interpolate
        %  - should have approparite stimuli and responses
        % For each stimulus
        %  - should have correct plugin ID (TBD)
        %  - should have event times (+ other?) stimulus parameters
        % For each response
        %  - should have numeric data from PDS

        
        function testEpochsShouldHaveNextPrevLinks(self)
            self.assumeTrue(false, 'Not implemented');
            
            import ovation.*
            
            epochs = asarray(self.epochGroup.getEpochs());
            
            for i = 2:length(epochs)
                prev = self.context.getObjectWithURI(epochs(i).getProperty(epochs(i).getOwner(), 'previousEpoch'));
                self.assertNotEmpty(prev);
                if(strfind(char(epochs(i).getProtocol().getName()), 'Intertrial'))
                    self.verifyEmpty(strfind(prev.getProtocol().getName(),'Intertrial'));
                    self.verifyNotEmpty(prev.getOwnerProperty('trialNumber'));
                else
                    self.verifyNotEmpty(strfind(prev.getProtocol().getName(),'Intertrial'));
                end
                
            end
        end
        
        
        function testImportsCorrectNumberOfEpochs(self)
            import ovation.*;
            
            % We expect PDS epochs + inter-trial epochs, but only import
            % the first nTrials
            expectedEpochCount = 2*self.nTrials - 1; % 10 trials + 9 inter-trials %(size(fileStruct.PDS.unique_number, 1) * 2) -1;
            
            self.assertEqual(expectedEpochCount, length(asarray(self.epochGroup.getEpochs())));
        end
        
        
        function testEpochShouldHaveDVParameters(self)
            import ovation.*;
            
            fileStruct = load(self.pdsFile, '-mat');
            dv = fileStruct.dv;
            
            % Convert DV paired cells to a struct
            dv.bits = cell2struct(dv.bits(:,2)',...
                num2cell(strcat('bit_', num2str(cell2mat(dv.bits(:,1)))), 2)',...
                2);
            
            dvMap = ovation.struct2map(dv);
            epochsItr = self.epochGroup.getEpochs().iterator();
            while(epochsItr.hasNext())
                epoch = epochsItr.next();
                keyItr = dvMap.keySet().iterator();
                while(keyItr.hasNext())
                    key = keyItr.next();
                    if(isempty(dvMap.get(key)))
                        continue;
                    end
                    if(isjava(dvMap.get(key)))
                        assertJavaEqual(dvMap.get(key),...
                            epoch.getDeviceParameters.get(key));
                    else
                        self.assertEqual(dvMap.get(key),...
                            epoch.getDeviceParameters().get(key));
                    end
                end
            end
        end
        
        
        function testEpochShouldHavePDSProtocolParameters(self)
            import ovation.*;
            fileStruct = load(self.pdsFile, '-mat');
            pds = fileStruct.PDS;
            
            
            epochs = asarray(self.epochGroup.getEpochs());
            
            i = 1;
            for e = 1:length(epochs)
                epoch = epochs(e);
                if(isempty(strfind(epoch.getProtocol().getName(), 'intertrial')))
                    self.verifyEqual(pds.targ1XY(i),...
                        epoch.getProtocolParameters.get('target1_XY_deg_visual_angle'));
                    if(isfield(pds, 'targ2XY'))
                        self.verifyEqual(pds.targ2XY(i),...
                            epoch.getProtocolParameters.get('target2_XY_deg_visual_angle'));
                    end
                    if(isfield(pds,'coherence'))
                        self.verifyEqual(pds.coherence(i),...
                            epoch.getProtocolParameters.get('coherence'));
                    end
                    if(isfield(pds, 'fp2XY'))
                        self.verifyEqual(pds.fp2XY(i),...
                            epoch.getProtocolParameters.get('fp2_XY_deg_visual_angle'));
                    end
                    if(isfield(pds,'inRF'))
                        self.verifyEqual(pds.inRF(i),...
                            epoch.getProtocolParameters.get('inReceptiveField'));
                    end
                    i = i+1;
                end
            end
        end
        
        function testEpochsShouldBeSequentialInTime(self)
            self.assumeTrue(false, 'Not implemented');
            
            import ovation.*;
            
            epochs = asarray(self.epochGroup.getEpochs());
            
            for i = 2:length(epochs)
                assertJavaEqual(epochs(i).getPreviousEpoch(),...
                    epochs(i-1));
            end
        end
               
        function testEpochStartAndEndTimeShouldBeDeterminedByDataPixxTime(self)
            import ovation.*;
            fileStruct = load(self.pdsFile, '-mat');
            pds = fileStruct.PDS;
            
            epochs = asarray(self.epochGroup.getEpochs());
            
            datapixxmin = min(pds.datapixxstarttime);
            pdsIdx = 1;
            for i = 1:length(epochs)
                epoch = epochs(pdsIdx);
                if(~isempty(strfind(char(epoch.getProtocol().getName()), 'intertrial')))
                    assertJavaEqual(epoch.getStart(),...
                        self.epochGroup.getStart().plusMillis(1000*(pds.datapixxstoptime(pdsIdx-1) - datapixxmin)));
                    assertJavaEqual(epoch.getEnd(),...
                        self.epochGroup.getStart().plusMillis(1000*(pds.datapixxstarttime(pdsIdx) - datapixxmin)));
                else
                    assertJavaEqual(epoch.getStart(),...
                        self.epochGroup.getStart.plusMillis(1000*(pds.datapixxstarttime(pdsIdx) - datapixxmin)));
                    assertJavaEqual(epoch.getEnd(),...
                        self.epochGroup.getStart().plusMillis(1000*(pds.datapixxstoptime(pdsIdx) - datapixxmin)));
                    pdsIdx = pdsIdx + 1;
                end
            end
        end
        
        function testShouldUseTrialFunctionNameAsEpochProtocolID(self)
            import ovation.*
            epochs = asarray(self.epochGroup.getEpochs());
            for n=1:length(epochs)
                self.assertTrue(epochs(n).getProtocol().getName().equals(java.lang.String(self.trialFunctionName)) ||...
                strcmp(char(epochs(n).getProtocol().getName()), [self.trialFunctionName '.intertrial']));
            end
        end
        
        function testShouldUseTrialFunctionNameAsEpochGroupLabel(self)
            
            self.assertTrue(self.epochGroup.getLabel().equals(java.lang.String(self.trialFunctionName)));
            
        end
        
        function testShouldAttachPDSAsEpochGroupResource(self)
            [~, pdsName, ext] = fileparts(self.pdsFile);
            self.assertNotEmpty(self.epochGroup.getResource([pdsName ext]));
        end
        
        function testEpochShouldHaveProperties(self)
            import ovation.*;
            fileStruct = load(self.pdsFile, '-mat');
            pds = fileStruct.PDS;
            
             epochs = asarray(self.epochGroup.getEpochs());
            for n=1:length(epochs)
                if(~isempty(strfind(epochs(n).getProtocol().getName(), 'intertrial')))
                    continue;
                end
                
                props = epochs(n).getUserProperties(epochs(n).getOwner());
                self.assertTrue(props.containsKey('dataPixxStart_seconds'));
                self.assertTrue(props.containsKey('dataPixxStop_seconds'));
                self.assertTrue(props.containsKey('uniqueNumber'));
                self.assertTrue(props.containsKey('uniqueNumberString'));
                self.assertTrue(props.containsKey('trialNumber'));
                self.assertTrue(props.containsKey('goodTrial'));
                if(isfield(pds,'coherence'))
                    self.assertTrue(props.containsKey('coherence'));
                end
                if(isfield(pds,'chooseRF'))
                    self.assertTrue(props.containsKey('chooseRF'));
                end
                if(isfield(pds,'timeOfChoice'))
                    self.assertTrue(props.containsKey('timeOfChoice'));
                end
                if(isfield(pds,'timeOfReward'))
                    self.assertTrue(props.containsKey('timeOfReward'));
                end
                if(isfield(pds,'timeOfFixation'))
                    self.assertTrue(props.containsKey('timeBrokeFixation'));
                end
                if(isfield(pds,'correct'))
                    if(pds.correct(n))
                        tags = epochs(n).getTags;
                        found = false;
                        for t = 1:lenth(tags);
                            if(strcmp(char(tags(t)), 'correct'))
                                found = true;
                            end
                        end
                        self.assertTrue(found);
                    end
                end
                
            end
        end
        
        function testEpochShouldHaveResponseDataFromPDS(self)
            import ovation.*
            
            fileStruct = load(self.pdsFile, '-mat');
            pds = fileStruct.PDS;
            
            
            epochs = asarray(self.epochGroup.getEpochs().iterator());
            eyeTrackingEpoch = 1;
            for i=1:length(epochs)
                epoch = epochs(i);
                if(~isempty(epoch.getMeasurement('eye_tracker')))
                    assert(isempty(strfind(epoch.getProtocol().getName(), 'intertrial')));
                    r = nm2data(epoch.getMeasurement('eye_tracker'));
                    rData = reshape(r.getFloatingPointData(),...
                        r.getShape()');
                    
                    
                    assertElementsAlmostEqual(pds.eyepos{eyeTrackingEpoch}(:,1:2), rData);
                    
                    eyeTrackingEpoch = eyeTrackingEpoch + 1;
                end
            end
        end
        
        function testEpochProtocolParametersShouldHaveStimulusParameters(self)
            
            fileStruct = load(self.pdsFile, '-mat');
            dv = fileStruct.dv;
            
            % Convert DV paired cells to a struct
            dv.bits = cell2struct(dv.bits(:,2)',...
                num2cell(strcat('bit_', num2str(cell2mat(dv.bits(:,1)))), 2)',...
                2);
            
            dvMap = ovation.struct2map(dv);
            
            
            epochsItr = self.epochGroup.getEpochs().iterator();
            while(epochsItr.hasNext())
                epoch = epochsItr.next();
                
                keyItr = dvMap.keySet().iterator();
                while(keyItr.hasNext())
                    key = keyItr.next();
                    if(isempty(dvMap.get(key)))
                        continue;
                    end
                    if(isjava(dvMap.get(key)))
                        assertJavaEqual(dvMap.get(key),...
                            epoch.getProtocolParameters().get(key));
                        assertJavaEqual(dvMap.get(key),...
                            epoch.getDeviceParameters().get(key));
                    else
                        self.assertEqual(dvMap.get(key),...
                            epoch.getProtocolParameters().get(key));
                        self.assertEqual(dvMap.get(key),...
                            s.getDeviceParameters.get(key));
                    end
                end
            end
            
            
        end
                
        function testEpochGroupShouldHavePDSStartTime(self)
            import ovation.*;
            fileStruct = load(self.pdsFile, '-mat');
            pds = fileStruct.PDS;
            
            idx = find(pds.datapixxstarttime == min(pds.datapixxstarttime));
            unum = pds.unique_number(idx(1),:);
            
            startTime = datetime(unum(1), unum(2), unum(3), unum(4), unum(5), unum(6), 0, self.timezone.getID());
            
            
            assertJavaEqual(self.epochGroup.getStart(),...
                startTime);
            
        end
        
        function testEpochGroupShouldHavePDSEndTime(self)
            import ovation.*;
            
            fileStruct = load(self.pdsFile, '-mat');
            pds = fileStruct.PDS;
            
            totalDurationSeconds = max(pds.datapixxstoptime) - min(pds.datapixxstarttime);
            
            assertJavaEqual(self.epochGroup.getEnd(),...
                self.epochGroup.getStart().plusMillis(1000*totalDurationSeconds));
        end
    end
end