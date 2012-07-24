package IMPostProcess;
 
use strict;
use warnings;
use Cwd;
use File::Copy;
use File::Find;
use File::Slurp;
use File::Path;
use File::Basename;
use Tie::File;
use Digest::SHA1 qw (
    sha1
    sha1_hex
    sha1_base64
);
use Algorithm::Diff qw (
    diff
    sdiff
);
use Archive::Extract;
use Text::CSV::Simple;
use Spreadsheet::WriteExcel::Big;

use base 'Exporter';

our @EXPORT = qw(
    extract_zipfiles
    move_to_archive
    process_generic_file
    process_bat_file
    process_cmd_file
    process_csv_file
    process_dmc_file
    process_htm_file
    process_ini_file
    process_jcl_file
    process_out_file
    process_rmc_file
    process_rmp_file
    process_rmp_file
    process_rpt_file
    process_txt_file
    process_alog_file
    process_flog_file
    process_rlog_file
    process_rmfmgo_file
    process_Projectlog_file
    process_Visionlog_file
    report_unique_file
    read_csv_file
);

BEGIN {
    my $startvalue;
    my $row;
    my @return_values;

    sub reset_start_values {
        $startvalue = $row = 0;
        @return_values = ();
    };

    sub process_html_subarray {
        my ($index, $array_ref) = @_;

        my @differences = sdiff [split /\n/, $array_ref->[1]], [split /\n/, $array_ref->[2]];
        push @return_values, map [$startvalue + $_, $differences[$_][1], $differences[$_][2]], grep $differences[$_][0] ne 'u', (0 .. $#differences);
        $startvalue += @differences;
    };

    sub process_csv_subarray {
        my ($index, $array_ref) = @_;

        if (ref $array_ref->[1] eq '') {
            my @temp_array = map '', (0 .. $#{$array_ref->[2]});
            $array_ref->[1] = \@temp_array;
        };
        if (ref $array_ref->[2] eq '') {
            my @temp_array = map '', (0 .. $#{$array_ref->[1]});
            $array_ref->[2] = \@temp_array;
        };
        my @differences = map {[$_, $array_ref->[1][$_], $array_ref->[2][$_]]} grep $array_ref->[1][$_] ne $array_ref->[2][$_], (0 .. $#{$array_ref->[1]});
        push @return_values, [$row, [@differences]] if scalar @differences;
        $row++;
    };
    
    sub get_return_values {
        return ($startvalue, \@return_values);
    }
}

my %eval_hash = (
    generic => q{
    },
    bat => q{
        map s/\w:.+?$files_to_process[$filenumber][1]/<replaced path>/g, @test;
    },
    cmd => q{
        map s/\w:.+?$files_to_process[$filenumber][1]/<replaced path>/g, @test;
    },
    csv => q{
        map s/\w:.+?$files_to_process[$filenumber][1]/<replaced path>/g, @test;
    },
    dmc => q{
        map {
            s/(rmfmversion)\s+\d+/$1 <version number>/g;
            s/(Vision)\s+\d+\.\d+\.\d+/$1 <version number>/g;
            s/(Created).+$/$1 <replaced timestamp>/g;
            s/\0//g;
        }
        @test;
    },
    htm => q{
        chomp @test;
        my $html_string = join "\n", @test;
        $html_string =~ s/(o:gfxdata\s*=\s*)"[^"]*"/$1\[base_64_image_data\]/gs;
        $html_string =~ s/([^>])\s*?[\015|\012]+\s*([^<\s])/$1 $2/sg;
        $html_string =~ s/^\s+//mg;
        @test = split /(?=<tr)/, $html_string;
        # remove the just introduced '<tr' string from the first array-element
        map {
			s/\w:.+?$files_to_process[$filenumber][1]/<replaced path>/g;
			s/x\:num=\".*\"/<replaced_x_num>/g;
			s/x\:num/<replaced_x_num>/g;
			s/<o\:Created>\d\d\d??\d??-\d\d??-\d\d??T\d\d??:\d\d:\d\dZ<\/o\:Created>/<htm_create_datetime>/g;
			s/<o\:LastSaved>\d\d\d??\d??-\d\d??-\d\d??T\d\d??:\d\d:\d\dZ<\/o\:LastSaved>/<htm_create_datetime>/g;
		}
		@test;
    },
    ini => q{
    },
    jcl => q{
        map {
            s/(SET PROJECT=)$testid/$1<replaced buildnumber>/i;
            s/(SET PRODUCT=RMFMAGIC\.)$testid/$1<replaced buildnumber>/i;
        } @test;
    },
    log => q{
            my $testid = $files_to_process[$filenumber][1];
            map {
                s/(?<= date[ ])                         # the word date, followed by an escaped space (we're using extended RE's) as anchor point
                \w{3}\s+\w{3}\s+\d+\s+                  # date (Day Mon 'day of month') followed by at least one space-char
                \d+:\d+:\d+\s+                          # time (hours:mins:secs; 24 hour clock) followed by at least one space-char
                \d+                                     # year (should be four digits, accept at least one)
                    /<replaced timestamp>/xg;           # replacement string
                s/^\d+\/\d+\/\d+\s+\d+:\d+:\d+\s[AP]M   # date-time MM\/dd\/YYYY hh:mm:ss AM\/PM
                    /<replaced timestamp>/xg;
                s/\w:[^:]+?[\/\\\\]$testid([\/\\\\])    # driveletter followed by path up to and including testnumber Should be changed to [\/\\]+$testid([\/\\]+)
                    /<replaced path>$1/xg;
                s/((?:started|ended)[ ](?:at|on)).+$    # line ending with start\/stop time
                    /$1 <replaced timestamp>/xg;
                s/^.*?Page\s+\d+.*?$                    # page header\/footers
                    //xg;
            } @test;
            my @empty_lines = sort {$b <=> $a} grep $test[$_] =~ /^\s*<replaced timestamp>\s*$/, (0 .. $#test);
            map splice (@test, $_, 1), @empty_lines;
    },
    alog => q{
            my $testid = $files_to_process[$filenumber][1];
            map {
                s/(?<= date[ ])                         # the word date, followed by an escaped space (we're using extended RE's) as anchor point
                \w{3}\s+\w{3}\s+\d+\s+                  # date (Day Mon 'day of month') followed by at least one space-char
                \d+:\d+:\d+\s+                          # time (hours:mins:secs; 24 hour clock) followed by at least one space-char
                \d+                                     # year (should be four digits, accept at least one)
                    /<replaced timestamp>/xg;           # replacement string
                s/^\d+\/\d+\/\d+\s+\d+:\d+:\d+\s[AP]M   # date-time MM\/dd\/YYYY hh:mm:ss AM\/PM
                    /<replaced timestamp>/xg;
                s/\w:[^:]+?[\/\\\\]$testid([\/\\\\])    # driveletter followed by path up to and including testnumber Should be changed to [\/\\]+$testid([\/\\]+)
                    /<replaced path>$1/xg;
                s/((?:started|ended)[ ](?:at|on)).+$    # line ending with start\/stop time
                    /$1 <replaced timestamp>/xg;
                s/^.*?Page\s+\d+.*?$                    # page header\/footers
                    //xg;
                s/(Vision)                              # use Vision as anchor point
                    \s+                                 # followed by at least one space-character
                    \d+\.\d+\.\d+                       # dot-separated version number
                    /$1 <replaced versionnumber>/x;
            } @test;
            my @empty_lines = sort {$b <=> $a} grep $test[$_] =~ /^\s*<replaced timestamp>\s*$/, (0 .. $#test);
            map splice (@test, $_, 1), @empty_lines;
    },
    flog => q{
            my $testid = $files_to_process[$filenumber][1];
            map {
                s/\d{2}:\d{2}:\d{2}                     # time
                    \son\s                              # literal text
                    \d{4}-\d{2}-\d{2}                   # normalized date
                /<replaced timestamp>/x;
                s/(RMFMAGIC\.)                          # literal text as start-anchor
                    $testid                             # text to be replaced
                    (\S*)                               # literal text as stop-anchor
                    \s+                                 # at least one spacecharacter
                    .*                                  # remainder of get-command
                /$1<replaced buildnumber>$2 <replaced destination-path>/ix;
                s/(RMFMAGIC\.)                          # literal text as start-anchor
                    $testid                             # text to be replaced
                    (\S*)                               # literal text as stop-anchor
                /$1<replaced buildnumber>$2/ix;
            } @test;
            my @empty_lines = sort {$b <=> $a} grep $test[$_] =~ /^\s*<replaced timestamp>\s*$/, (0 .. $#test);
            map splice (@test, $_, 1), @empty_lines;
    },
    out => q{
        my $testid = $files_to_process[$filenumber][1];
        map {
            s/((?:started|ended)[ ](?:at|on)).+$    # line ending with start\/stop time
                /$1 <replaced timestamp>/xg;
            s/
                \s                                      # space character
                \d{2}\.\d{2}\.\d{2}                     # three 'double-digits' separated by dots
                \s                                      # space character
                JOB\d{5}                                # jobnumber (JOB followed by five digits)
                \s+
                /<replaced job identifier>/x;
            s/\w+?DAY.*?\s\d{4}$                        # full date enclosed between 'four-dash'-patterns
                /<replaced timestamp>/x;
            s/(Vision)                                  # use Vision as anchor point
                \s+                                     # followed by at least one space-character
                \d+\.\d+\.\d+                           # dot-separated version number
                /$1 <replaced versionnumber>/x;
            s/((?:started|ended)[ ](?:at|on)).+$        # line ending with start\/stop time
                /$1 <replaced timestamp>/xg;
            s/(RMFMAGIC\.|PROJECT=)                              # literal text as start-anchor
                $testid                                 # text to be replaced
                /$1<replaced buildnumber>/ix;
            s/JOB\d{5}                                  # jobnumber (JOB followed by five digits)
                /<replaced job identifier>/x;
            s/(LAST[ ]ACCESS[ ]AT[ ])
                \d{2}:\d{2}:\d{2}                       # time of day (24 hour clock)
                \s+
                ON
                \s+
                \w+?DAY,.*?,\s+\d{4}                    # long date
                /$1<replaced timestamp>/x;
            s/(COPY\s+)
                \d{2}:\d{2}:\d{2}                       # time of day (24 hour clock)
                \s+
                \w{3}\s+\d+\s+\w{3}\s+\d{4}             # short date
                /$1<replaced timestamp>/x;
            s/((?:START)|(?:STOP))(\s+)                 # anchor: START-STOP followed by spacecharacters
                \d{7}\.\d{4}                            # decimal date: 7 digits decimal point 4 dogits
                /<replaced decimal date>/xi;
            s/(----)[ ]
                \w+?DAY,
                \s+
                \d+[ ]\w{3}[ ]\d{4}[ ](---)
                /$1<replaced timestamp>$2/xi;
            s/(-\s+)
                \d+\s+\w{3}\s+\d{4}
                /<replaced date>/x;
            } @test;
            my @empty_lines = sort {$b <=> $a} grep $test[$_] =~ /^\s*<replaced timestamp>\s*$/, (0 .. $#test);
            map splice (@test, $_, 1), @empty_lines;
    },
    rlog => q{
            my $testid = $files_to_process[$filenumber][1];
            map {
                s/(?<= date[ ])                         # the word date, followed by an escaped space (we're using extended RE's) as anchor point
                \w{3}\s+\w{3}\s+\d+\s+                  # date (Day Mon 'day of month') followed by at least one space-char
                \d+:\d+:\d+\s+                          # time (hours:mins:secs; 24 hour clock) followed by at least one space-char
                \d+                                     # year (should be four digits, accept at least one)
                    /<replaced timestamp>/xg;           # replacement string
                s/^\d+\/\d+\/\d+\s+\d+:\d+:\d+\s[AP]M   # date-time MM\/dd\/YYYY hh:mm:ss AM\/PM
                    /<replaced timestamp>/xg;
                s/\w:[^:]+?[\/\\\\]$testid([\/\\\\])    # driveletter followed by path up to and including testnumber Should be changed to [\/\\]+$testid([\/\\]+)
                    /<replaced path>$1/xg;
                s/((?:started|ended)[ ](?:at|on)).+$    # line ending with start\/stop time
                    /$1 <replaced timestamp>/xg;
                s/^.*?Page\s+\d+.*?$                    # page header (first line)
                    //xg;
                s/^\s+(?:\w\s)+.*                       # line starting with space followed by space separated characters (header, second line)
                    //x;
                s/^\s+RMF\s+Magic\s+Reduce              # program producing the logfile (header third line)
                    //x;
                s/\d+\.\d+\.\d+                         # dot-separated versionnumber
                    \s+                                 # followed by one or more space characters
                    (reduce)                            # anchor-point
                    /<replaced versionnumber> $1/xi;
            } @test;
            my @empty_lines = sort {$b <=> $a} grep $test[$_] =~ /^\s*<replaced timestamp>\s*$/, (0 .. $#test);
            map splice (@test, $_, 1), @empty_lines;
    },
    rmc => q{
        map s/(Created.*?on )\d+.\d+.\d+\s+\d+:\d+:\d+/$1<replaced timestamp>/g, @test;
    },
    rmp => q{
        map {
            s/\w:.+?$testid/<replaced path>/g;
            s/(run done at ).+?\d+:\d+/$1<replaced timestamp>/g;
            s/((?:Vision and )?Balance (?:analyze|reduce|migrate) ).+?(.log)\s*$/$1<replaced timestamp>$2/ig;
        } @test;
    },
    txt => q{
        map {
            s/\w:.+?$testid/<replaced path>/g;
            s/((?:Vision and )?Balance (?:analyze|reduce|migrate) ).+?(.log)\s*$/$1<replaced timestamp>$2/ig;
            s/(sysin\s+)\w:[\/\\\\]+[^\/\\\\]+[\/\\\\]+/$1<replaced path>/;
            s/\w:[\/\\\\]+[^\/\\\\]+[\/\\\\]+/<replaced path>/;
            s/^,+\s*$//;
            s/(Vision\s)                            # anchor point
                \d+\.\d+\.\d+                       # dot-separated versionnumber
                \s+                                 # followed by one or more space characters
                /$1<replaced versionnumber>/xi;
            s/\d+\.\d+\.\d+                         # dot-separated versionnumber
                \s+                                 # followed by one or more space characters
                (\((?:Reduce)\)|(?:\(Analyze)\))
                    /<replaced versionnumber> $1/xig;
            s/^(Created,
                .*?)                                # anchor
                \d+\/\d+\/\d{4}                     # slash separated date
                \s+                                 # space character(s)
                \d+:\d+                             # 24-hour-clock time, allowing for single digits
                ,                                   # trailing comma
                /$1<replaced timestamp>,/xi;
				s/unzip_smis_\d+/<txt_unzip_smis>/ig;    # FR-02331 replace timestamp in unzip_smis_20120627113502 into <unzip_smis>
         } @test;
    },
    rmfmgo => q{
        map s/\w:.+?$testid/<replaced path>/g, @test;
    },
    Projectlog => q{
        map {
            s/((?:started|ended)[ ](?:at|on)).+$    # line ending with start\/stop time
                /$1 <replaced timestamp>/xg;
            s/^\d+\/\d+\/\d+\s+\d+:\d+:\d+\s[AP]M   # date-time MM\/dd\/YYYY hh:mm:ss AM\/PM
                /<replaced timestamp>/xg;
            s/(Vision)                              # use Vision as anchor point
                \s+                                 # followed by at least one space-character
                \d+\.\d+\.\d+                       # dot-separated version number
                /$1 <replaced versionnumber>/x;
            s/\w:[^:]+?[\/\\\\]$testid([\/\\\\])    # driveletter followed by path up to and including testnumber Should be changed to [\/\\]+$testid([\/\\]+)
                /<replaced path>$1/xg;
			s/unzip_smis_\d+/<proj_unzip_smis>/ig;    # FR-02331 replace timestamp in unzip_smis_20120627113502 into <unzip_smis>
        } @test;
    },
    Visionlog => q{
        map {
            s/((?:started|ended)[ ](?:at|on)).+$    # line ending with start\/stop time
                /$1 <replaced timestamp>/xg;
            s/(Vision)                              # use Vision as anchor point
                \s+                                 # followed by at least one space-character
                \d+\.\d+\.\d+                       # dot-separated version number
                /$1 <replaced versionnumber>/x;
			s/unzip_smis_\d+/<vis_unzip_smis>/ig;    # FR-02331 replace timestamp in unzip_smis_20120627113502 into <unzip_smis>
        } @test;
    },
);

sub process_tied {
    my ($type, $base_directory, $old_test, $new_test, $filename) = @_;

    my @files_to_compare;
    my @files_to_process = map ["$base_directory/${_}$filename", $_], ($old_test, $new_test);

    for (0, 1) {
        my $filenumber = $_;
        my $testid = $files_to_process[$filenumber][1];
        tie my @test, 'Tie::File', $files_to_process[$filenumber][0];
        eval $eval_hash{$type};
        my @empty_lines = sort {$b <=> $a} grep $test[$_] =~ /^\s*$/, (0 .. $#test);
        map splice (@test, $_, 1), @empty_lines;
        $files_to_compare[$filenumber] = \@test;
    }

    my @differences = diff($files_to_compare[0], $files_to_compare[1]);

    for (0, 1) {
        untie @{$files_to_compare[$_]};
    }

    map unlink ($_->[0]), @files_to_process unless @differences;
    return \@differences;
}

sub process_generic {
    my ($type, $base_directory, $old_test, $new_test, $filename) = @_;

    my @files_to_compare;
    my @files_to_process = map ["$base_directory/${_}/$filename", $_], ($old_test, $new_test);

    for (0, 1) {
        my $filenumber = $_;
        my $testid = $files_to_process[$filenumber][1];
        my @test = read_file($files_to_process[$filenumber][0]);
        eval $eval_hash{$type} if exists $eval_hash{$type} && $eval_hash{$type} ne '';
        die $@ if $@ ne '';
        my @empty_lines = sort {$b <=> $a} grep $test[$_] =~ /^\s*$/, (0 .. $#test);
        map splice (@test, $_, 1), @empty_lines;
        write_file ($files_to_process[$filenumber][0], @test);
        $files_to_compare[$filenumber] = \@test unless defined $files_to_compare[$filenumber];
    }

    my @differences = sdiff($files_to_compare[0], $files_to_compare[1]);
    if (!@differences) {
        map unlink ($_->[0]), @files_to_process;
        return;
    }
    return \@differences;
}

sub read_table_rows {
    my ($type, $base_directory, $old_test, $new_test, $filename) = @_;

    my @files_to_compare;
    my @files_to_process = map ["$base_directory/${_}/$filename", $_], ($old_test, $new_test);

    for (0, 1) {
        my $filenumber = $_;
        my $testid = $files_to_process[$filenumber][1];
        my @test = read_file($files_to_process[$filenumber][0]);
        eval $eval_hash{$type} if exists $eval_hash{$type} && $eval_hash{$type} ne '';
        die $@ if $@ ne '';
        my @empty_lines = sort {$b <=> $a} grep $test[$_] =~ /^\s*$/, (0 .. $#test);
        map splice (@test, $_, 1), @empty_lines;
        write_file ($files_to_process[$filenumber][0], @test);
        $files_to_compare[$filenumber] = \@test unless defined $files_to_compare[$filenumber];
    }

    my @differences = sdiff($files_to_compare[0], $files_to_compare[1]);
    if (!@differences) {
        map unlink ($_->[0]), @files_to_process;
        return;
    }
    return \@differences;
}

sub process_ageneric {
    my ($type, $base_directory, $old_test, $new_test, $filename) = @_;

    my @files_to_compare;
    my @files_to_process = map ["$base_directory/${_}/$filename", $_], ($old_test, $new_test);

    for (0, 1) {
        my $filenumber = $_;
        my $testid = $files_to_process[$filenumber][1];
        my @test = read_file($files_to_process[$filenumber][0]);
        eval $eval_hash{$type} if exists $eval_hash{$type} && $eval_hash{$type} ne '';
        die $@ if $@ ne '';
        my @empty_lines = sort {$b <=> $a} grep $test[$_] =~ /^\s*$/, (0 .. $#test);
        map splice (@test, $_, 1), @empty_lines;
        write_file ($files_to_process[$filenumber][0], @test);
        $files_to_compare[$filenumber] = \@test unless defined $files_to_compare[$filenumber];
    }

    my @differences = diff($files_to_compare[0], $files_to_compare[1]);
    return \@differences;
}

sub extract_zipfiles {
    my ($base_directory, $old_test, $new_test, $hash_ref) = @_; # as we know how the hash is set-up there's no need to recurse it; this may be an issue for the future

    my @test_ids = ($old_test, $new_test);
    my $log_message = "\n";

    foreach my $partner (keys %{$hash_ref}) {
        my @files = @{$hash_ref->{$partner}};
        foreach my $file (@files) {
            for (0, 1) {
                my $qualified_file_name = "$base_directory/$test_ids[$_]/$file";
                $log_message .= sprintf "Extracting %s\n", $file;
                move $qualified_file_name, my $archive = "$qualified_file_name.gz";
                my $extracter = Archive::Extract->new (archive => "$archive"); # maybe we have to define the type (type => 'gz')
                $extracter->extract(to => $qualified_file_name);
                unlink $archive;
            }
        }
    }
    return $log_message;
}

sub process_bat_file {
    my ($base_directory, $old_test, $new_test, $filename) = @_;

    my $differences = process_ageneric('bat', $base_directory, $old_test, $new_test, $filename);

    return if !@$differences;
    write_differences_ageneric ($filename, $differences);
    return ["Found unexpected differences in $filename"];
}

sub process_cmd_file {
    my ($base_directory, $old_test, $new_test, $filename) = @_;

    my $differences = process_ageneric('cmd', $base_directory, $old_test, $new_test, $filename);

    return if !@$differences;
    write_differences_ageneric ($filename, $differences);
    return ["Found unexpected differences in $filename"];
}

sub process_rpt_file {
  my ($base_directory, $old_test, $new_test, $filename) = @_;
  my $data_to_compare = eval { get_csv_data($base_directory, $old_test, $new_test, $filename) };
  return [ "ERROR: $@" ] if $@;

    my @logmessage;

    reset_start_values();

    my @report_header = ([shift @{$data_to_compare->[0]}], [shift @{$data_to_compare->[1]}]);
    # as the @report_header is the only real difference between a report-file and a 'plain' csv-file
    # we'll use the same subs process the report-file:

    push @logmessage, pre_process_csv_data($data_to_compare, $filename) if scalar @{diff $data_to_compare->[0][0], $data_to_compare->[1][0]};
    my $changed_rows = get_changed_rows($data_to_compare, \@logmessage);
    do {
        map unlink ($_->[0]),
        map ["$base_directory/${_}$filename", $_],
        ($old_test, $new_test);
        return report_csv_changes ($filename, \@logmessage);
    } unless scalar grep ! /u/, keys %$changed_rows;

    compare_and_export_csv_data ($filename, $old_test, $new_test, $changed_rows, \@logmessage);
    return report_csv_changes ($filename, \@logmessage);
}

sub process_csv_file {
    my $data_to_compare = get_csv_data(my ($base_directory, $old_test, $new_test, $filename) = @_);

    my @logmessage;
    reset_start_values();
    push @logmessage, pre_process_csv_data($data_to_compare, $filename) if scalar @{diff $data_to_compare->[0][0], $data_to_compare->[1][0]};
    my $changed_rows = get_changed_rows($data_to_compare, \@logmessage);
    do {
        map unlink ($_->[0]),
        map ["$base_directory/${_}$filename", $_],
        ($old_test, $new_test);
        return report_csv_changes ($filename, \@logmessage);
    } unless scalar grep ! /u/, keys %$changed_rows;

    compare_and_export_csv_data ($filename, $old_test, $new_test, $changed_rows, \@logmessage);

    return report_csv_changes ($filename, \@logmessage);
}

sub compare_and_export_csv_data {
    my ($filename, $old_test, $new_test, $changed_rows, $logmessage_ref) = @_;

        my %column_to_export = (
            0 => undef,
            1 => undef,
        );
        my %fixed_column = %column_to_export;
        map {
            my $old_data = $_->[0];
            my $new_data = $_->[1];
            map {
                $column_to_export{$_}++ if $old_data->[$_] ne $new_data->[$_];
            } (0..$#$old_data)
        }  @{$changed_rows->{'c'}};
        my @columns_to_export = sort {$a <=> $b} keys %column_to_export;
        my @exported_columns = map {
            my $old_data = $_->[0];
            my $new_data = $_->[1];
            [
                map {
                    [$_, $old_data->[$_], $new_data->[$_]]
                } @columns_to_export
            ];
        }  @{$changed_rows->{'c'}};

        my @tabs_and_header = map ${$changed_rows->{'u'}}[0][0][$_], sort {$a<=> $b} keys %column_to_export;

        push @$logmessage_ref, 'Changed columns:';
        push @$logmessage_ref, map {
            sprintf "\t%s (%d rows)",
                ${$changed_rows->{'u'}}[0][0][$_],
                $column_to_export{$_};
            } grep defined $column_to_export{$_}, sort {$a<=> $b} keys %column_to_export;
        splice @tabs_and_header, 0, 0, ($old_test, $new_test);
        export_as_excel_file($filename, \@tabs_and_header, \@exported_columns, \%fixed_column);
    #    export_as_excel_file($filename, $data_to_compare, $differences, [$old_test, $new_test], [0, 1]);

        # NB $differences is a ref to @return_values, so resetting the startvalues effectively clears the differences
        # if that's not what we want, we may decide to rename the sub into set_strtvalues and invoke it before running the comarisons

        return report_csv_changes ($filename, $logmessage_ref);
}

sub export_as_excel_file {
    my ($filename, $tabs_and_header_ref, $exported_columns_ref, $fixed_column_ref) = @_;

    my @testids = splice @$tabs_and_header_ref, 0, 2;
    my $spreadsheet_ref = create_spreadsheet($filename, \@testids, {});
    format_spreadsheet($spreadsheet_ref->{workbook}, $#{$tabs_and_header_ref});
    map worksheet_write_testresults($spreadsheet_ref->{workbook}{worksheet}{$testids[$_]}, $exported_columns_ref, $_ + 1, $tabs_and_header_ref), (0 .. $#testids);
    worksheet_write_differences($spreadsheet_ref->{workbook}{worksheet}{diff}, $exported_columns_ref, $tabs_and_header_ref, $fixed_column_ref);
    $spreadsheet_ref->{workbook}->close;
    my $wbTest;


#my ($filename, $test_results_ref, $differences_ref, $testids_ref) = @_;
#
#my $spreadsheet_ref = create_spreadsheet($filename, $testids_ref, {});
#format_spreadsheet($spreadsheet_ref->{workbook}, $#{$test_results_ref->[0][0]});
#map worksheet_write_testresults($spreadsheet_ref->{workbook}{worksheet}{$testids_ref->[$_]}, $differences_ref, $test_results_ref->[$_]), (0 .. $#{$testids_ref});
#worksheet_write_differences($spreadsheet_ref->{workbook}{worksheet}{diff}, $differences_ref, $test_results_ref->[0]);
#$spreadsheet_ref->{workbook}->close;
}

sub worksheet_write_differences {
    my ($worksheet_ref, $differences_ref,$header_ref, $fixed_column_ref) = @_;

    my @differences = @$differences_ref;
    my %fixed_column = %$fixed_column_ref;

    my $row = 0;
    # force the headerrow to be written
    $worksheet_ref->write($row++, 0, $header_ref);
    map {
        my @cells = @{$_};
        $worksheet_ref->write($row++, 0,
            [
                map {
                    my ($old_value, $new_value) = ($_->[1], $_->[2]);
                    if (exists $fixed_column{$_->[0]} ) {
                        if ($old_value ne $new_value) {
                            "< '$old_value'\n> '$new_value'"
                        }
                        else {
                            $new_value;
                        }
                    }
                    else {
                        get_difference($old_value, $new_value) if $old_value ne $new_value;
                    }
                } @cells
            ]
        );
    } @$differences_ref;
}

sub get_difference {
    my ($old_value, $new_value) = @_;

    #if both cells contain numeric data print difference
    # if not: treat conents as strings and print old value ('<'-prefixed) and new value ('>'-prefixed) on separate lines in the same cell
    my $cell_content = (
        $old_value =~ /
            ^\s*                # any number of leading space-characters
            [\+-]?              # an optional plus or minus sign
            \s*                 # any number of space-characters
            \d+                 # at least one digit
            (?:\.\d+)?          # an optional decimal point followed by at least one digit
            \s*                 # any number of trailing space-characterss; thus ignoring scientfic notation!!!
            $/x
        &&
        $new_value =~ /
            ^\s*                # any number of leading space-characters
            [\+-]?              # an optional plus or minus sign
            \s*                 # any number of space-characters
            \d+                 # at least one digit
            (?:\.\d+)?          # an optional decimal point followed by at least one digit
            \s*                 # any number of trailing space-characterss; thus ignoring scientfic notation!!!
            $/x
        )
        ? $new_value - $old_value
        : "< '$old_value'\n> '$new_value'";

    return $cell_content;
}

sub worksheet_write_testresults {
    my ($worksheet_ref, $differences_ref, $index, $header_ref) = @_;

#    my @test_results = @$test_results_ref;
    my @differences = @$differences_ref;

    my $row = 0;
    # force the headerrow to be written
    $worksheet_ref->write($row++, 0, $header_ref);
    map {
        my @cells = @{$_};
        $worksheet_ref->write($row++, 0,
            [
                map {$_->[$index]} @cells
            ]
        );
    } @$differences_ref;
}

sub get_changed_rows {
    my ($data_to_compare, $message_ref) = @_;

    my %description = (
        c   => 'modified',
        u   => 'unchanged',
        '+' => 'added',
        '-' => 'deleted',
    );

    my %changes;
    my %sha1_hash;
    # LS: some rows may contain undef values (when columns were added
    # or removed between the two data sets being compared); to avoid
    # 'undefined value' warnings, I replace undef with '' before
    # calculating the checksum
    my @changes = sdiff
        [map {my $sha1 = sha1_hex(map { $_ // '' } @{$_}); $sha1_hash{$sha1} = $_; $sha1} @{$data_to_compare->[0]}],
        [map {my $sha1 = sha1_hex(map { $_ // '' } @{$_}); $sha1_hash{$sha1} = $_; $sha1} @{$data_to_compare->[1]}];
        map {push @{$changes{$_->[0]}}, [$_->[1] ? $sha1_hash{$_->[1]} : '', $_->[2] ? $sha1_hash{$_->[2]} : '']}  @changes;

    map {push @$message_ref, sprintf "Number of $description{$_} rows: %d", scalar @{$changes{$_}} if exists $changes{$_}} ('c', '+', '-');
    return \%changes;
}

sub process_generic_file {
    my ($base_directory, $old_test, $new_test, $filename) = @_;

    my $differences = process_ageneric('generic', $base_directory, $old_test, $new_test, $filename);

    return if !@$differences;
    write_differences_ageneric ($filename, $differences);
    return ["Found unexpected differences in $filename"];
}

sub process_dmc_file {
    my ($base_directory, $old_test, $new_test, $filename) = @_;

    my $differences = process_ageneric('dmc', $base_directory, $old_test, $new_test, $filename);

    return if !@$differences;
    write_differences_ageneric ($filename, $differences);
    return ["Found unexpected differences in $filename"];
}

sub process_htm_file {
    my ($base_directory, $old_test, $new_test, $filename) = @_;

    my $differences = read_table_rows('htm', $base_directory, $old_test, $new_test, $filename);
    return if !@$differences;

    my ($offset_old, $offset_new) = (0, 0);
    my @hunks;
    foreach (@$differences) {
        my @temp_array_old = split "\n", $_->[1];
        my @temp_array_new = split "\n", $_->[2];
        push @hunks, map {
            my @lines = @$_;
            [map [$_->[0], $_->[1] += $_->[0] eq '-' ? $offset_old : $offset_new , $_->[2]], @lines]
        } diff \@temp_array_old, \@temp_array_new;
        $offset_old += $#temp_array_old;
        $offset_new += $#temp_array_new;
    }
    write_differences_ageneric ($filename, \@hunks);
    return return ["Found unexpected differences in $filename"];
}

sub process_ini_file {
    my ($base_directory, $old_test, $new_test, $filename) = @_;

    my $differences = process_ageneric('ini', $base_directory, $old_test, $new_test, $filename);

    return if !@$differences;
    write_differences_ageneric ($filename, $differences);
    return ["Found unexpected differences in $filename"];
}

sub process_jcl_file {
    my ($base_directory, $old_test, $new_test, $filename) = @_;

    my $differences = process_ageneric('jcl', $base_directory, $old_test, $new_test, $filename);

    return if !@$differences;
    write_differences_ageneric ($filename, $differences);
    return ["Found unexpected differences in $filename"];
}

sub process_alog_file {
    my ($base_directory, $old_test, $new_test, $filename) = @_;

    my $differences = process_ageneric('alog', $base_directory, $old_test, $new_test, $filename);

    return if !@$differences;
    write_differences_ageneric ($filename, $differences);
    return ["Found unexpected differences in $filename"];
}

sub process_flog_file {
    my ($base_directory, $old_test, $new_test, $filename) = @_;

    my $differences = process_ageneric('flog', $base_directory, $old_test, $new_test, $filename);

    return if !@$differences;
    write_differences_ageneric ($filename, $differences);
    return ["Found unexpected differences in $filename"];
}

sub process_rlog_file {
    my ($base_directory, $old_test, $new_test, $filename) = @_;

    my $differences = process_ageneric('rlog', $base_directory, $old_test, $new_test, $filename);

    return if !@$differences;
    write_differences_ageneric ($filename, $differences);
    return ["Found unexpected differences in $filename"];
}

sub process_rmc_file {
    my ($base_directory, $old_test, $new_test, $filename) = @_;

    my $differences = process_ageneric('rmc', $base_directory, $old_test, $new_test, $filename);

    return if !@$differences;
    write_differences_ageneric ($filename, $differences);
    return ["Found unexpected differences in $filename"];
}

sub process_rmp_file {
    my ($base_directory, $old_test, $new_test, $filename) = @_;

    my $differences = process_ageneric('rmp', $base_directory, $old_test, $new_test, $filename);

    return if !@$differences;
    write_differences_ageneric ($filename, $differences);
    return ["Found unexpected differences in $filename"];
}

sub process_txt_file {
    my ($base_directory, $old_test, $new_test, $filename) = @_;

    my $differences = process_ageneric('Projectlog', $base_directory, $old_test, $new_test, $filename);

    return if !@$differences;
    write_differences_ageneric ($filename, $differences);
    return ["Found unexpected differences in $filename"];
}

sub process_out_file {
    my ($base_directory, $old_test, $new_test, $filename) = @_;

    my $differences = process_ageneric('out', $base_directory, $old_test, $new_test, $filename);

    return if !@$differences;
    write_differences_ageneric ($filename, $differences);
    return ["Found unexpected differences in $filename"];
}

sub process_rmfmgo_file {
    my ($base_directory, $old_test, $new_test, $filename) = @_;

    my $differences = process_ageneric('rmfmgo', $base_directory, $old_test, $new_test, $filename);

    return if !@$differences;
    write_differences_ageneric ($filename, $differences);
    return ["Found unexpected differences in $filename"];
}

sub process_Projectlog_file {
    my ($base_directory, $old_test, $new_test, $filename) = @_;

    my $differences = process_ageneric('Projectlog', $base_directory, $old_test, $new_test, $filename);

    return if !@$differences;
    write_differences_ageneric ($filename, $differences);
    return ["Found unexpected differences in $filename"];
}

sub process_Visionlog_file {
    my ($base_directory, $old_test, $new_test, $filename) = @_;

    my $differences = process_ageneric('Visionlog', $base_directory, $old_test, $new_test, $filename);

    return if !@$differences;
    write_differences_ageneric ($filename, $differences);
    return ["Found unexpected differences in $filename"];
}

sub get_changed_lines {
    my $differences = shift;

    return [map [$_, $differences->[$_]], grep $differences->[$_][0] ne 'u', (0 .. $#$differences)]
}

sub get_csv_data {
        my ($base_directory, $old_test, $new_test, $filename) = @_;

        my @files_to_compare;
        my @files_to_process = map ["$base_directory/${_}/$filename", $_], ($old_test, $new_test);

        for (0, 1) {
            my $filenumber = $_;
            my $testid = $files_to_process[$filenumber][1];
            my @test = read_csv_file($files_to_process[$filenumber][0]);
            my @empty_lines = sort {$b <=> $a} grep $test[$_] =~ /^\s*$/, (0 .. $#test);
            map splice (@test, $_, 1), @empty_lines;
            $files_to_compare[$filenumber] = \@test unless defined $files_to_compare[$filenumber];
        }

        return \@files_to_compare;
    
}

sub read_csv_file {
    my ( $filename ) = @_;

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
        die "CSV parser error " . $csv->error_diag() . "; file $filename; line " . $csv->error_input;
      }
        );
    
    my @data = $parser->read_file( $filename );
    return @data;
}

sub pre_process_csv_data{
    my ($data_to_compare, $filename) = @_;

    my @new_data = @{$data_to_compare->[0]};
    my @old_data = @{$data_to_compare->[1]};

    my @logmessage = ("Column definition for $filename has changed");
    my @additional_columns =  map $_->[2],grep $_->[0] =~ /\+|c/,sdiff $old_data[0], $new_data[0];
    my @removed_columns =  map $_->[1],grep $_->[0] =~ /-|c/,sdiff $old_data[0], $new_data[0];

    my %summary = map {($_, '+')} @additional_columns;
    map {
        if (exists $summary{$_}) {
            $summary{$_} = 'r';
        }
        else {
            $summary{$_} = '-';
        }
    } @removed_columns;

    @additional_columns = grep $summary{$_} eq '-', sort keys (%summary);
    @removed_columns = grep $summary{$_} eq '+', sort keys (%summary);

    push @logmessage, "New column(s):", map "\t$_", @additional_columns if @additional_columns;
    push @logmessage, "Deleted column(s): ", map "\t$_", @removed_columns if @removed_columns;

    my $mapping_ref = map_columns($new_data[0], $old_data[0]); #reorder and/or remove metrics
    remap_data($data_to_compare, $mapping_ref);

    return join "\n", @logmessage;
}

sub remap_data {
    my ($data_ref, $mapping_ref) = @_;

    my @new_data_mapping = @{$mapping_ref->[0]};
    my @old_data_mapping = @{$mapping_ref->[1]};

    my @new_data = @{$data_ref->[0]};
    my @old_data = @{$data_ref->[1]};

    @new_data = map [remap_row($_, \@new_data_mapping)], @new_data;
    @old_data = map [remap_row($_, \@old_data_mapping)], @old_data;

    $data_ref->[0] = \@new_data;
    $data_ref->[1] = \@old_data;
}

sub remap_row {
    my ($data_ref, $mapping_ref) = @_;

    my @remapped_row;
    foreach my $index (0 .. $#{$mapping_ref}) {
        $remapped_row[$mapping_ref->[$index][0]] = $data_ref->[$mapping_ref->[$index][1]];
    }

    return @remapped_row;
}

sub map_columns {
    my ($new_header_ref, $old_header_ref) = @_;

# dereference the column-names
    my @new_header_names = @$new_header_ref;
    my @old_header_names = @$old_header_ref;

# map columnnumbers and index to hash (name => number)

    my %new_map = map {$new_header_names[$_],$_} (0 .. $#new_header_names); 
    my %old_map = map {$old_header_names[$_],$_} (0 .. $#old_header_names);

    my $index = 0;

# renumber columns that exist in both versions maintaining the original order
    my %new_remapped_header =  map {$new_header_names[$_], [$index++, $_]} grep exists $old_map{$new_header_names[$_]}, (0 .. $#new_header_names);

# all columns existing in the new table should be mapped to the re-mapped columns in that table (metric => [post_map_column, pre_map_column])
    my %old_remapped_header = map {$old_header_names[$_], [$new_remapped_header{$old_header_names[$_]}[0], $_]} grep exists $new_remapped_header{$old_header_names[$_]}, (0 .. $#old_header_names);

    return [[values %new_remapped_header], [values %old_remapped_header]]
}

sub create_spreadsheet {
    my ($filename, $sheets_ref, $format_ref) = @_;

    $filename =~ s/\//\/diff\//;
    $filename =~ s/\.csv/_diff.xls/i;
    my $path = $filename;
    $path =~ s/[^\/]+$//;
    mkpath $path if ! -d $path;

    my %spreadsheet;
    my $workbook = $spreadsheet{workbook} = Spreadsheet::WriteExcel::Big->new("$filename");
    my $format = $spreadsheet{workbook}{format}{bodytext} = $workbook->add_format();
    $format->set_size(10);
    $format->set_font('Verdana');
    my $format2 = $spreadsheet{workbook}{format}{header} = $workbook->add_format();
    $format2->set_size(10);
    $format2->set_font('Verdana');
    $format2->set_bold();
    $format2->set_bg_color('53');

    foreach my $worksheet (@$sheets_ref, "diff") {
        $spreadsheet{workbook}{worksheet}{$worksheet} = $workbook->add_worksheet($worksheet);
        $spreadsheet{workbook}{worksheet}{$worksheet}->freeze_panes(1,0);
    }

    return \%spreadsheet;
}

sub format_spreadsheet {
    my ($workbook_ref, $number_of_columns) = @_;

    foreach my $worksheet (keys %{$workbook_ref->{worksheet}}) {
        $workbook_ref->{worksheet}{$worksheet}->set_column(0, $number_of_columns, undef, $workbook_ref->{format}{bodytext});
        $workbook_ref->{worksheet}{$worksheet}->set_row(0, undef, $workbook_ref->{format}{header});
    }
}

sub write_difference {
    my ($row_ref, $cell_ref) = @_;

    my $cell_content = ($cell_ref->[1] =~ /\s*[\+-]?\s*\d+(?:\.\d+)?\s*$/ && $cell_ref->[2] =~ /^\s*[\+-]?\s*\d+(?:\.\d+)?\s*$/) ? $cell_ref->[2] - $cell_ref->[1] : "< '$cell_ref->[2]'\n> '$cell_ref->[1]'";
    $row_ref->[$cell_ref->[0]] = $cell_content;
}

sub write_differences_generic {
    my ($filename, $old_test, $new_test, $differences_ref) = @_;

    $filename =~ /^(.*?)[\/](.*)$/;
    my $path = "${1}/diff/"; # testname/diff
    my $file = $2;
    $file =~ s/\//_/g;

    mkpath $path if !-d $path;
    my @logmessage = "Found unexpected differences in $filename:";

    open FILEOUT, ">$path$file" or die "Couldn't open $path$file for output\n";
    foreach my $row (@$differences_ref) {
        $row->[1][1] =~ s/[\r\n]+$//;
        $row->[1][2] =~ s/[\r\n]+$//;
        push @logmessage, sprintf "< %s", $row->[1][2];
        print FILEOUT "$logmessage[-1]\n";
        push @logmessage, sprintf "> %s", $row->[1][1];
        print FILEOUT "$logmessage[-1]\n";
    }
    close FILEOUT;

    return \@logmessage;
}

sub write_differences_ageneric {
    my ($filename, $differences_ref) = @_;

    my $hunk_texts_ref = process_differences ($differences_ref);

    $filename =~ /^(.*?)[\/](.*)$/;
    my $path = "${1}/diff/"; # testname/diff
    my $file = $2;
    $file =~ s/\//_/g;

    mkpath $path if !-d $path;
    write_file "$path$file", @$hunk_texts_ref;
}

sub process_differences {
    my ($differences_ref) = @_;

    my ($total_number_of_deleted_lines, $total_number_of_inserted_lines);
    my ($current_number_of_deleted_lines, $current_number_of_inserted_lines);

    my @hunk_texts;
    my $hunks_ref = create_hunks($differences_ref);

    foreach my $hunk (@$hunks_ref) { # $hunk should be renamed to $hunk_ref

        my @delete_bounds = process_hunk($hunk->{deleted});
        my @deleted_lines = map $_->[0], @{$hunk->{deleted}};
        my @insert_bounds = process_hunk($hunk->{inserted});
        my @inserted_lines = map $_->[0], @{$hunk->{inserted}};

        $total_number_of_deleted_lines += ($current_number_of_deleted_lines = @deleted_lines);
        $total_number_of_inserted_lines += ($current_number_of_inserted_lines = @inserted_lines);

        my $hunk_text;
        if (!$current_number_of_inserted_lines) {
            $hunk_text = sprintf "%s%sd%s\n%s\n",
                $delete_bounds[0],
                $current_number_of_deleted_lines > 1 ? ",$delete_bounds[1]" :'',
                $delete_bounds[1] - $total_number_of_deleted_lines + $total_number_of_inserted_lines,
                join "\n", @deleted_lines;
        }
        elsif (!$current_number_of_deleted_lines) {
            $hunk_text = sprintf "%sa%s%s\n%s\n",
                $insert_bounds[1] + $total_number_of_deleted_lines - $total_number_of_inserted_lines,
                $insert_bounds[0],
                $current_number_of_inserted_lines > 1 ? ",$insert_bounds[1]" : '',
                join "\n", @inserted_lines;
        }
        else {
            $hunk_text = sprintf "%d%sc%d%s\n%s\n",
                $delete_bounds[0],
                $current_number_of_deleted_lines > 1 ? ",$delete_bounds[1]" :'',
                $insert_bounds[0],
                $current_number_of_inserted_lines > 1 ? ",$insert_bounds[1]" : '',
                join "\n", @deleted_lines,
                    '---',
                    @inserted_lines;
        }
        push @hunk_texts, $hunk_text;
    }
    return \@hunk_texts;
}

sub create_hunks {
    my ($differences_ref) = @_;

    my @hunks;

    foreach my $hunk_ref (@{$differences_ref}) {
        my @deleted_lines = map {[$_->[1], "< $_->[2]"]} grep $_->[0] eq '-', @$hunk_ref;
        my @inserted_lines = map {[$_->[1], "> $_->[2]"]} grep $_->[0] eq '+', @$hunk_ref;
        push @hunks, {
            deleted     => \@deleted_lines,
            inserted    => \@inserted_lines
        };
    }
    return \@hunks;
}

sub process_hunk {
    my ($block_ref) = @_;

    return (undef, undef) if !@{$block_ref};

    my @delete_bounds = ($block_ref->[0][0],$block_ref->[-1][0]);
    foreach (@{$block_ref}) {
        splice @{$_}, 0, 1;
        $_->[0] =~ s/\s*$//;
    }
    return @delete_bounds;
}

sub report_csv_changes {
    my ($filename, $message_ref) = @_;

    $filename =~ /^(.*?)[\/](.*)$/;
    my $path = "${1}/diff/"; # testname/diff
    my $file = $2;
    $file =~ s/\//_/g;

    mkpath $path if !-d $path;

    open FILEOUT, ">$path$file" or die "Couldn't open $path$file for output\n";
    foreach my $row (@$message_ref) {
        print FILEOUT "$row\n";
    }
    close FILEOUT;

    return $message_ref;
}

sub report_unique_file {
    my ($build, $filename, $message) = @_;

    $filename =~ /^(.*?)[\/](.*)$/;
    my $path = "${1}/diff/"; # testname/diff
    my $file = $2;
    $file =~ s/\//_/g;

    mkpath $path if !-d $path;

    open FILEOUT, ">$path$file" or die "Couldn't open $path$file for output\n";
    print FILEOUT "$message\n";
    close FILEOUT;
}

sub get_subdirectories {
    my ($current_directory, $subdir_ref, $tree_ref) = @_;

    chdir $current_directory;
    opendir DIR, '.';
    my @directories =
        map "$current_directory/$_",
        grep !rmdir     # if we can't remove the dir it contains files which have to be moved
        , grep -d       # only directories
        , grep !/^\./   # ignore current and parent directories
        , readdir DIR;
    closedir DIR;

    push @$subdir_ref, $current_directory;

    if (!@directories) {
        push @$tree_ref, $current_directory;
        return;
    }

    foreach my $next_directory (@directories) {
        chdir $next_directory;
        get_subdirectories($next_directory, $subdir_ref, $tree_ref);
        chdir '..';
        #try to remove the 'next' directory in case all its siblings are empty
        rmdir $next_directory;
    }
}

sub move_to_archive {
    my ($source_root, $target_root) = @_;

    my @source_tree = ();
    my @source_dirs = ();
    my @target_dirs = ();

    my $current_directory = cwd;

    get_subdirectories($source_root, \@source_dirs, \@source_tree);

    chdir $current_directory;

    my @target_tree = @source_tree = grep !/^$target_root/, @source_tree;

    @target_tree = grep s/^$source_root/$target_root/, @target_tree;
    map mkpath ($_), @target_tree;

    @target_dirs = @source_dirs;
    map s/^$source_root/$target_root/, @target_dirs;

    #map source_path to target_path
    link_source_to_target(map {$source_dirs[$_], $target_dirs[$_]} (0 .. $#source_dirs));

    find (\&copy_file, $source_root);
}

{
    my %source_to_target;

    sub link_source_to_target {
        %source_to_target = @_;
    }

    sub copy_file {
        return if -d;
        do {
            copy $_, "$source_to_target{$File::Find::dir}/$_";
        } if exists $source_to_target{$File::Find::dir};
    }
}

1;
