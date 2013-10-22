function result = sort_epochs(epochs)
    startMillis = zeros(size(epochs));
    for i = 1:length(epochs)
        startMillis(i) = epochs(i).getStart().getMillis();
    end
    [~, sortIdx] = sort(startMillis);
    
    result = {};
    for i = 1:length(sortIdx)
        result{i} = epochs(sortIdx(i)); %#ok<AGROW>
    end
end
