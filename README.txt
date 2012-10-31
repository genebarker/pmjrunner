#====================================================================
# Copyright 2012 State of Wyoming
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied. See the License for the specific language governing
# permissions and limitations under the License.
#====================================================================

README for pmjrunner - Poor Man's Job Runner
---------------------------------------------------------------------
pmjrunner executes a sequence of batch programs that have
dependencies between them. Use the -h option to display detailed
help and read the program description.

--- Setup ---
1. Verify system requirements in place, properly configured,
   and in the system path:
   [Linux]
   o Perl 5
   o mutt
   o dos2unix
   [Windows]
   o Active Perl 5 (activestate.com)
   o blat (blat.net)

2. Copy pmjrunner files to your system; preferably in its own
   directory. Linux users, run dos2unix on pmjrunner.pl to tidy its
   line-endings.

3. Create a directory for your job run definition. This is
   where pmjrunner will store each run's log files and the
   status of the current / last run.

4. Create a job run config file. Use winjob.cfg or linuxjob.cfg as a
   starting point. Setting descriptions:

   [Global for the job run]
   o JOB_RUN_NAME - Human readable name for job run
   o WORKING_DIR - Directory to run the job and store its results
     (same as the one created in Step 3)
   o LOG_ROTATION_COUNT - Maximum number of log runs to keep in the
     above directory before starting over with job run #1
   o EMAIL_SUBSCRIBERS - Comma separated list of email subscribers
     to the job run results - set to '' for none
   o BATCH_WINDOW_START / BATCH WINDOW_END - If a step in the run
     must be started within a batch window, set these parms with the
     window's start and end times (use hh:mm format, set both to
     '00:00' if not used)
   o SECONDS_BETWEEN_TRIES - If a step can be tried more than once,
     set this to how many seconds you want pmjrunner to wait between
     subsequent tries

   [Each step in the job run]
   o name - Human readable name for the step
   o execute_cmd - Exact text of the command to execute the step
     (program) from the WORKING_DIR
   o validate_cmd - Exact text of the command to execute from the
     WORKING_DIR to validate step completed successfully - set to ''
     for none
   o prereq_steps - Comma separated list of steps (their step #'s)
     that must be completed successfully before this step can be
     tried - set to '' for none
   o obey_batch_window - If the step may only be started within the
     batch window, set this to 'YES', otherwise 'NO'
   o max_tries - If you wish a step to be tried multiple times
     before giving-up, set this to that number. For most jobs, this
     is set to 1
   o stop_run_on_failure - If consequences of this step failing are
     so big, that you want to terminate the entire job run, set this
     to 'YES', otherwise 'NO'
   o email_log_file - If you need the terminal output of this step
     always sent to subscribers set this to 'YES', otherwise 'NO'
     (note: output of failed steps are always emailed)

5. Run pmjrunner using this config. For example:
   > perl pmjrunner.pl -n -f myjobrun.cfg

--- Version History ---
The code was designed and written by Eugene F. Barker with lots of
help from seasoned system admin's and developers of real-world high
volume production systems here at the State. A lot of their
knowledge is baked-in to pmjrunner's simple, yet powerful design.

v1.4.3 2012.10.26
o Fixed sort when listing all log files
o Fixed display log file option
o Tidied sample windows config file

v1.4.2 2012.10.10
o Add sort to status command output
o Corrected email syntax for multiple attachments
o Add dos2unix instruction to README

v1.4 2012.10.03
o Added a new WORKING_DIR setting to the job run config file
o Rewrote to require and use job run config supplied in the command
o Added directory and status file setup for new job runs
o Added job run log rotation option
o Added job run number padding so entries always list sequentially
o Added debug option with lots of print statements
o Rewrote status option to display contents of job run directory
o Changed linux mail client to mutt
o Changed body of result email to job run log (log.txt)
o Expanded and rewrote help
o Added README.txt with setup instructions and version history
o Added example job run config files: winjob.cfg & linuxjob.cfg
o Added Apache license information

v1.3 2012.08.27
o Optimized appending method used to create step log files
o Added dos2unix cleaning to step log files

v1.2 2012.08.20
o Changed name to avoid conflicts with several other programs
o Added job run step option to attach step's log file to the job run
  report email
o Updated report email to include log files for the failed steps
o Updated step log files to use .txt extension

v1.1 2011.01.18
o Added config file validation
o Added status file validation
o Improved comments / readability
o Added configurable seconds between retries delay
o Corrected batch window check bug
o Corrected program exit status unsuppressed warnings
o Updated help display to conform to command-line program standards

v1.0 2011.01.07
o Original version

.
.
.