CC = g++
GCC = gcc
CFLAGS += -std=c++0x -I/home/samfs-02/LANDER/plander/include -g -Wall
LDFLAGS = -lpcap -lz -lbz2 -lpthread
LDLIBS = -L /home/samfs-02/LANDER/plander/lib -ltrace

#want to link static, hence below
PLANDER_LIBDIR = /home/samfs-02/LANDER/plander/lib
TRACELIBS = $(PLANDER_LIBDIR)/libtrace.a $(PLANDER_LIBDIR)/libwandio.a
LDLIBS = 

ALL_USC_IP=all_usc_ips.fsdb
DYNAMIC_USC_IP=allowed_usc_dynamic_ips.fsdb
USC_IP_CATEGORY=usc_ip_blocks.txt

usciplist: ${USC_IP_CATEGORY} 

prog = activeip_metric_stats_opt_new activeip_metric_stats_opt get_f_l_ts tracesplit

default: all


all: usciplist ${prog} 

tracesplit: tracesplit.o ${TRACELIBS}
	${GCC} ${LDFLAGS} $^ -o $@ 
tracesplit.o: tracesplit.c
	${GCC} -I/home/samfs-02/LANDER/plander/include -g -Wall -c tracesplit.c 

activeip_metric_stats_opt: activeip_metric_stats_opt.o $(TRACELIBS)
activeip_metric_stats_opt_new: activeip_metric_stats_opt_new.o $(TRACELIBS)

get_f_l_ts: get_f_l_ts.o ${TRACELIBS}


${USC_IP_CATEGORY}: ${ALL_USC_IP} ${DYNAMIC_USC_IP} 
	cat ${ALL_USC_IP} | grep -v "^#" | awk '{print $$1"\tall"}' >$@_
	cat ${DYNAMIC_USC_IP} | grep -v "^#" | awk '{print $$1"\tdynamic"}' >>$@_
	test -s $@_ && mv $@_ $@


clean:
	rm -f *~ *.o ${prog} ${USC_IP_CATEGORY}


