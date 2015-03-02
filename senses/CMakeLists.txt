PROJECT( senses )
cmake_minimum_required(VERSION 2.8.0 FATAL_ERROR)

#
# cmake3.1+ provides this as part of normal flags, but it
# will take quite a while before we can use that as the
# minimum version.
#
option(ENABLE_ASAN "Build with Address-Sanitizer, (gcc >= 4.8, clang >= 3.1)" OFF)

if (ENABLE_ASAN)
	if (ASAN_TYPE)
		set(CMAKE_C_FLAGS "-fsanitize=${ASAN_TYPE} ${CMAKE_C_FLAGS}")
	else()
		set(CMAKE_C_FLAGS "-fsanitize=address ${CMAKE_C_FLAGS}")
	endif()
endif (ENABLE_ASAN)

#
# For finding the shared memory interface and corresponding
# Platform functions. When that API is more stable, we'll
# simply wrap it in a library but for now, we require
# compiler and layout compliance.
#
if (NOT ARCAN_SOURCE_DIR)
	message(FATAL_ERROR "ARCAN_SOURCE_DIR is not set, use -DARCAN_SOURCE_DIR=")
endif()

add_definitions(
	-Wall
	-Wno-unused-function # -Wuseless-warning
	-D__UNIX
	-DPOSIX_C_SOURCE
	-DGNU_SOURCE
	-std=gnu11 # shmif-api requires this
	-DPLATFORM_HEADER=\"${ARCAN_SOURCE_DIR}/platform/platform.h\"
)

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
	message("------------------*Debug Build*--------------------")
	add_definitions(-g -D_DEBUG -O0 -fno-omit-frame-pointer -D_DEBUG_NOLOG)
endif (CMAKE_BUILD_TYPE STREQUAL "Debug")

include_directories(${ARCAN_SOURCE_DIR}/shmif /usr/local/include)

SET(LIBRARIES
	pthread
	m
)

SET(SHMIF_SOURCES
	${ARCAN_SOURCE_DIR}/platform/posix/warning.c
	${ARCAN_SOURCE_DIR}/platform/posix/fdpassing.c
	${ARCAN_SOURCE_DIR}/shmif/arcan_shmif_control.c
	${ARCAN_SOURCE_DIR}/shmif/arcan_shmif_interop.c
)

if (${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
	add_definitions(-DARCAN_SHMIF_OVERCOMMIT)
	list(APPEND SHMIF_SOURCES
		${ARCAN_SOURCE_DIR}/platform/darwin/time.c
		${ARCAN_SOURCE_DIR}/platform/darwin/sem.c
	)

elseif (${CMAKE_SYSTEM_NAME} MATCHES "Linux")
	message("[*] Linux detected, enabling msense")
	set(ENABLE_MSENSE true)
	LIST(APPEND SHMIF_SOURCES
		${ARCAN_SOURCE_DIR}/platform/posix/sem.c
		${ARCAN_SOURCE_DIR}/platform/posix/time.c
	)
	LIST(APPEND LIBRARIES
		rt
	)
endif()

link_libraries(${LIBRARIES})

set(XLT_SOURCES ${SHMIF_SOURCES} xlt_supp.c xlt_supp.h)
set(SENSE_SOURCES ${SHMIF_SOURCES} sense_supp.c rwstat.c rwstat.h sense_supp.h)

add_executable(sense_pipe sense_pipe.c ${SENSE_SOURCES})
add_executable(sense_file sense_file.c ${SENSE_SOURCES})

find_library(CAPSTONE_LIBRARY NAMES capstone)
if (CAPSTONE_LIBRARY)
	message("[*] Capstone found, enabling xlt_capstone")
	add_executable(xlt_capstone ${SHMIF_SOURCES} xlt_capstone.c xlt_supp.c)
	target_link_libraries(xlt_capstone ${CAPSTONE_LIBRARY})
else()
	message("[ ] Capstone not found, xlt_capstone disabled")
endif()

if (ENABLE_MSENSE)
	add_executable(sense_mem sense_mem.c ${SENSE_SOURCES})
endif()
add_executable(xlt_seqver xlt_seqver.c ${XLT_SOURCES})
add_executable(xlt_verify xlt_verify.c ${XLT_SOURCES})
add_executable(xlt_dpipe xlt_dpipe.c ${XLT_SOURCES})
add_executable(xlt_ascii xlt_ascii.c ${XLT_SOURCES})

