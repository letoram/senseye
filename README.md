About
=====

Senseye is a dynamic visual binary analysis and debugging tool intended to
assist in monitoring, analysing and grasping large data feeds e.g. static
files, dynamic streams and live memory. It is also powerful as part of a
build-test-refine loop when developing parsers and reversing file formats.

For more details on design, roadmap, use and features, take a look at the
[Senseye Github Wiki](https://github.com/letoram/senseye/wiki).

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
     sudo apt-get install libfreetype6-dev libopenal-dev libsdl1.2-dev libluajit-5.1-dev)
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
disassembly translators. If it is not installed, its current master branch
will be cloned and linked statically. To disable disassembly support,
add -DDISABLE\_CAPSTONE=ON

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

Workflow
=====

Sensors _provides_ data in lower levels of abstractions, typically byte
sequences etc. Think of them as measuring probes you attach to whatever
you want to gather measurements from.

The main UI then provides a number of visual and statistical tools for
working with raw data from sensors and help you find patterns and
properties to help you _classify_ and _group_ related data.

Lastly, _translators_ then interprets selected data blocks and provide
you with higher level representations.

Both sensors and translators work as separate processes that can be
connected and disconnected at will. This provides a tighter feedback loop
for specific cases e.g. when reversing a file format and developing a
parser.

There is nothing in the workflow that prevents hybrids though, i.e.
translators that also act as a sensor, packers/unpackers for various
formats could work in that way, there just is not anything like that
in the project currently.

Sensors
=====

The following sensors are currently included:

*sense_pipe* works as a step in a pipes and filters chain,
where it grabs data from standard input, samples and then
forwards on standard output.

The control window is a simple red or green square indicating
if the pipe is still alive or not.

*sense_file* works on mapping static files, i.e. whole files by
mmapping the entire file.

The control window is a static preview of the entire file,
along with an indicator of the current file position. It can also
be used to quickly seek.

*sense_mem* (linux only) works works by parsing /proc/[pid]/maps
for a specific pid and allows you to navigate allocated pages and
browse / sample their data.

The control window shows the currently available maps (reparsed
whenever navigation is provided) and the arrow keys / enter is used
to move between regions and spawn data windows.

Sensors are the more complex parts to develop, as there is both
a low level data acquisition component, IPC for providing data
and a UI part (that require some knowledge of Lua and the Arcan
Lua API) hiding in senseye/senses/\*.lua.

Translators
====

The following translators are currently included:

*xlt_dpipe* is a rather expensive translator that, on each sample,
forks out and executes the specified command-line application
(like /usr/bin/file -), with a pair connected to STDOUT/STDIN of
the new process. The sample data is pushed on STDIN, the result
is interpreted and rendered as ASCII text. It is intended for
magic- value style classifiers.

*xlt_capstone* is built if the capstone disassembly library
was found. It provides a mnenmonic based disassembler view,
with user definable coloring, formatting etc.

*xlt_ascii* is minimal example of a translator, it provides
7-bit ASCII rendering of the incoming data, with some minor
options to control line- feed behavior.

*xlt_hex* provides the basic numeric 'hex' view that tend to be useful,
incldies numerical representations of selected byte values,
including coloring schemes, different lengths, floating point etc.

*xlt_verify* and *xlt_seqver* are used for verification, testing
and debugging purposes and can mostly be ignored. Verify just renders
the data received again (which can help isolate corruption or
graphics- related issues) and seqver outputs a binary true/false
based on if the input data comes in incremental / wrapping sequences
(e.g. 0x01, 0x02, 0x03, 0xff, 0x04, 0x05, 0x06, 0xff) etc. testing
packing / unpacking in transfers.

Translators are much simpler to develop, typically one or two
callbacks that need to be implemented, with most fancy behavior
implemented by the xlt\_supp.\* files.

UI
====
A better introduction to the UI will be posted in video form,
there is too much experimentation going on still for that to
be worthwhile. Some keybindings can be replaced by editing the
keybindings.lua file and you should probably check it out for
a better view on how to avoid using the mouse for everything.

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
        gconf.lua        - configuration management
        wndshared.lua    - navigation, window management (resizing, zooming,)
        keybindings.lua  - default keybindings
    senses\
        code for the main sensors and translators, primarily data acquisition
        (sense_file,mem,pipe.c) with some minor statistics and
        translation done in rwstat.c and event-loop management in sense_supp.c
        xlt_* for translators, with xlt_supp doing event-loop management.
    res\
        (mostly cherry-picked from the arcan codebase)
        shared resources, fonts, support scripts for UI features, window
        management etc. cherry picked from the arcan repository.
