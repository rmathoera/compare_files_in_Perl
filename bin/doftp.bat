@rem = '--*-Perl-*--';
@rem = '
@echo off
SETLOCAL
rem input /P Password: %%ftppwd
rem window "ftp %1"
if exist %0 goto scriptpluspathplusbat
if exist %0.bat goto scriptpluspath
:script
perl -x -S %0.bat %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
:scriptpluspath
perl -x %0.bat %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
:scriptpluspathplusbat
perl -x %0 %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
@rem ';
#! perl
###########################################################BeginFile############

###########################################################EndFile##############

use strict;
#assert sanity

scalar(@ARGV)==1 || die "doftp <ftp-command-file>";

# open ftp input file and ftp command file

open( FTPCMDS, "$ARGV[0]") || die "Could not open $ARGV[0]";
open( FTP, ">tmp.ftp") || die "Could not open tmp.ftp";

#copy first line

my($totnofiles,$nodirs,$nofiles) = (0,0,0);

my $line = <FTPCMDS>; print FTP "literal USER ".$line;
chomp $line;

#get passwd and add it

#print "User $line password: \n";
#open(NULLOUT, "nul");
#select(NULLOUT);
#chomp($line = <STDIN>);
#select(STDOUT);

#print FTP "literal PASS $line\n";
print FTP "literal PASS ".$ENV{'MVSPWD'}."\n";

#remove all but one "cd .."

print FTP "cd ..\n";
$line = <FTPCMDS>;
while ($line =~ m/^cd/) {$line = <FTPCMDS>;}

#copy "ascii" line
#$line =~ m/^ascii$/ || die "next command after cd should be ascii, not <$_>";
#print FTP $line;

$line =~ s/put -z (.*)/put $1/;
print FTP $line;

#copy rest and remove -z on put commands
while ($line = <FTPCMDS>) {
    if ( $line =~ /put / )
    {
      $totnofiles++;
    }
    $line =~ s/put -z (.*)/put $1/;
    print FTP $line;
}
print FTP "quit\n"; # Quit from FTP session isn't automatic in Win2000

#close files
close(FTP);
close(FTPCMDS);

open DUMP, ">ftp.log" || die " Could not open ftp.log";
#activate ftp
open RESULT, "ftp -n -s:tmp.ftp $ENV{'MVSHOST'} |";
while ($line = <RESULT>)
{
  chomp $line;
  if ($line =~ /^257 /)
  { $nodirs++;
    print "\r dirs = $nodirs files = $nofiles        ";
  }
  if ($line =~ /^226 /)
  { $nofiles++;
    print "\r dirs = $nodirs files = $nofiles/$totnofiles   ";
  }
  if ($line =~ /^125 [A-Z]/)
  {
    print "\r".$line."          ";
  }
  if ($line =~ /^5\d\d [A-Z]/)
  {
    print "\n\t".$line."\n";
  }
  if ($line =~ /^4\d\d [A-Z]/)
  {
    print "\n\t".$line."\n";
  }
  if ($line =~ /^3\d\d [A-Z]/)
  {
    print "\n\t".$line."\n" if (!($line =~ /^331/));
  }
  if ($line =~ /^230 [A-Z]/)
  {
    print "\n".$line."\n";
  }
  print DUMP $line."\n" if (!($line =~ "literal PASS"));
}
print "\n";
close DUMP;
close RESULT;

#cleanup
unlink("tmp.ftp");
__END__
:endofperl
ENDLOCAL
