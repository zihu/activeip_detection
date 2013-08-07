#!/bin/bash 
# by Zi: zihu@usc.edu
# this script does two things:
# 1. split/move traces to each 15 minutes bin. if a trace doesn't cross bins, just move it to the right bin, otherwise, we have to split the trace and put different parts to different bins
# 2. process traces, if a bin get all the necessary traces, process it.

# bin time range: 15 minutes
INTERVAL=900 
INPUTFILE=$1

#ACTIVEIP_STATDIR="/home/zihu/activeip_stat"
ACTIVEIP_STATDIR="/lander/LANDER/zihu/activeip_stats"
[ -d "$ACTIVEIP_STATDIR" ] || exit 1 

ALL_STATUS_RECORD="$ACTIVEIP_STATDIR/all_bin_records.dat"
ALL_TRACES_RECORD="$ACTIVEIP_STATDIR/all_traces_records.dat"
ALL_IN_TRACES_RECORD="$ACTIVEIP_STATDIR/all_in_traces_records.dat"

S_TIME=$(date "+%Y%m%d-%H%M%S")
echo $S_TIME $INPUTFILE >> $ALL_IN_TRACES_RECORD



#check if required file exits?
[ -e "$INPUTFILE" ] || exit 1
GET_F_L_TS_BIN="$ACTIVEIP_STATDIR/get_f_l_ts"
[ -e "$GET_F_L_TS_BIN" ] || exit 1
TRACE_SPLIT="$ACTIVEIP_STATDIR/tracesplit"
[ -e "$TRACE_SPLIT" ] || exit 1

#extract lander name:
dirname=${INPUTFILE%/*}
landername=${dirname##*/}
basename=${INPUTFILE##*/}

BIN_TMP_DIR="$ACTIVEIP_STATDIR/bin_tmp_data/$landername"
[ -d "$BIN_TMP_DIR" ] || mkdir -p "$BIN_TMP_DIR"

IN_PROCESS_DIR="$ACTIVEIP_STATDIR/in_process"
[ -d "$IN_PROCESS_DIR" ] || mkdir -p "$IN_PROCESS_DIR"



LOG_OD="$ACTIVEIP_STATDIR/log/$landername"
[ -d "$LOG_OD" ] || mkdir -p "$LOG_OD"

TMPDEBUG=$LOG_OD/"activeip_stats.debug"
TMPERR=$LOG_OD/$basename.stats.err

# get start time and end time of the trace
st_end_t=$(2>$TMPERR $GET_F_L_TS_BIN "$INPUTFILE" )
if [ "$?" != "0" ]; then
 	echo "fail: get start and end time of: $INPUTFILE" >>$TMPDEBUG
	exit 1
fi

TRACE_ST=$(echo $st_end_t | awk '{print $1}')
TRACE_ET=$(echo $st_end_t | awk '{print $2}')
bad_trace1=`echo "$TRACE_ST <= 0" | bc`
bad_trace2=`echo "$TRACE_ET <= 0" | bc`
if [ $bad_trace1 -eq 1 ] || [ $bad_trace2 -eq 1 ] ;then
  echo "bad trace:" $INPUTFILE >> $TMPDEBUG
  exit 1
fi

TRACE_SEQN=$(echo $basename | awk -F'-' '{print $3}')
TRACE_KEY=$(echo $basename | awk -F'-' '{print $4}')
#time now?
N_TIME_S=$(date +%s)

# seven days? too old
DAY_SEC=604800
DIFF_DELAY=`echo "$N_TIME_S - $TRACE_ST" | bc`
bad_trace=`echo "$DIFF_DELAY > $DAY_SEC" | bc`

if [ $bad_trace -eq 1 ];then
  echo "too old trace:" $INPUTFILE >> $TMPDEBUG
  exit 1
fi


S_TIME=$(date "+%Y%m%d-%H%M%S")


# caculate which bin this trace should go to
BIN_INDEX_S=`echo "$TRACE_ST / $INTERVAL" | bc`
BIN_INDEX_E=`echo "$TRACE_ET / $INTERVAL" | bc`
DIFF_BIN=`echo "$BIN_INDEX_E - $BIN_INDEX_S" | bc`

if [ $DIFF_BIN -lt 0 ]; then
  echo "bad trace:" $INPUTFILE >> $TMPDEBUG
  exit 1
elif [ $DIFF_BIN -eq 0 ]; then
  # trace doesn't cross bin; move the trace to that bin;
  TRACE_BIN_ST=`echo "$BIN_INDEX_S * $INTERVAL " | bc`
  TRACE_BIN_ET=`echo "($BIN_INDEX_S + 1) * $INTERVAL " | bc`

  BIN_FN_BASE=`date -d @$TRACE_BIN_ST "+%Y%m%d-%H%M%S"`
  BIN_INDEX_DIR="$BIN_TMP_DIR/$BIN_FN_BASE"
  echo "Trace:$basename $TRACE_ST $TRACE_ET $TRACE_SEQN Bin:$BIN_FN_BASE $TRACE_BIN_ST $TRACE_BIN_ET" >> $TMPDEBUG
  [ -d "$BIN_INDEX_DIR" ] || mkdir -p "$BIN_INDEX_DIR"
  /bin/mv $INPUTFILE  $BIN_INDEX_DIR
else 
  # trace cross bins, split the trace and move segments to corresponding bins.
  while [ $BIN_INDEX_S -le $BIN_INDEX_E ] 
  do
    TRACE_BIN_ST=`echo "$BIN_INDEX_S * $INTERVAL " | bc` 
    TRACE_BIN_ET=`echo "($BIN_INDEX_S + 1) * $INTERVAL " | bc`
    BIN_FN_BASE=`date -d @$TRACE_BIN_ST "+%Y%m%d-%H%M%S"`
    BIN_INDEX_DIR="$BIN_TMP_DIR/$BIN_FN_BASE"
    echo "Trace:$basename $TRACE_ST $TRACE_ET $TRACE_SEQN Bin:$BIN_FN_BASE $TRACE_BIN_ST $TRACE_BIN_ET" >> $TMPDEBUG
    [ -d "$BIN_INDEX_DIR" ] || mkdir -p "$BIN_INDEX_DIR"
     
    CMPSS=`echo "$TRACE_ST >= $TRACE_BIN_ST" | bc`
    CMPSE=`echo "$TRACE_ST <= $TRACE_BIN_ET" | bc`
    CMPES=`echo "$TRACE_ET >= $TRACE_BIN_ST" | bc`
    CMPEE=`echo "$TRACE_ET <= $TRACE_BIN_ET" | bc`

    PARTIALTRACE=$BIN_INDEX_DIR/$basename
    if [ $CMPSS -eq 1 ] && [ $CMPSE -eq 1 ]; then
      PARTIALTRACE=$PARTIALTRACE"-end"
      2>>$TMPERR $TRACE_SPLIT -s $TRACE_ST -e $TRACE_BIN_ET "erf:$INPUTFILE" "erf:$PARTIALTRACE"
    elif [ $CMPES -eq 1 ] && [ $CMPEE -eq 1 ]; then
      PARTIALTRACE=$PARTIALTRACE"-start"
      2>>$TMPERR $TRACE_SPLIT -s $TRACE_BIN_ST -e $TRACE_ET "erf:$INPUTFILE" "erf:$PARTIALTRACE"
    else
      2>>$TMPERR $TRACE_SPLIT -s $TRACE_BIN_ST -e $TRACE_BIN_ET "erf:$INPUTFILE" "erf:$PARTIALTRACE"
    fi
    ((BIN_INDEX_S=BIN_INDEX_S+1))
  done
fi

E_TIME=$(date "+%Y%m%d-%H%M%S")
#record all the traces processed and the processing time
echo $S_TIME $E_TIME $INPUTFILE >> $ALL_TRACES_RECORD




# check if any bin has all the ERF files it requires. 
# if a bin has all required ERF files, process the bin
BINS_DIR="$BIN_TMP_DIR"
# 6 hours for a lock to expire
MAX_LOCK_ALIVE_TIME=21600
# one minute for monitoring directory updates
MAX_WAIT_TIME=60
# 12 hours for a bin directory to expire
MAX_EXPIRE_TIME=43200
[ -d "$BINS_DIR" ] || exit 1 


# acquire lock
acquire_lock()
{
  lock_name="$ACTIVEIP_STATDIR/$1"
  check_lock_time=$(date "+%Y%m%d-%H%M%S")
  # if other processes are merging the bin, can not get the lock.
  if ! /bin/mkdir $lock_name >/dev/null 2>&1; then
    # if the lock dir is too old, may be something is wrong, delete it to free the lock
    lock_modtime=$(stat -c%Y $lock_name)
    lock_now=$(date +%s)
    lock_gap=`echo "$lock_now - $lock_modtime" | bc`

    # the lock dir is too old, delete it.
    if [ $lock_gap -gt $MAX_LOCK_ALIVE_TIME ]; then 
      echo "$check_lock_time: lock: $1, modified: $lock_modtime, now: $lock_now, gap: $lock_gap"
      /bin/rm -rf $lock_name
      /bin/mkdir $lock_name
      return 1
    else
      return 0
    fi
  fi
  return 1
}

# release lock
release_lock()
{
  lock_name="$ACTIVEIP_STATDIR/$1"
  /bin/rm -rf $lock_name
}


check_traces()
{
  local N_FIELDS=0
  local LABEL=""
  local BEGIN_SEQ=0
  local END_SEQ=0
  local BIN_DIR_W_TRACES="$1"
  local FILES=$(ls $BIN_DIR_W_TRACES)
  [ -z "$FILES" ] && return 2
 
  # get the start and end sequence #.
  while read trace
  do
    N_FIELDS=$(echo $trace | awk -F'-' '{print NF}')
    if [ "$N_FIELDS" == "5" ];then
      LABEL=$(echo $trace | awk -F'-' '{print $NF}')
      [ $LABEL == "start" ] && BEGIN_SEQ=$( echo $trace | awk -F'-' '{print $3}')
      [ $LABEL == "end" ] && END_SEQ=$( echo $trace | awk -F'-' '{print $3}')
    fi
  done <<< "$(ls $BIN_DIR_W_TRACES| grep "^201.*" | sort )"

  # didn't find begin and end? we need to wait
  if [ $BEGIN_SEQ -eq 0 ] || [ $END_SEQ -eq 0 ]; then
    return 0
  fi


  # look at the sequence number of each trace
  local GAP=0
  while read trace
  do
    SEQ=$(echo $trace | awk -F'-' '{print $3}')
    EXP_SEQ=$(echo "$BEGIN_SEQ + $GAP " | bc)
    [ $EXP_SEQ -ne $SEQ ] && return 0

    # if sequence exceed end sequence, something goes wrong here 
    [ $SEQ -gt $END_SEQ ] && return 0 

    # if sequence small then begin seq, something goes wrong here
    [ $SEQ -lt $BEGIN_SEQ ] && return 0

    ((GAP=GAP+1))
  done <<< "$(ls $BIN_DIR_W_TRACES | grep "^201.*" | sort )"
  return 1
}




#function for processing traces
#take a bin directory as input, sort all erf files and process them one by one
ACTIVEIP_STATS_BIN="$ACTIVEIP_STATDIR/activeip_metric_stats_opt"
[ -e "$ACTIVEIP_STATS_BIN" ] || exit 1

PROCESS_TRACES="$ACTIVEIP_STATDIR/all_processed_bins.dat"

process_bin()
{
  S_TIME=$(date "+%Y%m%d-%H%M%S")
  local bin_dir=$1
  local RSLT_OD="$ACTIVEIP_STATDIR/RSLT/$landername"
  [ -d "$RSLT_OD" ] || mkdir -p "$RSLT_OD"
  local td_basename=${bin_dir##*/}

  local DEBUG_OD="$ACTIVEIP_STATDIR/DEBUG"
  [ -d "$DEBUG_OD" ] || mkdir -p "$DEBUG_OD"
   
  local RSLT_FN=$td_basename".stats"
  local TMPOUT=$RSLT_OD/$td_basename".stats"
  local TMPERR=$DEBUG_OD/$td_basename".err"
  local RSLT_FN_GZ=$RSLT_FN".tar.gz"
  local args="-t 1"

  #sort erf files, and construct the args list
  while read trace
  do
   p_trace="$bin_dir/$trace"
   args="$args $p_trace" 
  done <<< "$(ls $bin_dir | grep "^201.*" | sort )"
  #echo $args

  echo $S_TIME $args >> $TMPERR
  #feed sorted erf file list to the processing code
  err=$( 2>&1 >$TMPOUT $ACTIVEIP_STATS_BIN $args )
  if [ "$?" != "0" ]; then
    echo "$err" >>$TMPERR
    return 0
  fi
  E_TIME=$(date "+%Y%m%d-%H%M%S")
  #record all the traces processed and the processing time
  echo $S_TIME $E_TIME $bin_dir >> $PROCESS_TRACES

  #compress the result file
  cd $RSLT_OD && tar -zcf $RSLT_FN_GZ $RSLT_FN && /bin/rm -rf $RSLT_FN && cd -
  # delete the bin directory after it is processed.
  /bin/rm -rf $bin_dir


  return 1
}


LOCK_LOG="$ACTIVEIP_STATDIR/acquire_loc.log"
while read BIN_TRACES_DIR
do
  traces_dir=$BINS_DIR/$BIN_TRACES_DIR
  #if the bin directory is modified in the last $MAX_WAIT_TIME seconds, then wait for next round to process it
  modtime=$(stat -c%Y $traces_dir)
  now=$(date +%s)
  gap=`echo "$now - $modtime" | bc`
  # too young, continue to wait.
  if [ $gap -lt $MAX_WAIT_TIME ]; then 
    continue
  fi
    
  # check if others are processing this bin?
  lock_dir=$BIN_TRACES_DIR".loc" 
  acquire_lock $lock_dir
  if [ "$?" == "0" ];then
    echo $INPUTFILE $BIN_TRACES_DIR "F">> $LOCK_LOG
    continue
  fi
  echo $INPUTFILE $BIN_TRACES_DIR "S">> $LOCK_LOG

 

  inprocess_trace=$IN_PROCESS_DIR/$BIN_TRACES_DIR
  #check if the bin has all the necessary erf files
  #if it has, then process all erf files in the bin one by one, in time order 
  check_traces $traces_dir
  retv="$?"
  if [ "$retv" == "0" ];then
    #if it is too old, process it anyway. 
    if [ $gap -gt $MAX_EXPIRE_TIME ]; then 
      # move it
      if [ -d $inprocess_trace ]; then
        /bin/mv $inprocess_trace $inprocess_trace"_$now"
      fi
      /bin/mv -f $traces_dir $IN_PROCESS_DIR
      #process it
      process_bin $inprocess_trace
      release_lock $lock_dir
      break
    else 
      release_lock $lock_dir
      continue
    fi
  elif [ "$retv" == "1" ];then
    #move it for processing
    if [ -d $inprocess_trace ]; then
      /bin/mv $inprocess_trace $inprocess_trace"_$now"
    fi
    /bin/mv -f $traces_dir $IN_PROCESS_DIR
    #[ -d $inprocess_trace ] || /bin/mv -f $traces_dir $IN_PROCESS_DIR
    #process it
    process_bin $inprocess_trace
    # after process release the lock 
    release_lock $lock_dir
    break
  elif [ "$retv" == "2" ];then
    echo "empty directory: $traces_dir" >>$TMPERR
    continue
  else
    echo "unrecognize ret value from check_traces()" >>$TMPERR
    continue
  fi
done <<< "$(ls $BINS_DIR)"

# delete the error log if nothing bad happens
errlog_size=$(stat -c%s $TMPERR)
if [ $errlog_size -eq 0 ]; then
  /bin/rm $TMPERR
fi

exit 0
