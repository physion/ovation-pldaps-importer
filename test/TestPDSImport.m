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
            fileStruct = load(self.pdsFile, '-mat');
            
            % We expect PDS epochs + inter-trial epochs
            expectedEpochCount = (size(fileStruct.PDS.unique_number, 1) * 2) -1;
            
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
                            epoch.getProtocolParameter(key));
                    else
                        assertEqual(dvMap.get(key),...
                            epoch.getProtocolParameter(key));
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
                        epoch.getProtocolParameter('target1_XY_deg_visual_angle'));
                    if(isfield(pds, 'targ2XY'))
                        self.verifyEqual(pds.targ2XY(i),...
                            epoch.getProtocolParameter('target2_XY_deg_visual_angle'));
                    end
                    if(isfield(pds,'coherence'))
                        self.verifyEqual(pds.coherence(i),...
                            epoch.getProtocolParameter('coherence'));
                    end
                    if(isfield(pds, 'fp2XY'))
                        self.verifyEqual(pds.fp2XY(i),...
                            epoch.getProtocolParameter('fp2_XY_deg_visual_angle'));
                    end
                    if(isfield(pds,'inRF'))
                        self.verifyEqual(pds.inRF(i),...
                            epoch.getProtocolParameter('inReceptiveField'));
                    end
                    i = i+1;
                end
            end
        end
        
        function testEpochsShouldBeSequentialInTime(self)
            
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
            
            epochs = self.epochGroup.getEpochs();
            
            datapixxmin = min(pds.datapixxstarttime);
            pdsIdx = 1;
            for i = 1:length(epochs)
                epoch = epochs(pdsIdx);
                if(~isempty(strfind(char(epoch.getProtocolID()), 'intertrial')))
                    assertJavaEqual(epoch.getStartTime(),...
                        self.epochGroup.getStartTime.plusMillis(1000*(pds.datapixxstoptime(pdsIdx-1) - datapixxmin)));
                    assertJavaEqual(epoch.getEndTime(),...
                        self.epochGroup.getStartTime.plusMillis(1000*(pds.datapixxstarttime(pdsIdx) - datapixxmin)));
                else
                    assertJavaEqual(epoch.getStartTime(),...
                        self.epochGroup.getStartTime.plusMillis(1000*(pds.datapixxstarttime(pdsIdx) - datapixxmin)));
                    assertJavaEqual(epoch.getEndTime(),...
                        self.epochGroup.getStartTime.plusMillis(1000*(pds.datapixxstoptime(pdsIdx) - datapixxmin)));
                    pdsIdx = pdsIdx + 1;
                end
            end
        end
        
        function testShouldUseTrialFunctionNameAsEpochProtocolID(self)
            epochs = self.epochGroup.getEpochs();
            for n=1:length(epochs)
                assertTrue(epochs(n).getProtocolID().equals(java.lang.String(self.trialFunctionName)) ||...
                strcmp(char(epochs(n).getProtocolID()), [self.trialFunctionName '.intertrial']));
            end
        end
        
        function testShouldUseTrialFunctionNameAsEpochGroupLabel(self)
            
            assertTrue(self.epochGroup.getLabel().equals(java.lang.String(self.trialFunctionName)));
            
        end
        
        function testShouldAttachPDSAsEpochGroupResource(self)
            [~, pdsName, ext] = fileparts(self.pdsFile);
            assertTrue( ~isempty(self.epochGroup.getResource([pdsName ext])));
        end
        
        function testEpochShouldHaveProperties(self)
            import ovation.*;
            fileStruct = load(self.pdsFile, '-mat');
            pds = fileStruct.PDS;
            
             epochs = self.epochGroup.getEpochs();
            for n=1:length(epochs)
                if(~isempty(strfind(epochs(n).getProtocolID(), 'intertrial')))
                    continue;
                end
                
                props = epochs(n).getOwnerProperties().keySet();
                assertTrue(props.contains('dataPixxStart_seconds'));
                assertTrue(props.contains('dataPixxStop_seconds'));
                assertTrue(props.contains('uniqueNumber'));
                assertTrue(props.contains('uniqueNumberString'));
                assertTrue(props.contains('trialNumber'));
                assertTrue(props.contains('goodTrial'));
                if(isfield(pds,'coherence'))
                assertTrue(props.contains('coherence'));
                end
                if(isfield(pds,'chooseRF'))
                assertTrue(props.contains('chooseRF'));
                end
                if(isfield(pds,'timeOfChoice'))
                assertTrue(props.contains('timeOfChoice'));
                end
                if(isfield(pds,'timeOfReward'))
                assertTrue(props.contains('timeOfReward'));
                end
                if(isfield(pds,'timeOfFixation'))
                assertTrue(props.contains('timeBrokeFixation'));
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
                        assertTrue(found);
                    end
                end
                
            end
        end
        
        function testEpochShouldHaveResponseDataFromPDS(self)
            fileStruct = load(self.pdsFile, '-mat');
            pds = fileStruct.PDS;
            
            experiment = self.epochGroup.getExperiment();
            
            devices.eye_tracker = experiment.externalDevice('Eye Trac 6000', 'ASL');
            devices.eye_tracker_timer = experiment.externalDevice('Windows', 'Microsoft');
            
            epochs = self.epochGroup.getEpochs();
            eyeTrackingEpoch = 1;
            for i=1:length(epochs)
                epoch = epochs(i);
                if(~isempty(epoch.getResponse(devices.eye_tracker.getName())))
                    assert(isempty(strfind(epoch.getProtocolID(), 'intertrial')));
                    r = epoch.getResponse(devices.eye_tracker.getName());
                    rData = reshape(r.getFloatingPointData(),...
                        r.getShape()');
                    
                    
                    assertElementsAlmostEqual(pds.eyepos{eyeTrackingEpoch}(:,1:2), rData);
                    
                    assertFalse(isempty(epoch.getResponse(devices.eye_tracker_timer.getName())));
                    r = epoch.getResponse(devices.eye_tracker_timer.getName());
                    rData = r.getFloatingPointData();
                    assertElementsAlmostEqual(pds.eyepos{eyeTrackingEpoch}(:,3), rData);
                    
                    eyeTrackingEpoch = eyeTrackingEpoch + 1;
                end
            end
        end
        
        function testEpochStimuliShouldHavePluginIDAndParameters(self)
            experiment = self.epochGroup.getExperiment();
            trialFunction = self.epochGroup.getLabel();
            pluginID = ['edu.utexas.huk.pladapus.' char(trialFunction)];
            
            fileStruct = load(self.pdsFile, '-mat');
            dv = fileStruct.dv;
            
            % Convert DV paired cells to a struct
            dv.bits = cell2struct(dv.bits(:,2)',...
                num2cell(strcat('bit_', num2str(cell2mat(dv.bits(:,1)))), 2)',...
                2);
            
            dvMap = ovation.struct2map(dv);
            
            devices.psychToolbox = experiment.externalDevice('PsychToolbox', 'Huk lab');

            epochsItr = self.epochGroup.getEpochsIterable().iterator();
            while(epochsItr.hasNext())
                epoch = epochsItr.next();
                s = epoch.getStimulus(devices.psychToolbox.getName());
                if(isempty(s))
                    continue;
                end
                
                assertTrue(strcmp(pluginID, char(s.getPluginID())));
                
                keyItr = dvMap.keySet().iterator();
                while(keyItr.hasNext())
                    key = keyItr.next();
                    if(isempty(dvMap.get(key)))
                        continue;
                    end
                    if(isjava(dvMap.get(key)))
                        assertJavaEqual(dvMap.get(key),...
                            s.getStimulusParameter(key));
                        assertJavaEqual(dvMap.get(key),...
                            s.getDeviceParameters.get(key));
                    else
                        assertEqual(dvMap.get(key),...
                            s.getStimulusParameter(key));
                        assertEqual(dvMap.get(key),...
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
            
            
            assertJavaEqual(self.epochGroup.getStartTime(),...
                startTime);
            
        end
        
        function testEpochGroupShouldHavePDSEndTime(self)
            import ovation.*;
            
            fileStruct = load(self.pdsFile, '-mat');
            pds = fileStruct.PDS;
            
            totalDurationSeconds = max(pds.datapixxstoptime) - min(pds.datapixxstarttime);
            
            assertJavaEqual(self.epochGroup.getEndTime(),...
                self.epochGroup.getStartTime().plusMillis(1000*totalDurationSeconds));
        end
    end
end