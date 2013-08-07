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
#include <unordered_map>
#include <unordered_set>
#include <boost/functional/hash.hpp>
#include <arpa/inet.h>
using namespace std;

typedef unsigned long ulong;
typedef unsigned int uint;
typedef unsigned short ushort ;



class flow_key
{
  public:
    ulong _src_ip;
    uint _src_port;
    ulong _dst_ip;
    uint _dst_port;
    ushort _protocol;
  public:
    flow_key();
    flow_key(ulong src_ip, uint src_port, ulong dst_ip, uint dst_port, ushort protocol)
    {
      _src_ip = src_ip;
      _src_port = src_port;
      _dst_ip = dst_ip;
      _dst_port = dst_port;
      _protocol = protocol;
    }
    
    bool operator == (const flow_key &right) const
    {
      return (_src_ip == right._src_ip && _src_port == right._src_port && _dst_ip == right._dst_ip && _dst_port == right._dst_port && _protocol == right._protocol);
    }

    bool operator < (const flow_key &right) const
    {
      if ( _src_ip == right._src_ip ) 
      {
	if ( _dst_ip == right._dst_ip )
	{
	  if ( _src_port == right._src_port ) 
	  {
	    if ( _dst_port == right._dst_port)
	      return _protocol < right._protocol;
	    else
	      return _dst_port < right._dst_port;
	  }
	  else 
	  {
	    return _src_port < right._src_port;
	  }
	}
	else 
	{
	  return _dst_ip < right._dst_ip;
	}
      }
      else 
      {
	return _src_ip < right._src_ip;
      }
    }    

    
};

class fk_hash
{
  public:
  size_t operator() (const flow_key & fk) const
  {
        size_t seed = 0;
        boost::hash_combine(seed, fk._src_ip);
        boost::hash_combine(seed, fk._src_port);
	boost::hash_combine(seed, fk._dst_ip);
	boost::hash_combine(seed, fk._dst_port);
	boost::hash_combine(seed, fk._protocol);
        return seed;
  }
};


double lastts = 0.0;
double startts = 0.0;
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


//timestamp srcIP and dstIP tuple. 
struct ts_src_dst
{
  double _ts;
  unsigned long _src;
  unsigned long _dst;
};

//stats information for each IP address
struct stat_info 
{
  unsigned long _tcp_synack_event;
  unsigned long _pair_event;
  unsigned long _srccount;
  unsigned long _dstcount;
  unsigned long _srcbytes;
  unsigned long _dstbytes;
  unordered_set<unsigned long> _uniq_end_set;
  unordered_set<unsigned long> _uniq_dst_set;
  unordered_set<unsigned long> _uniq_src_set;
};


unordered_map<flow_key, double, fk_hash >* pre_bin_packets = new unordered_map<flow_key, double, fk_hash >;
unordered_map<flow_key, double, fk_hash >* cur_bin_packets = new unordered_map<flow_key, double, fk_hash >;
//map<flow_key, double >* pre_bin_packets = new map<flow_key, double>;
//map<flow_key, double >* cur_bin_packets = new map<flow_key, double>;

double cur_bin_start_ts = 0.0;
double pre_bin_start_ts = 0.0;

unordered_map<unsigned long, stat_info> ip_records;

void update_ip_records(unsigned long src, unsigned long dst, bool is_typsynack, bool is_pair, unsigned short bytes)
{

  //update dst -> source set

  unordered_map<unsigned long, stat_info>::iterator mit;
  //update src ip record;
  mit = ip_records.find(src);
  if(mit != ip_records.end())
  {
    (mit->second)._srccount += 1;
    (mit->second)._srcbytes += bytes;
    if(is_typsynack)
      (mit->second)._tcp_synack_event += 1;
    if(is_pair)
      (mit->second)._pair_event += 1;
    //update src -> unique destination set
    ((mit->second)._uniq_end_set).insert(dst);
    ((mit->second)._uniq_dst_set).insert(dst);
  }
  else
  {
    struct stat_info temp_record;
    temp_record._srccount = 1;
    temp_record._dstcount = 0;
    temp_record._srcbytes = bytes;
    temp_record._dstbytes = 0;
    (temp_record._uniq_end_set).insert(dst);
    (temp_record._uniq_dst_set).insert(dst);
    if(is_typsynack)
      temp_record._tcp_synack_event = 1;
    else
      temp_record._tcp_synack_event = 0;
    if(is_pair)
      temp_record._pair_event = 1;
    else
      temp_record._pair_event = 0;
    ip_records.insert(pair<unsigned long, stat_info>(src, temp_record));
  }


  //update dst ip record;
  mit = ip_records.find(dst);
  if(mit != ip_records.end())
  {
    (mit->second)._dstcount += 1;
    (mit->second)._dstbytes += bytes;
    //update dst -> source set
    ((mit->second)._uniq_end_set).insert(src);
    ((mit->second)._uniq_src_set).insert(src);
  }
  else
  {
    struct stat_info temp_record;
    temp_record._srccount = 0;
    temp_record._dstcount = 1;
    temp_record._srcbytes = 0;
    temp_record._dstbytes = bytes;
    temp_record._tcp_synack_event = 0;
    temp_record._pair_event = 0;
    (temp_record._uniq_end_set).insert(src);
    (temp_record._uniq_src_set).insert(src);
    ip_records.insert(pair<unsigned long, stat_info>(dst, temp_record));
  }

}




static void per_packet(libtrace_packet_t *packet, const double interval)
{

  // two proof events, TCP SYN+ACK; SRC-DST pair. 
  bool is_tcpsynack = false;
  bool is_pair = false;

  uint64_t bytes = 0;
  uint src_port=0;
  uint dst_port=0;

	/* Packet data */
	uint32_t remaining;
	/* L3 data */
	void *l3;
	uint16_t ethertype;
	libtrace_tcp_t *tcp = NULL;
	libtrace_udp_t *udp = NULL;
	libtrace_ip_t *ip = NULL;
	libtrace_icmp_t *icmp = NULL;


	ts = trace_get_seconds(packet);
	bytes = trace_get_wire_length(packet);

	if(startts == 0.0)
	{
	  startts = trace_get_seconds(packet);
	  prets = startts;
	  curts = startts;
	  begints = startts;
	}
	else
	{
	  prets = curts;
	  curts = ts;
	  endts = ts;
	}


 	l3 = trace_get_layer3(packet,&ethertype,&remaining);

	if (!l3)
	{
	  /* Probable ARP or something */
	  return;
	}

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
			  if(src_ip.s_addr == 0 || dst_ip.s_addr ==0)
			    return;
			}
			break;
		default:
			return;
	}

	/* Parse the udp/tcp/icmp payload */
	switch(ip->ip_p) {
		case 1:
		  	icmp = trace_get_icmp(packet);
			src_port=0;
			dst_port=0;
			if(icmp->type == 0) // || icmp->type == 3 || icmp->type == 5 || icmp->type == 11)
			{
			  //ICMP reply/error packet;
			}
			break;
		case 6:
			tcp = trace_get_tcp(packet);
			//proof event: syn+ack packet;
			if(tcp && tcp->syn && tcp->ack)
			{
			  src_port=tcp->source;
			  dst_port=tcp->dest;
			  is_tcpsynack = true;
			}
			break;
		case 17:
			udp = trace_get_udp(packet);
			if(udp)
			{
			  src_port=udp->source;
			  dst_port=udp->dest;
			}
			break;
		default:
			return;
	}



	/*
        memset(srcip_buf, 0, 256);
        memset(dstip_buf, 0, 256);
        strcpy(srcip_buf, inet_ntoa(src_ip));
        strcpy(dstip_buf, inet_ntoa(dst_ip));
	*/

	unordered_map<flow_key, double, fk_hash >::iterator fk_mit;
	//search curernt second bin and last second bin for reverse five tuples;
	flow_key r_flow_key(dst_ip.s_addr, dst_port, src_ip.s_addr, src_port, ip->ip_p);
	if(cur_bin_packets->size()!=0)
	{
	  //first search current second bin
	  fk_mit=cur_bin_packets->find(r_flow_key);
	  if(fk_mit!=cur_bin_packets->end() && (ts-(fk_mit->second) <= interval ))
	  {
	    is_pair = true;
	    /*
            src_ip1.s_addr = (fk_mit->first)._src_ip;
            dst_ip1.s_addr = (fk_mit->first)._dst_ip;
            memset(srcip_buf1, 0, 256);
            memset(dstip_buf1, 0, 256);
            strcpy(srcip_buf1, inet_ntoa(src_ip1));
            strcpy(dstip_buf1, inet_ntoa(dst_ip1));
            printf("%f\t%s\t%s\t%f\t%s\t%s\n",fk_mit->second, srcip_buf1, dstip_buf1, ts, srcip_buf, dstip_buf);
	    */

	  }
	  else
	  {
	    //search last second bin if no match in current second bin
	    fk_mit=pre_bin_packets->find(r_flow_key);
	    if((fk_mit!=pre_bin_packets->end())&& (ts-(fk_mit->second) <= interval ))
	    {
	      is_pair = true;

	      /*
	      src_ip1.s_addr = (fk_mit->first)._src_ip;
            dst_ip1.s_addr = (fk_mit->first)._dst_ip;
            memset(srcip_buf1, 0, 256);
            memset(dstip_buf1, 0, 256);
            strcpy(srcip_buf1, inet_ntoa(src_ip1));
            strcpy(dstip_buf1, inet_ntoa(dst_ip1));
            printf("%f\t%s\t%s\t%f\t%s\t%s\n",fk_mit->second, srcip_buf1, dstip_buf1, ts, srcip_buf, dstip_buf);
	    */

	    }
	  }
	}
	else
	{
	  if(pre_bin_packets->size()!=0)
	  {
	    fk_mit=pre_bin_packets->find(r_flow_key);
	    if((fk_mit!=pre_bin_packets->end())&& (ts-(fk_mit->second) <= interval ))
	    {
	      /*
	      src_ip1.s_addr = (fk_mit->first)._src_ip;
            dst_ip1.s_addr = (fk_mit->first)._dst_ip;
            memset(srcip_buf1, 0, 256);
            memset(dstip_buf1, 0, 256);
            strcpy(srcip_buf1, inet_ntoa(src_ip1));
            strcpy(dstip_buf1, inet_ntoa(dst_ip1));
            printf("%f\t%s\t%s\t%f\t%s\t%s\n",fk_mit->second, srcip_buf1, dstip_buf1, ts, srcip_buf, dstip_buf);
	    */

	      is_pair = true;
	    }
	  }
	}

	//place the new packet to current second bin or last second bin;
	flow_key temp_flow_key(src_ip.s_addr, src_port, dst_ip.s_addr, dst_port, ip->ip_p);
	if(pre_bin_packets->size()==0)
	{
	  pre_bin_packets->insert(pair<flow_key, double>(temp_flow_key, ts));
	  pre_bin_start_ts = ts;
	}
	else
	{
	  //put it into the last second bin if the packet is in the range of the last second bin
	  if(ts- pre_bin_start_ts <= interval)
	  {
	    fk_mit=pre_bin_packets->find(temp_flow_key);
	    if(fk_mit!=pre_bin_packets->end())
	    {
	      //find match, only need update timestamp  
	      fk_mit->second = ts;
	    }
	    else
	    {
	      pre_bin_packets->insert(pair<flow_key, double>(temp_flow_key, ts));
	    }
	  }
	  //put it into the current second bin if the packet is beyond the range of the last second bin
	  else
	  {
	    if(cur_bin_packets->size()==0)
	    {
	      cur_bin_packets->insert(pair<flow_key, double>(temp_flow_key, ts));
	      cur_bin_start_ts = ts; 
	    }
	    else
	    {
	      if(ts- cur_bin_start_ts <= interval)
	      {
	        fk_mit=cur_bin_packets->find(temp_flow_key);
	        if(fk_mit!=cur_bin_packets->end())
	        {
		  //update timestamp to be the most recent
		  fk_mit->second = ts;
	        }
	        else
	        {
		  cur_bin_packets->insert(pair<flow_key, double>(temp_flow_key, ts));
	        }
	      }
	      else
	      {
		//current second bin becomes the last second bin, we need to create a new current bin;
		//clear the last second bin;
		pre_bin_packets->clear();
		//current second bin becomes old
		pre_bin_packets = cur_bin_packets;
		pre_bin_start_ts = cur_bin_start_ts;
		//create a new current bin map
		unordered_map<flow_key, double, fk_hash >* temp_bin_packets = new unordered_map<flow_key, double, fk_hash>;
		temp_bin_packets->insert(pair<flow_key, double>(temp_flow_key, ts));
		cur_bin_packets = temp_bin_packets;
		cur_bin_start_ts = ts;
	      }
	    }
	  }
	}

	//update stats info for both the src and dst ip in this packet. 
	update_ip_records(ntohl(src_ip.s_addr), ntohl(dst_ip.s_addr), is_tcpsynack, is_pair, bytes);
}

static void usage(char *argv0)
{
	fprintf(stderr,"usage: %s [ --filter | -f bpfexp ]  [ --max-interval | -t interval ]\n\t\t[ --help | -h ] [ --libtrace-help | -H ] libtraceuri...\n",argv0);
}

/*
void print_all_alive_ip()
{
  set<unsigned long>::iterator it;
  struct in_addr alive_ip;
  for(it= alive_ip_set.begin(); it != alive_ip_set.end(); it++)
  {
    alive_ip.s_addr = (*it);
    //printf("%lu\t%s\n",(*it), inet_ntoa(alive_ip));
    printf("%s\n", inet_ntoa(alive_ip));

  }
}
*/

  
void print_all_ip_statsinfo()
{
  unordered_map<unsigned long, stat_info>::iterator mit;
  struct in_addr ip_addr;
  for(mit= ip_records.begin(); mit != ip_records.end(); mit++)
  {
    ip_addr.s_addr = mit->first;
    printf("%02x\t%lu\t%lu\t%lu\t%lu\t%lu\t%lu\t%lu\t%lu\t%lu\n", ip_addr.s_addr,(mit->second)._tcp_synack_event,(mit->second)._pair_event, (mit->second)._srccount, (mit->second)._dstcount, (mit->second)._srcbytes, (mit->second)._dstbytes, ((mit->second)._uniq_end_set).size(), ((mit->second)._uniq_dst_set).size(), ((mit->second)._uniq_src_set).size());
  }
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

	//print out all alive IP in the set
	//print_all_alive_ip();


	//print the start time and end time of this data file;
	printf("#trace start:%f\ttrace end:%f\tduration:%f\n", begints, endts, (endts-begints));


	//print fsdb header
	printf("#fsdb ip_hex tcp_synack_events pair_events pkts_count_as_src pkts_count_as_dst bytes_count_as_src bytes_count_as_dst uniq_end_count uniq_dst_count uniq_src_count\n");

	//print the stats info of all ip addresses in this data file
	print_all_ip_statsinfo();

	//clear all containers. 
	pre_bin_packets->clear();
	cur_bin_packets->clear();
	ip_records.clear();

	return 0;
}
