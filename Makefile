CC = g++
GCC = gcc
CFLAGS += -std=c++0x -I/home/samfs-02/LANDER/plander/include -g -Wall
LDFLAGS = -lpcap -lz -lbz2 -lpthread
LDLIBS = -L /home/samfs-02/LANDER/plander/lib -ltrace

#want to link static, hence below
PLANDER_LIBDIR = /home/samfs-02/LANDER/plander/lib
TRACELIBS = $(PLANDER_LIBDIR)/libtrace.a $(PLANDER_LIBDIR)/libwandio.a
LDLIBS = 

prog = activeip_metric_stats_opt_new get_f_l_ts tracesplit

default: all


all: usciplist update_workdir ${prog} 

tracesplit: tracesplit.o ${TRACELIBS}
	${GCC} ${LDFLAGS} $^ -o $@ 
tracesplit.o: tracesplit.c
	${GCC} -I/home/samfs-02/LANDER/plander/include -g -Wall -c tracesplit.c 

activeip_metric_stats_opt: activeip_metric_stats_opt.o $(TRACELIBS)
activeip_metric_stats_opt_new: activeip_metric_stats_opt_new.o $(TRACELIBS)

get_f_l_ts: get_f_l_ts.o ${TRACELIBS}


ALL_USC_IP=all_usc_ips.fsdb
DYNAMIC_USC_IP=allowed_usc_dynamic_ips.fsdb
USC_IP_CATEGORY=usc_ip_blocks.txt

usciplist: ${USC_IP_CATEGORY} 

${USC_IP_CATEGORY}: ${ALL_USC_IP} ${DYNAMIC_USC_IP} 
	cat ${ALL_USC_IP} | grep -v "^#" | awk '{print $$1"\tall"}' >$@_
	cat ${DYNAMIC_USC_IP} | grep -v "^#" | awk '{print $$1"\tdynamic"}' >>$@_
	test -s $@_ && mv $@_ $@


CUR_DIR=${shell pwd | sed 's/\//\\\//g'}


CRONTABS=activeip.crontab
${CRONTABS}: ${CRONTABS}.template
	sed 's/WORKING_DIR/${CUR_DIR}/g' ${CRONTABS}.template > $@

ACTIVEIP_STATS=activeip_stats_bin.sh
${ACTIVEIP_STATS}: ${ACTIVEIP_STATS}.template
	sed 's/WORKING_DIR/${CUR_DIR}/g' ${ACTIVEIP_STATS}.template > $@

FILL_BIN=fill_bin.sh
${FILL_BIN}: ${FILL_BIN}.template
	sed 's/WORKING_DIR/${CUR_DIR}/g' ${FILL_BIN}.template > $@

update_workdir: ${CRONTABS} ${ACTIVEIP_STATS} ${FILL_BIN}


clean:
	rm -f *~ *.o ${prog} ${USC_IP_CATEGORY} ${CRONTABS} ${ACTIVEIP_STATS} ${FILL_BIN}

package: 
	tar -vzcf activeip_stats.tar.gz README.md Makefile activeip_metric_stats_opt_new.c get_f_l_ts.c tracesplit.c \
	${CRONTABS}.template ${ACTIVEIP_STATS}.template ${FILL_BIN}.template ${ALL_USC_IP} ${DYNAMIC_USC_IP}
