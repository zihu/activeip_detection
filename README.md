#activeip_detection by Zi Hu zihu@usc.edu
#process lander traces to find out active ip addresses
======================================================
steps to run the code:

1. compile:  
	type "make clean all" to compile the code (the Makefile is specified to work on HPCC, if you are working on other machines, you need to modify the Makefile)

Before you run the code, I highly suggest you to check that the working directory is correct in all the scripts, to do so, you need to check three files:
	1) activeip.crontab
	2) activeip_stats_bin.sh
	3) fill_bin.sh
        
	to make sure that the variable: ACTIVEIP_STATDIR is set to the current directory. (which means to make sure ACTIVEIP_STATDIR=/current/working/directory )
  	Usually, it should be set correctly, but just in case. 

2. run:
	this code is supposed to be run on HPCC, basically you need to create two cron jobs to run the code. There is already an cron job file in this directory, you only need:
	type "cat activeip.crontab | crontab"  to add the cron jobs. ATTENTION: this will erase your old cron jobs;

	One thing to mention is that these cron jobs are set to work on host anonimized data, if your need to analyze the raw data, you need to modify this line:
	*/4 * * * * $DISPATCHER -w 30 -j 160 -n 1 $ACTIVEIPSTAT/fill_bin.sh host 
	to something like:
	*/4 * * * * $DISPATCHER -w 30 -j 160 -n 1 $ACTIVEIPSTAT/fill_bin.sh raw

3. go:
	following the instructions in "https://wiki.isi.edu/div7/index.php/Lander:Collecting_Data_at_USC" to enable data dilevery.
	Then you are ready to go.

4. result: 
	all results will be stored in the RSLT folder which is located in the same directory as the code.  


