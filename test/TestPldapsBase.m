classdef TestPldapsBase < ovation.test.ClassFixtureTestCase
    
    properties(Constant)
        
        
        % We're tied to the test fixture defined by these files and values,
        % but this is the only dependency. There shouldn't be any magic numbers
        % in the test code.
        
        pdsFile = 'fixtures/jlyTest040212tmpdots1109.PDS';
        plxFile = 'fixtures/jlyTest040212tmpDots1103.mat';
        plxRawFile = 'fixtures/jlyTest040212tmpDots1103.plx';
        plxExpFile = 'fixtures/jlyTest040212tmpdots1109.exp';
        
        %         pdsFile = 'fixtures/jlyTest040212tmpSaccadeMapping1102.PDS';
        %         plxFile = 'fixtures/jlyTest040212tmpSaccadeMapping1103.mat';
        %         plxRawFile = 'fixtures/jlyTest040212tmpSaccadeMapping1103.plx';
        %         plxExpFile = 'fixtures/jlyTest040212tmpdots1109.exp';
        
        timezone = org.joda.time.DateTimeZone.forID('US/Central');
    end
    
    properties 
        epochGroup
    end
    
    methods
        
        function localFixture(self)
            import ovation.*;
            
            ctx = self.context;
            
            project = ctx.insertProject('TestImportMapping',...
                'TestImportMapping',...
                datetime());
            
            expt = project.insertExperiment('TestImportMapping',...
                datetime());
            
            source = ctx.insertSource('animal', 'animal-id');
            
            protocol = ctx.insertProtocol('PDS Protocol', 'TEST');
            interTrialProtocol = ctx.insertProtocol('PDS Intertrial Protocol', 'TEST');
            
            warning('off', 'ovation:import:plx:unique_number');
            
            % Import the PDS file
            tic;
            self.epochGroup = ImportPldapsPDS(expt,...
                source,...
                protocol,...
                interTrialProtocol,...
                self.pdsFile,...
                self.timezone);
            toc;
            self.epochGroup.addResource('edu.utexas.huk.pds', self.pdsFile);
            
            pdsStruct = load(self.pdsFile, '-mat');
            dv = pdsStruct.dv;
            
%             tic;
%             ImportPLX(self.epochGroup,...
%                 self.plxFile,...
%                 dv.bits,...
%                 self.plxRawFile,...
%                 self.plxExpFile);
%             toc;
            
            
        end
    end
end
