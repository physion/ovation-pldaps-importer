function epoch = findEpochByUniqueNumber(epochGroup, uniqueNumber, varargin)
    
    import ovation.*
    
    if(nargin >= 3)
        uniqueNumberCache = varargin{1};
    else
        uniqueNumberCache = [];
    end
    
    epoch = [];
    if(isempty(epochGroup))
        return;
    end
    
    if(~isempty(uniqueNumberCache))
        if(uniqueNumberCache.uniqueNumber.containsKey(num2str(uniqueNumber)))
            epoch = uniqueNumberCache.uniqueNumber.get(num2str(uniqueNumber));
            return;
        elseif(uniqueNumberCache.truncatedUniqueNumber.containsKey(num2str(uniqueNumber)))
            epoch = uniqueNumberCache.truncatedUniqueNumber.get(num2str(uniqueNumber));
            warning('ovation:import:plx:unique_number', 'uniqueNumber appears to be 8-bit truncated');
            return;
        end
    end
    
    epochs = asarray(epochGroup.getEpochs());
    
    for i = 1:length(epochs)
        epoch = epochs(i);
        
        epochUniqueNumber = epoch.getUserProperty(epoch.getOwner(), 'uniqueNumber');
        if(~isempty(epochUniqueNumber))
            uNum = zeros(1, epochUniqueNumber.size());
            for j = 1:length(uNum)
                uNum(j) = epochUniqueNumber.get(j-1);
            end
            
            if(all(uNum == uniqueNumber))
                uniqueNumberCache.put(num2str(uNum), epoch);
                return;
            end
            
            if(all(mod(uNum,256) == uniqueNumber))
                warning('ovation:import:plx:unique_number', 'uniqueNumber appears to be 8-bit truncated');
                return;
            end
        end
        
    end
    
    epoch = [];
end