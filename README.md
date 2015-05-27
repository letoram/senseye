About
=====

Senseye is a dynamic visual binary analysis and debugging tool intended to
assist in monitoring, analysing and grasping large data feeds e.g. static
files, dynamic streams and live memory. It is also powerful as part of a
build-test-refine loop when developing parsers and reversing file formats.

For a lot more detail on design, roadmap, use and features, take a look at the
wiki at [Senseye Github Wiki](https://github.com/letoram/senseye/wiki).

It current runs on Linux/FreeBSD/OSX, with a Windows port hiding in the near
future.

Compiling
======

Senseye uses [Arcan](https://github.com/letoram/arcan) as display server
and graphics engine to provide the user interface, representations and
other data transformations.

The short version for building arcan:

    [first, fix dependencies (freetype, openal, sdl1.2, luajit5.1, clang >= 3.1)
     for debian/ubuntu:
     sudo apt-get install libsqlite3-dev libfreetype6-dev libopenal-dev libsdl1.2-dev libluajit-5.1-dev)
    ]

    git clone https://github.com/letoram/arcan.git
    or (for a debian/ubuntu)
    mkdir arcan/build ; cd arcan/build
    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DVIDEO_PLATFORM=sdl ../src
    make -j 12
    sudo make install

Now you are ready to build the sensors and translators:

    git clone https://github.com/letoram/senseye.git
    mkdir senseye/build ; cd senseye/build
    cmake ../senses

It is possible to avoid installing arcan and using an in-source build with:

    cmake -DARCAN_SOURCE_DIR=/path/to/arcan/src ../senses

Senseye uses [Capstone engine](http://www.capstone-engine.org) for providing
disassembly translators. If it is not installed, its current master branch will
be cloned and linked statically. To disable disassembly support, add
-DENABLE\_CAPSTONE=OFF (or use an interactive cmake interface for better
control).

Starting
=====

To just fire up the UI and feed it some of the included testing data,
you could do the following:

First, fire up the UI:

    arcan -p /path/to/senseye/res -w 800 -h 800 /path/to/senseye/senseye &

Then attach a sensor or two:

    ./sense_file ../tests/test.bin &
    cat ../tests/test.bin | ./sense_pipe 1> /dev/null &

Optionally one or more translators:

    ./xlt_ascii &
    ./xlt_dpipe /usr/bin/file - &
    ./xlt_hex &
    ./xlt_capstone -a x86-64 &

Note that on OSX, the default libraries may not be in the search
path for the linker:

export DYLD_FALLBACK_LIBRARY_PATH=/usr/local/lib/arcan


Repository
=====

_files that might be of interest)_

    senseye\
        senseye.lua      - main script
        histogram.lua    - basic per-frame statistics
        alphamap.lua     - window for showing / highlighting metadata
        distgram.lua     - track byte- distances
        patfind.lua      - visual based pattern matching
        translators.lua  - translator specific window management
        modelwnd.lua     - camera management, 3d mapping, pointcloud
        shaders.lua      - GLSL1.2 based shaders for mapping/displacement/color
        pictune.lua      - Tool for finding raw image parameters
        gconf.lua        - configuration management
        wndshared.lua    - navigation, window management (resizing, zooming,)
        keybindings.lua  - default keybindings
    senses\
        code for the main sensors and translators, primarily data acquisition
        (sense_file,_mfile,_mem,_pipe.c) with some minor statistics and
        translation done in rwstat.c and event-loop management in sense_supp.c
        xlt_* for translators, with xlt_supp doing event-loop management.
    res\
        (mostly cherry-picked from the arcan codebase)
        shared resources, fonts, support scripts for UI features and window
        management.
