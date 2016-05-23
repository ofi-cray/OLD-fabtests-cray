#!/usr/bin/env python
#
# Copyright (c) 2015 Cray Inc.  All rights reserved.
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
# This script runs a fabtest client and server instance of the given
# test program.
#
# ASSUMPTIONS:
# - Client and server are invoked in the exact same way except that the
#   client takes a final argument that is the server address
#
import argparse, subprocess
import sys, socket
import os, select, fcntl, time # for timeout stuff
from signal import SIGALRM

class fabtest:
    def __init__(self, _name, _fabric, _timeout, _args=None, _nnodes='1', _ntasks='-1', _nthreads='-1', _launcher=None, _server_addr=None, _nodelist=None, _cpu_bind=''):
        self.name = _name
        self.fabric = _fabric
        self.args = _args
        self.nnodes = _nnodes
        self.ntasks = _ntasks
        self.nthreads = _nthreads
        self.timeout = _timeout
        self.launcher = _launcher
        self.server_addr = _server_addr
        self.nodelist = _nodelist
        self.cpu_bind = _cpu_bind

    def start(self):
        cmd = list()
        if self.launcher == 'srun':
            cmd += ['srun', '-N'+self.nnodes, '--exclusive', '-t'+self.formattedTimeout()]
            if self.ntasks != '-1':
                cmd += [ '-n'+self.ntasks ]
            else:
                cmd += [ '--ntasks-per-node=1' ]
            if self.nthreads != '-1':
                cmd += [ '-c'+self.nthreads ]
            if self.nodelist != None:
                cmd += [ '-w'+self.nodelist ]
            if self.cpu_bind != '-1':
                cmd += [ '--cpu_bind='+self.cpu_bind ]
        elif self.launcher == 'aprun':
            cmd += ['aprun', '-n'+self.nnodes, '-t'+str(self.timeout)]
            if self.ntasks != '-1':
                cmd += [ '-N'+self.ntasks ]
            else:
                cmd += [ '-N1' ]
            if self.nthreads != '-1':
                cmd += [ '-d'+self.nthreads ]
            if self.nodelist != None:
                cmd += [ '-L'+self.nodelist ]
        cmd += [self.name, '-f', self.fabric]
        if self.args != None:
            cmd += self.args.split()
        if self.server_addr == None:
            sys.stdout.write('Starting server: ')
        else:
            if self.server_addr != None:
                cmd += [self.server_addr]
            sys.stdout.write('Starting client: ')
        sys.stdout.write(('%s\n')%(' '.join(cmd)))

        try:
            self.start_time = time.time()
            self.p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            self.end_time = self.start_time+self.timeout
            return 0
        except (OSError, ValueError) as ex:
            sys.stdout.write(('Failed to start: %s\n')%(str(ex)))
            return -1

    def formattedTimeout(self):
        if self.launcher == 'srun':
            return ('%02d:%02d:%02d')%(self.timeout/3600, (self.timeout%3600)/60, self.timeout%60)
        else:
            return str(self.timeout)
            

    #
    # Newer versions of python subprocess support a time out for
    # wait() and functions that call wait(), e.g. communicate().  For
    # now, implement our own.  This version waits on one or more
    # streams, so maybe it's preferable anyways.
    #
    # Don't want to send SIGALRM, as it will may not respond if
    # holding certain locks
    #
    class ReadTimeoutException(Exception):
        def __init__(self, message):
            super(fabtest.ReadTimeoutException, self).__init__(message)
            sys.stdout.write(('%s\n')%(message))

    @staticmethod
    def waitall(plist):
        num_procs = 0
        streams = list()
        no_timeout = list()
        done = list()
        for proc in plist:
            if proc.launcher == None:
                stream = proc.p.stdout
                flags = fcntl.fcntl(stream.fileno(), fcntl.F_GETFL)
                flags |= os.O_NONBLOCK
                fcntl.fcntl(stream.fileno(), fcntl.F_SETFL, flags)
                streams.append(stream)
                done.append(False)
            else:
                streams.append(None)
                no_timeout.append([num_procs, proc])
                done.append(True)
            num_procs += 1
        # output buffers
        buffers = ['']*num_procs
        # just the streams were waiting on
        sstreams = filter(None, streams)
        # not really SIGALRM, but pretend it is
        retvals = [-SIGALRM]*num_procs
        max_end_time = max(p.end_time for p in plist)
        try:
            while sum(d for d in done) != num_procs:
                now = time.time()
                ready_set = select.select(sstreams, [], [], max(0, max_end_time-now))[0]
                for i in range(num_procs):
                    if streams[i] == None:
                        continue
                    if streams[i] in ready_set:
                        bytes = streams[i].read()
                        if len(bytes) == 0:
                            done[i] = True
                            retvals[i] = plist[i].p.wait()
                            continue
                        buffers[i] += bytes
                    if plist[i].end_time <= now:
                        raise fabtest.ReadTimeoutException('Timeout: process '+str(i))
        except fabtest.ReadTimeoutException:
            for proc in plist:
                try:
                    proc.p.kill()
                except:
                    pass

        # Now wait for procs who's timeout is enforced by the launcher
        for p in no_timeout:
            i = p[0]
            buffers[i] += p[1].p.communicate()[0]
            retvals[i] = p[1].p.returncode

        # Note that if one of the processes exits with failure early
        # on, we still wait the entire timeout duration.

        return (retvals, buffers)
        


def _main():
    parser = argparse.ArgumentParser(description='Run a client-server fabtest.')
    parser.add_argument('test', metavar='test', type=str);
    parser.add_argument('-f', '--fabric', dest='fabric', action='store', default='sockets', choices=['gni', 'psm', 'usnic', 'sockets'], help='Network fabric')
    # TODO: ssh to other hosts
    # parser.add_argument('--local-server', dest='local_server', action='store_true', default=True, help='Run the server locally')
    # parser.add_argument('--local-client', dest='local_client', action='store_true', default=True, help='Run the client locally')
    parser.add_argument('--launcher', dest='launcher', default=None, choices=['aprun', 'srun', None], help='Launcher mechnism')
    parser.add_argument('--nnodes', dest='nnodes', default='1', help='Number of hardware threads per node')
    parser.add_argument('--ntasks', dest='ntasks', default='-1', help='Number of tasks')
    parser.add_argument('--nthreads', dest='nthreads', default='-1', help='Number of client nodes')
    # TODO: for ssh version
    # parser.add_argument('-c', '--client-addr', metavar='addr', dest='client_addr', default=None, help='Client address')
    parser.add_argument('--client-args', metavar='args', dest='client_args', action='store', default=None, help='Client args')
    parser.add_argument('-s', '--server-addr', metavar='addr', dest='server_addr', action='store', default=None, help='Server address')
    parser.add_argument('--server-args', metavar='args', dest='server_args', action='store', default=None, help='Server args')
    parser.add_argument('--no-server', dest='run_server', default=True, action='store_false', help='Do not run a server')
    parser.add_argument('-t', '--timeout', dest='timeout', action='store', type=int, default=60, help='timeout')
    parser.add_argument('--nodelist', dest='nodelist', default=None, help='List of nodes to execute on')
    parser.add_argument('--cpu_bind', dest='cpubind', default='-1', help='CPU binding option')

    args = parser.parse_args()

    ret = 0
    testname = args.test
    fabric = args.fabric
    # local_server = args.local_server
    # local_client = args.local_client
    launcher = args.launcher
    nnodes = args.nnodes
    ntasks = args.ntasks
    nthreads = args.nthreads
    # client_addr = args.client_addr
    client_args = args.client_args
    server_addr = args.server_addr
    server_args = args.server_args
    run_server = args.run_server
    timeout = args.timeout
    nodelist = args.nodelist
    cpubind = args.cpubind

    waitlist = list();
    if run_server:
        server = fabtest(testname, fabric, timeout, server_args)
        if server.start() != 0:
            sys.stdout.write('Server failed to start.\n')
            return -1
        waitlist.append(server)

        if server_addr == None:
            server_addr = socket.gethostbyname(socket.gethostname())

    client = fabtest(testname, fabric, timeout, client_args, nnodes, ntasks, nthreads, launcher, server_addr, nodelist, cpubind)
    if client.start() != 0:
        sys.stdout.write('Client failed to start.\n')
        return -1
    waitlist.append(client)

    # Possibly give option to save these to a file for diff'ing
    (retvals, output) = fabtest.waitall(waitlist)
    for i,retval in enumerate(retvals):
        if retval != 0:
            ret = -1
        sys.stdout.write(('\nProcess %d return value: %d\n=== OUTPUT ===\n')%(i, retval))
        sys.stdout.write(output[i])
        sys.stdout.write('===\n')

    return ret

if __name__ == '__main__':
    sys.exit(_main())

