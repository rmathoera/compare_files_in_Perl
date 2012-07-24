#!/usr/bin/perl -w

###############################################################################
# Copyright:  (c) 2004-2012 by IntelliMagic B.V.  All Rights Reserved
#
# Name:
#   IM_Compare.pl
#
# Purpose:
#   compare RMFmagic_test_output currentversion previuosversion
#
###############################################################################

=head1 IM_Compare.pl

IM_Compare.pl - compare IntelliMagic test results

=head1 SUBROUTINES:

=cut

# Define and set default value, to be used from or for Perl functions 
use strict;
use warnings;
use Cwd qw( abs_path cwd );
use File::Path;
use File::Copy;
use File::Slurp;
use Tie::File;
use Net::SMTP;

use File::Basename;
use File::Compare;
use File::Find;
use Time::Local;

use File::Glob ':glob';
use Term::ReadKey;
use Net::SMTP;
use File::Copy::Recursive qw(dircopy);

# Define all internal Intellimagic Vision functions
use IMPostProcess;

# Set current path into variable $dir
my $dir = cwd();

# --------------------------------------------------------------------
# Prototypes
# --------------------------------------------------------------------
sub folderCompare($$);
sub dmcCompare ($$$$);
sub csvCompare ($$$$);
sub textCompare ($$$$);
sub replace_in_file($$);
sub delete_file_if_empty($);
sub file_newer($$);
#sub check_argument();
#sub read_config();
#sub check_config();
#sub write_log();

# --------------------------------------------------------------------
# global variables that will be used in this script only
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
my $VERSION = "3.0.0";    # script version
# Base test folder setup
my $scriptdir = $dir;
my $configdir = $dir;
$configdir =~ s#/#\\#g;
$configdir =~ s#^(.*)\\.*#$1#;
$rootdir = dirname($scriptdir);
$bindir = "$rootdir/bin";
$runbasedir = "$rootdir/run";
$resultsbasedir = "$rootdir/Results";
$sysindir = "$rootdir/Sysin";
my $rundir = "";
my $resultsdir = "";
my $testversion = "";
my $rc = 0;
my $testname = "";

# --------------------------------------------------------------------
# main script of Compare function
# --------------------------------------------------------------------

read_config("$configdir/tests.cfg");
check_config(); # at the moment this is a stub!!!
preset_configuration();

# $testname  $Config{currenttests}  $Config{previoustests}
check_argument();

# open the logfile
open_log($resultsdir, $testname);
write_log ("Script Directory $scriptdir");
write_log ("Config Directory $configdir");
write_log ("Start compare of test          : $testname");
write_log ("Compare of currenttests        : $Config{currenttests}");
write_log ("Compared against previoustests : $Config{previoustests}");

new_folder_compare($Config{currenttests}, $Config{previoustests}, $testname);

# close the log
close_log();
# --------------------------------------------------------------------
# End of Compare function
# --------------------------------------------------------------------


# --------------------------------------------------------------------
# Check switches to be processed
# --------------------------------------------------------------------
sub preset_configuration {

	my $zuserid = uc($Config{zosuserid});
	my $zpw     = $Config{zospw};
	$ENV{MVSHOST} = $Config{zoshost};
	$ENV{MVSUSER} = $zuserid;
	$ENV{MVSPWD} = $zpw;

	$testversion = $Config{currenttests};
	$rundir = "$runbasedir/$Config{currenttests}";
	$resultsdir = "$resultsbasedir/$Config{currenttests}";
	return;
}

# --------------------------------------------------------------------
# Check switches to be processed
# --------------------------------------------------------------------
sub check_argument {
# proces command-line input
#	my ($arg1, $arg2, $arg3) = @_;

	if ($ARGV[0] ne '') {
		$testname = "$ARGV[0]";
		}
	if ($ARGV[1] ne '') {
		$Config{currenttests} = "$ARGV[1]";
		}
	if ($ARGV[2] ne '') {
		$Config{previoustests} = "$ARGV[2]";
		}
#	return;
}

=head1 sort_rows

=head2 NAME

sort_rows - sort rows of fields lexicographically

=head2 SYNOPSIS

  my @sorted_rows = sort_rows( [ 'row 1 field 1', 'row 1 field 2' ], 
                               [ 'row 2 field 1', 'row 2 field 2' ] );

=head2 DESCRIPTION

Sorts an array of array references ("rows") based on field-by-field
lexicographic order, except for the first array reference which is
assumed to represent a header row and remains at the beginning of the
array.

The rows are compared field by field, starting at the first field.
Field values are compared lexicographically.

=cut
sub sort_rows {
  my (@rows) = @_;
  my @headerrow = @{$rows[0]};

  my @sortedrows = sort 
  {
    my $i = 0;
    my $result = $a->[$i] cmp $b->[$i];
    while (not $result and ++$i <= $#{$a}) {
      $result = $a->[$i] cmp $b->[$i];
    }
    $result;
  }
  @rows[1..$#rows];
  return ( \@headerrow, @sortedrows ); # header row comes first
}

=head1 write_csv_file

=head2 NAME

write_csv_file - write rows of fields to a CSV file

=head1 SYNOPSIS

  write_csv_file('target_file_name', [ 'row 1 field 1', 'row 1 field 2' ], 
                                     [ 'row 2 field 1', 'row 2 field 2' ] );

=head1 DESCRIPTION

Writes data values from an array of array references ("rows") to a
file in CSV format.  Each dereferenced array reference is written to
one line in the CSV file (assuming the field values contain no
newlines).  Fields are separated by commas in the CSV file.  Double
quotes in the field values are escaped by doubling them (" => "").  All
data values that do not resemble a simple number (optional sign, one
or more decimal digits, optional period, optional digits) are enclosed
in double quotes.

=head1 NOTES

Unfortunately, L<IMPostProcess::read_csv_file> (using
L<Text::CSV::Simple>) has removed field-value-delimiting double
quotes, and cannot be configured to leave those intact.
L<Text::CSV_XS> (but not L<Text::CSV::Simple>) can write csv files,
but does not distinguish between numerical and non-numerical values
and might write some non-numerical values (that don't contain comma,
newline, or double quote) without enclosing double quotes.  Our dba
csv files always have values in text columns enclosed in double
quotes.  We aim to double-quote all non-numerical values; we may still
end up with different quoting than in the original csv file if an
original text field happens to contain a value that looks like a
numerical value.

=cut
sub write_csv_file {
  my ($filename, @rows) = @_;
  unless (open FILE, '>', $filename) {
    write_log ("FAILED to open file %$filename for writing sorted rows -- keeping possibly unsorted rows");
    return;
  }
  my $row = shift @rows;        # header row
  print FILE join(',', @$row) . "\n";
  while ($row = shift @rows) {
    print FILE join(',', map { s/\"/\"\"/g; m|^[-+]?\d+(?:\.\d+)?$|? $_: "\"$_\"" } @$row) . "\n";
  }
  close FILE;
}

# Memory efficient way of sorting a csv file
sub sort_csv_file( $ )
  {
    my ( $file ) = @_;

    my @lines = ();
    my $parser = Text::CSV::Simple->new( { allow_whitespace => 1 } );
    $parser->add_trigger(
                         before_parse => sub { 
                           my ( $self, $line ) = @_;
                           die unless $line =~ /,/i;
                         }
                        );
    $parser->add_trigger(
                         on_failure => sub { 
                           my ($self, $csv ) = @_;
                           # unfortunately, no line number is available
                           die "CSV parser error " . $csv->error_diag() . "; file $file; line " . $csv->error_input;
                         }
                        );
    $parser->add_trigger(
                         after_parse => sub {
                           my ( $self, @data ) = @_;
                           my $line = join(',', map { m|^[-+]?\d+(?:\.\d+)?$|? $_: "\"$_\"" } @{$data[0]});
                           push ( @lines, $line );
                           die "Don't add data to global structure";
                         }
                        );

    $parser->read_file( $file );
    $parser = undef;

    if (open ( my $out, '>', $file )) {
      print $out $lines[0]."\n";
      foreach ( sort @lines[1..$#lines] )
      {
        print $out $_."\n";
      }
      close $out;
    } else {
      write_log ("FAILED to open file $file for writing sorted rows -- keeping possibly unsorted rows");
      return;
    }
  }

# --------------------------------------------------------------------
# Folder compare
# --------------------------------------------------------------------
sub new_folder_compare {
    my ($current_build, $previous_build, $test_id) = @_;
    my @starting_directories;
    my $compare_standard;
    my $reference_path;
    my $current_path;

    my $root_directory = cwd . "/../Results";
    my $temp_dir_root = cwd . "/../tmp_$$";

    my $files_differ;
    my %files;
    my %path;

    if (!-d "$root_directory/$current_build/$test_id" || !-d "$root_directory/$previous_build/$test_id") {
        write_log ("Test $test_id has not been defined for build $current_build and/or $previous_build");
        write_log ("$root_directory/$current_build/$test_id");
        write_log ("$root_directory/$previous_build/$test_id");
    return
    }

    $compare_standard = sub {
        my ($source_file, $destination_file, $file_key, $path);
        $file_key = $destination_file = $source_file = $File::Find::name;
        return if /^\./; #don't bother with hidden files and parent and current directories
        return if $file_key =~ /\/(?:diff|unzipped)\//;
        $file_key =~ s/^.*?[\/\\]$reference_path[\/\\]//; # relative to test directory
        $destination_file =~ s/$reference_path/$current_path/;
        if (-f $source_file) {
            return if exists $files{$file_key};
            if (!-f $destination_file) {
                $files{$file_key} = $reference_path;
                return;
            }
            return if -B $source_file && $source_file !~ /\.dmc$/;

            # LS 2012-06-19 If the contents of the source and
            # destination files differ from each other, then copies of
            # them should end up in the temp directory.  If the
            # contents are identical, then no copies should end up in
            # the temp directory.  If the files are .csv files in the
            # dba folder, then their contents should be compared only
            # after sorting them (because old original .csv files
            # weren't sorted while new original .csv files are --
            # leading to spurious difference detections).  The
            # original files should not be modified.
            
            # (There are also .csv files in the report folder; those
            # use the regional format and might have multiple header
            # lines, unlike the .csv files in the dba folder, which
            # always use a fixed format and always have a single
            # header line.  There is no sort order problem for .csv
            # files in the report folder at the moment, so we only
            # treat .csv files in the dba folder differently.)

            my $dbacsv = qr[\bdba/[^./]+\.csv$]i; # matches dba csv files

            if ($source_file !~ $dbacsv) {
              # not dba csv files: compare first, copy if different
              $files{$file_key} = ( $files_differ = compare ($source_file, $destination_file)) ? '!=' : '==';
              write_log (sprintf "Comparing %s (files %s)",
                         $file_key,
                         $files_differ
                         ? 'differ'
                         : 'are identical');
              return if !$files_differ;
            }

            # the next block can (should) be moved into its own sub!

            if (!exists $path{$File::Find::dir}) {
              my $new_path = $File::Find::dir;
              $new_path =~ s/^$root_directory/$temp_dir_root/;
              $path{$File::Find::dir} = [$new_path];
              mkpath $new_path;
              $new_path =~ s/$reference_path/$current_path/;
              push @{$path{$File::Find::dir}}, $new_path;
              mkpath $new_path;
            }
            copy $source_file, $path{$File::Find::dir}->[0];
            copy $destination_file, $path{$File::Find::dir}->[1];

            if ($source_file =~ $dbacsv) {
              # dba csv files: copied first, now sort and compare.
              # If equal, then delete copies.
              my ($file_name) = $file_key =~ m|/([^/]+)$|; # file name only
              foreach (0..1) {
                my $f = $path{$File::Find::dir}->[$_] . "/$file_name";
                sort_csv_file($f);
              }
              $files{$file_key} = ( $files_differ = compare ($path{$File::Find::dir}->[0] . "/$file_name", $path{$File::Find::dir}->[1] . "/$file_name")) ? '!=' : '==';
              write_log (sprintf "Comparing %s (files %s)",
                         $file_key,
                         $files_differ
                         ? 'differ'
                         : 'are identical');
              if (not $files_differ) {
                unlink $path{$File::Find::dir}->[$_] . "/$file_name" foreach 0..1;
                delete $path{$File::Find::dir};
                return;
              }
            }
        }
    };
    $reference_path = $current_build;
    $current_path = $previous_build;
    @starting_directories = ("$root_directory/$reference_path/$test_id");

	# Cleanup old diff map, before starting new compare
    rmtree "$starting_directories[0]/diff" if -d "$starting_directories[0]/diff";
    mkpath "$starting_directories[0]/diff";

    find($compare_standard, @starting_directories);

    $reference_path = $previous_build;
    $current_path = $current_build;
    @starting_directories = ("$root_directory/$reference_path/$test_id");
    find($compare_standard, @starting_directories);
    foreach my $file (keys %files) {
        delete $files{$file} if $files{$file} eq '==';
    }

    my %unique_file;
    my @unique_files = map {
        my $test = $files{$_};
        $_ =~ /^[\/\\]*([^\/\\]+)[\/\\]/;
        if ($1) {
            my $test_id = $1;
            $unique_file{$test_id}{$test} = [] if !exists $unique_file{$test_id}{$test};
            push @{$unique_file{$test_id}{$test}}, $_;
        }
        $_;
    } grep $files{$_} ne '!=', (keys %files);

	# delete all unique files from array $files
    map delete $files{$_}, @unique_files;

	# update $files list with only the files that are available in both maps and has suffix 'rpt' 'csv' 'log'
    my %files_to_check;
    my @files_to_check = map {
        $_ =~ /^[\/\\]*([^\/\\]+)[\/\\].*?\.(\w+)$/;
        my ($test_id, $type) = ($1, $2);
  		$type = lc $type;
        $type = 'rpt' if $type eq 'csv' and /\/report\//; # csv file with leading lines
        if ($type eq 'log') {
            my $log = $_;
            $log =~ /([^\/]+)\.log$/i;
            my $logname = $1;
			if ( $logname =~ /$test_id/i )
			{
				$type = 'Project'.$type;
			}
			elsif ( $logname =~ /rmfmagic/i )
			{
				$type = 'Vision'.$type;
			}
			else
			{
				$type = lc substr($logname,0,1).$type;
			}
        }
        $files_to_check{$type}{$test_id} = [] if !exists $files_to_check{$type}{$test_id};
        push @{$files_to_check{$type}{$test_id}}, $_;
        [$_, $type, $test_id];
    } grep /[\/\\]/, (keys %files);

	# extract all DMC files
    for my $type ('dmc') {
        do {
            my $log_message = extract_zipfiles(
                $temp_dir_root,
                $current_build,
                $previous_build,
                $files_to_check{$type}
            );
            write_log($log_message);
        } if exists $files_to_check{$type};
    }
	# Reports all unique files
    report_unique_files($test_id, $unique_file{$test_id}, {$previous_build => '< File no longer exists', $current_build => '> File is new'}) if keys %unique_file;

    my %function_hash = %{fill_function_hash()};

    foreach my $type (sort keys %files_to_check) {
        my %files_to_check_by_type = %{$files_to_check{$type}};
	
        do {
            write_log ("No preprocessing function defined for filetype '$type'. Reverting to generic compare (all differences reported)");
            $type = 'generic';
        } if !exists $function_hash{$type};
        
	foreach my $test_id (sort keys %files_to_check_by_type) {
            my @files_to_check = @{$files_to_check_by_type{$test_id}};
            my @indices = sort {$b <=> $a} (0 .. $#files_to_check);

            foreach my $file_index (@indices) {
                write_log (sprintf "Processing %s", $files_to_check[$file_index]);
                my $log_message = &{$function_hash{$type}}($temp_dir_root, $previous_build, $current_build, $files_to_check[$file_index]) if exists $function_hash{$type};

                do {
                    write_log(join "\n", @$log_message); # should go into test-summary instead of 'ordinary' log
                    next;
                } if defined $log_message && @$log_message;

                write_log("No differences found after post-processing $files_to_check[$file_index]");
                splice @{$files_to_check_by_type{$test_id}}, $file_index, 1;
                unlink "$temp_dir_root/$current_build/$files_to_check[$file_index]";
            }
            delete $files_to_check{$type}{$test_id} unless @{$files_to_check_by_type{$test_id}};
        }
        delete $files_to_check{$type} unless keys %{$files_to_check{$type}};
    }

# move postprocessed files with differences from <tempdir>/<build>/<test> to Results/<build>/<test>/diff
    my $source_root = "$temp_dir_root/$current_build/$test_id";
    my $target_root = "$root_directory/$current_build/$test_id/diff/text";
    $source_root =~ s/[^\/]*\/\.\.\///g;
    $source_root =~ s/[^\/]*\/\.\///g;
    $target_root =~ s/[^\/]*\/\.\.\///g;
    $target_root =~ s/[^\/]*\/\.\///g;
    move_to_archive($source_root, $target_root) if (-d $source_root);
# and don't forget to cleanuo after us..
    rmtree $temp_dir_root or die "Couldn't remove temporary directory $temp_dir_root\n";
#move difference from ./<test>/<diff> to Results/<build>/<test>/diff
    $source_root = cwd . "/$test_id/diff";
    $target_root = "$root_directory/$current_build/$test_id/diff";
    $target_root =~ s/[^\/]*\/\.\.\///g;
    $target_root =~ s/[^\/]*\/\.\///g;
    my $cwd = cwd;
    move_to_archive($source_root, $target_root)  if (-d $source_root);
    chdir $cwd;
#cleaning up the run-directory as well...
# one dir up from $source_root as we want to get rid of the testname as well
    rmtree "$cwd/$test_id" ; 

    rollup_diff_files($target_root, $test_id);
}
# --------------------------------------------------------------------
#  end of test compare
# --------------------------------------------------------------------

# --------------------------------------------------------------------
#  from here all sub functions used for the main script.
# --------------------------------------------------------------------
sub fill_function_hash {
    return {
        bat         => \&process_bat_file,
        cmd         => \&process_cmd_file,
        csv         => \&process_csv_file,
        CSV         => \&process_csv_file,
        dmc         => \&process_dmc_file,
        htm         => \&process_htm_file,
        ini         => \&process_ini_file,
        jcl         => \&process_jcl_file,
        out         => \&process_out_file,
        rmc         => \&process_rmc_file,
        rmp         => \&process_rmp_file,
        rpt         => \&process_rpt_file,
        txt         => \&process_txt_file,
        flog        => \&process_flog_file,
        alog        => \&process_alog_file,
        rlog        => \&process_rlog_file,
        input       => \&process_txt_file,
        rmfmgo      => \&process_rmfmgo_file,
        Visionlog   => \&process_Visionlog_file,
        Projectlog  => \&process_Projectlog_file,
        generic     => \&process_generic_file,
    }
}

# --------------------------------------------------------------------
# Create list and report of all unique files
# --------------------------------------------------------------------
sub report_unique_files {
    my ($test_id, $hash_ref, $message_ref) = @_;

#    write_log('');
    foreach my $resultset (sort {$b cmp $a} keys %$hash_ref) {
        write_log("File(s) unique for resultset $resultset:");
        foreach (@{$hash_ref->{$resultset}}) {
            my $unique_file = $_;
            $unique_file =~ /^[^\/]+\/(.+)$/;
            write_log("\t$1");
            report_unique_file($resultset, "$test_id/$1", $message_ref->{$resultset});
        }
    }
}

# --------------------------------------------------------------------
# Create report of differences found after compare.
# --------------------------------------------------------------------
sub rollup_diff_files {
    my ($rootdirectory, $testname) = @_;

    my @days = qw (
        SUN
        MON
        TUE
        WED
        THU
        FRI
        SAT
    );
    my @months = qw (
        JAN
        FEB
        MAR
        APR
        MAY
        JUN
        JUL
        AUG
        SEP
        OCT
        NOV
        DEC
    );
    my $cwd = cwd;
    chdir $rootdirectory;

    opendir DIR, $rootdirectory or die "Couldn't open $rootdirectory\n";
    my @diff_files = grep -f, readdir DIR;
    closedir DIR;

    my @diff_log;

	if (@diff_files) 
	{
		foreach my $file (@diff_files) {
			my @status = stat $file;
			my @mtime = localtime $status[9];
			my @data = read_file $file;
			map s/[\r\n]+$/\n/, @data;
			my $datestring = sprintf "%s %s %02d %02d:%02d:%02d %04d",
				$days[$mtime[6]],
				$months[$mtime[4]],
				$mtime[3],
				$mtime[2],
				$mtime[1],
				$mtime[0],
				$mtime[5] + 1900;
			unshift @data, "--------------- ---------------------------- ---------------\n";
			unshift @data, sprintf "Difference file last changed: %s\n",
				$datestring;
			unshift @data, sprintf "Difference file created:      %s\n",
				$datestring;
			unshift @data, "Difference file size (bytes): $status[7]\n";
			unshift @data, "--------------- Differences for $file ---------------\n";
			push @data, "--------------- End diff for $file    ---------------\n\n";
			push @diff_log, @data;
		}
		chomp $diff_log[-1];
		write_file "$rootdirectory/../../${testname}_diff.txt", @diff_log or die "Couldn't write differences to ${testname}_diff.txt\n";
	} else
	{
	    write_log("No differences found in all files that have been compared!");
        open DIFFOUTPUT, ">$rootdirectory/../../${testname}_diff.txt" or die "Cannot open file $rootdirectory/../../${testname}_diff.txt: $!\n";
        close DIFFOUTPUT;
	}
    chdir $cwd;
}

# --------------------------------------------------------------------
# Sub to compare results for a single folder against the same folder from
# the previous test. Will also flag if a folder/file does not exist anymore.
# Makes recursive calls to itself to compare per folder
# --------------------------------------------------------------------
sub folderCompare($$)
{
  # params in @_ (test name, sub folder)
  my ($testname, $subfolder) = @_;

  my $currenttestfolder = "$resultsdir/$testname/$subfolder";
  my $previoustestfolder = "$resultsbasedir/$Config{previoustests}/$testname/$subfolder";
  if ($subfolder eq "") {
    $currenttestfolder = "$resultsdir/$testname";
    $previoustestfolder = "$resultsbasedir/$Config{previoustests}/$testname";
  } else {
    $currenttestfolder = "$resultsdir/$testname/$subfolder";
    $previoustestfolder = "$resultsbasedir/$Config{previoustests}/$testname/$subfolder";
  }
  my $diff_folder  = "$resultsdir/$testname/diff";
  my $prev_diff_folder = "$resultsbasedir/$Config{previoustests}/$testname/diff";

  my $diffcmd = "$bindir/diff.exe --ignore-all-space --ignore-blank-lines --ignore-space-change";

  if ($subfolder eq "") {
    write_log("Comparing files in root folder ...");
  } else {
    write_log("Comparing files in folder $subfolder ...");
  }

  mkdir($diff_folder) unless (-d $diff_folder);
  mkdir($prev_diff_folder) unless (-d $prev_diff_folder);

  if (-d $currenttestfolder) {
    opendir(CURRENTTESTFOLDER, $currenttestfolder) || die "can't opendir current test folder $subfolder: $!";
    my @currentfiles = readdir(CURRENTTESTFOLDER);
    closedir CURRENTTESTFOLDER;

    # ToDo: compare number of files/folders

    # Now process each folder/file
    foreach (@currentfiles) {
      next if (m/^\./);                        # no processing for . or .. directories
      print nicetime() . ": processing $_\n";
      next if (m/RMF Magic reduce .*\.log/i);  # do not attempt to compare script generated reduce log files, filename contains run date/time
      next if (m/RMF Magic analyze .*\.log/i); # do not attempt to compare script generated analyze log files, filename contains run date/time
      next if (m/\.jcl\.out/i);
      next if (m/ftp\.input/i);
      next if (m/ftp\.log/i);
      next if (m/ftpexec\./i);
      next if (m/rmfmagic\.cmd/i);

      if (-e "$previoustestfolder/$_") {
        # File/folder exists in both current result set and previous result set
        if (-d "$currenttestfolder/$_") {
          # Another folder, call recursive folderCompare, unless folder name includes diff or unzipped
          my $subsubfolder;
          if ($subfolder eq "") {
            $subsubfolder = $_;
          } else {
            $subsubfolder = "$subfolder/$_";
          }
          folderCompare($testname, $subsubfolder) unless (m/diff/i or m/unzipped/i);

        } elsif (-B "$currenttestfolder/$_") {
          # Binary file, make sure it exists in the previous results
          # Do processing for *.dmc files
          next unless (m/\.dmc$/i);

          # Process DMC file
	  print nicetime() .": dmc-comparing file $_\n";
          dmcCompare($testname, $currenttestfolder, $previoustestfolder, $_);

        } elsif (-f "$currenttestfolder/$_") {
          # A text file, post process and compare. Rules and compare tools used depend on the file extension
          # *.log
          # *.rmc
          # *.csv

          if ($currenttestfolder =~ m/[\/\\]report/i)
          {
            # Generic text compare for report folder CSV files, as they are not really CSV files
			my $filesize = -s "$currenttestfolder/$_";
			print nicetime() . ": csv-comparing file $_ (using diff, $filesize bytes)\n";
            textCompare($testname, $currenttestfolder, $previoustestfolder, $_);

          } elsif (m/\.csv/i) {
            # CSV file comparison
			my $filesize = -s "$currenttestfolder/$_";
			print nicetime() . ": csv-comparing file $_ (using differ, $filesize bytes)\n";
            csvCompare($testname, $currenttestfolder, $previoustestfolder, $_);

          } else {
            # Generic text compare
			my $filesize = -s "$currenttestfolder/$_";
			print nicetime() . ": txt-comparing file $_ (using diff, $filesize bytes)\n";
            textCompare($testname, $currenttestfolder, $previoustestfolder, $_);
          }
        }
      } else {
        # File/folder is not present in previous result set. Write an error.
        if (-d "$currenttestfolder/$_")
        {
          write_log("Folder $subfolder/$_ is new. It did not exist in the previous result set.");
          writeErrorDiff("$diff_folder/$_.txt", "Folder $subfolder/$_ is new. It did not exist in the previous result set.", "$_");
        } else {
          write_log("File $subfolder/$_ is new. It did not exist in the previous result set.");
          writeErrorDiff("$diff_folder/$_", "File $subfolder/$_ is new. It did not exist in the previous result set.", "$_");
        }
      }
    }

    if (-e $previoustestfolder) {
      opendir(PREVTESTFOLDER, $previoustestfolder) || die "can't opendir current test folder $subfolder: $!";
      my @previousfiles = readdir(PREVTESTFOLDER);
      closedir PREVTESTFOLDER;

      foreach (@previousfiles) {
        if (!(-e "$currenttestfolder\\$_")) {
          next if (m/RMF Magic reduce .*\.log/i);  # do not attempt to compare script generated reduce log files, filename contains run date/time
          next if (m/RMF Magic analyze .*\.log/i); # do not attempt to compare script generated analyze log files, filename contains run date/time
          next if (m/\.jcl\.out/i);
          next if (m/ftp\.input/i);
          next if (m/ftp\.log/i);
          next if (m/ftpexec\./i);
          next if (m/rmfmagic\.cmd/i);

          # File/folder did exist in previous test results, but no longer exists. Write an error
          if (-d "$previoustestfolder\\$_") {
            write_log("Folder $subfolder\\$_ did exist in previous result set, but no longer exists in current result set.");
            writeErrorDiff("$diff_folder\\$_.txt", "Folder $subfolder\\$_ did exist in previous result set, but no longer exists in current result set", "$currenttestfolder\\$_");
          } else {
            write_log("File $subfolder\\$_ did exist in previous result set, but no longer exists in current result set.");
            writeErrorDiff("$diff_folder\\$_", "File $subfolder\\$_ did exist in previous result set, but no longer exists in current result set", "$currenttestfolder\\$_");
          }
        }
      }
    }

  } elsif (-d $previoustestfolder) {
    # Folder did exist in previous results, write an error
    write_log("Folder $subfolder does not exist in current result set but did exist in previous result set.");
    writeErrorDiff("$diff_folder\\$subfolder", "Folder $subfolder does not exist in current result set but did exist in previous result set", "$subfolder");
  }

}

# --------------------------------------------------------------------
# Sub to write diff file in case of non-existing compare to file
# --------------------------------------------------------------------
sub writeErrorDiff {
  # params in @_ (diff file to write, where the file is missing, missing csv file)
  my ($diff_file, $missing_where, $missing_file) = @_;

  open DIFFOUTPUT, ">$diff_file" or die "Cannot open diff file $diff_file: $!\n";
  print DIFFOUTPUT "Difference found, missing file in $missing_where test set to compare to $missing_file\n";
  close DIFFOUTPUT;
}

# --------------------------------------------------------------------
# Sub to compare two dmc files
# --------------------------------------------------------------------
sub dmcCompare ($$$$)
{
  # params in @_ (test name, folder with current test results, folder with previous test results, DMC file to compare)
  my ($testname, $currenttestfolder, $previoustestfolder, $dmcFile) = @_;

  my $diff_folder  = "$resultsdir/$testname/diff";
  my $prev_diff_folder = "$resultsbasedir/$Config{previoustests}/$testname/diff";
  my $diffcmd = "$bindir/diff.exe --ignore-all-space --ignore-blank-lines --ignore-space-change";
  write_log ("Start DMC compare function ");																	# for debug only added.
  
  if (file_newer("$currenttestfolder/$dmcFile", "$diff_folder/$dmcFile")) {
    # We need to unzip both DMC files
    mkdir("$diff_folder/unzipped") unless (-d "$diff_folder/unzipped");
    dmcUnzip($dmcFile, $currenttestfolder, "$diff_folder/unzipped");

    unless (-e "prev_diff_folder/unzipped/$dmcFile") {
      # If the unzipped and post procecced file does not exist for the previous test result set, process it
      mkdir("$prev_diff_folder/unzipped") unless (-d "$prev_diff_folder/unzipped");
      dmcUnzip($dmcFile, $previoustestfolder, "$prev_diff_folder/unzipped");

      replace_in_file("$prev_diff_folder/unzipped/$dmcFile",
                      sub {
                        s!(model '.*', description='Created ).*(')!$1\<rundatetime\>$2!i;
                        s!(generated by RMF Magic )\d+\.\d+\.\d+!$1<version>!i;
                        s!(rmfmversion )\d\d\d\d\d!$1<version>!i;
                        $_;
                      } );
    }

    replace_in_file("$diff_folder/unzipped/$dmcFile",
                    sub {
                      s!(model '.*', description='Created ).*(')!$1\<rundatetime\>$2!i;
                      s!(generated by RMF Magic )\d+\.\d+\.\d+!$1<version>!i;
                      s!(rmfmversion )\d\d\d\d\d!$1<version>!i;
                      $_;
                    } );

    # Compare
    my $full_diff_cmd = "$diffcmd \"$prev_diff_folder/unzipped/$dmcFile\" \"$diff_folder/unzipped/$dmcFile\" >\"$diff_folder/$dmcFile\"";
    $full_diff_cmd =~ s/\//\\/g;
    `$full_diff_cmd`;

    delete_file_if_empty "$diff_folder/$dmcFile";
	write_log ("End of DMC compare function.");
  }
}

# --------------------------------------------------------------------
# Sub to compare two csv files
# --------------------------------------------------------------------
sub csvCompare ($$$$)
{
  # params in @_ (test name, folder with current test results, folder with previous test results, CSV file to compare)
  my ($testname, $currenttestfolder, $previoustestfolder, $csvFile) = @_;

  my $diff_folder  = "$resultsdir/$testname/diff";
  my $diffcmd = "$bindir/XMLDiff/differ.exe --";

  if (file_newer("$currenttestfolder/$_", "$diff_folder/$csvFile.txt")) {
    # No need to post process CSV files
	write_log ("csvCompare $previoustestfolder/$_ $currenttestfolder/$_");
	my @previous = read_file( "$previoustestfolder/$_" );
	write_file( "$previoustestfolder/$_.sorted", sort @previous );
	my @current = read_file( "$currenttestfolder/$_" );
	write_file( "$currenttestfolder/$_.sorted", sort @current );
	
    # Compare
    my $full_diff_cmd = "$diffcmd \"$previoustestfolder/$_.sorted\" \"$currenttestfolder/$_.sorted\" -excel-file \"$diff_folder/$csvFile.xml\" >\"$diff_folder/$csvFile.txt\"";
    $full_diff_cmd =~ s/\//\\/g;
#    `$full_diff_cmd`;
    system $full_diff_cmd;

    delete_file_if_empty "$diff_folder/$csvFile.txt";
    delete_file_if_empty "$diff_folder/$csvFile.xml";
  }
}

# --------------------------------------------------------------------
# Sub to post-process two text files before diff
# --------------------------------------------------------------------
sub textPreDiff($$$$$$$)
{
  # params in @_ (test name, text file to update, diff folder, run dir for test, resultsdir for test, zos test id)
  my ($testname, $testfolder, $textFile, $diff_folder, $rundir, $resultsdir, $zostestid) = @_;

  my $matchresultsdir = $resultsdir;
  my $matchrundir = $rundir;

  if ($textFile =~ m/$testname\.log/i)
  {
    replace_in_file("$diff_folder/text/$textFile",
                    sub {
                      s!^\"(.*)\"$!$1!i;
                      $_;
                    } );

    replace_in_file("$diff_folder/text/$textFile",
                    sub {
                      s!(RMF0004N.*RMF Magic).*(reduce started at).*!$1 \<runversion\> $2 \<rundatetime\>!i;
                      s!(RMF0005N.*RMF Magic).*(analyze started at).*!$1 \<runversion\> $2 \<rundatetime\>!i;
                      s!(RMF0006.*RMF Magic ended at).*!$1 \<rundatetime\>!i;
                      s!$matchresultsdir!\<resultsdir\>!ig;
                      s!$matchrundir!\<rundir\>!ig;
                      s!^\d\d??[/-]\d\d??[/-]\d\d\d??\d?? \d\d??:\d\d:\d\d( [AP]M)?!<rundatetimemsg>!i;
                      s!(Loading CSV files into database finished, total execution time )\d\d:\d\d:\d\d!$1<CSV load time>!i;
                      $_;
                    } );
  } else
  {
    replace_in_file("$diff_folder/text/$textFile",
                    sub {
                      s!(.*RMF Magic by IntelliMagic ).*(Page.*)!$1 $2!i;
                      s!$matchresultsdir!\<resultsdir\>!ig;
                      s!$matchrundir!\<rundir\>!ig;
                      s!(RMF0004N.*RMF Magic).*(reduce started at).*!$1 \<runversion\> $2 \<rundatetime\>!i;
                      s!(RMF0005N.*RMF Magic).*(analyze started at).*!$1 \<runversion\> $2 \<rundatetime\>!i;
                      s!(RMF0006.*RMF Magic ended at).*!$1 \<rundatetime\>!i;
                      s!(\\* Created by IntelliMagic RMF Magic/Collector on ).*( \*)!$1 <rundatetime> $2!i;
                      s!RMF Magic reduce .*\.log!reduce.log!i;
                      s!RMF Magic analyze .*\.log!analyze.log!i;
                      s!^(LastRun=Last Reduce run done at )\d\d??[/-]\d\d??[/-]\d\d\d??\d?? \d\d??:\d\d(:\d\d)?( [AP]M)?!$1<rundatetimemsg>!i;
                      s!^(LastRun=Last Analyze run done at )\d\d??[/-]\d\d??[/-]\d\d\d??\d?? \d\d??:\d\d(:\d\d)?( [AP]M)?!$1<rundatetimemsg>!i;
					  s!x\:num=\".*\"!<x-num>!i;
					  s!x\:num!<x-num>!i;
                      s!<o:Created>\d\d\d??\d??-\d\d??-\d\d??T\d\d??:\d\d:\d\dZ</o:Created>!<o:Created><htm_create_datetime></o:Created>!i;
                      s!<o:LastSaved>\d\d\d??\d??-\d\d??-\d\d??T\d\d??:\d\d:\d\dZ</o:LastSaved>!<o:LastSaved><htm_create_datetime></o:LastSaved>!i;
                      s!SET PROJECT=.*?\.!SET PROJECT=<runver>\.!i;
                      s!RMFMAGIC\.$zostestid!RMFMAGIC\.<runver>!i;
                      $_;
                    } );
  }

  # Replace version number in all files in Excel folder, and HTML folder
  if (($testfolder =~ m/Excel$/i) ||
      ($textFile =~ m/\.htm$/i))
  {
    replace_in_file("$diff_folder/text/$textFile",
                    sub {
                      s!(RMFM4W )\d\.\d\.\d+!$1<version>!i;
                      s!(RMF Magic for Windows )\d\.\d\.\d+!$1<version>!i;
                      s!(Copyright (C) 2003-)\d+!$1<curyear>s!i;
					  s!x\:num=\".*\"!<x-num>!i;
					  s!x\:num!<x-num>!i;
                      s!<o\:Created>\d\d\d??\d??-\d\d??-\d\d??T\d\d??:\d\d:\d\dZ<\/o\:Created>!<htm_create_datetime>!i;
                      s!<o\:LastSaved>\d\d\d??\d??-\d\d??-\d\d??T\d\d??:\d\d:\d\dZ<\/o\:LastSaved>!<htm_create_datetime>!i;

                      $_;
                    } );
  }

  if ($textFile =~ m/index.txt/i)
  {
    replace_in_file("$diff_folder/text/$textFile",
                    sub {
                      s!(RMF Magic for Windows )\d\.\d\.\d+!$1<version>!i;
                      $_;
                    } );
  }

}

# --------------------------------------------------------------------
# Sub to compare two text files
# --------------------------------------------------------------------
sub textCompare ($$$$)
{
  # params in @_ (test name, folder with current test results, folder with previous test results, text file to compare)
  my ($testname, $currenttestfolder, $previoustestfolder, $textFile) = @_;

  my $diff_folder  = "$resultsdir/$testname/diff";
  my $prev_diff_folder = "$resultsbasedir/$Config{previoustests}/$testname/diff";
  my $diffcmd = sprintf "%s --ignore-all-space --ignore-blank-lines --ignore-space-change --ignore-case",
    $^O eq 'MSWin32'
        ? "$bindir/diff.exe"
        : 'diff';

  # Include subfolders of base test folder in file name of file to compare
  # print "$currenttestfolder $resultsdir $textFile\n";
  my $copyFile = "$currenttestfolder/$textFile";
  my $matchresultsdir = "$resultsdir/$testname/";
  $matchresultsdir =~ s/\/+/\//g;

  $copyFile =~ s/^$matchresultsdir//;
  $copyFile =~ s/\//_/g;

  write_log("- Compare text file $copyFile - Preparing...");

  if (file_newer("$currenttestfolder/$_", "$diff_folder/$textFile.txt")) {
    # Need to post process text files, post process in temp location
    mkdir("$diff_folder/text") unless (-d "$diff_folder/text");

    copy( "$currenttestfolder/$textFile", "$diff_folder/text/$copyFile" ) or warn "Cannot copy $currenttestfolder/$textFile to $diff_folder/text/$copyFile: $!";

    unless (-e "prev_diff_folder/text/$copyFile") {
      # If the unzipped and post procecced file does not exist for the previous test result set, process it
      unless (-d "$prev_diff_folder/text") {mkdir("$prev_diff_folder/text");}
      copy( "$previoustestfolder/$textFile", "$prev_diff_folder/text/$copyFile" ) or warn "Cannot copy $previoustestfolder/$textFile to $diff_folder/text/$copyFile: $!";

      textPreDiff($testname, $currenttestfolder, $copyFile, $prev_diff_folder, "$runbasedir/$Config{previoustests}", "$resultsbasedir/$Config{previoustests}", $Config{previoustests});
    }

    textPreDiff($testname, $currenttestfolder, $copyFile, $diff_folder, $rundir, $resultsdir, $Config{currenttests});

    # Compare
    write_log("- Compare text file $copyFile - Comparing...");
#    `$diffcmd \"$prev_diff_folder\\text\\$copyFile\" \"$diff_folder\\text\\$copyFile\" >\"$diff_folder\\$copyFile\"`;
    my $full_diff_cmd = "$diffcmd \"$prev_diff_folder/text/$copyFile\" \"$diff_folder/text/$copyFile\" >\"$diff_folder/$copyFile\"";
    $full_diff_cmd =~ s/\//\\/g if $^O eq 'MSWin32';
    `$full_diff_cmd`;


    write_log("- Compare text file $copyFile - Done.");

    delete_file_if_empty "$diff_folder/$copyFile";
  }
}

# --------------------------------------------------------------------
# Sub to unzip a dmc file
# FR-00166, JWE.
# --------------------------------------------------------------------
sub dmcUnzip {

  # params in @_ (source dmc file, source DMC file folder, destination folder for unzipped dmc)
  my ($dmc_file, $src_folder, $dest_folder) = @_;

  mkdir ($dest_folder) unless (-d $dest_folder);

	`$rundir\\dmcunzip.exe \"$src_folder\\$dmc_file\" \"$dest_folder\\$dmc_file\"`;

}

# --------------------------------------------------------------------
# Logging functions
# $resultsdir no more used , only for backward compatibilty
# --------------------------------------------------------------------
sub open_log {
    my ($resultsdir, $testname) = @_;
#    my $logfile = "$resultsdir/$Config{currenttests}_$Config{previoustests}_$testname.log";
    my $logfile = "$resultsbasedir/$Config{currenttests}/$Config{currenttests}_$Config{previoustests}_$testname.log";

  $ENV{USERNAME} = $ENV{USER} if !exists $ENV{USERNAME};
  $ENV{COMPUTERNAME} = "$ENV{USERNAME}'s computer" if ! exists $ENV{COMPUTERNAME};

  open LOG, ">>$logfile" or return 0;

  my $old_fh = select(LOG); # save output handle, set LOG to current
  $| = 1;                   # unbuffer output to current output handle
  select($old_fh);          # restore former current handle

  write_log("-" x 75);
  write_log("  RMFmagic doCompare version $VERSION");
  write_log("  Copyright (C) 2003-2009 IntelliMagic B.V. All rights reserved.");
  write_log("  $logfile");
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
#    print LOG "@_\n";  # and to LOG
    print LOG "[". nicedate() ." ".nicetime() ."] @_\n";  # and to LOG

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
      if ($1 eq 'versions' or
          $1 eq 'tests' or
          $1 eq 'default') {
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

    if ($section ne 'override' and
        $Config{lc($key)}) {
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
# Name:         executeRemote
# Syntax:       executeRemote($testmachine, $execcmd);
# Parameters:   $testmachine, $execcmd
# Return value: Return value of (remote) command
# Purpose:      Executes $execcmd either locally or $testmachine remotely,
#               depending on where the test was started
# --------------------------------------------------------------------
sub executeRemote($$)
{
  my $testmachine = shift;
  my $execcmd = shift;

  if ($ENV{COMPUTERNAME} eq $testmachine) {
    # Execute locally
    return log_exec("$execcmd");

  } elsif ($ENV{COMPUTERNAME} eq "IMSERVER4") {
    # IMSERVER4 - machine is not avaliable - 03-01-2012, RMA
    # Push the scripted test to $testmachine
    # Create a batch file that will execute on the remote system
    # Use psexec to copy and execute the batch file on the remote system
    open RUNCOMMAND, ">$resultsdir\\execremote.cmd";
    print RUNCOMMAND "\@echo off\n";
    print RUNCOMMAND "net use T: \\\\imserver5\\testsuite\n";
    print RUNCOMMAND "net use U: \\\\imserver5\\testdata\n";
    print RUNCOMMAND "$execcmd\n";
    close RUNCOMMAND;

    return log_exec("$bindir\\psexec.exe -i 0 -accepteula \\\\$testmachine -u $Config{winuserid} -p $Config{winpw} -c \"$resultsdir\\execremote.cmd\"");
  }
}
