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
        %  - should have original plx file attached as Resource
        %  - should have PLX exp file attached as Resource
        % For each Epoch
        %  - should have trial function name as protocol ID
        %  - should have protocol parameters from dv, PDS
        %  - should have start and end time defined by datapixx
        %  - should have sequential time with prev/next 
        %  - should have next/pre [not implemented in Ovation 2.0]
        %    - intertrial Epochs should interpolate
        %  - should have approparite stimuli and responses
        % For each stimulus
        %  - should have event times (+ other?) stimulus parameters
        % For each response
        %  - should have numeric data from PDS

        
        function testEpochsShouldHaveNextPrevLinks(self)
            
            import ovation.*
            
            epochs = asarray(self.epochGroup.getEpochs());
            
            for i = 2:length(epochs)
                prev = self.context.getObjectWithURI(epochs(i).getJserProperty(epochs(i).getOwner(), 'previousEpoch'));
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
            
            warning('off') %#ok<*WNOFF>
            fileStruct = load(self.pdsFile, '-mat');
            warning('on') %#ok<*WNON>
            dv = fileStruct.dv;
            
            % Convert DV paired cells to a struct
            dv.bits = cell2struct(dv.bits(:,2)',...
                num2cell(strcat('bit_', num2str(cell2mat(dv.bits(:,1)))), 2)',...
                2);
            
            dv = rmfield(dv, 'params');
            
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
                        self.verifyEqual(dvMap.get(key),...
                            epoch.getDeviceParameters().get(key));
                    end
                end
            end
        end
        
        
        function testEpochShouldHavePDSProtocolParameters(self)
            import ovation.*;
            warning('off')
            fileStruct = load(self.pdsFile, '-mat');
            warning('on')
            pds = fileStruct.PDS;
            
            
            epochs = sort_epochs(asarray(self.epochGroup.getEpochs()));
            
            i = 1;
            for e = 1:length(epochs)
                epoch = epochs{e};
                if(isempty(strfind(char(epoch.getProtocol().getName()), 'Intertrial')))
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
            
            import ovation.*;
            
            epochs = sort_epochs(asarray(self.epochGroup.getEpochs()));
            
            for i = 2:length(epochs)
                self.verifyEqual(epochs{i}.getStart().getMillis(),...
                    epochs{i-1}.getEnd().getMillis(), 'AbsTol', 500);
            end
        end
               
        function testEpochStartAndEndTimeShouldBeDeterminedByDataPixxTime(self)
            import ovation.*;
            warning('off')
            fileStruct = load(self.pdsFile, '-mat');
            warning('on')
            pds = fileStruct.PDS;
            
            epochs = sort_epochs(asarray(self.epochGroup.getEpochs()));
            
            datapixxmin = min(pds.datapixxstarttime);
            pdsIdx = 1;
            for i = 1:length(epochs)
                epoch = epochs{pdsIdx};
                if(~isempty(strfind(char(epoch.getProtocol().getName()), 'Intertrial')))
                    if(pdsIdx > 1)
                        self.verifyEqual(epoch.getStart(),...
                            self.epochGroup.getStart().plusMillis(1000*(pds.datapixxstoptime(pdsIdx-1) - datapixxmin)));
                        self.verifyEqual(epoch.getEnd(),...
                            self.epochGroup.getStart().plusMillis(1000*(pds.datapixxstarttime(pdsIdx) - datapixxmin)));
                    end
                else
                    self.verifyEqual(epoch.getStart(),...
                        self.epochGroup.getStart.plusMillis(1000*(pds.datapixxstarttime(pdsIdx) - datapixxmin)));
                    self.verifyEqual(epoch.getEnd(),...
                        self.epochGroup.getStart().plusMillis(1000*(pds.datapixxstoptime(pdsIdx) - datapixxmin)));
                    pdsIdx = pdsIdx + 1;
                end
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
            warning('off')
            fileStruct = load(self.pdsFile, '-mat');
            warning('on')
            pds = fileStruct.PDS;
            
            epochs = sort_epochs(asarray(self.epochGroup.getEpochs()));
            pdsIdx = 0;
            for n=1:length(epochs)
                epoch = epochs{n};
                if(~isempty(strfind(epoch.getProtocol().getName(), 'Intertrial')))
                    continue;
                end
                
                pdsIdx = pdsIdx + 1;
                
                props = epoch.getUserProperties(epoch.getOwner());
                self.assertTrue(props.containsKey('dataPixxStart_seconds'));
                self.assertTrue(props.containsKey('dataPixxStop_seconds'));
                self.assertTrue(props.containsKey('uniqueNumber'));
                self.assertTrue(props.containsKey('uniqueNumberString'));
                self.assertTrue(props.containsKey('trialNumber'));
                self.assertTrue(props.containsKey('goodTrial'));
                if(isfield(pds,'coherence'))
                    self.verifyTrue(epoch.getProtocolParameters().containsKey('coherence'));
                end
                if(isfield(pds,'chooseRF'))
                    self.verifyTrue(props.containsKey('chooseRF'));
                end
                if(isfield(pds,'timeOfChoice'))
                    self.verifyTrue(props.containsKey('timeOfChoice'));
                end
                if(isfield(pds,'timeOfReward'))
                    self.verifyTrue(props.containsKey('timeOfReward'));
                end
                if(isfield(pds,'timeOfFixation'))
                    self.verifyTrue(props.containsKey('timeBrokeFixation'));
                end
                if(isfield(pds,'correct'))
                    if(pds.correct(pdsIdx))
                        self.verifyTrue(epoch.getTags().values().contains('correct'));
                    end
                end 
            end
        end
        
        function testEpochShouldHaveResponseDataFromPDS(self)
            import ovation.*
            
            warning('off')
            fileStruct = load(self.pdsFile, '-mat');
            warning('on')
            pds = fileStruct.PDS;
            
            
            epochs = asarray(self.epochGroup.getEpochs().iterator());
            eyeTrackingEpoch = 1;
            for i=1:length(epochs)
                epoch = epochs(i);
                if(isempty(strfind(epoch.getProtocol().getName(), 'Intertrial')))
                    
                    rData = asnumeric(epoch.getMeasurement('Eye position'));
                    
                    self.verifyEqual(pds.eyepos{eyeTrackingEpoch}(:,1), rData.position_x);
                    self.verifyEqual(pds.eyepos{eyeTrackingEpoch}(:,2), rData.position_y);
                    self.verifyEqual(pds.eyepos{eyeTrackingEpoch}(:,3), rData.time);
                    
                    eyeTrackingEpoch = eyeTrackingEpoch + 1;
                end
                
            end
        end
        
        function testEpochProtocolParametersShouldHaveStimulusDeviceParameters(self)
            import matlab.unittest.constraints.*;
            
            warning('off')
            fileStruct = load(self.pdsFile, '-mat');
            warning('on')
            dv = fileStruct.dv;
            
            % Convert DV paired cells to a struct
            dv.bits = cell2struct(dv.bits(:,2)',...
                num2cell(strcat('bit_', num2str(cell2mat(dv.bits(:,1)))), 2)',...
                2);
            
            parametersMap = ovation.struct2map(dv.params);
            
            
            epochsItr = self.epochGroup.getEpochs().iterator();
            while(epochsItr.hasNext())
                epoch = epochsItr.next();
                
                keyItr = parametersMap.keySet().iterator();
                while(keyItr.hasNext())
                    key = keyItr.next();
                    if(isempty(parametersMap.get(key)))
                        continue;
                    end
                    if(isjava(parametersMap.get(key)))
                        assertJavaEqual(parametersMap.get(key),...
                            epoch.getProtocolParameters().get(key));
                        assertJavaEqual(parametersMap.get(key),...
                            epoch.getDeviceParameters().get(key));
                    else
                        self.verifyThat(parametersMap.get(key), ...
                            IsEqualTo(epoch.getProtocolParameters().get(key)));
                    end
                end
            end
            
            
        end
                
        function testEpochGroupShouldHavePDSStartTime(self)
            import ovation.*;
            warning('off')
            fileStruct = load(self.pdsFile, '-mat');
            warning('on')
            pds = fileStruct.PDS;
            
            idx = find(pds.datapixxstarttime == min(pds.datapixxstarttime));
            unum = pds.unique_number(idx(1),:);
            
            startTime = datetime(unum(1), unum(2), unum(3), unum(4), unum(5), unum(6), 0, self.timezone.getID());
            
            
            assertJavaEqual(self.epochGroup.getStart(),...
                startTime);
            
        end
    end
end