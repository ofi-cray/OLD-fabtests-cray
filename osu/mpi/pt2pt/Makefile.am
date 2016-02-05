
pt2ptdir = $(pkglibexecdir)/mpi/pt2pt
bin_PROGRAMS = osu_bibw \
	       osu_bw \
	       osu_latency \
	       osu_mbw_mr \
	       osu_multi_lat

osu_bw_SOURCES = osu_bw.c osu_pt2pt.c osu_pt2pt.h
osu_bibw_SOURCES = osu_bibw.c osu_pt2pt.c osu_pt2pt.h
osu_latency_SOURCES = osu_latency.c osu_pt2pt.c osu_pt2pt.h
osu_multi_lat_SOURCES = osu_multi_lat.c osu_pt2pt.c osu_pt2pt.h
osu_latency_mt_SOURCES = osu_latency_mt.c osu_pt2pt.c osu_pt2pt.h

if MPI2_LIBRARY
    bin_PROGRAMS += osu_latency_mt
endif

