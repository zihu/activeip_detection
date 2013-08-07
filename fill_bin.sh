#!/bin/bash 
# by Zi: zihu@usc.edu
# this script does two things:
# 1. split/move traces to each 15 minutes bin. if a trace doesn't cross bins, just move it to the right bin, otherwise, we have to split the trace and put different parts to different bins
# 2. process traces, if a bin get all the necessary traces, process it.

# bin time range: 15 minutes
INTERVAL=900 
INPUTFILE=$1

ACTIVEIP_STATDIR="/home/samfs-02/LANDER/zihu/activeip_stat"
[ -d "$ACTIVEIP_STATDIR" ] || exit 1 

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

VINPUT_DIR="$ACTIVEIP_STATDIR/vinput_dir/$landername"
[ -d "$VINPUT_DIR" ] || mkdir -p "$VINPUT_DIR"
file_count=$(ls $VINPUT_DIR | wc -l)
if [ $file_count -lt 500 ];then
  /bin/touch $VINPUT_DIR/$basename.txt
fi


# delete the error log if nothing bad happens
errlog_size=$(stat -c%s $TMPERR)
if [ $errlog_size -eq 0 ]; then
  /bin/rm $TMPERR
fi

exit 0
