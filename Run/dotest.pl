#!/usr/bin/perl -w

###############################################################################
# Copyright:  (c) 2004-2010 by IntelliMagic B.V.  All Rights Reserved
#
# Name:
#   dotest.pl
#
# Purpose:
#   test IntelliMagic Vision
#
###############################################################################

require Cwd;
use Cwd 'abs_path';
use strict;
use File::Path;
use File::Copy;
use File::Glob ':glob';
use Term::ReadKey;
use Tie::File;
use Net::SMTP;

use File::Copy::Recursive qw(dircopy);
# --------------------------------------------------------------------
# Prototypes
# --------------------------------------------------------------------
sub testCompare($$$$$);
sub replace_in_file($$);
sub delete_file_if_empty($);
sub file_newer($$);
sub executePCapp($$);

# --------------------------------------------------------------------
# global variables
# --------------------------------------------------------------------
#use vars qw(%Config @ReqVars @ReqDirs @ReqDirsSS @ReqProgs @ReqProgsSS @ReqProgsPC);

use vars qw(%Config);                                                   # configuration
use vars qw(%Tests);                                                    # tests to run
use vars qw($testpc $testzos);                                          # options

# $rootdir        - root folder for tests
# $runbasedir     - run folder
# $resultsbasedir - results base folder
# $sysindir       - SYSIN folder
use vars qw($rootdir $bindir $runbasedir $resultsbasedir $sysindir);

my $VERSION = "2.0.0";    # script version

###########################################################################
# Base test folder setup
###########################################################################

my $configdir = abs_path($0);
$configdir =~ s#/#\\#g;
$configdir =~ s#^(.*)\\.*#$1#;
$configdir =~ s#^(.*)\\.*#$1#;

$rootdir = $configdir; # Rootdir is the same as the folder with the test configuration

$bindir = "$rootdir\\bin";
$runbasedir = "$rootdir\\run";
$resultsbasedir = "$rootdir\\Results";
$sysindir = "$rootdir\\Sysin";

###########################################################################
# Read the file tests.cfg containing test settings
###########################################################################

read_config("$configdir\\tests.cfg");
check_config();
mail_start_test();

my $rc = 0;

my $zuserid = uc($Config{zosuserid});
my $zpw     = $Config{zospw};
$ENV{MVSHOST} = $Config{zoshost};
$ENV{MVSUSER} = $zuserid;
$ENV{MVSPWD} = $zpw;

###########################################################################
# Configuration dependent test folder setup
#
# Make sure folders exist, and match the options
###########################################################################

my $testversion = $Config{currenttests};
my $rundir = "$runbasedir\\$Config{currenttests}";
my $resultsdir = "$resultsbasedir\\$Config{currenttests}";

unless (-d $rundir) {
  mkpath ($rundir) or die "Cannot create current version run folder: $!\n";
}

unless (-d $resultsbasedir) {
  mkpath ($resultsbasedir) or die "Cannot create results folder: $!\n";
}

unless (-d "$resultsdir") {
    mkpath ("$resultsdir") or die "Cannot create current version results folder: $!\n";
}

# open the logfile
open_log();

###########################################################################
# Read the command line options
# - option to test PC/mainframe
# -
###########################################################################

$testpc = 1;  # perform pc based tests, also perform script based tests
$testzos = 0; # perform zos based tests

for (@ARGV) {
  if (/\-testpc/) {
    $testpc = 0;
  } elsif (/-testzos/) {
    $testzos = 0;
  } elsif (/\+testpc/) {
    $testpc = 1;
  } elsif (/\+testzos/) {
    $testzos = 1;
  }
}


# check dependencies of options
# - currently no dependencies

# print the options selected
write_log("  Selected options for test run $Config{currenttests}:");
write_log("  - Compare against test run $Config{previoustests}") if (defined($Config{previoustests}));
write_log("  - Perform PC and script based tests") if ($testpc);
write_log("  - Perform zOS based tests") if ($testzos);
write_log("-" x 75);

###########################################################################
# All commmand line input has been done
# Check if required (executable) files exist
###########################################################################

# The test run requires all of the files that are part of the IntelliMagic Vision installation.
# Copy all files from Program Files\IntelliMagic\IntelliMagic Vision and Balance to the test folder

###########################################################################
# Determine if tests will be run locally or on a remote system

my $testremote = 0;

if ($ENV{COMPUTERNAME} eq "IMSERVER4" || $ENV{COMPUTERNAME} eq "IMTERMINAL")
{
  $testremote = 1;
}

###########################################################################
# Reboot remote test machines

if ($testpc)
{
  if ($testremote)
  {
    log_section("Prepare test environment. Reboot remote Windows test systems.");

    # Reboot
    #$rc = log_exec("$bindir\\psshutdown.exe -accepteula -r -f -c -t 10 -u $Config{winuserid} -p $Config{winpw} \\\\IMRMF-XP03");

    # Wait for reboot to happen
    #log_exec("$bindir\\sleep.exe 30");
  }
}

###########################################################################
# DELETE previous test results from the z/OS system

if ($testzos)
{
  # Submit the rmfdelt job
  write_log("  Submit RMFDELT JCL");
  $rc = log_exec("perl $bindir\\submitjcl.pl $runbasedir\\rmfdelt.jcl $resultsdir\\rmfdelt.jcl.out");
}

###########################################################################
# Upload z/OS XMIT files and receive into 'RMFMAGIC.$testversion.*

if ($testzos)
{
  sendreceive_XMITfiles();
  $rc = 0;
}


###########################################################################
# Wait for remote test machines to be alive

if ($testpc)
{
  if ($testremote)
  {
    log_section("Check test environment. Wait for reboot of remote Windows test systems.");

    # Wait 10 times 30 seconds
    my $waitcnt = 0;
    $rc = 1;
    while ($rc && $waitcnt < 11)
    {
      $rc = executePCapp("IMRMF-XP03", "exit 0");

      write_log("remote execution return code is $rc");

      $waitcnt++;

      if ($rc) {
        # wait 30 seconds
        log_exec("$bindir\\sleep.exe 30");
      }
    }
  }
}

if ($rc)
{
  write_log("Cannot start tests, remote system IMRMF-XP03 not available");
  exit($rc);
}


###########################################################################
# Determine which tests

# Perform each test
my $testname = "";

foreach $testname (sort(keys %Tests)) 
{
    my $Test = $Tests{$testname}; # Get the Test structure
    # $$Test{RunTestFrom} now indicates where to start with the test (reduce, analyze, or script)
    # $$Test{TestPlatforms} indicates test platforms (PC, zOS, or script)
    # $$Test(TestMachine} indicates what machine to run the test on (Machine name or IP address)
    # $$Test{TestFile} indicates which file to use for the test (SMF or RMZ/RMC filename)

    my ($teststart, $testplatform, $testmachine, $testfile) = ($$Test{RunTestFrom}, $$Test{TestPlatforms}, $$Test{TestMachine}, $$Test{TestFile});

    # Print test currently running
    if (($testpc && $testplatform eq 'PC') || ($testzos && $testplatform eq 'zOS')) 
    {
        log_section("Execute test $testname ...");

        # Copy files for this test to the test folder
        if (copyTest($testname, $teststart, $testplatform, $testmachine, $testfile) == 0)
        {
            # in case of z/OS tests, we need to create a new JCL library and upload JCL+License to it
            if ($testzos && $$Test{TestPlatforms} eq 'zOS') 
            {
                createTestJCL($testname, $teststart, $testplatform, $testmachine, $testfile);
            }

            # Now we check whether we'll run a balance test or not
            # we'll always run on a PC (for now).
            if ($teststart eq 'balance') 
            {
                balanceTest($testname, $teststart, $testplatform, $testmachine, $testfile);
                
            } elsif ($teststart eq 'reduce' || $teststart eq 'analyze') 
            {
                # Now run the reduce test (if applicable)
                if ($teststart eq 'reduce') 
                {
                    reduceTest($testname, $teststart, $testplatform, $testmachine, $testfile);
                }

                # Now run the analyze test
                analyzeTest($testname, $teststart, $testplatform, $testmachine, $testfile);

            }

            # Now post-process results and compare results to previous test results
            testCompare($testname, $teststart, $testplatform, $testmachine, $testfile);

        } else
        {
            write_log("  ERROR: Cannot run tests for test $testname. No input commands found.");
        }

    } elsif ($testpc && $testplatform eq 'script') {
        log_section("Execute test $testname ...");

        testScript($testname, $teststart, $testplatform, $testmachine, $testfile);

        # Dump the Excel files (if created) to text files
        dumpExcelForScriptedTest($testname, $teststart, $testplatform, $testmachine, $testfile);
        
        # Now post-process results and compare results to previous test results
        testCompare($testname, $teststart, $testplatform, $testmachine, $testfile);

    } else
    {
        log_section("Skip test $testname ...");
    }
}

# close the log
close_log();
mail_tester();

###########################################################################
# Sub to copy test files from sysin folder to test folder (where the tests are run)
###########################################################################

sub copyTest
{
  # params in @_ (test name, test start, test platforms, test file)
  my ($testname, $teststart, $testplatform, $testmachine, $testfile) = @_;

  # Create the test folder
  unless (-d "$resultsdir\\$testname")
  {
    mkpath ("$resultsdir\\$testname") or die "Cannot create current test results folder: $!\n";
  }

  # Copy test files from sysin folder to test folder
  if (-d "$sysindir\\$testname")
  {
    # use glob to expand wildcard
    for my $file ( <$sysindir\\$testname\\*> ) {
      copy( $file, "$resultsdir\\$testname" ) or warn "Cannot copy $file: $!";
      chmod 0666, $file;
    }

  } else
  {
    # Test sysin folder not found, return an error.
    return 1;
  }

    # Pre-process the test files
  for my $file ( <$resultsdir\\$testname\\*> )
  {
    replace_in_file($file,
                    sub {
                      s!%testprojectfolder%!$resultsdir\\$testname!i;
                      s!%datafolder%!$Config{smfdata}\\$testfile!i;
                      s!%binfolder%!$bindir!i;
                      s!%runfolder%!$rundir!i;
                      s!%testproject%!$testname!i;
                      $_;
                    } );
  }
}


###########################################################################
# Sub to perform a single PC reduce test
###########################################################################

sub reduceTestPC {
  # params in @_ (test name, test start, test platforms, test file)
  my ($testname, $teststart, $testplatform, $testmachine, $testfile) = @_;
  my $sysprint = "$resultsdir\\$testname\\reduce.log";

  # Print test currently running
  write_log("- Run PC reduce for test $testname ...");

  # Reduce run depends on:
  # - rmfmagic.exe ($rundir\\rmfmagic.exe)
  # - sysin        ($sysindir\\$testname\_reduce.txt)
  # - sysprint     ($sysprint)
  my @sourcefiles = ("$rundir\\rmfmagic.exe", "$sysindir\\$testname\_reduce.txt");
  my @targetfiles = ("$sysprint");
  my $rc = requireRun(\@sourcefiles, \@targetfiles);
  if ($rc == 0) {
      write_log("  == Skip PC reduce for test $testname, results up-to-date ==");
      return;
    }

  # Create the command file
  write_log("  Create reduce commands file");
  open RMFCOMMAND, ">$rundir\\commands.txt";
  print RMFCOMMAND "typerun  reduce\n";
  print RMFCOMMAND "project  $resultsdir\\$testname\n";
  print RMFCOMMAND "sysin    $resultsdir\\$testname\\$testname\_reduce.txt\n";
  print RMFCOMMAND "smf      $Config{smfdata}\\$testfile\n";
  print RMFCOMMAND "sysprint $sysprint\n";
  print RMFCOMMAND "license  $rundir\\license.ini\n";
  close RMFCOMMAND;

  # Run RMF magic
  write_log("  Execute reduce");
  $rc = executePCapp($testmachine, "\"$rundir\\rmfmagic.exe\" \"$rundir\\commands.txt\"");

  # Done PC specific part
}

###########################################################################
# Sub to perform a single PC balance test
###########################################################################

sub balanceTestPC {
	  # params in @_ (test name, test start, test platforms, test file)
	  my ($testname, $teststart, $testplatform, $testmachine, $testfile) = @_;

	  # Print test currently running
	  write_log("- Run PC balance for test $testname ...");

	  # # Let's see if we need to run a reduce and/or analyze
	  reduceTest($testname, $teststart, $testplatform, $testmachine, $testfile);
	  analyzeTest($testname, $teststart, $testplatform, $testmachine, $testfile);

	  my $tc_sysin = "$resultsdir\\$testname";

	  opendir SYSIN, $tc_sysin or die "Oops, cannot open $sysindir: $!";
	  my $sysin_file;

	  foreach $sysin_file (readdir SYSIN) {

  	      if ( $sysin_file =~ /${testname}.*_balance\.txt$/ ) {

    		   print "$sysin_file\n";
			   my $b_file = $sysin_file;

			   # Create vars for the Migration command & log file names
			   my $filename = substr($b_file,0,-4);
			   my $migrationcommandfile = "${filename}" . ".filegeneratedlist.txt";
			   my $migrationlogfile = "${filename}" . ".migrationadvisor.log";
			   my $sysprint = "${resultsdir}\\${testname}\\${filename}" . ".log";

			   write_log("  Create Migration command file (${migrationcommandfile}) in $rundir.\n");
			   open BALANCECOMMAND, ">${resultsdir}\\${testname}\\${migrationcommandfile}";
			   print BALANCECOMMAND "typerun  migrate\n";
			   print BALANCECOMMAND "project  ${resultsdir}\\${testname}\n";
			   print BALANCECOMMAND "sysin  $resultsdir\\$testname\\${b_file}\n";
			   print BALANCECOMMAND "sysprint  ${sysprint}\n";
			   print BALANCECOMMAND "seldev  ${resultsdir}\\${testname}\\report\\SELDEV.CSV\n";
			   print BALANCECOMMAND "volcsv0  ${resultsdir}\\${testname}\\balance\\TUE\@DMIG.csv\n";
			   print BALANCECOMMAND "dba  ${resultsdir}\\${testname}\\balance\n";
			   print BALANCECOMMAND "license  ${rundir}\\license.ini\n";
			   close BALANCECOMMAND;

			   # Run Balance
			   write_log("  Execute Migration for $b_file");
			   $rc = executePCapp($testmachine, "\"${rundir}\\balance.exe\" \"${resultsdir}\\${testname}\\${migrationcommandfile}\"  > \"${resultsdir}\\${testname}\\${migrationlogfile}\"");

			}
		}

		# Done PC specific part

	}

###########################################################################
# Sub to perform a single PC analyze test
###########################################################################

sub analyzeTestPC {
  # params in @_ (test name, test start, test platforms, test file)
  my ($testname, $teststart, $testplatform, $testmachine, $testfile) = @_;
  my $sysprint = "$resultsdir\\$testname\\analyze.log";

  # Print test currently running
  write_log("- Run PC analyze for test $testname ...");

  # Analyze run depends on:
  # - rmfmagic.exe  ($rundir\\rmfmagic.exe)
  # - sysin         ($sysindir\\$testname\_analyze.txt)
  # - RMC+RMZ files ($resultsdir\\$testname\\$testname.RMC+$resultsdir\\$testname\\$testname.RMZ)
  # - hardware.ini  ($rundir\\hardware.ini)
  # - sysprint      ($sysprint)
  # - dba\*.csv     ($resultsdir\\$testname\\dba\\*.csv)
  # - report\*.csv  ($resultsdir\\$testname\\report\\*.csv)
  my @sourcefiles = ("$rundir\\rmfmagic.exe", "$sysindir\\$testname\_analyze.txt", "$resultsdir\\$testname\\$testname.RMC", "$resultsdir\\$testname\\$testname.RMZ", "$rundir\\hardware.ini");
  my @targetfiles = ("$sysprint", "$resultsdir\\$testname\\dba\\*.csv", "$resultsdir\\$testname\\report\\*.csv");
  my $rc = requireRun(\@sourcefiles, \@targetfiles);
  if ($rc == 0) {
    write_log("  == Skip PC analyze for test $testname, results up-to-date ==");
    return;
  }

  # Create the command file
  write_log("  Create analyze commands file");
  open RMFCOMMAND, ">$rundir\\commands.txt";
  print RMFCOMMAND "typerun  analyze\n";
  print RMFCOMMAND "project  $resultsdir\\$testname\n";
  print RMFCOMMAND "sysin    $resultsdir\\$testname\\$testname\_analyze.txt\n";
  if (-f "$resultsdir\\$testname\\$testname\_geoxparm.txt")
  {
    print RMFCOMMAND "geoxparm $resultsdir\\$testname\\$testname\_geoxparm.txt\n";
  } else
  {
    print RMFCOMMAND "*geoxparm $resultsdir\\$testname\\$testname\_geoxparm.txt\n";
  }
  print RMFCOMMAND "sysprint $sysprint\n";
  print RMFCOMMAND "license  $rundir\\license.ini\n";
  close RMFCOMMAND;

  # Run RMF magic
  write_log("  Execute analyze");
  executePCapp($testmachine, "\"$rundir\\rmfmagic.exe\" \"$rundir\\commands.txt\"");

  # Done PC specific part
}


###########################################################################
# Sub to perform a single zOS reduce test
###########################################################################

sub reduceTestzOS {
  # params in @_ (test name, test start, test platforms, test file)
  my ($testname, $teststart, $testplatform, $testmachine, $testfile) = @_;
  my $sysprint = "$resultsdir\\reduce.log";
  my $testnameUC = uc($testname);
  my $currenttests = uc($Config{currenttests});

  # Print test currently running
  write_log("- Run z/OS reduce for test $testname ...");

  # z/OS reduce run depends on:
  # - *.XMIT ($rundir\\zos\\*.xmit)
  # - sysin  ($sysindir\\$testname\_reduce.txt)
  # - LOG    ($resultsdir\\$testname\\reduce.log)
  my @sourcefiles = ("$rundir\\zos\\*.xmit", "$sysindir\\$testname\_reduce.txt");
  my @targetfiles = ("$resultsdir\\$testname\\reduce.log");
  my $rc = requireRun(\@sourcefiles, \@targetfiles);
  if ($rc == 0) {
    write_log("  == Skip z/OS reduce for test $testname, results up-to-date ==");
    return;
  }

  # Submit the reduce job
  write_log("  Submit reduce JCL");
  $rc = log_exec("perl $bindir\\submitjcl.pl $resultsdir\\$testname\\\$2reduce.jcl $resultsdir\\$testname\\\$2reduce.jcl.out");

  # Download results (LOG)
  write_log("  Get reduce LOG");
  open FTPINPUT, ">$resultsdir\\$testname\\ftp.input";
  print FTPINPUT "$zuserid\n";
  print FTPINPUT "cd ..\n";
  print FTPINPUT "ascii\n";
  print FTPINPUT "get RMFMAGIC.$currenttests.$testnameUC.LOG $resultsdir\\$testname\\reduce.log\n";
  print FTPINPUT "get RMFMAGIC.$currenttests.$testnameUC.RMC $resultsdir\\$testname\\$testname.rmc\n";
  print FTPINPUT "bin\n";
#  print FTPINPUT "get RMFMAGIC.$currenttests.$testnameUC.RMZ $resultsdir\\$testname\\$testname.rmz\n";
  close FTPINPUT;
  log_exec("$bindir\\doftp.bat $resultsdir\\$testname\\ftp.input\n");

  # Done z/OS specific part
}


###########################################################################
# Sub to perform a single zOS analyze test
###########################################################################

sub analyzeTestzOS {
  # params in @_ (test name, test start, test platforms, test file)
  my ($testname, $teststart, $testplatform, $testmachine, $testfile) = @_;
  my $sysprint = "$resultsdir\\$testname\\analyze.log";
  my $testnameUC = uc($testname);
  my $currenttests = uc($Config{currenttests});

  # Print test currently running
  write_log("- Run z/OS analyze for test $testname ...");

  # z/OS Analyze run depends on:
  # - *.XMIT        ($rundir\\zos\\*.xmit)
  # - sysin         ($sysindir\\$testname\_analyze.txt)
  # - reduce LOG    ($resultsdir\\$testname\\reduce.log)
  # - LOG           ($resultsdir\\$testname\\analyze.log)
  # - IMGZIP
  my @sourcefiles = ("$rundir\\zos\\*.xmit", "$sysindir\\$testname\_analyze.txt", "$resultsdir\\$testname\\reduce.log");
  my @targetfiles = ("$resultsdir\\$testname\\analyze.log", "$resultsdir\\$testname\\$testname.imgzip");
  my $rc = requireRun(\@sourcefiles, \@targetfiles);
  if ($rc == 0) {
    write_log("  == Skip z/OS analyze for test $testname, results up-to-date ==");
    return;
  }

  # Submit the analyze job
  write_log("  Submit analyze JCL");
  $rc = log_exec("perl $bindir\\submitjcl.pl $resultsdir\\$testname\\\$3analze.jcl $resultsdir\\$testname\\\$3analze.jcl.out");

  # Submit the csv2pc job
  write_log("  Submit CSV2PC JCL");
  $rc = log_exec("perl $bindir\\submitjcl.pl $resultsdir\\$testname\\\$4csv2pc.jcl $resultsdir\\$testname\\\$4csv2pc.jcl.out");

  # Download results (LOG)
  write_log("  Get analyze LOG and IMGZIP file");
  open FTPINPUT, ">$resultsdir\\$testname\\ftp.input";
  print FTPINPUT "$zuserid\n";
  print FTPINPUT "cd ..\n";
  print FTPINPUT "ascii\n";
  print FTPINPUT "get RMFMAGIC.$currenttests.$testnameUC.RUN.LOG $resultsdir\\$testname\\analyze.log\n";
  print FTPINPUT "bin\n";
  print FTPINPUT "get RMFMAGIC.$currenttests.$testnameUC.RUN.IMGZIP $resultsdir\\$testname\\$testname.imgzip\n";
  close FTPINPUT;
  log_exec("$bindir\\doftp.bat $resultsdir\\$testname\\ftp.input\n");

  # Decrompress imgzip file
  write_log("  Execute IMGUNZIP");
  my $currentdir = chdir();
  chdir("$resultsdir\\$testname");
  log_exec("$rundir\\imgzip.exe UNZIP \"$resultsdir\\$testname\\$testname.imgzip\"");
  chdir($currentdir);

  # Done z/OS specific part
}


###########################################################################
# Sub to compare results for a single folder against the same folder from
# the previous test. Will also flag if a folder/file does not exist anymore.
# Makes recursive calls to itself to compare per folder
###########################################################################
# Moved to doCompare.pl

###########################################################################
# Sub to compare results for a single test against the previous test results
# Makes recursive calls to folderCompare to compare per folder
###########################################################################

sub testCompare($$$$$)
{
  # params in @_ (test name, test start, test platforms, test file)
  my ($testname, $teststart, $testplatform, $testmachine, $testfile) = @_;

  if (!(-d "$resultsbasedir\\$Config{previoustests}\\$testname")) {
    write_log("Cannot compare results to previous results. Previous results do not exist.");

    return;
  }

  if ($testremote)
  {
    # Push the scripted test to $testmachine
    # Create a batch file that will execute on the remote system
    # Use psexec to copy and execute the batch file on the remote system
    open RUNCOMMAND, ">$resultsdir\\compremote.cmd";
    print RUNCOMMAND "\@echo off\n";
    print RUNCOMMAND "net use T: \\\\imserver5\\testsuite\n";
    print RUNCOMMAND "net use U: \\\\imserver5\\testdata\n";
    print RUNCOMMAND "t:\n";
    print RUNCOMMAND "cd \"$runbasedir\"\n";
    print RUNCOMMAND "IM_Compare.pl $testname\n";
    close RUNCOMMAND;

    log_exec("$bindir\\psexec.exe -i 0 -accepteula \\\\IMRMF-XP03 -u $Config{winuserid} -p $Config{winpw} -c \"$resultsdir\\compremote.cmd\"");
  } else
  {
    # Execute locally
    log_exec("$runbasedir\\IM_Compare.pl $testname");
  }
}

###########################################################################
# Sub to perform a single reduce test
###########################################################################

sub reduceTest {
  # params in @_ (test name, test start, test platforms, test file)
  my ($testname, $teststart, $testplatform, $testmachine, $testfile) = @_;

  if ($testpc && $testplatform eq 'PC') {
    reduceTestPC(@_);
  }
  if ($testzos && $testplatform eq 'zOS') {
    reduceTestzOS(@_);
  }
}


###########################################################################
# Sub to perform a single balance test
###########################################################################

sub balanceTest {
  # params in @_ (test name, test start, test platforms, test file)
  my ($testname, $teststart, $testplatform, $testmachine, $testfile) = @_;
  print $testpc;

  if ($testpc && $testplatform eq 'PC') {
    print $testpc;
    balanceTestPC(@_);
  }
  else {
      print " We don't support balance on zOS, not that I know of anyway!";
	  write_log("!!! Balnce is not supported on zOS.");
  }
}

###########################################################################
# Sub to perform a single analyze test
###########################################################################

sub analyzeTest {
  # params in @_ (test name, test start, test platforms, test file)
  my ($testname, $teststart, $testplatform, $testmachine, $testfile) = @_;

  if ($testpc && $testplatform eq 'PC') {
    analyzeTestPC(@_);
  }
  if ($testzos && $testplatform eq 'zOS') {
    analyzeTestzOS(@_);
  }
}

###########################################################################
# Sub to perform a single scripted test
###########################################################################

sub testScript {
  # params in @_ (test name, test start, test platforms, test file)
  my ($testname, $teststart, $testplatform, $testmachine, $testfile) = @_;

  # Print test currently running
  write_log("- Run script for test $testname ...");

  # Scripted run depends on:
  # - RMFM4W.exe   ($rundir\\RMFM4W.exe)
  # - rmfmagic.exe ($rundir\\rmfmagic.exe)
  # - sysin        ($sysindir\\$testname.rmfmgo)
  # - sysprint     ($resultsdir\\$testname\\$testname.log)
  my @sourcefiles = ("$rundir\\RMFM4W.exe", "$rundir\\rmfmagic.exe", "$sysindir\\$testname.rmfmgo");
  my @targetfiles = ("$resultsdir\\$testname\\$testname.log");
  my $rc = requireRun(\@sourcefiles, \@targetfiles);
  if ($rc == 0) {
    write_log("  == Skip script for test $testname, results up-to-date ==");
    return;
  }

  # Copy files for this script to the project test folder
  if (copyTest($testname, $teststart, $testplatform, $testmachine, $testfile) == 1)
  {
    write_log("  ERROR: Cannot run tests for test $testname. No input commands found.");
    return;
  }

  chdir "$resultsdir\\$testname";

  # If a command file with the test name exists, run the command file, otherwise run the RMFM4W GUI
  my $cmdfile = "$resultsdir\\$testname\\$testname.cmd";
  my $scriptfile = "$resultsdir\\$testname\\$testname.rmfmgo";

  if (-f "$cmdfile")
  {
    $rc = executePCapp($testmachine, "call \"$cmdfile\"");
  } elsif (-f "$scriptfile")
  {
    $rc = executePCapp($testmachine, "\"$rundir\\RMFM4W.EXE\" /S \"$scriptfile\" /L \"$resultsdir\\$testname\\$testname.log\"");
  } else
  {
    write_log("ERROR: Cannot run scripted test. No script and no command file found!");
  }
}

###########################################################################
# Sub to dump Excel output from a scripted test to TXT files
###########################################################################

sub dumpExcelForScriptedTest {
  # params in @_ (test name, test start, test platforms, test file)
  my ($testname, $teststart, $testplatform, $testmachine, $testfile) = @_;

  # Print test currently running
  write_log("- Dump Excel output to TXT files for test $testname ...");

  chdir "$resultsdir\\$testname";

  # Create dumpXLS script in the project test folder
  open DUMPSCRIPT, ">$resultsdir\\$testname\\$testname\_dumpXLS.rmfmgo";
  print DUMPSCRIPT "Project Name = '$resultsdir\\$testname';\n";
  print DUMPSCRIPT "DumpXLS;\n";
  close DUMPSCRIPT;

  # Run the script to Dump to XLS
  my $scriptfile = "$resultsdir\\$testname\\$testname\_dumpXLS.rmfmgo";

  $rc = executePCapp($testmachine, "\"$rundir\\RMFM4W.EXE\" /S \"$scriptfile\" /L \"$scriptfile.log\"");
}


###########################################################################
# Sub to write diff file in case of non-existing compare to file
###########################################################################

sub writeErrorDiff {
  # params in @_ (diff file to write, where the file is missing, missing csv file)
  my ($diff_file, $missing_where, $missing_file) = @_;

  open DIFFOUTPUT, ">$diff_file" or die "Cannot open diff file $diff_file: $!\n";
  print DIFFOUTPUT "Difference found, missing file in $missing_where test set to compare to $missing_file\n";
  close DIFFOUTPUT;
}

###########################################################################
# Sub to compare two dmc files
###########################################################################
# Moved to doCompare.pl

###########################################################################
# Sub to compare two csv files
###########################################################################
# Moved to doCompare.pl

###########################################################################
# Sub to compare two text files
###########################################################################
# Moved to doCompare.pl

###########################################################################
# Sub to unzip a dmc file
# FR-00166, JWE.
###########################################################################
# Moved to doCompare.pl

###########################################################################
# Sub to get the latest modify time for a file mask. Returns the latest
# modify time, or zero if no existing files matched
###########################################################################

sub latestModifyTime {
  # params in @_ (file mask)
  my ($file_mask) = @_;

  # expand optional wildcards and verify mtime for each found file
  my @lstFiles = glob($file_mask);

  my $latestMTime;

  my $currentFile = "";
  while ($currentFile = shift @lstFiles) {
    if (-f $currentFile) { # When the file mask is not a mask, we need to verify that the file exists
      $latestMTime = (stat($currentFile))[9] unless (defined($latestMTime));

      $latestMTime = (stat($currentFile))[9] if ((stat($currentFile))[9] > $latestMTime);
    }
  }

  return 0 unless (defined $latestMTime);
  return $latestMTime;
}

###########################################################################
# Sub to get the latest modify time for a file mask. Returns the latest
# modify time, or zero if no existing files matched
###########################################################################

sub earliestModifyTime {
  # params in @_ (file mask)
  my ($file_mask) = @_;

  # expand optional wildcards and verify mtime for each found file
  my @lstFiles = glob($file_mask);

  my $earliestMTime;

  my $currentFile = "";
  while ($currentFile = shift @lstFiles) {
    if (-f $currentFile) { # When the file mask is not a mask, we need to verify that the file exists
      $earliestMTime = (stat($currentFile))[9] unless (defined($earliestMTime));

      $earliestMTime = (stat($currentFile))[9] if ((stat($currentFile))[9] < $earliestMTime);
    }
  }

  return 0 unless (defined($earliestMTime));
  return $earliestMTime;
}

###########################################################################
# Sub to verify if we need to re-run part of the test.
# This sub returns 1 if any of the dependent files are older
# than the source files. This sub returns 0 otherwise.
###########################################################################

sub requireRun {
  # params in @_ (reference to source files, reference to target files)
  my ($source_file_masks, $target_file_masks) = @_;

  my $source_latest_mtime = 0;
  my $target_earliest_mtime;
  my $current_latest_mtime;

  my $source_file_mask = "";
  while ($source_file_mask = shift @{$source_file_masks}) {
    $current_latest_mtime = latestModifyTime($source_file_mask);

    $source_latest_mtime = $current_latest_mtime if ($source_latest_mtime < $current_latest_mtime);
  }

  my $target_file_mask = "";
  while ($target_file_mask = shift @{$target_file_masks}) {
    $current_latest_mtime = earliestModifyTime($target_file_mask);

    $target_earliest_mtime = $current_latest_mtime unless (defined($target_earliest_mtime));
    $target_earliest_mtime = $current_latest_mtime if ($current_latest_mtime < $target_earliest_mtime);
  }

  if ($source_latest_mtime == 0) {
    write_log("!!! Serious error encountered. Executable or input file missing !!!");
    return 0; # Cannot rerun since some file is missing
  }
  if ($target_earliest_mtime == 0) {
    return 1; # Need to rerun, some target file doesn't exist
  }
  if ($target_earliest_mtime < $source_latest_mtime) {
    print "Need to rerun, target mtime (". localtime($target_earliest_mtime) . ") < source mtime (". localtime($source_latest_mtime) . ")\n";
    return 1; # Need to rerun, some target file modified earlier than some source file
  }

  return 0; # No need to rerun
}

###########################################################################
# z/OS support functions
###########################################################################

sub createTestJCL {
  # params in @_ (test name, test start, test platforms, test file)
  my ($testname, $teststart, $testplatform, $testmachine, $testfile) = @_;
  my $testnameUC = uc($testname);
  my $currenttests = uc($Config{currenttests});

  # Customize JCL and submit to create a test dataset with JCL for this test run
  customizeJCL($testname, "$runbasedir\\newtestds.jcl", "$resultsdir\\$testname\\$testname\_nds.jcl", "RMF Magic test create data set JCL");
  $rc = log_exec("perl $bindir\\submitjcl.pl $resultsdir\\$testname\\$testname\_nds.jcl $resultsdir\\$testname\\$testname\_nds.jcl.out");

  # copy JCL and input commands to test results folder, including customization of JCL
  if (-d "$sysindir\\$testname\\")
  {
    if (-f "$sysindir\\$testname\\\$2reduce.jcl")
    {
      customizeJCL($testname, "$sysindir\\$testname\\\$2reduce.jcl", "$resultsdir\\$testname\\\$2reduce.jcl", "RMF Magic test reduce JCL");
      customizeJCL($testname, "$sysindir\\$testname\\\$3analze.jcl", "$resultsdir\\$testname\\\$3analze.jcl", "RMF Magic test analyze JCL");
    } else
    {
      customizeJCL($testname, "$runbasedir\\reduce.jcl", "$resultsdir\\$testname\\\$2reduce.jcl", "RMF Magic test reduce JCL");
      customizeJCL($testname, "$runbasedir\\analze.jcl", "$resultsdir\\$testname\\\$3analze.jcl", "RMF Magic test analyze JCL");
    }

    copy( "$sysindir\\$testname\\reduce.txt", "$resultsdir\\$testname\\reduce.txt" ) or warn "Cannot copy $sysindir\\$testname\\reduce.txt: $!";
    copy( "$sysindir\\$testname\\analyze.txt", "$resultsdir\\$testname\\analyze.txt" ) or warn "Cannot copy $sysindir\\$testname\\analyze.txt: $!";
    if (-f "$sysindir\\$testname\\geoxparm.txt")
    {
      copy("$sysindir\\$testname\\geoxparm.txt", "$resultsdir\\$testname\\geoxparm.txt") or warn "Cannot copy $sysindir\\$testname\\geoxparm.txt: $!";
    }
  } else 
  {
    customizeJCL($testname, "$runbasedir\\reduce.jcl", "$resultsdir\\$testname\\\$2reduce.jcl", "RMF Magic test reduce JCL");
    customizeJCL($testname, "$runbasedir\\analze.jcl", "$resultsdir\\$testname\\\$3analze.jcl", "RMF Magic test analyze JCL");

    copy( "$sysindir\\$testname\_reduce.txt", "$resultsdir\\$testname\\reduce.txt" ) or warn "Cannot copy $sysindir\\$testname\_reduce.txt: $!";
    copy( "$sysindir\\$testname\_analyze.txt", "$resultsdir\\$testname\\analyze.txt" ) or warn "Cannot copy $sysindir\\$testname\_analyze.txt: $!";
    if (-f "$sysindir\\$testname\_geoxparm.txt")
    {
      copy("$sysindir\\$testname\_geoxparm.txt", "$resultsdir\\$testname\\geoxparm.txt") or warn "Cannot copy $sysindir\\$testname\_geoxparm.txt: $!";
    }
  }
  
  # Customize CSV2PC job to submit (and upload for future reference) as part of JCL
  customizeJCL($testname, "$runbasedir\\csv2pc.jcl", "$resultsdir\\$testname\\\$4csv2pc.jcl", "RMF Magic test csv2pc JCL");

  # Now upload the JCL and input statements
  open FTPINPUT, ">$resultsdir\\$testname\\ftp.input";
  print FTPINPUT "$zuserid\n";
  print FTPINPUT "cd ..\n";
  print FTPINPUT "ascii\n";
  print FTPINPUT "put -z $resultsdir\\$testname\\\$2reduce.jcl RMFMAGIC.$currenttests.$testnameUC.JCL(\$2REDUCE)\n";
  print FTPINPUT "put -z $resultsdir\\$testname\\\$3analze.jcl RMFMAGIC.$currenttests.$testnameUC.JCL(\$3ANALZE)\n";
  print FTPINPUT "put -z $resultsdir\\$testname\\\$4csv2pc.jcl RMFMAGIC.$currenttests.$testnameUC.JCL(\$4CSV2PC)\n";
  print FTPINPUT "put -z $resultsdir\\$testname\\reduce.txt RMFMAGIC.$currenttests.$testnameUC.JCL(REDUCE)\n";
  print FTPINPUT "put -z $resultsdir\\$testname\\analyze.txt RMFMAGIC.$currenttests.$testnameUC.JCL(ANALYZE)\n";
#  if (-f "$resultsdir\\$testname\\geoxparm.txt")
#  {
#    print FTPINPUT "put -z $resultsdir\\$testname\\geoxparm.txt RMFMAGIC.$currenttests.$testnameUC.JCL(GEOXPARM)\n";
#  }
  close FTPINPUT;
  log_exec("$bindir\\doftp.bat $resultsdir\\$testname\\ftp.input\n");

}

sub customizeJCL {
  # params in @_ (test name (upper case), original JCL file, target customized JCL file,
  #               description of what is customized)
  my ($testname, $orgJCLfile, $newJCLfile, $description) = @_;
  my $testnameUC = uc($testname);
  my $currenttests = uc($Config{currenttests});

  my $Test = $Tests{$testname}; # Get the Test structure
                                # $$Test{RunTestFrom} now indicates where to start with the test (reduce or analyze)
                                # $$Test{TestPlatforms} indicates test platforms (PC or zOS)
                                # $$Test(TestMachine} indicates what machine to run the test on (Machine name or IP address)
                                # $$Test{TestFile} indicates which file to use for the test (SMF or RMZ/RMC filename)

  my ($teststart, $testplatform, $testmachine, $testfile) = ($$Test{RunTestFrom}, $$Test{TestPlatforms}, $$Test{TestMachine}, $$Test{TestFile});
  $testfile = uc($testfile);

  open RMFJCLIN, "$orgJCLfile" or die "Cannot open $description input: $!\n";
  open RMFJCLOUT, ">$newJCLfile" or die "Cannot open $description output: $!\n";
  while (<RMFJCLIN>) {
    s#IMUSGU1#$zuserid#;
    s#(//\s+SET PROJECT)=\w+\s*#$1=$currenttests.$testnameUC #;
    s#(//\s+SET PRODUCT)=\w+\s*#$1=RMFMAGIC.$currenttests #;
    s#(//\s+SET USERHLQ)=\w+\s*#$1=RMFMAGIC #;

    if ($teststart eq 'reduce') {
      s#(//SMF      DD DISP=SHR,DSN)=&USERHLQ\.\.&PROJECT\.\.SMF#$1=$testfile#;
    }

    print RMFJCLOUT;
  }
  close RMFJCLOUT;
  close RMFJCLIN;
}

sub sendreceive_XMITfiles
{
  # Create the FTP commands to send the XMIT files
  open FTPINPUT, ">$resultsdir\\ftp.input";
  print FTPINPUT "$zuserid\n";
  print FTPINPUT "bin\n";
  print FTPINPUT "quote site lrecl=80 blksize=6160 recfm=fb primary=10 secondary=10\n";
  print FTPINPUT "put $rundir\\zos\\rmfhw.xmit $zuserid.rmfhw.xmitbin\n";
  print FTPINPUT "put $rundir\\zos\\rmfjcl.xmit $zuserid.rmfjcl.xmitbin\n";
  if (-f "$rundir\\zos\\rmfjcl.db2.xmit")
  {
    print FTPINPUT "put $rundir\\zos\\rmfjcl.db2.xmit $zuserid.rmfjcl.db2.xmitbin\n";
  }
  if (-f "$rundir\\zos\\rmfdbrm.db2.xmit")
  {
    print FTPINPUT "put $rundir\\zos\\rmfdbrm.db2.xmit $zuserid.rmfdbrm.db2.xmitbin\n";
  }
  print FTPINPUT "put $rundir\\zos\\rmfload.xmit $zuserid.rmfload.xmitbin\n";
  print FTPINPUT "quit\n";
  close FTPINPUT;
  log_exec("$bindir\\doftp.bat $resultsdir\\ftp.input\n");

  # Create the Receive job and execute
  open RECEIVEJCL, ">$resultsdir\\receive.jcl";
  print RECEIVEJCL "//${zuserid}R JOB ,IMUSGU1,NOTIFY=IMUSGU1,MSGLEVEL=(1,1),        \n";
  print RECEIVEJCL "//             COND=(16,LT), Terminate if a step ends with RC>4\n";
  print RECEIVEJCL "//             REGION=0M                                       \n";
  print RECEIVEJCL "//*                                                        \n";
  print RECEIVEJCL "//STEPHW   EXEC PGM=IKJEFT01,REGION=0M,DYNAMNBR=50         \n";
  print RECEIVEJCL "//SYSTSIN  DD *                                            \n";
  print RECEIVEJCL "receive inda('$zuserid.rmfhw.xmitbin')                     \n";
  print RECEIVEJCL "da('rmfmagic.$testversion.hardware')                       \n";
  print RECEIVEJCL "end                                                        \n";
  print RECEIVEJCL "//SYSTSPRT DD SYSOUT=*                                     \n";
  print RECEIVEJCL "//SYSTSOUT DD SYSOUT=*                                     \n";
  print RECEIVEJCL "//SYSIN    DD DUMMY                                        \n";
  print RECEIVEJCL "//*                                                        \n";
  print RECEIVEJCL "//STEPJCL  EXEC PGM=IKJEFT01,REGION=0M,DYNAMNBR=50         \n";
  print RECEIVEJCL "//SYSTSIN  DD *                                            \n";
  print RECEIVEJCL "receive inda('$zuserid.rmfjcl.xmitbin')                    \n";
  print RECEIVEJCL "da('rmfmagic.$testversion.jcl')                            \n";
  print RECEIVEJCL "end                                                        \n";
  print RECEIVEJCL "//SYSTSPRT DD SYSOUT=*                                     \n";
  print RECEIVEJCL "//SYSTSOUT DD SYSOUT=*                                     \n";
  print RECEIVEJCL "//SYSIN    DD DUMMY                                        \n";
  print RECEIVEJCL "//*                                                        \n";
  print RECEIVEJCL "//STEPLD   EXEC PGM=IKJEFT01,REGION=0M,DYNAMNBR=50         \n";
  print RECEIVEJCL "//SYSTSIN  DD *                                            \n";
  print RECEIVEJCL "receive inda('$zuserid.rmfload.xmitbin')                   \n";
  print RECEIVEJCL "da('rmfmagic.$testversion.load')                           \n";
  print RECEIVEJCL "end                                                        \n";
  print RECEIVEJCL "//SYSTSPRT DD SYSOUT=*                                     \n";
  print RECEIVEJCL "//SYSTSOUT DD SYSOUT=*                                     \n";
  print RECEIVEJCL "//SYSIN    DD DUMMY                                        \n";
  print RECEIVEJCL "//*                                                        \n";
  if (-f "$rundir\\zos\\rmfjcl.db2.xmit")
  {
    print RECEIVEJCL "//STPJDB2  EXEC PGM=IKJEFT01,REGION=0M,DYNAMNBR=50       \n";
    print RECEIVEJCL "//SYSTSIN  DD *                                          \n";
    print RECEIVEJCL "receive inda('$zuserid.rmfjcl.db2.xmitbin')              \n";
    print RECEIVEJCL "da('rmfmagic.$testversion.db2.jcl')                      \n";
    print RECEIVEJCL "end                                                      \n";
    print RECEIVEJCL "//SYSTSPRT DD SYSOUT=*                                   \n";
    print RECEIVEJCL "//SYSTSOUT DD SYSOUT=*                                   \n";
    print RECEIVEJCL "//SYSIN    DD DUMMY                                      \n";
    print RECEIVEJCL "//*                                                      \n";
  }
  if (-f "$rundir\\zos\\rmfdbrm.db2.xmit")
  {
    print RECEIVEJCL "//STPDBRM  EXEC PGM=IKJEFT01,REGION=0M,DYNAMNBR=50       \n";
    print RECEIVEJCL "//SYSTSIN  DD *                                          \n";
    print RECEIVEJCL "receive inda('$zuserid.rmfdbrm.db2.xmitbin')             \n";
    print RECEIVEJCL "da('rmfmagic.$testversion.db2.dbrm')                     \n";
    print RECEIVEJCL "end                                                      \n";
    print RECEIVEJCL "//SYSTSPRT DD SYSOUT=*                                   \n";
    print RECEIVEJCL "//SYSTSOUT DD SYSOUT=*                                   \n";
    print RECEIVEJCL "//SYSIN    DD DUMMY                                      \n";
    print RECEIVEJCL "//*                                                      \n";
  }
  close RECEIVEJCL;
  $rc = log_exec("perl $bindir\\submitjcl.pl $resultsdir\\receive.jcl $resultsdir\\receive.jcl.out");

  # Upload the license
  open FTPINPUT, ">$resultsdir\\ftp.input";
  print FTPINPUT "$zuserid\n";
  print FTPINPUT "cd ..\n";
  print FTPINPUT "ascii\n";
  print FTPINPUT "put $rundir\\license.ini rmfmagic.$testversion.jcl(license)\n";
  print FTPINPUT "quit\n";
  close FTPINPUT;
  log_exec("$bindir\\doftp.bat $resultsdir\\ftp.input\n");
}

###########################################################################
# Logging functions
###########################################################################

sub open_log {
  my $logfile = "$resultsdir\\$Config{currenttests}.log";

  open LOG, ">>$logfile" or return 0;

  my $old_fh = select(LOG); # save output handle, set LOG to current
  $| = 1;                   # unbuffer output to current output handle
  select($old_fh);          # restore former current handle

  write_log("-" x 75);
  write_log("  RMFmagic Test Suite version $VERSION");
  write_log("  Copyright (C) 2003-2009 IntelliMagic B.V. All rights reserved.");
  write_log(" ");
  write_log("  " . nicedate() . " " . nicetime() .
            "     $ENV{USERNAME}\@$ENV{COMPUTERNAME}");
  write_log( "-" x 75, "\n");

  return 1;
}

# --------------------------------------------------------------------
# Name:         close_log
# Syntax:       close_log();
# Parameters:
# Return value:
# Purpose:      close log file LOG
# History:
#   990727 0.0.1 KoosL: Created
# --------------------------------------------------------------------
sub close_log {
    write_log("\n" . "-" x 75);
    write_log("\n  Finished at " . nicedate() . " " . nicetime());
    write_log("\n" . "-" x 75);

    close LOG;
}

# --------------------------------------------------------------------
# Name:         log_section
# Syntax:       log_section($description);
# Parameters:   $description
# Return value:
# Purpose:      start a new log section
# History:
#   990727 0.0.1 KoosL: Created
# --------------------------------------------------------------------
sub log_section {
    my $line = "\n" . "-" x 75 . "\n" .
               "[" . nicetime() . "] $_[0]\n\n";
    print $line;
    print LOG $line;
}

# --------------------------------------------------------------------
# Name:         write_log
# Syntax:       write_log();
# Parameters:   list of values to write to log
# Return value:
# Purpose:      write values (strings) to log file
# History:
#   990727 0.0.1 KoosL: Created
# --------------------------------------------------------------------
sub write_log {
    print "@_\n";      # print to STDOUT
    print LOG "@_\n";  # and to LOG
}

# --------------------------------------------------------------------
# Name:         log_exec
# Syntax:       $rc = log_exec($cmd);
# Parameters:   $cmd
# Return value: $rc return value of executed command
# Purpose:      executes $cmd, writes output to log file
# History:
#   990727 0.0.1 KoosL: Created
# --------------------------------------------------------------------
sub log_exec {
#    my $cmd = $_[0];
#    write_log("Executing $cmd\n");
#    my @output = `$cmd`;
#    write_log(@output);
#    return $?;
    my $cmd = $_[0];
    write_log("Executing $cmd\n");
    open EXEC, "$cmd |";
    while (<EXEC>) {
      chomp;
      write_log($_);
    }
    close EXEC;
    return $?;
}

# --------------------------------------------------------------------
# Name:         log_verify
# Syntax:       $error = log_verify($filename);
# Parameters:   $filename
# Return value: $error = 0 if file exists, 1 otherwise
# Purpose:      verifies existence of $filename, writes to log file
# History:
#   990727 0.0.1 KoosL: Created
# --------------------------------------------------------------------
sub log_verify {
    my $filename = $_[0];
    my $line = "\nVerifying existence of $filename: ";
    my $found = -e $filename;
    $line .= $found ? "Found\n" : "Not found\n";
    write_log($line);
    return not $found;
}

# --------------------------------------------------------------------
# Name:         nicedate
# Syntax:       $datestring = nicedate();
# Parameters:
# Return value: date string
# Purpose:      returns printable string of the current date
# History:
#   990727 0.0.1 KoosL: Created
# --------------------------------------------------------------------
sub nicedate {
    my @time = localtime();
    $time[4]++;  # month is 0-based
    return sprintf "%d-%.2d-%.2d", $time[5]+1900, $time[4], $time[3];
}

# --------------------------------------------------------------------
# Name:         nicetime
# Syntax:       $timestring = nicetime();
# Parameters:
# Return value: time string
# Purpose:      returns printable string of the current time
# History:
#   990727 0.0.1 KoosL: Created
# --------------------------------------------------------------------
sub nicetime {
    my @time = localtime();
    return sprintf "%.2d:%.2d:%.2d", $time[2], $time[1], $time[0];
}

# --------------------------------------------------------------------
# Name:         read_config
# Syntax:       read_config($filename);
# Parameters:   $filename
# Return value: none
# Purpose:      reads configuration data from a file into %Config
# History:
#   990727 0.0.1 KoosL: Created
# --------------------------------------------------------------------
sub read_config {
  my $filename = $_[0];
  my ($key, $val);
  my $section = "";
  open CFG, "$filename" or die "Cannot open configuration file: $!\n";

  while (<CFG>) {
      chomp;
      s/(#.*)$//g;               # remove comments
      next if /^\s*$/;           # skip empty lines

      # sections?
      if (/\[(.*)\]/) {
          # found a section. Valid sections are [versions], [tests], [default] and [computername]
          # Treat [tests] and [computername] differently
          if ($1 eq 'versions' or $1 eq 'tests' or  $1 eq 'default') {
              $section = $1;
              next;
            }

          if ($1 eq $ENV{'COMPUTERNAME'}) {
              $section = 'override';
              next;
            }

          $section = 'skip';
          next;
        }

      next if ($section eq 'skip'); # skip override settings for other PC's

      if ($section eq 'tests') {
          # process test line
	      # Lines consists of:
	      # test_name#where_to_start_the_test#platformsmf/rmz/rmc_name
          #
	      my ($testname, $teststart, $testplatform, $testmachine, $testfile) = split/@/;
	      $testname =~ s/^\s+//;     # remove leading blanks
	      $testname =~ s/\s+$//;     # remove trailing blanks
	      $teststart =~ s/^\s+//;    # remove leading blanks
	      $teststart =~ s/\s+$//;    # remove trailing blanks
	      $testplatform =~ s/^\s+//; # remove leading blanks
	      $testplatform =~ s/\s+$//; # remove trailing blanks
	      $testmachine =~ s/^\s+//; # remove leading blanks
	      $testmachine =~ s/\s+$//; # remove trailing blanks
	      $testfile =~ s/^\s+//;     # remove leading blanks
	      $testfile =~ s/\s+$//;     # remove trailing blanks

	       # Now store in the %Tests structure
	       if ($testname && $teststart && $testplatform && $testmachine && $testfile) {
              $Tests{lc($testname)} = {
	              RunTestFrom => $teststart,
		          TestPlatforms => $testplatform,
                  TestMachine   => $testmachine,
		          TestFile => $testfile
	            };

	        }

	      next;
        }

      next unless /=/;           # skip if no '=' found
      ($key, $val) = split /=/;
      for ($key) {
          s/^\s+//;              # remove leading blanks
          s/\s+$//;              # remove trailing blanks
        }

      for ($val) {
          s/^\s+//;
          s/\s+$//;
          s/^"//;                # remove leading/trailing quotes
          s/"$//;
          s/(%(\w+)%)/$Config{lc($2)}/eg;  # expand vars
        }

      if ($section ne 'override' and $Config{lc($key)}) {
          # skip if a key was already defined and it is not the PC override section
          next;
        }
      $Config{lc($key)} = $val if ($key && $val); # store
    }
  close CFG;
}

# --------------------------------------------------------------------
# Name:         check_config
# Syntax:       check_config();
# Parameters:
# Return value:
# Purpose:      checks validity of configuration data
# History:
#   990727 0.0.1 KoosL: Created
# --------------------------------------------------------------------
sub check_config {
  # ToDo
}

# --------------------------------------------------------------------
# Name:         replace_in_file
# Syntax:       replace_in_file($filename, $sub);
# Parameters:   $filename, $sub
# Return value: 1 on failure
# Purpose:      modifies $filename in place using $sub.
# --------------------------------------------------------------------
sub replace_in_file($$)
{
    my $filename = shift;
    my $replacementSub = shift;

    chmod 0666, $filename;

    tie my @thetie, 'Tie::File', $filename or die "Can't tie $filename: $!";
    foreach (@thetie)
    {
        $_ = &$replacementSub($_);
    }
    untie @thetie;

    return 0;
}

# --------------------------------------------------------------------
# Name:         delete_file_if_empty
# Syntax:       delete_file_if_empty($filename);
# Parameters:   $filename
# Return value: 1 on failure
# Purpose:      deletes $filename if it is empty (0 bytes big).
# --------------------------------------------------------------------
sub delete_file_if_empty($)
{
    my $filename = shift;
    if (-z $filename)
    {
      unlink $filename;
    }

    return 0;
}

# --------------------------------------------------------------------
# Name:         file_newer
# Syntax:       file_newer($file1, $file2);
# Parameters:   $file1, $file2
# Return value: 0 if $file1 older than $file2, 1 if $file1 newer than $file2.
# Purpose:      Compares file age of $file1 to file age of $file2.
# --------------------------------------------------------------------
sub file_newer($$)
{
  my $file1 = shift;
  my $file2 = shift;

  return 1 unless (-e $file2); # file to compare to does not exist, this means newer
  return 0 unless (-e $file1); # this file should actually be there, assume older

  if ((stat($file1))[9] > (stat($file2))[9]) {
    return 1;
  } else {
    return 0;
  }
}

# --------------------------------------------------------------------
# Name:         executePCapp
# Syntax:       executePCapp($testmachine, $execcmd);
# Parameters:   $testmachine, $execcmd
# Return value: Return value of (remote) command
# Purpose:      Executes $execcmd either locally or $testmachine remotely,
#               depending on where the test was started
# --------------------------------------------------------------------
sub executePCapp($$)
{
  my $testmachine = shift;
  my $execcmd = shift;

  if ($ENV{COMPUTERNAME} eq $testmachine) {
    # Execute locally
    return log_exec("$execcmd");

  } elsif ($testremote) {
    # Push the scripted test to $testmachine
    # Create a batch file that will execute on the remote system
    # Use psexec to copy and execute the batch file on the remote system
    open RUNCOMMAND, ">$resultsdir\\runremote.cmd";
    print RUNCOMMAND "\@echo off\n";
    print RUNCOMMAND "net use T: \\\\imserver5\\testsuite\n";
    print RUNCOMMAND "net use U: \\\\imserver5\\testdata\n";
#    print RUNCOMMAND "$bindir\\pskill -accepteula excel.exe\n";
#    print RUNCOMMAND "$bindir\\pskill -accepteula RMFM4W.exe\n";
#    print RUNCOMMAND "$bindir\\pskill -accepteula rmfmagic.exe\n";
	print RUNCOMMAND "del \"C:\\Documents and Settings\\swtester\\Application Data\\Microsoft\\Excel\\XLSTART\\RMF Magic Excel runtime.xls\"\n";
	print RUNCOMMAND "copy \"$rundir\\RMF Magic Excel runtime.xls\" \"C:\\Documents and Settings\\swtester\\Application Data\\Microsoft\\Excel\\XLSTART\"\n";
    print RUNCOMMAND "$execcmd\n";
    close RUNCOMMAND;

    return log_exec("$bindir\\psexec.exe -i 0 -accepteula \\\\$testmachine -u $Config{winuserid} -p $Config{winpw} -c \"$resultsdir\\runremote.cmd\"");
  }
}

# --------------------------------------------------------------------

sub mail_tester
{
    my $from = "$Config{email_from}";
    my $to = "$Config{email_to}";
    my $subject;

    if ($rc)
    {
      $subject = "Tests for $Config{currenttests} failed";
    } else
    {
      $subject = "Tests for $Config{currenttests} ran successfully. Check diffs.";
    }

    my $smtp = Net::SMTP->new('immaster.intellimagic.local');

    $smtp->mail($from);
    $smtp->to($to);

    $smtp->data();
    $smtp->datasend("From: $from\n");
    $smtp->datasend("To: $to\n");
    $smtp->datasend("Subject: $subject\n");
    $smtp->datasend("\n");

    my $logfile = "$resultsdir\\$Config{currenttests}.log";
    open my $log, $logfile or die;
    while (<$log>)
    {
	$smtp->datasend($_);
    }

    $smtp->quit;
}

sub mail_start_test
{
    my $from = "$Config{email_from}";
    my $to = "$Config{email_to}";
    my $subject = "Test is started for $Config{currenttests} against $Config{previoustests};";

    my $smtp = Net::SMTP->new('immaster.intellimagic.local');
    $smtp->mail($from);
    $smtp->to($to);
    $smtp->data();
    $smtp->datasend("From: $from\n");
    $smtp->datasend("To: $to\n");
    $smtp->datasend("Subject: $subject\n");
    $smtp->datasend("\n");
	
	my $cfgfile = "$configdir\\cleantests.cfg";
    open LOG, $cfgfile;
    while (<LOG>)
    {
		$smtp->datasend($_);
    }
	close LOG;
	close $cfgfile;
    $smtp->quit;
}

sub clean_configuration_file
{
  my $file = shift;
  my $cleanfile = shift;
  
  open CLEANCFG, ">$cleanfile";
  open CFG, "$file";
  while (<CFG>) {
    s/(#.*)$//g;               # remove comments
    next if /^\s*$/;           # skip empty lines
	print CLEANCFG;
  }
  close CFG;
  close CLEANCFG;
}

# --------------------------------------------------------------------
# The End.
# --------------------------------------------------------------------

