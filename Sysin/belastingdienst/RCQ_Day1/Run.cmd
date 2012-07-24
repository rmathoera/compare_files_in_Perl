@echo off

set MVSHOST=172.29.122.81
set MVSUSER=IMUSGU1
set MVSPWD=tmlk910

echo Upload parameters
ftp -s:upload.ftp -n %MVSHOST% > upload_ftp.log

echo Run Reduce
T:\rmfmagic\bin\submitjcl.pl $2reduce.jcl $2reduce.log

echo Run Analyze
T:\rmfmagic\bin\submitjcl.pl $3analze.jcl $3analze.log

echo Load data into database
T:\rmfmagic\bin\submitjcl.pl $4dbload.jcl $4dbload.log

