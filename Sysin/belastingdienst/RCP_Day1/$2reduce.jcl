//IMUSGU1R JOB ,IMUSGU1,NOTIFY=IMUSGU1,MSGLEVEL=(1,1),
//             COND=(16,LT), Terminate if a step ends with RC>4
//             REGION=0M
//*
//* RUN RMF MAGIC REDUCE RUN: INITIAL SMF COMPRESSION RUN
//*
//* MODIFY JCL PARAMETERS FOR YOUR DATASET NAMES
//* LARGE INSTALLATIONS MAY REQUIRE MORE THAN 64 MBYTE
//*
//   SET PROJECT=BDIENST
//   SET RUN=RCPD1         IDENTIFIER USED FOR DATASET DATABASE TABLE
//*                               USE THE SAME IDENTIFIER IN $3ANALZE
//*
//   SET PRODUCT=RMFMAGIC.T630B469    WHERE THE PRODUCT IS INSTALLED
//   SET USERHLQ=RMFMAGIC.TSUITE      YOUR USERID FOR STUDY DATASETS
//*
//* !!!!!  UP TO 10 SMF DATA SETS CAN BE ALLOCATED !!!!!!
//* !!!!! MODIFY SMF ALLOCATION OR SPECIFY ON CALL !!!!!
//* !!!!!    SMF DATA MUST BE SORTED PER DDNAME    !!!!!
//*
//*
//* (C) INTELLIMAGIC BV, THE NETHERLANDS
//* WWW.INTELLIMAGIC.NET
//*
//* INSTALLATION NOTES:
//* - MAKE SURE THAT YOUR REGION IS LARGE (64 MBYTE OR MORE)
//* - MAKE SURE THAT THE C-RUNTIME LIBRARIES ARE IN THE LINKLIST,
//*   OR ADD THEM TO THE STEPLIB
//* - WHEN YOUR INSTALLATION DOES NOT ACCEPT THE LOW LEVEL QUALIFIERS
//*   YOU CAN USE
//*     ANY VB-255 LLQ FOR THE RMC FILE.  DO NOT USE A VBA LLQ
//*     ANY FB LLQ FOR THE RMZ FILE
//*
//*
//CLEANUP  EXEC PGM=IEFBR14
//DBA      DD DISP=(MOD,DELETE),UNIT=SYSDA,SPACE=(TRK,0),
//            DSN=&USERHLQ..&PROJECT..&RUN..DBA
//RMC      DD DISP=(MOD,DELETE),UNIT=SYSDA,SPACE=(TRK,0),
//            DSN=&USERHLQ..&PROJECT..RMC
//RMZ      DD DISP=(MOD,DELETE),UNIT=SYSDA,SPACE=(TRK,0),
//            DSN=&USERHLQ..&PROJECT..RMZ
//SYSPRINT DD DISP=(MOD,DELETE),UNIT=SYSDA,SPACE=(TRK,0),
//            DSN=&USERHLQ..&PROJECT..LOG
//*
//REDUCE   EXEC PGM=RMFMAGIC,REGION=0K,PARM=REDUCE
//STEPLIB  DD DISP=SHR,DSN=&PRODUCT..LOAD
//SMF      DD DISP=SHR,DSN=RMFMAGIC.TSUITE.BDIENST.RCP1.ZRF
//SMF1     DD DISP=SHR,DSN=RMFMAGIC.TSUITE.BDIENST.RCP2.ZRF
//SMF2     DD DISP=SHR,DSN=RMFMAGIC.TSUITE.BDIENST.RCP3.ZRF
//SMF3     DD DISP=SHR,DSN=RMFMAGIC.TSUITE.BDIENST.RCP4.ZRF
//SMF4     DD DISP=SHR,DSN=RMFMAGIC.TSUITE.BDIENST.RCE1.ZRF
//SMF5     DD DISP=SHR,DSN=RMFMAGIC.TSUITE.BDIENST.RCE2.ZRF
//* SMF2   DD DISP=SHR,DSN=.. OTHER DATA SET MERGED WITH DDNAME=SMF ..
//* SMF3   DD DISP=SHR,DSN=.. OTHER DATA SET MERGED WITH DDNAME=SMF ..
//* ..... USE UP TO 10 INPUT FILES: SMF AND SMF1 - SMF9
//* SMF9   DD DISP=SHR,DSN=.. OTHER DATA SET MERGED WITH DDNAME=SMF ..
//LICENSE  DD DISP=SHR,DSN=&PRODUCT..JCL(LICENSE)
//HARDWARE DD DISP=SHR,DSN=&PRODUCT..HARDWARE
//*
//* ARRAY AND ARRAY01 - ARRAY18 SPECIFY EMC OR HDS ARRAY INPUT FILES
//*
//* EMC INPUT FILE IS THE OUTPUT FROM #SQ MIRROR
//* HDS INPUT FILE IS THE CONFIGURATION FILE IN XML FORMAT
//*
//ARRAY    DD DUMMY
//*
//*  IF SUPPLYING CAPACITY INFORMATION REPLACE //DCOLLECT DD DUMMY
//*  WITH //DCOLLECT DD DISP=SHR,DSN=<DATA SET CREATED IN $1CAPCTY>
//*
//DCOLLECT DD DUMMY
//*DCOLLECT DD DISP=SHR,DSN=&USERHLQ..&PROJECT..CAPACITY.ZRD
//*
//SYSPRINT DD SYSOUT=*,DCB=(LRECL=255,RECFM=VBA)
//LISTING  DD DCB=(LRECL=600,BLKSIZE=28000,RECFM=VBA),
//            DISP=(NEW,CATLG),UNIT=SYSDA,SPACE=(CYL,(3,3),RLSE),
//            DSN=&USERHLQ..&PROJECT..LOG
//DBA      DD DISP=(NEW,CATLG),UNIT=SYSDA,DSNTYPE=LIBRARY,
//            SPACE=(CYL,(10,50,105),RLSE),
//            DCB=(LRECL=4096,RECFM=VB,BLKSIZE=28000),
//            DSN=&USERHLQ..&PROJECT..&RUN..DBA
//RMC      DD DISP=(NEW,CATLG),UNIT=SYSDA,
//            SPACE=(CYL,(2,2),RLSE),
//            DCB=(LRECL=400,RECFM=VB,BLKSIZE=27998),
//            DSN=&USERHLQ..&PROJECT..RMC
//* NOTE: YOU NEED ABOUT 100 CYLINDERS RMZ FOR EVERY GBYTE OF RAW SMF
//RMZ      DD DISP=(NEW,CATLG),UNIT=SYSDA,
//            SPACE=(CYL,(200,200),RLSE),
//            DCB=(LRECL=4096,RECFM=FB,BLKSIZE=24576),
//            DSN=&USERHLQ..&PROJECT..RMZ
//SYSIN    DD DISP=SHR,DSN=&USERHLQ..&PROJECT..JCL(REDUCE)
