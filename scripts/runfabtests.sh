#!/bin/bash

trap cleanup_and_exit SIGINT

#
# Default behavior with no args will use sockets provider with loopback
#
declare BIN_PATH
declare PROV="sockets"
declare TEST_TYPE="quick"
declare SERVER="127.0.0.1"
declare SSH_SERVER="eval"
declare CLIENT="127.0.0.1"
declare SSH_CLIENT="eval"
declare EXCLUDE
declare GOOD_ADDR="192.168.10.1"
declare -i VERBOSE=0
declare TEST_OUTPUT=0
declare CLUSTER=0
declare CLUSTER_LAUNCH_CMD="srun -n1 --exclusive"
declare CLUSTER_LAUNCH_SCRIPT="run_local_cs.sh"

# base ssh,  "short" and "long" timeout variants:
declare -r bssh="ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=2 -o BatchMode=yes"
if [ -z "$(which timeout 2> /dev/null)" ]; then
	# forego timeout
	declare -r sssh="${bssh}"
	declare -r lssh="${bssh}"
else
	declare -r sssh="timeout 60s ${bssh}"
	declare -r lssh="timeout 90s ${bssh}"# else
fi
declare ssh=${sssh}

declare -r c_outp=$(mktemp fabtests.c_outp.XXXXXX)
declare -r s_outp=$(mktemp fabtests.s_outp.XXXXXX)

declare -i skip_count=0
declare -i pass_count=0
declare -i fail_count=0

simple_tests=(
	"cq_data"
	"dgram"
	"dgram_waitset"
	"msg"
	"msg_epoll"
	"msg_sockets -s CLIENT_ADDR"
	"poll"
	"rdm"
	"rdm_rma_simple"
	"rdm_rma_trigger"
	"rdm_shared_ctx"
	"rdm_tagged_peek"
	"scalable_ep"
	"cmatose"
)

short_tests=(
	"msg_pingpong -I 5"
	"msg_rma -o write -I 5"
	"msg_rma -o read -I 5"
	"msg_rma -o writedata -I 5"
	"rdm_atomic -I 5 -o all"
	"rdm_cntr_pingpong -I 5"
	"rdm_inject_pingpong -I 5"
	"rdm_multi_recv -I 5"
	"rdm_pingpong -I 5"
	"rdm_rma -o write -I 5"
	"rdm_rma -o read -I 5"
	"rdm_rma -o writedata -I 5"
	"rdm_tagged_pingpong -I 5"
	"ud_pingpong -I 5"
	"rc_pingpong -n 5"
)

standard_tests=(
	"msg_pingpong"
	"msg_pingpong -v"
	"msg_pingpong -P"
	"msg_pingpong -P -v"
	"msg_rma -o write"
	"msg_rma -o read"
	"msg_rma -o writedata"
	"rdm_atomic -o all -I 10000"
	"rdm_cntr_pingpong"
	"rdm_inject_pingpong"
	"rdm_multi_recv"
	"rdm_pingpong"
	"rdm_pingpong -v"
	"rdm_pingpong -P"
	"rdm_pingpong -P -v"
	"rdm_rma -o write"
	"rdm_rma -o read"
	"rdm_rma -o writedata"
	"rdm_tagged_pingpong"
	"ud_pingpong"
	"ud_pingpong -v"
	"ud_pingpong -P"
	"ud_pingpong -P -v"
	"rc_pingpong"
)

unit_tests=(
	"av_test -d GOOD_ADDR -n 1 -s SERVER_ADDR"
	"dom_test -n 2"
	"eq_test"
	"size_left_test"
)

function errcho() {
	>&2 echo $*
}

function print_border {
	echo "# --------------------------------------------------------------"
}

function print_results {
	local test_name=$1
	local test_result=$2
	local test_time=$3
	local server_out_file=$4
	local client_out_file=$5

	if [ $VERBOSE -eq 0 ] ; then
		# print a simple, single-line format that is still valid YAML
		printf "%-50s%10s\n" "$test_exe:" "$test_result"
	else
		# Print a more detailed YAML format that is not a superset of
		# the non-verbose output.  See ofiwg/fabtests#259 for a
		# rationale.
		emit_stdout=0
		case $test_result in
			Pass)
				[ $VERBOSE -ge 3 ] && emit_stdout=1
				;;
			Notrun)
				[ $VERBOSE -ge 2 ] && emit_stdout=1
				;;
			Fail)
				[ $VERBOSE -ge 1 ] && emit_stdout=1
				;;
		esac

		printf -- "- name:   %s\n" "$test_exe"
		printf -- "  result: %s\n" "$test_result"
		printf -- "  time:   %s\n" "$test_time"
		if [ $emit_stdout -eq 1 -a "$server_out_file" != "" ] ; then
			printf -- "  server_stdout: |\n"
			sed -e 's/^/    /' < $server_out_file
			if [ -n "$client_out_file" ] ; then
				printf -- "  client_stdout: |\n"
				sed -e 's/^/    /' < $client_out_file
			fi
		fi
	fi
}

function cleanup {
	${SSH_CLIENT} "ps -eo comm,pid | grep '^fi_' | awk '{print \$2}' | xargs kill -9" >& /dev/null
	${SSH_SERVER} "ps -eo comm,pid | grep '^fi_' | awk '{print \$2}' | xargs kill -9" >& /dev/null
	rm -f $c_outp $s_outp
}

function cleanup_and_exit {
	cleanup
	exit 1
}

# compute the duration in seconds between two floating point seconds values
# measured since the start of the UNIX epoch and print the result to stdout
function compute_duration {
	local s=$1
	local e=$2

	# just use perl, bc is fragile and forgets to include leading 0s when
	# numbers are <1.0
	perl -e "printf \"%.6f\n\", ($e - $s)"
}

function is_excluded {
	for i in $(echo "$EXCLUDE" | tr -s "," " "); do
		if [[ "$i" = "$1" ]]; then
			echo 1
			return
		fi
	done

	echo 0
}

function unit_test {
	local test=$1
	local ret1=0
	local test_exe=$(echo "fi_${test} -f $PROV" | \
	    sed -e "s/GOOD_ADDR/$GOOD_ADDR/g" \
	        -e "s/SERVER_ADDR/${SERVER}/g" \
	        -e "s/CLIENT_ADDR/${CLIENT}/g")
	local start_time
	local end_time
	local test_time

	local e=$(is_excluded $(echo "fi_${test}" | cut -d " " -f 1))
	if [ $e -eq 1 ]; then
		print_results "$test_exe" "Notrun" "0" "" ""
		skip_count+=1
		return
	fi

	start_time=$(date '+%s')

	${LAUNCH_CMD} ${BIN_PATH} "${test_exe}" &> $s_outp &
	p1=$!

	wait $p1
	ret1=$?

	end_time=$(date '+%s')
	test_time=$(compute_duration "$start_time" "$end_time")

	if [ $TEST_OUTPUT -ne 0 ]; then
		cat $s_outp
	fi

	if [ $ret1 -eq 61 ]; then
		print_results "$test_exe" "Notrun" "$test_time" "$s_outp"
		skip_count+=1
	elif [ $ret1 -ne 0 ]; then
		print_results "$test_exe" "Fail" "$test_time" "$s_outp"
		if [ $ret1 -eq 124 ]; then
			cleanup
		fi
		fail_count+=1
	else
		print_results "$test_exe" "Pass" "$test_time" "$s_outp"
		pass_count+=1
	fi
}

function run_unit_test {
	if [ $CLUSTER -eq 0 ]; then
		LAUNCH_CMD="${SSH_SERVER}"
	else
		LAUNCH_CMD="$CLUSTER_LAUNCH_CMD $CLUSTER_LAUNCH_SCRIPT 0"
	fi
	unit_test "$1"
}

function cs_test {
	local test=$1
	local ret1=0
	local ret2=0
	local test_exe=$(echo "fi_${test} -f $PROV" | \
	    sed -e "s/CLIENT_ADDR/${CLIENT}/g")
	local start_time
	local end_time
	local test_time

	local e=$(is_excluded $(echo "fi_${test}" | cut -d " " -f 1))
	if [ $e -eq 1 ]; then
		print_results "$test_exe" "Notrun" "0" "" ""
		skip_count+=1
		return
	fi

	start_time=$(date '+%s')

	${SSH_SERVER} ${BIN_PATH} "${test_exe} -s $SERVER" &> $s_outp &
	p1=$!
	sleep 1s

	${SSH_CLIENT} ${BIN_PATH} "${test_exe} $SERVER" &> $c_outp &
	p2=$!

	wait $p1
	ret1=$?

	wait $p2
	ret2=$?

	end_time=$(date '+%s')
	test_time=$(compute_duration "$start_time" "$end_time")

	if [ $TEST_OUTPUT -ne 0 ]; then
		cat $s_outp
		cat $c_outp
	fi

	if [ $ret1 -eq 61 -a $ret2 -eq 61 ]; then
		print_results "$test_exe" "Notrun" "$test_time" "$s_outp" "$c_outp"
		skip_count+=1
	elif [ $ret1 -ne 0 -o $ret2 -ne 0 ]; then
		print_results "$test_exe" "Fail" "$test_time" "$s_outp" "$c_outp"
		if [ $ret1 -eq 124 -o $ret2 -eq 124 ]; then
			cleanup
		fi
		fail_count+=1
	else
		print_results "$test_exe" "Pass" "$test_time" "$s_outp" "$c_outp"
		pass_count+=1
	fi
}

function run_cs_test {
	if [ $CLUSTER -eq 0 ]; then
		cs_test "$1"
	else
		LAUNCH_CMD="$CLUSTER_LAUNCH_CMD $CLUSTER_LAUNCH_SCRIPT 1"
		unit_test "$1"
	fi
}

function main {
	if [[ $1 == "quick" ]]; then
		local -r tests="unit simple short"
	else
		local -r tests=$(echo $1 | sed 's/all/unit,simple,standard/g' | tr ',' ' ')
	fi

	if [ $VERBOSE -eq 0 ] ; then
		printf "# %-50s%10s\n" "Test" "Result"
		print_border
	fi

	for ts in ${tests}; do
	ssh=${sssh}
	case ${ts} in
		unit)
			for test in "${unit_tests[@]}"; do
				run_unit_test "$test"
			done
		;;
		simple)
			for test in "${simple_tests[@]}"; do
				run_cs_test "$test"
			done
		;;
		short)
			for test in "${short_tests[@]}"; do
				run_cs_test "$test"
			done
		;;
		standard)
			ssh=${lssh}
			for test in "${standard_tests[@]}"; do
				run_cs_test "$test"
			done
		;;
		*)
			errcho "Unknown test set: ${ts}"
			exit 1
		;;
	esac
	done

	total=$(( $pass_count + $fail_count ))

	print_border

	printf "# %-50s%10d\n" "Total Pass" $pass_count
	printf "# %-50s%10d\n" "Total Notrun" $skip_count
	printf "# %-50s%10d\n" "Total Fail" $fail_count

	if [[ "$total" > "0" ]]; then
		printf "# %-50s%10d\n" "Percentage of Pass" $(( $pass_count * 100 / $total ))
	fi

	print_border

	cleanup
	exit $fail_count
}

function usage {
	errcho "Usage:"
	errcho "  $0 [OPTIONS] [provider] [host] [client]"
	errcho
	errcho "Run fabtests using provider between host and client (default"
	errcho "'sockets' provider in loopback-mode).  Report pass/fail/notrun status."
	errcho
	errcho "Options:"
	errcho -e " -g\tgood IP address from <host>'s perspective (default $GOOD_ADDR)"
	errcho -e " -v\tprint output of failing"
	errcho -e " -vv\tprint output of failing/notrun"
	errcho -e " -vvv\tprint output of failing/notrun/passing"
	errcho -e " -t\ttest set(s): all,quick,unit,simple,standard,short (default quick)"
	errcho -e " -e\texclude tests: cq_data,dgram_dgram_waitset,..."
	errcho -e " -p\tpath to test bins (default PATH)"
	exit 1
}

while getopts ":vt:p:g:e:l:co" opt; do
case ${opt} in
	t) TEST_TYPE=$OPTARG
	;;
	v) VERBOSE+=1
	;;
	p) BIN_PATH="PATH=${OPTARG}:${PATH}"
	;;
	g) GOOD_ADDR=${OPTARG}
	;;
	e) EXCLUDE=${OPTARG}
	;;
	l) CLUSTER_LAUNCH_CMD=${OPTARG}
	;;
	c) CLUSTER=1; CLIENT="LOCAL_IP_ADDR"; SERVER="LOCAL_IP_ADDR"
	;;
	o) TEST_OUTPUT=1
	;;
	:|\?) usage
	;;
esac

done

# shift past options
shift $((OPTIND-1))

if [[ $# -ge 4 ]]; then
	usage
fi

if [[ $# -ge 1 ]]; then
	PROV=$1
fi

if [ $CLUSTER -eq 0 ]; then
	if [[ $# -ge 2 ]]; then
		SERVER=$2
		SSH_SERVER="${ssh} ${SERVER}"
	fi

	if [[ $# -ge 3 ]]; then
		CLIENT=$3
		SSH_CLIENT="${ssh} ${CLIENT}"
	fi
fi

main ${TEST_TYPE}
