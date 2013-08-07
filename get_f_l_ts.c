#include "libtrace.h"
#include <inttypes.h>
#include <stdio.h>
#include <getopt.h>
#include <stdlib.h>
#include <string.h>
#include "lt_inttypes.h"
#include <list>
#include <set>
#include <map>
#include <arpa/inet.h>
using namespace std;

double lastts = 0.0;
double startts = -1.0;
double begints = 0.0;
double endts = 0.0;
double ts = 0.0;
double prets = 0.0;
double curts = 0.0;
uint64_t v4=0;
uint64_t v6=0;
uint64_t udp=0;
uint64_t tcp=0;
uint64_t icmp=0;
uint64_t ok=0;
struct in_addr src_ip, src_ip1;
struct in_addr dst_ip, dst_ip1;
char srcip_buf[256], srcip_buf1[256];
char dstip_buf[256], dstip_buf1[256];

static void per_packet(libtrace_packet_t *packet, const double interval)
{
	/* Packet data */
	uint32_t remaining;
	/* L3 data */
	void *l3;
	uint16_t ethertype;
	l3 = trace_get_layer3(packet,&ethertype,&remaining);

	libtrace_ip_t *ip = NULL;

	/* Get the UDP/TCP/ICMP header from the IPv4/IPv6 packet */
	switch (ethertype) {
		case 0x0800:
		  	ip = trace_get_ip(packet);
			if(!ip)
			  return;
			else
			{

			  src_ip.s_addr = (ip->ip_src).s_addr;
			  dst_ip.s_addr = (ip->ip_dst).s_addr;

			  if(src_ip.s_addr ==0 || dst_ip.s_addr ==0)
			    return;

	   		  ts = trace_get_seconds(packet);
			  if(startts < 0.0)
			  {
	  			startts=ts;
				//printf("%f\t%f\n", startts, ts);
			  }
			}
			break;
		default:
			return;
	}

}

static void usage(char *argv0)
{
	fprintf(stderr,"usage: %s [ --filter | -f bpfexp ]  [ --max-interval | -t interval ]\n\t\t[ --help | -h ] [ --libtrace-help | -H ] libtraceuri...\n",argv0);
}



int main(int argc, char *argv[])
{
	libtrace_t *trace;
	libtrace_packet_t *packet;
	libtrace_filter_t *filter=NULL;
	double interval=0.0;

	while(1) {
		int option_index;
		struct option long_options[] = {
			{ "filter",		1, 0, 'f' },
			{ "max-interval",	1, 0, 't' },
			{ "help",		0, 0, 'h' },
			{ "libtrace-help",	0, 0, 'H' },
			{ NULL,			0, 0, 0 }
		};

		int c= getopt_long(argc, argv, "f:t:hH",
				long_options, &option_index);

		if (c==-1)
			break;

		switch (c) {
			case 'f':
				filter=trace_create_filter(optarg);
				break;
			case 't':
				interval=atof(optarg);
				break;
			case 'H':
				trace_help();
				return 1;
			default:
				fprintf(stderr,"Unknown option: %c\n",c);
				/* FALL THRU */
			case 'h':
				usage(argv[0]);
				return 1;
		}
	}

	if (optind>=argc) {
		fprintf(stderr,"Missing input uri\n");
		usage(argv[0]);
		return 1;
	}

	while (optind<argc) {
		trace = trace_create(argv[optind]);
		++optind;

		if (trace_is_err(trace)) {
			trace_perror(trace,"Opening trace file");
			return 1;
		}

		if (filter)
			if (trace_config(trace,TRACE_OPTION_FILTER,filter)) {
				trace_perror(trace,"ignoring: ");
			}

		if (trace_start(trace)) {
			trace_perror(trace,"Starting trace");
			trace_destroy(trace);
			return 1;
		}

		packet = trace_create_packet();

		while (trace_read_packet(trace,packet)>0) {
			per_packet(packet, interval);
		}

		trace_destroy_packet(packet);

		if (trace_is_err(trace)) {
			trace_perror(trace,"Reading packets");
		}

		trace_destroy(trace);
	}
	printf("%f\t%f\n", startts, ts);

	return 0;
}
