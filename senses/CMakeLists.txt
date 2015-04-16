PROJECT( senses )
cmake_minimum_required(VERSION 2.8.12 FATAL_ERROR)
include(ExternalProject)

#
# cmake3.1+ provides this as part of normal flags, but it
# will take quite a while before we can use that as the
# minimum version.
#
option(ENABLE_CAPSTONE "Build Capstone- based Assembly translator" ON)
option(ENABLE_IMG "Build with Image- translator (not working)" OFF)
option(ENABLE_PEPE "Build PE- translator (not working)" OFF)
option(ENABLE_MEMSENSE "Build with /proc/pid/mem translator (needs permissions)" ON)

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
	option(ENABLE_ASAN "Build with Address-Sanitizer, (gcc >= 4.8, clang >= 3.1)" OFF)

	if (ENABLE_ASAN)
		if (ASAN_TYPE)
			set(CMAKE_C_FLAGS "-fsanitize=${ASAN_TYPE} ${CMAKE_C_FLAGS}")
		else()
			set(CMAKE_C_FLAGS "-fsanitize=address ${CMAKE_C_FLAGS}")
		endif()
	endif (ENABLE_ASAN)

	message("------------------*Debug Build*--------------------")
	add_definitions(-g -D_DEBUG -O0 -fno-omit-frame-pointer -D_DEBUG_NOLOG)
	set(DEBUG_XLT
		xlt_seqver
		xlt_verify
	)
endif()

add_compile_options(
	-Wall
	-Wno-unused-function # -Wuseless-warning
	-D__UNIX
	-D_POSIX_C_SOURCE=200809L
	-DGNU_SOURCE
	-D_BSD_SOURCE
	-std=iso9899:1999
)

if (ARCAN_SOURCE_DIR)
	add_subdirectory(${ARCAN_SOURCE_DIR}/shmif ashmif)
else()
	find_package(arcan_shmif REQUIRED)
endif()

# apply options

if(ENABLE_MEMSENSE)
	set(SENSE_MEM sense_mem)
endif()

if (ENABLE_PEPE)
	set(XLT_PEPE xlt_pepe)
endif()

if (ENABLE_IMG)
	set(XLT_IMG xlt_img)
endif()

if (ENABLE_CAPSTONE)
	set(XLT_CAPSTONE xlt_capstone)
endif()

include_directories(${ARCAN_SHMIF_INCLUDE_DIR})
link_libraries(pthread m ${ARCAN_SHMIF_LIBRARY})

add_library(xlt_supp STATIC xlt_supp.c xlt_supp.h)
add_library(sense_supp STATIC sense_supp.c rwstat.c rwstat.h sense_supp.h)

set(TRANSLATORS
	xlt_hex
	xlt_dpipe
	xlt_ascii
	${XLT_CAPSTONE}
	${XLT_PEPE}
	${XLT_IMG}
	${DEBUG_XLT}
)

set(SENSES
	sense_pipe
	sense_file
	${SENSE_MEM}
)

foreach(xlt ${TRANSLATORS})
	add_executable(${xlt} "${xlt}.c")
	target_link_libraries(${xlt} xlt_supp)
	install(TARGETS ${xlt} DESTINATION bin)
endforeach()

foreach(sense ${SENSES})
	add_executable(${sense} "${sense}.c")
	target_link_libraries(${sense} sense_supp)
	install(TARGETS ${sense} DESTINATION bin)
endforeach()

set(CMAKE_EXTERNAL_DEFS
	CMAKE_ARGS
	-DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
	-DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
	-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
	-DLIBTYPE=STATIC
)

if (ENABLE_PEPE)
	ExternalProject_Add(peparse
		SOURCE_DIR ${CMAKE_CURRENT_BINARY_DIR}/peparse
		GIT_REPOSITORY "https://github.com/letoram/pe-parse.git"
		UPDATE_COMMAND ""
		PATCH_COMMAND ""
		${CMAKE_EXTERNAL_DEFS}
		-DCMAKE_INSTALL_PREFIX=${CMAKE_CURRENT_BINARY_DIR}/peparse
	)

	target_link_libraries(xlt_pepe
		${BINARY_DIR}/parser-library/libpe-parser-library.a)
	target_include_directories(xlt_pepe PRIVATE ${SOURCE_DIR}/parser-library)
endif()

if (ENABLE_CAPSTONE)
	find_library(CAPSTONE_LIBRARY NAMES capstone)
	if (NOT CAPSTONE_LIBRARY)
		ExternalProject_Add(Capstone
			SOURCE_DIR ${CMAKE_CURRENT_BINARY_DIR}/capstone-src
			GIT_REPOSITORY "https://github.com/aquynh/capstone.git"
			UPDATE_COMMAND ""
			PATCH_COMMAND ""
			${CMAKE_EXTERNAL_DEFS}
			-DCMAKE_INSTALL_PREFIX=${CMAKE_CURRENT_BINARY_DIR}/capstone
			-DCAPSTONE_BUILD_SHARED=OFF
			-DCAPSTONE_BUILD_STATIC_RUNTIME=ON
			-DCAPSTONE_BUILD_TESTS=OFF
		)
		add_dependencies(xlt_capstone Capstone)
		set(CAPSTONE_LIBRARY ${CMAKE_CURRENT_BINARY_DIR}/capstone/lib/libcapstone.a)
		set(CAPSTONE_INCLUDE_DIRS ${CMAKE_CURRENT_BINARY_DIR}/capstone/include)
	endif()

	target_link_libraries(xlt_capstone ${CAPSTONE_LIBRARY})
	target_include_directories(xlt_capstone PRIVATE ${CAPSTONE_INCLUDE_DIRS})
endif()

# installation missing:
# preferably packaging (won't happen until 0.6)
# wrapper script to just run senseye to get arcan settings

