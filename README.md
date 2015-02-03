About
=====

Senseye is a dynamic visual binary analysis and debugging tool intended to
assist in monitoring, analysing and grasping large data feeds e.g. static
files, dynamic streams and live memory.

For a bit more of what that entails, please take a look at the [Senseye Github Wiki](https://github.com/letoram/senseye/wiki).

Senseye uses [Arcan](https://github.com/letoram/arcan) as display server
and graphics engine to provide the user interface, representations and
other data transformations.

As such it requires a recent and working arcan build, see _Compiling_ below
for more details on a quick and dirty setup and _Starting_ for information
on how to start the user interface and to connect a sensor.

Compiling
=====

This requires an arcan build to be present / installed, e.g. (assuming all
dependencies are installed: OpenGL, SDL, Freetype and openal for the build
settings mentioned below). You also need cmake (2.8+) and gcc4.8+ or clang.

    git clone https://github.com/letoram/senseye.git
    cd senseye
    git clone https://github.com/letoram/arcan.git
    mkdir build-arcan
    cd build-arcan
    cmake -DCMAKE_BUILD_TYPE=Release -DVIDEO_PLATFORM=sdl
     -DDISABLE_FRAMESERVERS=ON -DCMAKE_C_COMPILER=clang ../arcan/src
    make -j 4
    cd ..
    mkdir build
    cd build
    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang
     -DARCAN_SOURCE_DIR=../arcan/src ../senseye/senses
    make -j 4

The arcan build configuration above disables a lot of features that we have
no use for here. When arcan moves to a more mature stage (around 0.9) we can
replace some of this with a libarcan-shmif find module, and arcan itself is
hopefully packaged in a few distributions before then.

Starting
=====

To just fire up the UI and feed it some of the included testing data,
you could do the following:

First, fire up the UI:

    ../build-arcan/arcan -p ../res -w 800 -h 800 ../senseye &

and then attach a sensor or two:

    ./fsense ../tests/test.bin
    cat ../tests/test.bin | ./psense 1> /dev/null

Replacing the default background (res/background.png) to something less dull is highly recommended ;-)

Default Keybindings (META is set to RIGHT SHIFT):

_Data Windows_

     F1 - Toggle Fullscreen
     F2 - Grow Window x2 (+Meta, Shrink)
     F3 - Zoom In (+Meta, Zoom Out)
     META + BACKSPACE - Destroy Window
     C - Cycle Active Shader

_Global_

     F7-F8 - Grow/Shrink Point Size (for pointclouds)
     TAB - Toggle Popup (+ arrow keys to navigate)
     ESCAPE - Drop Popup
     META + LClick + Drag - Move Window

_3D Window_

     w,a,s,d - Navigate
     Spacebar - Toggle autorotate
     LClick + Drag - Rotate model
     META + Button - Forward to parent window

_Psense/Fsense_

     Spacebar - Toggle Play/Pause

_Fsense_

     Left/Right - Step row (+Meta, block)

_Msense_

     Main Window: Arrow keys - move cursor up/down
                  Enter key - try to sample and load the selected area
                  
     Data Window: r - refresh at current position
                  Left/Right - Step page forward/backward

_Histogram Window_

    LClick - Set new parent highlight value

Sensors
=====

The following sensors are currently included:

_psense_ works as a step in a pipes and filters chain, where it grabs data
from standard input, samples and then forwards on standard output.

_fsense_ works on static data, i.e. whole files by first mmapping the entire
file and sampling a preview buffer for overview / seeking purposes.

_msense_ (linux only) works by parsing /proc/[pid]/maps for a specific pid
and allows you to navigate allocated pages and browse / sample their data.

Repository
=====

_files that might be of interest)_

    senseye\
        senseye.lua      - main script
        shaders.lua      - GLSL1.2 based shaders for mapping/displacement
        keybindings.lua  - default keybindings
        wndshared.lua    - navigation, default key bindings and navigation
        histogram.lua    - basic per-frame statistics
        modelwnd.lua     - camera management, 3d mapping
    senses\
        code for the main sensors, primarily data acquisition
        (msense/fsense/psense.c) with some minor statistics and
        translation done in rwstat.c and event-loop management in senseye.c
    res\ 
        (mostly cherry-picked from the arcan codebase)
        shared resources, fonts, support scripts etc. mainly
        cherry picked from the arcan repository.
