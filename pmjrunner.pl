#!/usr/bin/perl
#-----------------------------------------------------------
# NAME:
#     pmjrunner - execute sequence of batch programs that
#                 have dependencies between them.
#
# SYNOPSIS:
#     perl pmjrunner.pl [options]
#
# DESCRIPTION:
#     pmjrunner is short for Poor Man's Job Runner. It's
#     designed to be used in combination with your OS's
#     default scheduler to provide for the intelligent
#     execution or restart of a sequence of batch programs
#     that have dependencies between them. Used in
#     combination with a tool like SSH, pmjrunner can
#     be used to execute a sequence of batch programs
#     across different nodes and OS's.
#
#     In pmjrunner, job runs are defined via a config
#     file. Each batch program is a step in the job run
#     definition. When pmjrunner executes the job run, the
#     terminal and error output of each step is logged to
#     ease issue diagnosis. Should a failure occur,
#     pmjrunner marks the step as failed, then moves on
#     and completes what it can skipping any dependent
#     steps. At the conclusion of the job run, the
#     results / failed steps are emailed to the job run's
#     email subscribers. Once the issue behind a failure
#     is resolved, the restart command can be used to
#     intelligently finish the job run. Restart
#     automatically skips completed steps, re-executes
#     failed steps, and executes any remaining skipped
#     steps.
#
#     To keep things simple, pmjrunner uses the job run's
#     working directory to store the job run's status and
#     its results. So the job run's status / results can
#     easily be monitored / reviewed by examining the
#     contents of this directory.
#
#     pmjrunner options:
#
#     -f CFGFILE, --file="CFGFILE"
#         Set the job run config file. This file defines
#         the job run's content, parameters, sequencing,
#         dependencies, and noticing. See the README and
#         example cfg's.
#
#     -n, --new
#         Start a new job run
#
#     -r, --restart
#         Restart the last job run and complete the
#         remaining steps
#
#     -x STEP#, --execute=STEP#,
#         Re-execute STEP# of the last job run
#
#     -w, --warnings
#         Override warnings (use with caution - be sure
#         that the pmjrunner process and its steps are no
#         longer running)
#
#     -i, --info
#         Display usage information [default]
#
#     -h, --help
#         Display detailed help
#
#     -l, --log
#         Display log file of the last / current job run
#
#     -s [STEP#], --status[=STEP#]
#         Display status of the last / current job run and 
#         log file for selected STEP# (* for all)
#
#     --debug
#         Display debug info (debug mode)
#
# RESOURCES:
#     The working directory for the job run is set in the
#     given CFGFILE. pmjrunner creates / uses the
#     following resources in that directory:
#
#     o jobruns          - Directory containing history of
#     |                    all job runs
#     +-o jobrun-[jobid] - Directory containing history of
#       |                  job run [jobid]
#       +-o log.txt      - File containing the event log
#       |                  for this job run
#       +-o step-[#]-[state].txt
#                        - File name indicates job step
#                          and its current state; file
#                          contains output of the job step
#     o .pmj-config.txt  - Contains copy of the last job
#                          run config file used
#     o .pmj-status.txt  - Contains info regarding the
#                          last attempted job run; used to
#                          validate job start / restart
#                          information
#     o .pmj-temp.txt    - Temp file used for capturing
#                          error output of each step
#
# NOTES:
#     o Written using Perl 5.10
#     o See example winjobrun.cfg and linuxjobrun.cfg
#       for job run configuration options
#     o See README file for setup instructions, design
#       notes, and version history
#
# COPYRIGHT:
#     Copyright 2012 State of Wyoming
#
#     Licensed under the Apache License, Version 2.0 (the "License");
#     you may not use this file except in compliance with the License.
#     You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#     Unless required by applicable law or agreed to in writing, software
#     distributed under the License is distributed on an "AS IS" BASIS,
#     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#     See the License for the specific language governing permissions and
#     limitations under the License.
#-----------------------------------------------------------                   
#-
# Set Perl options and modules used
#-
use strict;
use warnings;
use Cwd qw(getcwd abs_path);
use File::Copy;
use Getopt::Long qw(:config bundling);

#-
# Define local working directory file resources
#-
$main::LOG_FILE = "log.txt";
$main::CONFIG_FILE = ".pmj-config.txt";
$main::STATUS_FILE = ".pmj-status.txt";
$main::TMP_FILE = ".pmj-temp.txt";
$main::MAX_JOB_RUN = 999999;

#-
# Set command line options
#-
my $opt_f; my $opt_n; my $opt_r; my $opt_x; my $opt_w; my $opt_i; my $opt_h; my $opt_l; my $opt_s = "null"; my $debug;
my $options = GetOptions(
		"f|file=s" => \$opt_f,
		"n|new" => \$opt_n,
		"r|restart" => \$opt_r,
		"x|execute=s" => \$opt_x,
		"w|warnings" => \$opt_w,
		"i|info" => \$opt_i,
		"h|help" => \$opt_h,
		"l|log" => \$opt_l,
		"s|status:s" => \$opt_s,
		"debug" => \$debug,
	);

#-
# Parse command line arguments
#-
print "\npmjrunner v1.4.3\n";
print "(c)2012 State of Wyoming\n";
print "Licensed under the Apache License, Version 2.0\n";
if ($debug) { print "info: --debug (display debug info) option selected.\n"; }
if ($opt_w and $debug) { print "info: --warnings (override warnings) option selected.\n"; }
if ($opt_i) {
	if ($debug) { print "info: --info (display usage information) option selected.\n"; }
	display_usage_info();
	exit(0);
}

if ($opt_h) {
	if ($debug) { print "info: --help (display detailed help) option selected.\n"; }
	display_header();
	exit(0);
}

# remainder of options require config file for job run
# so try to process...
if ($opt_f) {
	if ($debug) { print "info: --file=\"$opt_f\" (set job run config file) option selected.\n"; }
	# verify that file exists and readable
	if (-e $opt_f and $debug) {	print "info: config file ($opt_f) for job run found.\n"; }
	if (not -r $opt_f) { die "error: config file ($opt_f) is not readable."; }
	if (not -T $opt_f) { die "error: config file ($opt_f) is not a regular text file."; }
} else {
	print "error: missing required options, see following usage information.\n";
	display_usage_info();
	exit(1);
}

# execute config file to set job run parm's
do $opt_f;
if ($debug) { print "info: job run config file loaded.\n"; }
validate_config();
if ($debug) { print "info: job run config file validated.\n"; }
$main::TOTAL_STEPS = scalar(@main::STEPS);

# store away path of the config
my $cfg_file_fqn = abs_path($opt_f) or die "error: unable to determine config file's fully qualified name... $!";
if ($debug) { print "info: retrieved config file's fully qualified name (" . $cfg_file_fqn . ").\n"; }

# set and get job run's working directory
chdir $main::WORKING_DIR or die "error: unable to set working directory ($main::WORKING_DIR)... $!";
if ($debug) { print "info: working directory set (" . getcwd() . ").\n"; }

# copy config file to job run's working dir
copy($cfg_file_fqn, $main::CONFIG_FILE) or die "error: unable to copy config file... $!";
if ($debug) { print "info: config file copied to working directory (" . $main::CONFIG_FILE . ").\n"; }

# check for job run status file in directory
if (-e $main::STATUS_FILE) {
	if ($debug) { print "info: status file ($main::STATUS_FILE) for job run found.\n"; }
	# verify that file readable
	if (not -r $main::STATUS_FILE) { die "error: status file ($main::STATUS_FILE) is not readable."; }
	if (not -w $main::STATUS_FILE) { die "error: status file ($main::STATUS_FILE) is not writable."; }
	if (not -T $main::STATUS_FILE) { die "error: status file ($main::STATUS_FILE) is not a regular text file."; }
} else {
	# new job run directory, so create a new job run status file
	open STATUS, '>', $main::STATUS_FILE or die "error: can't create status file ($main::STATUS_FILE)... $!";
	print STATUS "#-----------------------------------------------------------\n";
	print STATUS "# pmjrunner job run status file (DO NOT EDIT)\n";
	print STATUS "#\n";
	print STATUS "# This file is used to validate the start / restart of job\n";
	print STATUS "# runs.\n";
	print STATUS "#-----------------------------------------------------------\n";
	print STATUS "# Last / current job run status\n";
	print STATUS '$Job_Run_ID = ' . "0;\n";
	print STATUS '$Job_Run_Status = ' . "'NEW';\n";
	print STATUS "\n";
	print STATUS "# Last / current step in job run\n";
	print STATUS '$Step_Num = ' . "0;\n";
	print STATUS '$Step_Name = ' . "'';\n";
	print STATUS '$Step_Try_Num = ' . "1;\n";
	close(STATUS);
	if ($debug) { print "info: status file ($main::STATUS_FILE) created.\n"; }
}

# execute the status file to get last job run's status
do $main::STATUS_FILE;
if ($debug) { print "info: status file loaded.\n"; }
validate_status();
if ($debug) { print "info: status file validated.\n"; }

if ($opt_l) {
	if ($debug) { print "info: --log (display log file of the last / current job run)\n"; }
	if ($main::Job_Run_Status eq 'NEW') {
		die "error: this job run has not been executed, so there is no log to display.";
	}
	# setup sub directory for this particular job run
	$main::Job_Run_Dir = derive_jobrun_dirname();
	display_log();
	exit(0);
}

if ($opt_s ne 'null') {
	if ($opt_s eq '') {
		if ($debug) { print "info: --status (display status of the last / current job run)\n" };
	} elsif ($opt_s eq '*') {
		if ($debug) { print "info: --status=$opt_s (display status of the last / current job run and log files for all steps)\n"; }
	} elsif ($opt_s =~ /^\d+$/ and $opt_s > 0 and $opt_s <= $main::TOTAL_STEPS) {
		if ($debug) { print "info: --status=$opt_s (display status of the last / current job run and log file for selected step)\n"; }
	} else {
		die "error: invalid step number for this job run (must be 1 to $main::TOTAL_STEPS).";
	}
	if ($main::Job_Run_Status eq 'NEW') {
		die "error: this job run has not been executed, so there is no status to display.";
	}
	# setup sub directory for this particular job run
	$main::Job_Run_Dir = derive_jobrun_dirname();
	display_status();
	exit(0);
}

if ($opt_n) {
	if ($debug) { print "info: --new (start a new job run)\n"; }
	start_new_job_run();
} elsif ($opt_r) {
	if ($debug) { print "info: --restart (restart last job run)\n"; }
	restart_job_run();
} elsif ($opt_x) {
	if ($opt_x =~ /^\d+$/ and $opt_x > 0 and $opt_x <= $main::TOTAL_STEPS) {
		if ($debug) { print "info: --execute=$opt_x (re-execute step of the last job run)\n"; }
		execute_one_step();
	} else {
		die "error: invalid step number for this job run (must be 1 to $main::TOTAL_STEPS).";
	}
} else {
	print "info: no action selected, so display usage information.\n";
    display_usage_info();
}

exit(0);

#-
# Start new job run
#-
sub start_new_job_run {
	# make sure previous job run finished or is being overriden
	if ($main::Job_Run_ID) {
		if ($debug) { print "info: previous job run #$main::Job_Run_ID status is $main::Job_Run_Status.\n"; }
		if ($main::Job_Run_Status eq 'RUNNING') {
			print "warning: previous job run #$main::Job_Run_ID is still running or stalled.\n";
			if (not $opt_w) {
				die "error: new job run not started, use -w option to override warning and run anyways.\n";
			}
			if ($debug) { print "info: override warning and continue.\n"; }
		} elsif ($main::Job_Run_Status eq 'FAILED') {
			print "warning: previous job run #$main::Job_Run_ID did not complete successfully.\n";
			if (not $opt_w) {
				die "error: new job run not started, use -w option to override warning and run anyways.\n";
			}
			if ($debug) { print "info: override warning and continue.\n"; }
		}
	}

	# check if time to rollover job run count
	$main::Job_Run_ID++;
	if ($main::Job_Run_ID > $main::LOG_ROTATION_COUNT) {
		$main::Job_Run_ID = 1;
		if ($debug) { print "info: exceeded max job run count ($main::LOG_ROTATION_COUNT), so rolling-over to job run #1.\n"; }
	}
	# create root directory for job run logs if neccessary
	if (not -d "jobruns") {
		mkdir "jobruns" or die "error: can't create (jobruns) directory... $!";
		if ($debug) { print "info: created (jobruns) history directory.\n"; }
	}
	# setup sub directory for this particular job run
	$main::Job_Run_Dir = derive_jobrun_dirname();
	if (-not -d $main::Job_Run_Dir) {
		# setup new directory
		mkdir $main::Job_Run_Dir or die "error: can't create directory ($main::Job_Run_Dir) for this job run... $!";
		if ($debug) { print "info: created directory ($main::Job_Run_Dir) for this job run.\n"; }
	} else {
		# recycle existing directory
		if ($debug) { print "info: log rotation detected for ($main::Job_Run_Dir).\n"; }
		# delete the old files
		my @old_files = <$main::Job_Run_Dir/*.*>;
		if (@old_files > 0) {
			unlink @old_files or die "error: can't remove old files... $!";
			if ($debug) { print "info: removed (" . scalar(@old_files) . ") old files from this job run's directory.\n"; }
		}
	}
	my $mkdir_time = localtime();

	# create job run log and step files
	open LOGFILE, '>', "$main::Job_Run_Dir/$main::LOG_FILE" or die "error: can't create log file for job run... $!";
	print LOGFILE "#-----------------------------------------------------------\n";
	print LOGFILE "# $main::JOB_RUN_NAME\n";
	print LOGFILE "# job run #$main::Job_Run_ID\n";
	print LOGFILE "#-----------------------------------------------------------\n";
	print LOGFILE $mkdir_time . ": job run directory ($main::Job_Run_Dir) initialized\n";
	print LOGFILE $mkdir_time . ": job run log file ($main::LOG_FILE) created\n";
	close LOGFILE;
	if ($debug) { print "info: created / initialized main job run log file ($main::LOG_FILE).\n"; }

	for (my $i = 1; $i <= $main::TOTAL_STEPS; $i++) {
		my $step_filename = derive_step_filename($i, 'QUEUED');
		open STEPFILE, ">$step_filename" or die "error: can't create step status file(s) for job run... $!";
		close STEPFILE;
	}
	append_to_log("job run step status files created");
	if ($debug) { print "info: created / initialized the ($main::TOTAL_STEPS) job run step status files.\n"; }

	# initialize job run status file for new job
	$main::Job_Run_Status = "RUNNING";
	$main::Step_Num = 1;
	$main::Step_Name = "";
	$main::Step_Try_Num = 0;
	update_status();
	append_to_log("job run status file ($main::STATUS_FILE) initialized for new job run");
	if ($debug) { print "info: initialized job run status file for this new job run.\n"; }

	# execute a new job run
	execute_job_run();
}

#-
# Restart last job run
#-
sub restart_job_run {
	# make sure previous job finished or is being overriden
	if ($main::Job_Run_ID) {
		if ($debug) { print "info: previous job run #$main::Job_Run_ID status is $main::Job_Run_Status.\n"; }
		if ($main::Job_Run_Status eq 'RUNNING') {
			print "warning: previous job run #$main::Job_Run_ID is still running or stalled.\n";
			if (not $opt_w) {
				die "error: job run not restarted, use -w option to override warning and restart anyways.";
			}
			if ($debug) { print "info: override warning and continue.\n"; }
		} elsif ($main::Job_Run_Status eq 'SUCCEEDED') {
			die 'error: can not restart a successfully completed job run.';
		}
	} else {
		die 'error: no job run to restart.';
	}
	
	# set directory for job run
	$main::Job_Run_Dir = derive_jobrun_dirname();
	my $mkdir_time = localtime();

	# update job run log
	open LOGFILE, '>>', "$main::Job_Run_Dir/$main::LOG_FILE" or die "error: can't create log file for job run... $!";
	print LOGFILE "#-----------------------------------------------------------\n";
	print LOGFILE "# $main::JOB_RUN_NAME\n";
	print LOGFILE "# job run #$main::Job_Run_ID\n";
	print LOGFILE "#-----------------------------------------------------------\n";
	print LOGFILE $mkdir_time . ": job run restarted\n";
	close LOGFILE;
	if ($debug) { print "info: appended restart information to main job run log file ($main::LOG_FILE).\n"; }

	# initialize job run status file for restart job
	$main::Job_Run_Status = "RUNNING";
	$main::Step_Num = 1;
	$main::Step_Name = "";
	$main::Step_Try_Num = 0;
	update_status();
	append_to_log("job run status file ($main::STATUS_FILE) initialized for job restart");
	if ($debug) { print "info: initialized job run status file for this restarted job run.\n"; }

	# restart the last job run
	execute_job_run();
}

#-
# Re-execute one step of last job run
#-
sub execute_one_step {
	# make sure previous job finished or is being overriden
	if ($main::Job_Run_ID) {
		if ($debug) { print "info: previous job run #$main::Job_Run_ID status is $main::Job_Run_Status.\n"; }
		if ($main::Job_Run_Status eq 'RUNNING') {
			print "warning: previous job run #$main::Job_Run_ID is still running or stalled.\n";
			if (not $opt_w) {
				die "error: step not re-executed, use -w option to override warning and re-execute step anyways.\n";
			}
			if ($debug) { print "info: override warning and continue.\n"; }
		} elsif ($main::Job_Run_Status eq 'SUCCEEDED'){
			die 'error: can not re-execute step of a successfully completed job run.';
		}
	} else {
		die 'error: no job run to re-execute step.';
	}

	# set directory for job run
	$main::Job_Run_Dir = derive_jobrun_dirname();
	my $mkdir_time = localtime();

	# update job run log
	open LOGFILE, '>>', "$main::Job_Run_Dir/$main::LOG_FILE" or die "error: can't create log file for job run... $!";
	print LOGFILE "#-----------------------------------------------------------\n";
	print LOGFILE "# $main::JOB_RUN_NAME\n";
	print LOGFILE "# job run #$main::Job_Run_ID\n";
	print LOGFILE "#-----------------------------------------------------------\n";
	print LOGFILE $mkdir_time . ": manually re-executing step #$opt_x of job run\n";
	close LOGFILE;
	if ($debug) { print "info: appended re-execute information to main job run log file ($main::LOG_FILE).\n"; }

	# initialize job run status file for restart job
	$main::Job_Run_Status = "RUNNING";
	$main::Step_Num = $opt_x;
	$main::Step_Name = "";
	$main::Step_Try_Num = 0;
	update_status();
	append_to_log("job run status file ($main::STATUS_FILE) initialized");
	if ($debug) { print "info: initialized job run status file for this re-execute step attempt.\n"; }

	# re-execute the job run step
	execute_job_run();
}

#-
# Execute job run
#-
sub execute_job_run {
	# how to reference step info
	# $main::STEPS[index]{key};

	# primary job run loop (processes one step at a time)
	while ($main::Job_Run_Status eq 'RUNNING') {
		# The following var's must be set before looping
		# o $main::Step_Num - step to run
		# o $main::Step_Try_Num - number of trys attempted so far (in this loop)

		# set step index to correspond with step num
		my $step_idx = $main::Step_Num - 1;
		
		# set the step name
		$main::Step_Name = $main::STEPS[$step_idx]{name};

		# get current list of step statuses
		my @files = <$main::Job_Run_Dir/step-*>;
		@main::statuses = ();
		for my $file (@files) {
			my $step_n_stat = $file;
			$step_n_stat =~ s/.*step-\d*-//; # strip leading ch's of filename to get the status
			$step_n_stat =~ s/\.txt//; # strip trailing '.txt' from filename
			my $step_n_num = $file;
			$step_n_num =~ s/.*step-//; # strip leading ch's of filename to get the number
			$step_n_num =~ s/-.*//; # strip ch's trailing the number
			$main::statuses[$step_n_num - 1] = $step_n_stat; 
		}
		
		# check if pre-requisite steps are complete
		my $prereq_complete;
		if ($main::STEPS[$step_idx]{prereq_steps} eq '') {
			$prereq_complete = 1;
		} else {
			$prereq_complete = 1;
			# parse prereq_steps string into array of integers
			my @prereqs = split (/,|,\s*/, $main::STEPS[$step_idx]{prereq_steps});
			# make sure each prereq step has completed
			for my $prereq (@prereqs) {
				if ($main::statuses[$prereq - 1] ne 'SUCCEEDED') {
					$prereq_complete = 0;
					last;
				}
			}
		}
		
		# check if step complies with batch window
		my $inside_batch_window;
		if ($main::STEPS[$step_idx]{obey_batch_window} eq 'YES') {
			# calculate time now in min's
			my @now = localtime();
			my $nowmin = ($now[2] * 60) + $now[1];
			# calculate batch win start in min's
			my $startmin;
			my $tmp = $main::BATCH_WINDOW_START;
			$tmp =~ s/:.*//;
			$startmin = ($tmp + 0) * 60;
			$tmp = $main::BATCH_WINDOW_START;
			$tmp =~ s/^\d{1,2}://;
			$startmin += ($tmp + 0);
			# calculate batch win end in min's
			my $endmin;
			$tmp = $main::BATCH_WINDOW_END;
			$tmp =~ s/:.*//;
			$endmin = ($tmp + 0) * 60;
			$tmp = $main::BATCH_WINDOW_END;
			$tmp =~ s/^\d{1,2}://;
			$endmin += ($tmp + 0);
			# determine if in batch window
			if ($endmin == $startmin) {
				# in window if values are equal
				$inside_batch_window = 1;
			} elsif ($endmin < $startmin) {
				# check when window crosses days (i.e. 10pm - 2am)
				if ($nowmin >= $startmin or $nowmin < $endmin) {
					$inside_batch_window = 1;
				} else {
					$inside_batch_window = 0;
				}
			} else {
				# check when window occurs on same day
				if ($nowmin >= $startmin and $nowmin < $endmin) {
					$inside_batch_window = 1;
				} else {
					$inside_batch_window = 0;
				}
			}
		} else {
			$inside_batch_window = 1;
		}
		# process the current step
		append_to_log("processing step #$main::Step_Num [$main::STEPS[$step_idx]{name}]");
		if ($main::statuses[$step_idx] eq 'SUCCEEDED') {
			append_to_log("step #$main::Step_Num SKIPPED since step was completed successfully previously");
			update_status();
		} elsif (not $prereq_complete) {
			append_to_log("step #$main::Step_Num BLOCKED since prerequisite steps are incomplete");
			my $oldfilename = derive_step_filename($main::Step_Num, $main::statuses[$step_idx]);
			my $newfilename = derive_step_filename($main::Step_Num, 'BLOCKED');
			rename $oldfilename, $newfilename;
			update_status();
			$main::statuses[$step_idx] = 'BLOCKED';
		} elsif (not $inside_batch_window) {
			append_to_log("step #$main::Step_Num BLOCKED since it can not be executed inside the batch window");
			my $oldfilename = derive_step_filename($main::Step_Num, $main::statuses[$step_idx]);
			my $newfilename = derive_step_filename($main::Step_Num, 'BLOCKED');
			rename $oldfilename, $newfilename;
			update_status();
			$main::statuses[$step_idx] = 'BLOCKED';
		} else {
			$main::Step_Try_Num++;
			update_status();
			# update step status filename
			my $oldfilename = derive_step_filename($main::Step_Num, $main::statuses[$step_idx]);
			my $newfilename = derive_step_filename($main::Step_Num, 'RUNNING');
			rename $oldfilename, $newfilename;
			# prepare system command string
			my $step_successful = 0;
			# update step status file
			if ($main::Step_Try_Num == 1) {
				append_to_log("executing step #$main::Step_Num");
				open STEPFILE, ">$newfilename";
			} else {
				if ($main::SECONDS_BETWEEN_TRIES > 0) {
					append_to_log("waiting ($main::SECONDS_BETWEEN_TRIES) seconds before re-try");
					sleep $main::SECONDS_BETWEEN_TRIES;
				}
				append_to_log("re-trying step #$main::Step_Num");
				open STEPFILE, ">>$newfilename";
			}
			print STEPFILE getcwd() . ">$main::STEPS[$step_idx]{execute_cmd}\n";
			# execute the command and attach output to step file
			my $cmdoutput = `$main::STEPS[$step_idx]{execute_cmd} 2>$main::TMP_FILE`;
			print STEPFILE $cmdoutput;
			# get error output if any and append to step status file
			open TMPFILE, $main::TMP_FILE;
			while (<TMPFILE>) {
				print STEPFILE $_;
			}
			close TMPFILE;
			close STEPFILE;
			if ($? == 0) {
				# check if validation needed
				if ($main::STEPS[$step_idx]{validate_cmd} eq '') {
					$step_successful = 1;
				} else {
					# execute the validation
					append_to_log("validating step #$main::Step_Num");
					$oldfilename = $newfilename;
					$newfilename = derive_step_filename($main::Step_Num, 'VALIDATING');
					rename $oldfilename, $newfilename;
					open STEPFILE, ">>$newfilename";
					print STEPFILE getcwd() . ">$main::STEPS[$step_idx]{validate_cmd}\n";
					$cmdoutput = `$main::STEPS[$step_idx]{validate_cmd} 2>$main::TMP_FILE`;
					print STEPFILE $cmdoutput;
					# get error output if any and append to step status file
					open TMPFILE, $main::TMP_FILE;
					while (<TMPFILE>) {
						print STEPFILE $_;
					}
					close TMPFILE;
					close STEPFILE;
					if ($? == 0) {
						$step_successful = 1;
					}
				}
			}
			# for linux platform, use dos2unix to clean step file
			if ($^O ne 'MSWin32') {
				$cmdoutput = `dos2unix -k $newfilename`;
			}
			# check result of step execution & validation
			if ($step_successful) {
				append_to_log("step #$main::Step_Num SUCCEEDED");
				$oldfilename = $newfilename;
				$newfilename = derive_step_filename($main::Step_Num, 'SUCCEEDED');
				rename $oldfilename, $newfilename;
				$main::statuses[$step_idx] = 'SUCCEEDED';
			} else {
				append_to_log("step #$main::Step_Num FAILED (see step status file for detail)");
				$oldfilename = $newfilename;
				$newfilename = derive_step_filename($main::Step_Num, 'FAILED');
				rename $oldfilename, $newfilename;
				$main::statuses[$step_idx] = 'FAILED';
			}
		}

		# get count of step statuses
		my $succeeded = 0;
		foreach my $status (@main::statuses) {
			if ($status eq 'SUCCEEDED') { $succeeded++; }
		}
		
		# check if step should be retried
		if ($main::statuses[$step_idx] eq 'FAILED' && $main::Step_Try_Num < $main::STEPS[$step_idx]{max_tries}) {
			# continue loop (try same step again)
		}
		
		# check if job run should be stopped
		elsif (($main::statuses[$step_idx] eq 'FAILED' or $main::statuses[$step_idx] eq 'BLOCKED') && $main::STEPS[$step_idx]{stop_run_on_failure} eq 'YES') {
			my $endnote = "job run FAILED (job run stopped mid-run since step #$main::Step_Num $main::statuses[$step_idx])";
			append_to_log($endnote);
			$main::Job_Run_Status = 'FAILED'; # terminates loop
			update_status();
			if (send_email("$main::JOB_RUN_NAME (job run #$main::Job_Run_ID) FAILED", derive_jobrun_dirname() . "/$main::LOG_FILE", build_logfile_list())) {
				if ($debug) { print "info: email sent to subscribers.\n"; }
			} else {
				append_to_log("WARNING: job run result email request failed");
				print "warning: email send request failed.\n";
			}
			print "RESULT: " . $endnote . ".\n";
		}
		
		# check if job run completed successfully
		elsif ($succeeded == $main::TOTAL_STEPS and ($main::Step_Num == $main::TOTAL_STEPS or $opt_x)) {
			my $endnote = "job run SUCCEEDED (all $main::TOTAL_STEPS steps completed successfully)";
			append_to_log($endnote);
			$main::Job_Run_Status = 'SUCCEEDED'; # terminates loop
			update_status();
			if (send_email("$main::JOB_RUN_NAME (job run #$main::Job_Run_ID) SUCCEEDED", derive_jobrun_dirname() . "/$main::LOG_FILE", build_logfile_list())) {
				if ($debug) { print "info: email sent to subscribers.\n"; }
			} else {
				append_to_log("WARNING: job run result email request failed");
				print "warning: email send request failed.\n";
			}
			print "RESULT: " . $endnote . ".\n";
		}
		
		# check if job run completed with failures
		elsif ($main::Step_Num == $main::TOTAL_STEPS or $opt_x) {
			my $endnote = "job run FAILED ($succeeded of $main::TOTAL_STEPS steps completed successfully)";
			append_to_log($endnote);
			$main::Job_Run_Status = 'FAILED'; # terminates loop
			update_status();
			if (send_email("$main::JOB_RUN_NAME (job run #$main::Job_Run_ID) FAILED", derive_jobrun_dirname() . "/$main::LOG_FILE", build_logfile_list())) {
				if ($debug) { print "info: email sent to subscribers.\n"; }
			} else {
				append_to_log("WARNING: job run result email request failed");
				print "warning: email send request failed.\n";
			}
			print "RESULT: " . $endnote . ".\n";
		}
		
		# move on to next step
		else {
			$main::Step_Num++;
			$main::Step_Try_Num = 0;
			# continue loop
		}
	}
}

#-
# Display program help
#-
sub display_usage_info {
	print "\nUsage: perl pmjrunner.pl [options]\n";
	print "  -f CFGFILE  set job run config file\n";
	print "  -n          start a new job run\n";
	print "  -r          restart the last job run\n";
	print "  -x STEP#    re-execute step of the last job run\n";
	print "  -w          override start / restart warnings\n";
	print "  -i          display usage information\n";
	print "  -h          display detailed help\n";
	print "  -l          display log file of last / current job run\n";
    print "  -s [STEP#]  display status of last / current job run and\n";
    print "              log file for selected step (* for all)\n";
    print "  --debug     display debug information\n";
}

#-
# Display log file for the last/current job run
#-
sub display_log {
	my $logfile = abs_path($main::Job_Run_Dir) . "/" . $main::LOG_FILE;
	print "\n";
	open(LOGFILE, $logfile) or die("error: can't open $logfile... $!");
	while (<LOGFILE>) {
		print $_;
	}
	close(LOGFILE);
}

#-
# Display status of the last/current job run
#-
sub display_status {
	my $dirpath = abs_path($main::Job_Run_Dir);
	opendir(DIR, $dirpath) or die("error: can't open last / current job run's directory ($dirpath)... $!");
	print "\n";
	print "#-----------------------------------------------------------\n";
	print "# pmjrunner status\n";
	print "# job name    : $main::JOB_RUN_NAME\n";
	print "# job run #   : $main::Job_Run_ID\n";
	print "# job status  : $main::Job_Run_Status\n";
	print "# as found in : $dirpath\n";
	print "#-----------------------------------------------------------\n";
	foreach my $file (sort readdir(DIR)) {
		if ($file =~ /\.txt$/) { print "$file\n" };
	}
	closedir(DIR);
	# check if contents of step log file option used
	if ($opt_s ne '') {
		my $repattern = '';
		if ($opt_s eq '*') {
			$repattern = '^step-\d+-.+\.txt$';
		} else {
			my $digit = length($main::TOTAL_STEPS);
			$repattern = '^step-' . sprintf("%0${digit}d", int($opt_s)) . '-.+\.txt$';
		}
		opendir(DIR, $dirpath) or die("error: can't open last / current job run's directory ($dirpath)... $!");
		foreach my $file (sort readdir(DIR)) {
			if ($file =~ /$repattern/) {
				print "\n";
				open my $STEPFILE, '<', "$dirpath/$file" or die("error: can't open step log file... $!");
				print "#-----------------------------------------------------------\n";
				print "# log file for : $file\n";
				print "#-----------------------------------------------------------\n";
				while (my $line = <$STEPFILE>) {
					print $line;
				}
				close($STEPFILE);
			}
		}
		closedir(DIR);
	}
}

#-
# Update status file
#-
sub update_status {
	# read in status file
	open STATUS, $main::STATUS_FILE or update_status_error("error: can't read job run status file ($main::STATUS_FILE)... $!");
	my @lines = <STATUS>;
	close(STATUS);
	# overwrite status file with current status values
	open STATUS, ">$main::STATUS_FILE" or update_status_error("error: can't update job run status file ($main::STATUS_FILE)... $!");
	foreach my $line (@lines) {
		if	  ($line =~ '^\$Job_Run_ID\s=')		{ $line = '$Job_Run_ID = ' . "$main::Job_Run_ID;\n"; }
		elsif ($line =~ '^\$Job_Run_Status\s=') { $line = '$Job_Run_Status = \'' . "$main::Job_Run_Status';\n"; }
		elsif ($line =~ '^\$Step_Num\s=')		{ $line = '$Step_Num = ' . "$main::Step_Num;\n"; }
		elsif ($line =~ '^\$Step_Name\s=')		{ $line = '$Step_Name = \'' . "$main::Step_Name';\n"; }
		elsif ($line =~ '^\$Step_Try_Num\s=')	{ $line = '$Step_Try_Num = ' . "$main::Step_Try_Num;\n"; }
		print STATUS $line;
	}
	close(STATUS);

	#-
	# Deal with fatal error while updating status
	#-
	sub update_status_error {
		foreach my $line (@_) {
			append_to_log($line);
			print "$line\n";
		}
		my $msg = "Fatal error - job run aborted.";
		append_to_log($msg);
		print "$msg\n";
		exit(1);
	}
}

#-
# Derive job run directory name
#-
sub derive_jobrun_dirname {
	my $digits = length($main::LOG_ROTATION_COUNT);
	my $paddednum = sprintf("%0${digits}d", $main::Job_Run_ID);
	return "./jobruns/jobrun-$paddednum";
}

#-
# Derive step status file name
#-
sub derive_step_filename ($$) {
	my $digits = length($main::TOTAL_STEPS);
	my $paddednum = sprintf("%0${digits}d", $_[0]);
	return "$main::Job_Run_Dir/step-$paddednum-$_[1].txt";
}

#-
# Append to log
#-
sub append_to_log {
	open LOGFILE, ">>$main::Job_Run_Dir/$main::LOG_FILE";
	foreach my $line (@_) {
		my $text = localtime() . ": $line";
		print LOGFILE "$text\n";
		if ($debug) { print "info: append to log ($text).\n"; }
	}
	close LOGFILE;
}

#-
# Build log file list (CSV)
#-
sub build_logfile_list {
	# determine which step log files to include
	my $list = '';
	for (my $step_i = 0; $step_i < $main::TOTAL_STEPS; $step_i++) {
		my $step_status = $main::statuses[$step_i];
		if ($step_status eq 'FAILED' or ($step_status eq 'SUCCEEDED' and $main::STEPS[$step_i]{email_log_file} eq 'YES')) {
			$list = $list . "," . derive_step_filename($step_i + 1, $step_status);
		}
	}
	# strip leading comma from list
	$list =~ s/^,//g;
	return $list;
}

#-
# Send email
# $_[0] - subject
# $_[1] - message body text filename
# $_[2] - attachment filenames, comma separated (optional)
#-
sub send_email ($$;$) {
	# return if no subscribers
	if ($main::EMAIL_SUBSCRIBERS eq '') {
		if ($debug) { print "info: no email subscribers, so no email sent.\n"; }
		return;
	}
	my $tolist = $main::EMAIL_SUBSCRIBERS;
	# strip excess spaces from subscriber list
	$tolist =~ s/\s+//g;
	if ($debug) { print "info: list of email subscribers set ($tolist).\n"; }
	# determine command string to send mail
	my $cmd;
	if ($^O eq 'MSWin32') {
		# Windows program blat.exe
		my $bodyfile = $_[1];
		$bodyfile =~ s/\/+/\\/g; # adjust file's path to windows form
		$cmd = "blat \"$bodyfile\" -t $tolist -s \"$_[0]\"";
		if (defined $_[2] and $_[2] ne '') {
			my $filelist = $_[2];
			$filelist =~ s/\/+/\\/g; # adjust file's path to windows form
			$cmd = $cmd . " -attach \"$filelist\"";
		}
	} else {
		# assume standard Linux mutt program
		if (defined $_[2] and $_[2] ne '') {
			my $filelist = $_[2];
			$filelist =~ s/,/ -a /g;
			$cmd = "mutt -s \"$_[0]\" -a $filelist -- $tolist < \"$_[1]\"";
		} else {
			$cmd = "mutt -s \"$_[0]\" -- $tolist < \"$_[1]\"";
		}
	}
	# send the email
	if ($debug) { print "info: email command constructed ($cmd).\n"; }
	`$cmd`;
	if ($? == 0) {
		return(1); # success
	} else {
		return(0); # fail
	}
}

#-
# Validate configuration file is well formed
#-
sub validate_config {
	my $e1 = "error: bad config file ($opt_f) - ";
	if (not defined $main::JOB_RUN_NAME or not $main::JOB_RUN_NAME =~ /\w/) {
		die($e1 . '$JOB_RUN_NAME must be set to a non-empty alphanumeric string.');
	}
	if (not defined $main::WORKING_DIR or not -d $main::WORKING_DIR) {
		die($e1 . '$WORKING_DIR must be set to a valid directory.');
	}
	if (not defined $main::LOG_ROTATION_COUNT or not $main::LOG_ROTATION_COUNT =~ /^\d+$/ or
		$main::LOG_ROTATION_COUNT < 1 or $main::LOG_ROTATION_COUNT > $main::MAX_JOB_RUN) {
		die($e1 . '$LOG_ROTATION_COUNT must be set to a positive number (from 1 to ' . $main::MAX_JOB_RUN. ').');
	}
	if (not defined $main::EMAIL_SUBSCRIBERS or ($main::EMAIL_SUBSCRIBERS ne '' and not $main::EMAIL_SUBSCRIBERS =~ /^([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}){1}([,]\s*[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4})*$/)) {
		die($e1 . '$EMAIL_SUBSCRIBERS must be set to a comma separated list of valid email addresses OR \'\' for no subscribers.');
	}
	if (not defined $main::BATCH_WINDOW_START or not defined $main::BATCH_WINDOW_END or
		not $main::BATCH_WINDOW_START =~ /^\d{2}:\d{2}$/ or not $main::BATCH_WINDOW_END =~ /^\d{2}:\d{2}$/) {
		die($e1 . '$BATCH_WINDOW_START/$BATCH_WINDOW_END must be set to 24hr military time using the form \'hh:mm\'.');
	}
	my $hr = $main::BATCH_WINDOW_START;
	$hr =~ s/:.*//;
	my $min = $main::BATCH_WINDOW_START;
	$min =~ s/^\d{1,2}://;
	if ($hr > 23 or $min > 59) {
		die($e1 . '$BATCH_WINDOW_START must be set to a valid 24hr military time using the form \'hh:mm\'.');
	}
	$hr = $main::BATCH_WINDOW_END;
	$hr =~ s/:.*//;
	$min = $main::BATCH_WINDOW_END;
	$min =~ s/^\d{1,2}://;
	if ($hr > 23 or $min > 59) {
		die($e1 . '$BATCH_WINDOW_END must be set to a valid 24hr military time using the form \'hh:mm\'.');
	}
	if (not defined $main::SECONDS_BETWEEN_TRIES or not $main::SECONDS_BETWEEN_TRIES =~ /^\d+$/) {
		die($e1 . '$SECONDS_BETWEEN_TRIES must be set to a number (integer).');
	}
	if (not defined @main::STEPS or @main::STEPS < 1) {
		die($e1 . '$STEPS must contain at least one job step.');
	}
	foreach my $step_idx (0..(@main::STEPS -1)) {
		my $step_num = $step_idx + 1;
		my $e2 = $e1 . 'in @STEPS, step #' . $step_num;
		if (not defined $main::STEPS[$step_idx]{name} or not $main::STEPS[$step_idx]{name} =~ /\w/) {
			die($e2 . ' {name} must be set to a non-empty alphanumeric string.');
		}
		if (not defined $main::STEPS[$step_idx]{execute_cmd} or not $main::STEPS[$step_idx]{execute_cmd} =~ /\w/) {
			die($e2 . ' {execute_cmd} must be set to a command line string.');
		}
		if (not defined $main::STEPS[$step_idx]{validate_cmd} or ($main::STEPS[$step_idx]{validate_cmd} ne '' and not $main::STEPS[$step_idx]{validate_cmd} =~ /\w/)) {
			die($e2 . ' {validate_cmd} must be set to a command line string OR \'\' if not used.');
		}
		if (not defined $main::STEPS[$step_idx]{prereq_steps} or ($main::STEPS[$step_idx]{prereq_steps} ne '' and not $main::STEPS[$step_idx]{prereq_steps} =~ /^(\d+){1}([,]\s*\d+)*$/)) {
			die($e2 . ' {prereq_steps} must be set to a comma seperated list of pre-requisite step numbers OR \'\' for none.');
		}
		# validate prereq_step's contain valid earlier steps
		if ($main::STEPS[$step_idx]{prereq_steps} ne '') {
			my @prereqs = split (/,|,\s*/, $main::STEPS[$step_idx]{prereq_steps});
			for my $prereq (@prereqs) {
				if ($prereq <= 0 or $prereq >= $step_num) {
					die($e2 . ' {prereq_steps} can only contain previous step numbers.');
				}
			}
		}
		if (not defined $main::STEPS[$step_idx]{obey_batch_window} or not $main::STEPS[$step_idx]{obey_batch_window} =~ /^(YES|NO)$/) {
			die($e2 . ' {obey_batch_window} must be set to \'YES\' or \'NO\'.');
		}		
		if (not defined $main::STEPS[$step_idx]{max_tries} or not $main::STEPS[$step_idx]{max_tries} =~ /^\d+$/ or $main::STEPS[$step_idx]{max_tries} < 1) {
			die($e2 . ' {max_tries} must be a number (integer) greater than zero.');
		}
		if (not defined $main::STEPS[$step_idx]{stop_run_on_failure} or not $main::STEPS[$step_idx]{stop_run_on_failure} =~ /^(YES|NO)$/) {
			die($e2 . ' {stop_run_on_failure} must be set to \'YES\' or \'NO\'.');
		}		
		if (not defined $main::STEPS[$step_idx]{email_log_file} or not $main::STEPS[$step_idx]{email_log_file} =~ /^(YES|NO)$/) {
			die($e2 . ' {email_log_file} must be set to \'YES\' or \'NO\'.');
		}		
	}
}

#-
# Validate status file is well formed
#-
sub validate_status {
	my $e1 = "error: bad status file ($main::STATUS_FILE) - ";
	if (not defined $main::Job_Run_ID or not $main::Job_Run_ID =~ /^\d+$/) {
		die($e1 . '$Job_Run_ID must be set to a number (integer).');
	}
	if (not defined $main::Job_Run_Status or not $main::Job_Run_Status =~ /^(NEW|RUNNING|SUCCEEDED|FAILED)$/) {
		die($e1 . '$Job_Run_Status must be set to RUNNING, SUCCEEDED, or FAILED.');
	}
	
	# only need to check for existance of last/current
	# step values since they are always overwritten
	if (not defined $main::Step_Num) {
		die($e1 . '$Step_Num must be set to a valid step number (integer).');
	}
	if (not defined $main::Step_Name) {
		die($e1 . '$Step_Name must be set to a a non-empty alphanumeric string.');
	}
	if (not defined $main::Step_Try_Num) {
		die($e1 . '$Step_Try_Num must be set to a number (integer).');
	}
}

#-
# Display program header
#-
sub display_header {
	open my $FILE, '<', $0
		or die "error: can't open source file... $!";
	print "\n";
	my $marker = 2;
	while ($marker and my $line = <$FILE>) {
		if ($line =~ /^#!/) {
			next;
		} elsif ($line =~ /^#--/) {
			$marker--;
		} elsif ($line =~ /^# /) {
			$line =~ s/^# //;
			print $line;
		} else {
			print "\n";
		}
	}
}