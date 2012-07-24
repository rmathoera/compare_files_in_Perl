@echo off
REM ==============================================================
REM testname currenttest previoustest/gold standaard
REM creates under results\currentversion log file
REM file: currenttest_previoustest_testname.log
REM t660b297_t660b282_citigroup.log
REM was before t660b282_citigroup.log
REM ==============================================================

REM perl IM_Compare.pl citigroup t660b297 t660b282
REM perl IM_Compare.pl citigroup t660b328 t660b282
REM perl IM_Compare.pl citigroup t660b328 t660b297

REM Re-running some study's that where not correctly compared. During regression test
REM Test date 16-05-2012
REM perl IM_Compare.pl amex t660b493 t660b447
REM perl IM_Compare.pl principal_all t660b493 t660b447
REM perl IM_Compare.pl jones t660b493 t660b447
perl IM_Compare.pl finanxy t660b493 t660b447
REM perl IM_Compare.pl tdbank42 t660b493 t660b447
REM perl IM_Compare.pl wellszrd t660b493 t660b447
perl IM_Compare.pl johndeere t660b493 t660b447
