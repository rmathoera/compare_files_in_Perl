#!/usr/local/bin/perl

my($jcl,$outfile) = @ARGV;

if (not defined $jcl)
{
  print "Usage: submitjcl <jcl-file> <output-file>\n";
  exit 4;
}

my($host,$user,$password);

$outfile = $jcl.".out" unless (defined $outfile);

$host = $ENV{'MVSHOST'} || die "Environment variable MVSHOST must be defined";
$user = $ENV{'MVSUSER'} || die "Environment variable MVSUSER must be defined";
$password = $ENV{'MVSPWD'};
$user = uc($user);

if (not defined $password)
{
  print " $user\'s password:";
  chop($password = <STDIN>);
  print "\r------------------\n";
}

$jcl =~ s/\\/\//g;
#get jobname
open JCLFILE , "<$jcl";
my $jclline = <JCLFILE>;
my $postfix = undef;
if ($jclline =~ /^\/\/([\$\w]+) +JOB/)
{
  $postfix = $1;
  if (-e "ftpexec.$postfix")
  {
    print "JOB ALREADY RUNNING";
    exit 1;
  }
}
else
{
  print "JOBNAME MISSING";
  exit 2;
}
close JCLFILE;

open FTPCMD , ">ftpexec.$postfix";
print FTPCMD <<EOF
open $host
quote USER $user
quote PASS $password
quote site filetype=jes
put $jcl
quit
EOF
;
close FTPCMD;

my @ftplines  = `ftp.exe -n -s:ftpexec.$postfix`;
my $job = undef;
foreach my $line (@ftplines) # search for returned JOB number
{
  if ($line =~ /250\-It is known to JES as (JOB\d+)/) 
  {
    $job = $1;
  }
}
print "job=$job";
my $found = undef;

# check  if the job is finished
open FTPCMD , ">ftpexec.$postfix";
print FTPCMD <<EOF
open $host
quote USER $user
quote PASS $password
quote site filetype=jes
dir
quit
EOF
;

close FTPCMD;
my $timeout = 5;
while (not $found)
{
  my $jobactive = undef;
  my @ftpdirlines  = `ftp.exe -n -s:ftpexec.$postfix`;
  foreach my $line (@ftpdirlines)
  {
    if ($line =~ /$job IMUSGU1  OUTPUT/)
    {
      $jobactive = 1;
      $found = 1;
    }
    if ($line =~ /$job IMUSGU1  ACTIVE/
        || $line =~ /$job  INPUT/)
    {
      $timeout++ unless ($timeout > 60);
      $jobactive = 1;
    }
  }
  if (not $jobactive)
  {
    print "\n";
    print "JOB SEEMS TO BE KILLED $postfix ($job)\n";
#    print "JOB KILLED $postfix ($job)\n";

    print "FTP RESULTS:\n";
    foreach my $linedump (@ftpdirlines)
    {
      print "  $linedump\n";
    }

    unlink "ftpexec.$postfix";
    exit 5;
  }
  print ".";
  sleep $timeout;
#  $timeout++;
}
print "\n";
#retrieve
open FTPCMD , ">ftpexec.$postfix";
print FTPCMD <<EOF
open $host
quote USER $user
quote PASS $password
quote site filetype=jes
get $job $outfile
del $job
quit
EOF
;
close FTPCMD;

my @ftpdirlines  = `ftp.exe -n -s:ftpexec.$postfix`;
unlink "ftpexec.$postfix";
#scan outfile for RC
my $line;
my $rc = "99";

open RESULT, "<$outfile";
while (defined ($line = <RESULT>))
{
  if ($line =~ / IEF142I .* - STEP WAS EXECUTED - COND CODE (\w{4})/)
  {
    my $hexrc = $1;
    $rc = hex($1);
    chomp($line);
    print "RC=$rc (0x$hexrc) $line\n";
  }
  if ($line =~ /JOB NOT RUN - JCL ERROR/)
  {
    $rc = 99;
    chomp($line);
    print "RC=$rc $line\n";
  }
}
close RESULT;

if (4 < $rc ) 
{
  exit $rc
}
else # continue on warnings
{
  exit 0;
}
