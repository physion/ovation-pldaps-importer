=============================
PL-DA-PS importer for Ovation
=============================


This project contains Matlab[1]_ code for importing `PL-DA-PS <http://hukdata.cps.utexas.edu/archive/PLDAPS.html>` data into the `Ovation Scientific Data Management System <http://ovation.io>`.


Basic Usage
-----------

To use the importer:

#. add the project directory to the Matlab path
#. Choose an Ovation ``Experiment`` object to insert data into. To create a ``Project`` and ``Experiment``::

    >> import ovation.*
    >> context = NewDataContext();
    >> project = context.insertProject(<project name>, <project purpose>, <project start date>);
    >> experiment = project.insertExperiment(<expt purpose>, <expt start date>);
#. Insert a PL-DA-PS ``.PDS`` file as an ``EpochGroup``::

    >> epochGroup = ImportPladpsPDS(experiment,...
        <path to PDS file>,...
        trialFunctionName,...
        experimentTimeZone)
        

#. Export spike sorting data from a ``.plx`` to a Matlab ``.mat`` file::
    
    >> plx2mat ??
    
#. Append ``DerivedResponses`` with spike times and spike waveforms to ``Epochs`` already in the database::

    >> ImportPladpsPlx(epochGroup,...
        plxFilePath,...
        expFilePath);

This step will will issue a warning ``Epochs`` in the plexon data are not already represented by ``Epoch`` instances in the Ovation database.


Automated tests
---------------

To run the automated test suite:

#. Add ``pldaps-importer`` folder to the Matlab path
#. Add Matlab xUnit test framework to the Matlab path
#. From within the ``pldaps-importer/test`` directory::
    
    >> runtestsuite
    


License
-------

Copyright (c) 2012-2013, Physion LLC
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


.. [1] Matlab is a registered trademark of The Mathworks, Inc..


