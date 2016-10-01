/*
 * Copyright (c) 2013-2015 Intel Corporation.  All rights reserved.
 *
 * This software is available to you under the BSD license below:
 *
 *     Redistribution and use in source and binary forms, with or
 *     without modification, are permitted provided that the following
 *     conditions are met:
 *
 *      - Redistributions of source code must retain the above
 *        copyright notice, this list of conditions and the following
 *        disclaimer.
 *
 *      - Redistributions in binary form must reproduce the above
 *        copyright notice, this list of conditions and the following
 *        disclaimer in the documentation and/or other materials
 *        provided with the distribution.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AWV
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
 * BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
 * ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>
#include <time.h>
#include <netdb.h>
#include <unistd.h>

#include <limits.h>
#include <shared.h>

#include "fabtest.h"

static int persistent = 1;

//static struct timespec start, end;

static struct ft_series *series;
static int test_start_index, test_end_index = INT_MAX;
struct ft_info test_info;
struct fi_info *fabric_info;
struct ft_xcontrol ft_rx_ctrl, ft_tx_ctrl;
struct ft_control ft_ctrl;

size_t recv_size, send_size;

enum {
	FT_SUCCESS,
	FT_ENODATA,
	FT_ENOSYS,
	FT_ERROR,
	FT_MAX_RESULT
};

static int results[FT_MAX_RESULT];
static char *filename = NULL;
static char *provname = NULL;
static char *testname = NULL;


static int ft_nullstr(char *str)
{
	return (!str || str[0] == '\0');
}

static char *ft_strptr(char *str)
{
	return ft_nullstr(str) ? NULL : str;
}

static char *ft_test_type_str(enum ft_test_type enum_str)
{
	switch (enum_str) {
	case FT_TEST_LATENCY:
		return "latency";
	case FT_TEST_BANDWIDTH:
		return "bandwidth";
	default:
		return "test_unspec";
	}
}

static char *ft_class_func_str(enum ft_class_function enum_str)
{
	switch (enum_str) {
	case FT_FUNC_SEND:
		return "send";
	case FT_FUNC_SENDV:
		return "sendv";
	case FT_FUNC_SENDMSG:
		return "sendmsg";
	case FT_FUNC_INJECT:
		return "inject";
	case FT_FUNC_INJECTDATA:
		return "injectdata";
	default:
		return "func_unspec";
	}
}

static char *ft_wait_obj_str(enum fi_wait_obj enum_str)
{
	switch (enum_str) {
	case FI_WAIT_NONE:
		return "wait_none";
	case FI_WAIT_UNSPEC:
		return "wait_unspec";
	case FI_WAIT_SET:
		return "wait_set";
	case FI_WAIT_FD:
		return "wait_fd";
	case FI_WAIT_MUTEX_COND:
		return "wait_mutex_cond";
	default:
		return "";
	}
}

static void ft_show_test_info(void)
{
	printf("[%s,", test_info.prov_name);
	printf(" %s,", ft_test_type_str(test_info.test_type));
	printf(" %s,", ft_class_func_str(test_info.class_function));
	printf(" %s,", fi_tostr(&test_info.ep_type, FI_TYPE_EP_TYPE));
	printf(" %s,", fi_tostr(&test_info.av_type, FI_TYPE_AV_TYPE));
	printf(" eq_%s,", ft_wait_obj_str(test_info.eq_wait_obj));
	printf(" cq_%s,", ft_wait_obj_str(test_info.cq_wait_obj));
	printf(" [%s],", fi_tostr(&test_info.mode, FI_TYPE_MODE));
	printf(" [%s]]\n", fi_tostr(&test_info.caps, FI_TYPE_CAPS));
}

static int ft_check_info(struct fi_info *hints, struct fi_info *info)
{
	if (info->mode & ~hints->mode) {
		fprintf(stderr, "fi_getinfo unsupported mode returned\n");
		return -FI_EINVAL;
	}
	if (hints->caps != (hints->caps & info->caps)) {
		fprintf(stderr, "fi_getinfo missing caps\n");
		return -FI_EINVAL;
	}

	return 0;
}

static void ft_fw_convert_info(struct fi_info *info, struct ft_info *test_info)
{
	info->caps = test_info->caps;
	info->mode = test_info->mode;

	info->domain_attr->av_type = test_info->av_type;

	info->ep_attr->type = test_info->ep_type;
	info->ep_attr->protocol = test_info->protocol;
	info->ep_attr->protocol_version = test_info->protocol_version;

	if (!ft_nullstr(test_info->prov_name)) {
		info->fabric_attr->prov_name = strndup(test_info->prov_name,
					sizeof test_info->prov_name - 1);
	}
	if (!ft_nullstr(test_info->fabric_name)) {
		info->fabric_attr->name = strndup(test_info->fabric_name,
					sizeof test_info->fabric_name - 1);
	}
}

static void
ft_fw_update_info(struct ft_info *test_info, struct fi_info *info, int subindex)
{
	test_info->test_subindex = subindex;

	if (info->ep_attr) {
		test_info->protocol = info->ep_attr->protocol;
		test_info->protocol_version = info->ep_attr->protocol_version;
	}

	if (info->fabric_attr) {
		if (info->fabric_attr->prov_name) {
			strncpy(test_info->prov_name, info->fabric_attr->prov_name,
				sizeof test_info->prov_name - 1);
		}
		if (info->fabric_attr->name) {
			strncpy(test_info->fabric_name, info->fabric_attr->name,
				sizeof test_info->fabric_name - 1);
		}
	}
}

static int ft_fw_result_index(int fi_errno)
{
	switch (fi_errno) {
	case 0:
		return FT_SUCCESS;
	case FI_ENODATA:
		return FT_ENODATA;
	case FI_ENOSYS:
		return FT_ENOSYS;
	default:
		return FT_ERROR;
	}
}

static int ft_fw_server(void)
{
	struct fi_info *hints, *info;
	int ret;


	do {
		ret = ft_sock_recv(sock, &test_info, sizeof test_info);
		if (ret) {
			if (ret == -FI_ENOTCONN)
				ret = 0;
			break;
		}

		test_info.node[sizeof(test_info.node) - 1] = '\0';
		test_info.service[sizeof(test_info.service) - 1] = '\0';
		test_info.prov_name[sizeof(test_info.prov_name) - 1] = '\0';
		test_info.fabric_name[sizeof(test_info.fabric_name) - 1] = '\0';

		hints = fi_allocinfo();
		if (!hints)
			return -FI_ENOMEM;

		ft_fw_convert_info(hints, &test_info);
		printf("Starting test %d-%d: ", test_info.test_index,
			test_info.test_subindex);
		ft_show_test_info();
		ret = fi_getinfo(FT_FIVERSION, ft_strptr(test_info.node),
				 ft_strptr(test_info.service), FI_SOURCE,
				 hints, &info);
		if (ret) {
			FT_PRINTERR("fi_getinfo", ret);
		} else {
			if (info->next) {
				printf("fi_getinfo returned multiple matches\n");
				ret = -FI_E2BIG;
			} else {
				/* fabric_info is replaced when connecting */
				fabric_info = info;

				ret = ft_run_test();

				if (fabric_info != info)
					fi_freeinfo(fabric_info);
				fabric_info = NULL;
			}
			fi_freeinfo(info);
		}

		if (ret) {
			FT_PRINTERR("ft_fw_server", ret);
			printf("Node: %s\nService: %s\n",
				test_info.node, test_info.service);
			printf("%s\n", fi_tostr(hints, FI_TYPE_INFO));
		}
		fi_freeinfo(hints);

		printf("Ending test %d-%d, result: %s\n", test_info.test_index,
			test_info.test_subindex, fi_strerror(-ret));
		results[ft_fw_result_index(-ret)]++;
		ret = ft_sock_send(sock, &ret, sizeof ret);
		if (ret)
			FT_PRINTERR("ft_sock_send", ret);
	} while (!ret);

	return ret;
}

static int ft_fw_process_list(struct fi_info *hints, struct fi_info *info)
{
	int ret, subindex, result, sresult;

	for (subindex = 1, fabric_info = info; fabric_info;
	     fabric_info = fabric_info->next, subindex++) {

		printf("Starting test %d-%d: ", series->test_index, subindex);
		ft_show_test_info();
		ret = ft_check_info(hints, fabric_info);
		if (ret)
			return ret;

		ft_fw_update_info(&test_info, fabric_info, subindex);
		ret = ft_sock_send(sock, &test_info, sizeof test_info);
		if (ret) {
			FT_PRINTERR("ft_sock_send", ret);
			return ret;
		}

		result = ft_run_test();

		ret = ft_sock_recv(sock, &sresult, sizeof sresult);
		if (result) {
			FT_PRINTERR("ft_run_test", result);
			return result;
		}
		else if (ret) {
			FT_PRINTERR("ft_sock_recv", ret);
			return ret;
		}
		else if (sresult)
			return sresult;
	}

	return 0;
}

static int ft_fw_client(void)
{
	struct fi_info *hints, *info;
	int ret;

	hints = fi_allocinfo();
	if (!hints)
		return -FI_ENOMEM;

	for (fts_start(series, test_start_index);
	     !fts_end(series, test_end_index);
	     fts_next(series)) {

		fts_cur_info(series, &test_info);
		ft_fw_convert_info(hints, &test_info);

		ret = ft_getsrcaddr(opts.src_addr, opts.src_port, hints);
		if (ret)
			return ret;

		printf("Starting test %d / %d\n", test_info.test_index, series->test_count);
		ret = fi_getinfo(FT_FIVERSION, ft_strptr(test_info.node),
				 ft_strptr(test_info.service), 0, hints, &info);
		if (ret) {
			FT_PRINTERR("fi_getinfo", ret);
		} else {
			ret = ft_fw_process_list(hints, info);
			fi_freeinfo(info);
		}

		if (ret) {
			FT_PRINTERR("ft_fw_process_list", ret);
			fprintf(stderr, "Node: %s\nService: %s \n",
				test_info.node, test_info.service);
			fprintf(stderr, "%s\n", fi_tostr(hints, FI_TYPE_INFO));
		}

		printf("Ending test %d / %d, result: %s\n",
			test_info.test_index, series->test_count, fi_strerror(-ret));
		results[ft_fw_result_index(-ret)]++;
	}

	fi_freeinfo(hints);
	return 0;
}

static void ft_fw_show_results(void)
{
	printf("Success: %d\n", results[FT_SUCCESS]);
	printf("ENODATA: %d\n", results[FT_ENODATA]);
	printf("ENOSYS : %d\n", results[FT_ENOSYS]);
	printf("ERROR  : %d\n", results[FT_ERROR]);
}

static void ft_fw_usage(char *program)
{
	fprintf(stderr, "Usage:\n");
	fprintf(stderr, "  %s [OPTIONS] \t\t\tstart server\n", program);
	fprintf(stderr, "  %s [OPTIONS] <server_node> \tconnect to server\n", program);
	fprintf(stderr, "\nOptions:\n");
	FT_PRINT_OPTS_USAGE("-q <service_port>", "Management port for test");
	FT_PRINT_OPTS_USAGE("-h", "display this help output");
	fprintf(stderr, "\nServer only options:\n");
	FT_PRINT_OPTS_USAGE("-x", "exit after test run");
	fprintf(stderr, "\nClient only options:\n");
	FT_PRINT_OPTS_USAGE("-u <test_config_file>", "config file path (Either config file path or both provider and test config name are required)");
	FT_PRINT_OPTS_USAGE("-p <provider_name>", " provider name");
	FT_PRINT_OPTS_USAGE("-t <test_config_name>", "test config name");
	FT_PRINT_OPTS_USAGE("-y <start_test_index>", "");
	FT_PRINT_OPTS_USAGE("-z <end_test_index>", "");
	FT_PRINT_OPTS_USAGE("-s <address>", "source address");
	FT_PRINT_OPTS_USAGE("-B <src_port>", "non default source port number");
	FT_PRINT_OPTS_USAGE("-P <dst_port>", "non default destination port number"
		       " (config file service parameter will override this)");
}

void ft_free()
{
	if (filename)
		free(filename);
	if (testname)
		free(testname);
	if (provname)
		free(provname);
}

int main(int argc, char **argv)
{
	char *service = "2710";
	opts = INIT_OPTS;
	int ret, op;

	while ((op = getopt(argc, argv, "p:u:t:q:xy:z:h" ADDR_OPTS)) != -1) {
		switch (op) {
		case 'u':
			filename = strdup(optarg);
			break;
		case 'p':
			provname = strdup(optarg);
			break;
		case 't':
			testname = strdup(optarg);
			break;
		case 'q':
			service = optarg;
			break;
		case 'x':
			persistent = 0;
			break;
		case 'y':
			test_start_index = atoi(optarg);
			break;
		case 'z':
			test_end_index = atoi(optarg);
			break;
		default:
			ft_parse_addr_opts(op, optarg, &opts);
			break;
		case '?':
		case 'h':
			ft_fw_usage(argv[0]);
			ft_free();
			exit(1);
		}
	}

	if (optind < argc - 1) {
		ft_fw_usage(argv[0]);
		ft_free();
		exit(1);
	}

	opts.dst_addr = (optind == argc - 1) ? argv[optind] : NULL;

	if (opts.dst_addr) {
		if (!opts.dst_port)
			opts.dst_port = default_port;
		if (!filename) {
			if (!testname || !provname) {
				ft_fw_usage(argv[0]);
				ft_free();
				exit(1);
			} else {
				ret = asprintf(&filename, "%s/test_configs/%s/%s.test",
					CONFIG_PATH, provname, testname);
				if (ret == -1) {
					fprintf(stderr, "asprintf failed!\n");
					ft_free();
					exit(1);
				}
			}
		} else {
			testname = NULL;
			provname = NULL;
		}
		series = fts_load(filename);
		if (!series) {
			ft_free();
			exit(1);
		}

		ret = ft_sock_connect(opts.dst_addr, service);
		if (ret)
			goto out;

		ret = ft_fw_client();
		if (ret)
			FT_PRINTERR("ft_fw_client", ret);
		ft_sock_shutdown(sock);
	} else {
		ret = ft_sock_listen(service);
		if (ret)
			goto out;

		do {
			ret = ft_sock_accept();
			if (ret)
				goto out;

			ret = ft_fw_server();
			if (ret)
				FT_PRINTERR("ft_fw_server", ret);
			ft_sock_shutdown(sock);
		} while (persistent);
	}

	ft_fw_show_results();
out:
	if (opts.dst_addr)
		fts_close(series);
	ft_free();
	return ret;
}
