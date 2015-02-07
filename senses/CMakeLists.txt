PROJECT( senses )
cmake_minimum_required(VERSION 2.8.0 FATAL_ERROR)

#
# cmake3.1+ provides this as part of normal flags, but it
# will take quite a while before we can use that as the
# minimum version.
#
option(ENABLE_ASAN "Build with Address-Sanitizer, (gcc >= 4.8, clang >= 3.1)" OFF)
option(ENABLE_CAPSTONE "Build Msense with support for capstone disassembly" OFF)

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
	-D__UNIX
	-DPOSIX_C_SOURCE
	-DGNU_SOURCE
	-std=gnu11 # shmif-api requires this
	-DPLATFORM_HEADER=\"${ARCAN_SOURCE_DIR}/platform/platform.h\"
)

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
	message("------------------*Debug Build*--------------------")
	add_definitions(-g -D_DEBUG -O0 -fno-omit-frame-pointer)
endif (CMAKE_BUILD_TYPE STREQUAL "Debug")

include_directories(${ARCAN_SOURCE_DIR}/shmif)

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

if(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
	LIST(APPEND SHMIF_SOURCES
		${ARCAN_SOURCE_DIR}/platform/darwin/time.c
		${ARCAN_SOURCE_DIR}/platform/darwin/sem.c
	)
	add_definitions(-DARCAN_SHMIF_OVERCOMMIT)
else()
	LIST(APPEND SHMIF_SOURCES
		${ARCAN_SOURCE_DIR}/platform/posix/sem.c
		${ARCAN_SOURCE_DIR}/platform/posix/time.c
	)
	LIST(APPEND LIBRARIES
		rt
	)

	SET(MSENSE
		msense.c
		senseye.c
		rwstat.c
		rwstat.h
	)

	add_executable(msense ${MSENSE} ${SHMIF_SOURCES})
	target_link_libraries(msense ${LIBRARIES})
endif()

SET(PSENSE
	psense.c
	senseye.c
	rwstat.c
	rwstat.h
)

SET(FSENSE
	fsense.c
	senseye.c
	rwstat.c
	rwstat.h
)

add_executable(psense ${PSENSE} ${SHMIF_SOURCES})
add_executable(fsense ${FSENSE} ${SHMIF_SOURCES})

target_link_libraries(psense ${LIBRARIES})
target_link_libraries(fsense ${LIBRARIES})
