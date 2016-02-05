dnl Configury specific to osu tests

AC_DEFUN([OSU_CONFIGURE],
         [

AC_CHECK_PROG([MPICC],[mpicc],[mpicc])

# Checks for libraries.
AC_SEARCH_LIBS([sqrt], [m])
AC_SEARCH_LIBS([pthread_create], [pthread])

# Checks for header files.
AC_CHECK_HEADERS([stdlib.h string.h sys/time.h unistd.h])

# Checks for typedefs, structures, and compiler characteristics.
AC_C_INLINE

# Checks for library functions.
AC_CHECK_FUNCS([getpagesize gettimeofday memset sqrt])
AC_CHECK_FUNC([MPI_Init], [mpi_library=true])
AC_CHECK_FUNC([MPI_Accumulate], [mpi2_library=true])
AC_CHECK_FUNC([MPI_Get_accumulate], [mpi3_library=true])

AM_CONDITIONAL([MPI2_LIBRARY], [test x$mpi2_library = xtrue])
AM_CONDITIONAL([MPI3_LIBRARY], [test x$mpi3_library = xtrue])
AM_CONDITIONAL([MPI], [test x$mpi_library = xtrue])

AC_DEFINE([FIELD_WIDTH], [18], [Width of field used to report numbers])
AC_DEFINE([FLOAT_PRECISION], [2], [Precision of reported numbers])

AC_CONFIG_FILES([osu/Makefile
                 osu/mpi/Makefile
                 osu/mpi/pt2pt/Makefile
                 osu/mpi/startup/Makefile
                 osu/mpi/one-sided/Makefile
                 osu/mpi/collective/Makefile])
])
