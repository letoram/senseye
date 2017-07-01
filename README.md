About
=====

NOTE: CURRENTLY UNDERGOING SERIOUS REFACTORING, THE MASTER BRANCH IS NOT IN
A WORKING STATE. PLEASE STICK TO THE 1bab4b9c60ad43302e460a24de14a0ac136bea7f
COMMIT FOR WORKING WITH THE ARCAN 0.5.2 VERSION.

Senseye is a dynamic visual binary analysis and debugging tool intended to
assist in monitoring, analysing and grasping large data feeds e.g. static
files, dynamic streams and live memory. It is also powerful as part of a
build-test-refine loop when developing parsers and reversing file formats.

It current runs on Linux/FreeBSD/OSX. IRC chat @ #arcan on irc.freenode.net.

Compiling
======

Senseye uses [Arcan](https://github.com/letoram/arcan) as display server and
graphics engine to provide the user interface, representations and other data
transformations.

The short version for building arcan:

    git clone https://github.com/letoram/arcan.git
    mkdir arcan/build ; cd arcan/external/git; ./clone.sh ; cd ../../build
    cmake -DVIDEO_PLATFORM=sdl -DSTATIC_FREETYPE=ON -DSTATIC_SQLITE3=ON
          -DSTATIC_OPENAL=ON ../src
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

    arcan -p . -w 800 -h 800 /path/to/senseye/senseye &

Inside, you get access to the main menu via TAB. From there you can spawn
a terminal. From there you can attach a sensor or two:

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

And similarly for some other 'nixes (LD_LIBRARY_PATH=/usr/local/lib/arcan)

Hacking
=====

As mentioned at the top, everything is in flux now and for a month or two.
The codebase is divided into these folders:

    senseye/
           All the main UI code goes in here, along with the GPU part of
           some of the processing. The code- related folders are structured as:
           support/ reused UI scripts for components, window management and
                    input. These are cherry picked from other arcan projects.
           windows/ window behavior modification code
           handlers/ sensor and translator event handlers
           menus/ sensor, translator and system popups
           views/ data-views that create alternate representations

    senses/
           files prefixed with sense_ are sensors
           files prefxied with xlt_ are translators
           xlt_supp, sense_supp, rwstat are built into libsenseye that
           can be used to build sensors.
           For creating UIs, libshmif-tui from arcan is used, it is
           similar to TurboVison and NCurses - with better integration.

When a sensor connects, the connection point in senseye.lua is activated which
creates a window with the 'control' type if it identified as 'sensor' and with
the 'translator' type if it identified as a translator. When the control window
requests subwindows, those are created with the 'data' type.

The window is passed to wndshared_setup(wnd, type) that applies the specific
UI etc. that are unique to that particular type. The most complex type is 'data'
as it involves many UI actions like pan, zoom, event control, synchronization
between sampling offsets and so on.

The views folder is scanned on startup and scripts that parse are added to the
data window menu popup.
