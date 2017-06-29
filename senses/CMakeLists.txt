PROJECT( senses )
cmake_minimum_required(VERSION 2.8.12 FATAL_ERROR)
include(ExternalProject)
set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/modules)
#
# cmake3.1+ provides this as part of normal flags, but it
# will take quite a while before we can use that as the
# minimum version.
#
option(ENABLE_CAPSTONE "Build Capstone- based Assembly translator" ON)

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
		xlt_overlay
		xlt_crash
	)
endif()

add_compile_options(
	-Wall
	-Wno-unused-function # -Wuseless-warning
	-Wno-unused-value
	-Wno-unused-variable
	-D__UNIX
	-D_POSIX_C_SOURCE=200809L
	-DGNU_SOURCE
	-D_BSD_SOURCE
	-std=iso9899:1999
)

if(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
	set(SENSE_MEM sense_mem.c memif_osx.c)
endif()

if (${CMAKE_SYSTEM_NAME} MATCHES "Linux")
	set(SENSE_MEM sense_mem.c memif_linux.c)
	add_compile_options( -D__LINUX )
endif()

if (ARCAN_SOURCE_DIR)
	add_subdirectory(${ARCAN_SOURCE_DIR}/shmif ashmif)
else()
	find_package(arcan_shmif REQUIRED)
endif()

if (ENABLE_CAPSTONE)
	set(XLT_CAPSTONE xlt_capstone)
endif()

include_directories(${ARCAN_SHMIF_INCLUDE_DIR})
link_libraries(pthread ${ARCAN_SHMIF_LIBRARY} m)

add_library(senseye STATIC xlt_supp.c sense_supp.c rwstat.c)

set(TRANSLATORS
	xlt_hex
	xlt_dpipe
	xlt_ascii
	xlt_img
	xlt_pefile
	${XLT_CAPSTONE}
	${DEBUG_XLT}
)

set(SENSES
	sense_pipe
	sense_file
	sense_mfile
)

foreach(xlt ${TRANSLATORS})
	add_executable(${xlt} "${xlt}.c")
	target_link_libraries(${xlt} senseye)
	install(TARGETS ${xlt} DESTINATION bin)
endforeach()

if (SENSE_MEM)
	add_executable(sense_mem ${SENSE_MEM})
	target_link_libraries(sense_mem senseye)
	install(TARGETS ${sense} DESTINATION bin)
endif()

foreach(sense ${SENSES})
	add_executable(${sense} "${sense}.c")
	target_link_libraries(${sense} senseye)
	install(TARGETS ${sense} DESTINATION bin)
endforeach()

set(CMAKE_EXTERNAL_DEFS
	CMAKE_ARGS
	-DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
	-DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
	-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
	-DLIBTYPE=STATIC
)

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
			-DCAPSTONE_BUILD_STATIC=ON
			-DCAPSTONE_BUILD_TESTS=OFF
		)
		add_dependencies(xlt_capstone Capstone)
		set(CAPSTONE_LIBRARY ${CMAKE_CURRENT_BINARY_DIR}/capstone/lib/libcapstone.a)
		set(CAPSTONE_INCLUDE_DIRS ${CMAKE_CURRENT_BINARY_DIR}/capstone/include)
		# dbhint disabled for now, incomplete feature
		#		target_compile_definitions(xlt_capstone PRIVATE DBHINT_SUPPORT)
		#		find_package(SQLITE3)
	endif()

	target_link_libraries(xlt_capstone ${CAPSTONE_LIBRARY} ${SQLITE3_LIBRARIES})
	target_include_directories(xlt_capstone PRIVATE
		${SQLITE3_INCLUDE_DIR}
		${CAPSTONE_INCLUDE_DIRS}
	)
endif()

# installation missing:
# preferably packaging (won't happen until 0.6)
# wrapper script to just run senseye to get arcan settings

