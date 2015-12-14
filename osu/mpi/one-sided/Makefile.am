one_sideddir = $(pkglibexecdir)/mpi/one-sided
bin_PROGRAMS = osu_acc_latency osu_get_bw osu_get_latency osu_put_bibw osu_put_bw osu_put_latency

if MPI3_LIBRARY
    bin_PROGRAMS += osu_get_acc_latency osu_fop_latency osu_cas_latency
endif

osu_put_latency_SOURCES = osu_put_latency.c osu_1sc.c osu_1sc.h
osu_put_bw_SOURCES = osu_put_bw.c osu_1sc.c osu_1sc.h
osu_put_bibw_SOURCES = osu_put_bibw.c osu_1sc.c osu_1sc.h
osu_get_latency_SOURCES = osu_get_latency.c osu_1sc.c osu_1sc.h
osu_get_bw_SOURCES = osu_get_bw.c osu_1sc.c osu_1sc.h
osu_acc_latency_SOURCES = osu_acc_latency.c osu_1sc.c osu_1sc.h
osu_fop_latency_SOURCES = osu_fop_latency.c osu_1sc.c osu_1sc.h
osu_cas_latency_SOURCES = osu_cas_latency.c osu_1sc.c osu_1sc.h
