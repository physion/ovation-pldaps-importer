function assertJavaEqual(A, B, custom_message)
%assertJavaEqual Assert that inputs are equal
%   assertJavaEqual(A, B) throws an exception if A and B are not equal. 
%
%   assertJavaEqual(A, B, MESSAGE) prepends the string MESSAGE to the assertion
%   message if A and B are not equal.
%
%   Examples
%   --------
%   % This call returns silently.
%   assertJavaEqual(java.lang.String('abc'), java.lang.String('abc'));
%   
%   % This call throws an exception
%   assertJavaEqual(java.lang.String('abc'), java.lang.String('def'));


%   Barry Wark
%   Copyright 2012 Physion Consulting, LLC

    if nargin < 3
        custom_message = '';
    else
        custom_message = [custom_message '.'];
    end

    if (~A.equals(B))
        message = [custom_message ' Inputs are not equal. Expected: ' char(A.toString()) ' vs. Actual: ' char(B.toString())];
        throwAsCaller(MException('assertEqual:nonEqual', '%s', message));
    end
end
