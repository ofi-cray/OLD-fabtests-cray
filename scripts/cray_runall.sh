#!/bin/bash
#
# Copyright (c) 2015 Cray Inc.  All rights reserved.
# Copyright (c) 2015 Los Alamos National Security, LLC. All rights reserved.
#
# This software is available to you under a choice of one of two
# licenses.  You may choose to be licensed under the terms of the GNU
# General Public License (GPL) Version 2, available from the file
# COPYING in the main directory of this source tree, or the
# BSD license below:
#
#     Redistribution and use in source and binary forms, with or
#     without modification, are permitted provided that the following
#     conditions are met:
#
#      - Redistributions of source code must retain the above
#        copyright notice, this list of conditions and the following
#        disclaimer.
#
#      - Redistributions in binary form must reproduce the above
#        copyright notice, this list of conditions and the following
#        disclaimer in the documentation and/or other materials
#        provided with the distribution.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AWV
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
# BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
# ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

#
# globals:
#   provider to use for client/server "simple" tests
script_path=$(dirname "$0")
run_client_server=$script_path/run_client_server.py
run_local_cs=$script_path/run_local_cs.sh
expected_failures=$script_path/cray_runall_expected_failures
intermittent_failures=$script_path/cray_runall_intermittent_failures

usage() {
    ec=$1
    echo "cray_runall.sh [-d <dir>]"
    echo "   -d location of libfabric tests"
    exit $ec
}

my_exit() {
    # check for expected or intermittent failures
    expected=`awk '{ if ($1!="#") print $0 }' < $expected_failures`
    intermittent=`awk '{ if ($1!="#") print $0 }' < $intermittent_failures`
    # replace control characters with spaces
    expected=${expected//[[:cntrl:]]/ }
    intermittent=${intermittent//[[:cntrl:]]/ }
    fail_unexpected=0
    echo ""
    echo "Total tests run: "$total_tests
    echo "Tests passed: "$tests_passed
    echo "Tests failed: "$tests_failed
    echo ""
    if test $tests_failed -ne 0 ; then
	echo "Failing tests are:"
	for ftest in ${failed_tests[@]}; do
	    expr="$ftest[[:blank:]]"
	    lexpr="$ftest$"
	    if [[ "$expected" =~ $expr ]]; then
		echo "* $ftest (EXPECTED)"
		junk=$((tests_failed--))
		expected=${expected//$expr/}
	    elif [[ "$expected" =~ $lexpr ]]; then
		echo "* $ftest (EXPECTED)"
		junk=$((tests_failed--))
		expected=${expected%%$ftest}
	    elif [[ "$intermittent" =~ $expr ]] || [[ "$intermittent" =~ $lexpr ]]; then
		echo "* $ftest (INTERMITTENT)"
		junk=$((tests_failed--))
	    else
		echo "* $ftest"
		junk=$((fail_unexpected++))
	    fi
	done
    fi
    echo "Number of unexepected failures: "$fail_unexpected

    if test $total_skipped -ne 0 ; then
	echo ""
	echo "Skipped tests are:"
	for stest in ${skipped_tests[@]}; do
	    expr="$stest[[:blank:]]"
	    lexpr="$stest$"
	    echo "* $stest"
	    if [[ "$expected" =~ $expr ]]; then
		expected=${expected//$expr/}
	    elif [[ "$expected" =~ $lexpr ]]; then
		expected=${expected%%$stest}
	    fi
	done
	echo "Number skipped: "$total_skipped
    fi
    
    fail_expected=${expected//[[:blank:]]/}
    if [[ "$fail_expected" != "" ]]; then
	echo ""
	echo "The following tests were expected to fail, but passed:"
	for t in $expected; do
	    echo "* $t"
	    junk=$((tests_failed++))
	done
    fi

    exit $tests_failed
}

run_test() {
    test=$1
    echo Running $test
    if [ ! -x $testdir/$test ]; then
	echo "$test does not exist..  Skipping."
	junk=$((total_skipped++))
	skipped_tests=("${skipped_tests[@]}" $test)
	continue
    fi
    junk=$((total_tests++))
    $run_client_server $testdir/$test -f gni --launcher $launcher $2
    if [ $? != 0 ] ; then
	junk=$((tests_failed++))
	failed_tests=("${failed_tests[@]}" $test)
    else
	junk=$((tests_passed++))
    fi
    sleep 1
}

run_local_cs_test() {
    test=$1
    args="$2"
    echo Running $test
    if [ ! -x $testdir/$test ]; then
	echo "$test does not exist..  Skipping."
	junk=$((total_skipped++))
	skipped_tests=("${skipped_tests[@]}" $test)
	continue
    fi
    junk=$((total_tests++))
    $cs_launch_cmd $run_local_cs $testdir/$test "$args"
    if [ $? != 0 ] ; then
	junk=$((tests_failed++))
	failed_tests=("${failed_tests[@]}" $test)
    else
	junk=$((tests_passed++))
    fi
    sleep 1
}

tests_failed=0
tests_passed=0
testdir=${PWD}
declare -a failed_tests=()
declare -a skipped_tests=()

if [ $# -gt 0 ] ; then
  while getopts "d:h" option; do
    case $option in
      d) testdir=$OPTARG;;
      h) usage 0 ;;
      *) usage 1;;
    esac
  done
  shift $(($OPTIND-1))
fi

nprocs=1

#
# Check for srun or aprun
#
srun=`command -v srun`
if [ $? == 0 ]; then
    launcher="srun"
    cs_launch_cmd="srun -n1 --exclusive"
else
    aprun=`command -v aprun`
    if [ $? == 0 ]; then
        launcher="aprun"
        cs_launch_cmd="aprun -n1"
    else
        echo "Cannot find a supported job launcher (srun, aprun).  Please load the appropriate module"
        exit -1
    fi
fi

total_tests=0
total_skipped=0

# TODO: Figure out how to run these tests OR how to inject the
#       launcher script into runfabtests.sh

# unit=( \
#     fi_av_test \

# simple=( \
#     fi_cq_data \
#     fi_dgram \
#     fi_dgram_waitset \
#     fi_msg \
#     fi_msg_epoll \
#     fi_poll \
#     fi_rdm \
#     fi_rdm_rma_simple \
#     fi_rdm_shared_ctx \
#     fi_rdm_tagged_peek \
#     fi_scalable_ep )

# streaming=( \
#     fi_msg_rma \
#     fi_rdm_atomic \
#     fi_rdm_multi_recv \
#     fi_rdm_rma )

# ported=( \
#     fi_cmatose \
#     fi_rc_pingpong )

# complex=( \
#     fi_ubertest )

# all_tests="${unit[@]} ${simple[@]} ${pingpong[@]} ${streaming[@]} ${ported[@]} ${complex[@]}"

no_server=( \
    fi_av_test2 \
    fi_dom_test \
    fi_ep_test \
    fi_eq_test \
    fi_multi_dom_test \
    fi_size_left_test )

for test in ${no_server[@]}; do
    run_test "$test" "--no-server"
done

two_nodes=( \
     rdm_bw \
     rdm_latency \
     rdm_mbw_mr )

for test in ${two_nodes[@]}; do
    run_test "$test" "--no-server --nnodes=2"
done

two_nodes_threaded=( \
     rdm_bw_threaded \
     rdm_latency_threaded )

for test in ${two_nodes_threaded[@]} ; do
    for t in 1 2 4 8 12 16 24; do
	run_test "$test" "--no-server --nnodes=2 --nthreads=$t --client-args=-t$t"
    done
done

pingpong=( \
     fi_msg_pingpong \
     fi_rdm_cntr_pingpong \
     fi_rdm_inject_pingpong \
     fi_rdm_pingpong \
     fi_rdm_tagged_pingpong \
     fi_ud_pingpong )

# -I: iterations
PINGPONG_ARGS="-I 100"
PROV=gni

for test in ${pingpong[@]}; do
    run_local_cs_test $test "-f $PROV $PINGPONG_ARGS"
done

my_exit
