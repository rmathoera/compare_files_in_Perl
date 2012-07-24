//IMUSGU1C JOB ,IMUSGU1,NOTIFY=IMUSGU1,MSGLEVEL=(1,1),
//             COND=(16,LT), Terminate if a step ends with RC>4
//             REGION=0M
//*                                                                 
//* COPY JCL TO PROJECT SPECIFIC JCL DATASET                        
//* ADAPTED FROM $0NEWPRJ TO CLEANUP FIRST
//*                                                                 
//   SET PRODUCT=RMFMAGIC             WHERE THE PRODUCT IS INSTALLED
//   SET USERHLQ=USERHLQ              YOUR USERID FOR STUDY DATASETS
//   SET PROJECT=PROJECT              YOUR PROJECT                  
//*                                                                 
//* (C) 2003-2008 INTELLIMAGIC BV, THE NETHERLANDS                  
//* WWW.INTELLIMAGIC.NET                                            
//*                                                                 
//*
//* First perform cleanup: delete previous upload and build results
//*
//CLEANUP  EXEC PGM=IEFBR14                              
//JCL      DD DISP=(MOD,DELETE),UNIT=SYSDA,SPACE=(TRK,0),
//            DSN=&USERHLQ..&PROJECT..JCL
//*
//* 
//* Now allocate new JCL libraries
//*
//COPY  EXEC PGM=IEBCOPY                                            
//SYSPRINT DD SYSOUT=*                                              
//SYSIN    DD *                                                     
  COPY I=IN,O=OUT                                                   
//IN       DD DISP=SHR,DSN=&PRODUCT..JCL                            
//OUT      DD DISP=(NEW,CATLG),UNIT=SYSDA,                          
//            SPACE=(TRK,(35,30,30),RLSE),                          
//            DCB=(LRECL=80,RECFM=FB,BLKSIZE=4560),                 
//            DSN=&USERHLQ..&PROJECT..JCL                           