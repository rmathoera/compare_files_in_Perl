@echo off
REM Report Generator version 1.0.1
rem perl Report_generator_v1.pl ReportConfigt631b601.txt t631b601 > Report_all_t631b601.txt
rem perl Report_generator_v1.pl ReportConfigt640b800.txt t640b800 > Report_all_t640b800.txt
rem perl Report_generator_v1.pl ReportConfigt640b860.txt t640b860 > Report_all_t640b860.txt
rem perl Report_generator_v1.pl ReportConfigt640b866.txt t640b866 > Report_all_t640b866.txt
rem perl Report_generator_v1.pl ReportConfigt640b880.txt t640b880 > Report_all_t640b880.txt
rem perl Report_generator_v1.pl ReportConfigt641b820.txt t641b820 > Report_all_t641b820.txt
rem perl Report_generator_v1.pl ReportConfigt650b815.txt t650b815 > Report_all_t650b815.txt

REM Report Generator version 1.0.2, get SMI-S time elapses.
rem perl Report_generator_v1.0.2.pl ReportConfigt630b286.txt t630b286 > Report_all_t630b286.txt REM ???? no executables
rem perl Report_generator_v1.0.2.pl ReportConfigt630b469.txt t630b469 > Report_all_t630b469.txt
rem perl Report_generator_v1.0.2.pl ReportConfigt630b286.txt t630b286 > Report_all_t630b286.txt
rem perl Report_generator_v1.0.2.pl ReportConfigt631b601.txt t631b601 > Report_all_t631b601.txt
rem perl Report_generator_v1.0.2.pl ReportConfigt632b796.txt t632b796 > Report_all_t632b796.txt
rem perl Report_generator_v1.0.2.pl ReportConfigt640b600.txt t640b600 > Report_all_t640b600.txt REM ????? no executables
rem perl Report_generator_v1.0.2.pl ReportConfigt640b800.txt t640b800 > Report_all_t640b800.txt
rem perl Report_generator_v1.0.2.pl ReportConfigt640b880.txt t640b880 > Report_all_t640b880.txt
rem perl Report_generator_v1.0.2.pl ReportConfigt641b848.txt t641b848 > Report_all_t641b848.txt
rem perl Report_generator_v1.0.2.pl ReportConfigt641b916.txt t641b916 > Report_all_t641b916.txt
rem perl Report_generator_v1.0.2.pl ReportConfigt641b926.txt t641b926 > Report_all_t641b926.txt
rem perl Report_generator_v1.0.2.pl ReportConfigt650b815.txt t650b815 > Report_all_t650b815.txt
rem perl Report_generator_v1.0.2.pl ReportConfigt650b889.txt t650b889 > Report_all_t650b889.txt
rem perl Report_generator_v1.0.2.pl ReportConfigt650b917.txt t650b917 > Report_all_t650b917.txt

REM Report Generator version 1.0.3, added sequence number by Charts.
rem perl Report_generator_v1.0.3.pl ReportConfigt630b286.txt t630b286 > Report_all_t630b286.txt REM ???? no executables
rem perl Report_generator_v1.0.3.pl ReportConfigt630b469.txt t630b469 > Report_all_t630b469.txt
rem perl Report_generator_v1.0.3.pl ReportConfigt630b286.txt t630b286 > Report_all_t630b286.txt
rem perl Report_generator_v1.0.3.pl ReportConfigt631b601.txt t631b601 > Report_all_t631b601.txt
rem perl Report_generator_v1.0.3.pl ReportConfigt632b796.txt t632b796 > Report_all_t632b796.txt
rem perl Report_generator_v1.0.3.pl ReportConfigt640b600.txt t640b600 > Report_all_t640b600.txt REM ????? no executables
rem perl Report_generator_v1.0.3.pl ReportConfigt640b800.txt t640b800 > Report_all_t640b800.txt
rem perl Report_generator_v1.0.3.pl ReportConfigt640b880.txt t640b880 > Report_all_t640b880.txt
rem perl Report_generator_v1.0.3.pl ReportConfigt641b848.txt t641b848 > Report_all_t641b848.txt
rem perl Report_generator_v1.0.3.pl ReportConfigt641b916.txt t641b916 > Report_all_t641b916.txt
rem perl Report_generator_v1.0.3.pl ReportConfigt641b926.txt t641b926 > Report_all_t641b926.txt
rem perl Report_generator_v1.0.3.pl ReportConfigt650b815.txt t650b815 > Report_all_t650b815.txt
rem perl Report_generator_v1.0.3.pl ReportConfigt650b889.txt t650b889 > Report_all_t650b889.txt
rem perl Report_generator_v1.0.3.pl ReportConfigt650b917.txt t650b917 > Report_all_t650b917.txt

REM Report Generator take argument 2 as version dynamicly , no need for unquie reportconfig files.
REM also Report are put under ReportGenerator path under the Batch file and perl script.
REM perl Report_generator_v1.0.4.pl ReportConfig.txt t641b006 > ReportGenerator\Report_all_t641b006.txt
REM perl Report_generator_v1.0.4.pl ReportConfig.txt t650b054 > ReportGenerator\Report_all_t650b054.txt
REM perl Report_generator_v1.0.4.pl ReportConfig.txt t641b048 > ReportGenerator\Report_all_t641b048.txt
REM perl Report_generator_v1.0.4.pl ReportConfig.txt t642b165 > ReportGenerator\Report_all_t642b165.txt
REM perl Report_generator_v1.0.4.pl ReportConfig.txt t660b190 > ReportGenerator\Report_all_t660b190.txt
REM perl Report_generator_v1.0.4.pl ReportConfig.txt t643b205 > ReportGenerator\Report_all_t643b205.txt
REM perl Report_generator_v1.0.4.pl ReportConfig.txt t660b226 > ReportGenerator\Report_all_t660b226.txt
REM perl Report_generator_v1.0.4.pl ReportConfig.txt t660b239 > ReportGenerator\Report_all_t660b239.txt
REM perl Report_generator_v1.0.4.pl ReportConfig.txt t660b256 > ReportGenerator\Report_all_t660b256.txt REM no run
REM perl Report_generator_v1.0.4.pl ReportConfig.txt t660b268 > ReportGenerator\Report_all_t660b268.txt REM no run
REM perl Report_generator_v1.0.4.pl ReportConfig.txt t660b282 > ReportGenerator\Report_all_t660b282.txt
REM perl Report_generator_v1.0.4.pl ReportConfig.txt t660b297 > ReportGenerator\Report_all_t660b297.txt
REM perl Report_generator_v1.0.4.pl ReportConfig.txt t660b328 > ReportGenerator\Report_all_t660b328.txt
REM perl Report_generator_v1.0.4.pl ReportConfig.txt t660b343 > ReportGenerator\Report_all_t660b343.txt
REM perl Report_generator_v1.0.4.pl ReportConfig.txt t660b353 > ReportGenerator\Report_all_t660b353.txt
REM perl Report_generator_v1.0.4.pl ReportConfig.txt t660b357 > ReportGenerator\Report_all_t660b357.txt

@echo on
perl Report_generator_v1.0.4.pl ReportConfig.txt t660b361 > ReportGenerator\Report_all_t660b361.txt
perl Report_generator_v1.0.4.pl ReportConfig.txt t660b380 > ReportGenerator\Report_all_t660b380.txt REM no run
perl Report_generator_v1.0.4.pl ReportConfig.txt t660b391 > ReportGenerator\Report_all_t660b391.txt REM no run
perl Report_generator_v1.0.4.pl ReportConfig.txt t660b405 > ReportGenerator\Report_all_t660b405.txt
perl Report_generator_v1.0.4.pl ReportConfig.txt t660b418 > ReportGenerator\Report_all_t660b418.txt
perl Report_generator_v1.0.4.pl ReportConfig.txt t660b429 > ReportGenerator\Report_all_t660b429.txt
REM perl Report_generator_v1.0.4.pl ReportConfig.txt t660b437 > ReportGenerator\Report_all_t660b437.txt
REM perl Report_generator_v1.0.4.pl ReportConfig.txt t660b442 > ReportGenerator\Report_all_t660b442.txt
REM perl Report_generator_v1.0.4.pl ReportConfig.txt t660b447 > ReportGenerator\Report_all_t660b447.txt
