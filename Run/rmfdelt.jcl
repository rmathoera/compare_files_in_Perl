//IMUSGU1D JOB ,IMUSGU1,NOTIFY=IMUSGU1,MSGLEVEL=(1,1),
//             COND=(16,LT), Terminate if a step ends with RC>4
//             REGION=0M
//*JOB1
//*JOB2
//*JOB3
//*JOB4
//*--------------------------------------------------------------------
//*
//* RUN RMFDELT TO DELETE AN RMFMAGIC TEST INCLUDING ALL RESULTS
//*
//*   *   MATCH EXACTLY 1 QUALIFIER (QUALIFIER IS THE
//*       PART OF THE DATA SET NAME BETWEEN THE DOTS)
//*   **  MATCH ANY NUMBER OF QUALIFIERS (INCLUDING 0)
//*   %   MATCH EXACTLY 1 CHARACTER (EXACT POSITION)
//*
//*
//DEL      EXEC PGM=ADRDSSU,REGION=0M
//SYSPRINT DD SYSOUT=*
//OUT      DD DUMMY
//SYSIN    DD *
 DUMP DS(          -
         INC(RMFMAGIC.T660.B*.**, -
             RMFMAGIC.T661.B*.**, -
             RMFMAGIC.T670.B*.**)  -
         ) -
      OUTDDNAME(OUT) -
      ADMINISTRATOR -
      PROCESS(SYS1) -
      DELETE TOL(ENQF)
/*
