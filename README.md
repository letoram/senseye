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

It current runs on Linux/FreeBSD/OSX, with a Windows port hiding in the near
future.

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

Data Window Menu
=====

There are a few entries in the data menu that warrant some explanation.
First, recall that all transfers from a sensor to senseye is performed
over a shared memory mapping that is treated as a packed image, where
the build-time default is a 32-bit red,green,blue,alpha interleaved buffer.

_Packing_ (what is to be stored) controls how the sensor formats data,
_intensity_ means that the same byte will be set in the red, green and
blue channels). It is a sparse format that wastes a lot of bandwidth
but may be useful when higher semantic markers are encoded in the
alpha channel as the alpha resolution will be per byte rather than in
groups of three or four.

_histogram intensity_ is a variant of _intensity_ where the channel value
will be the running total frequency of that particular byte value.
_tight (alpha)_ is similar to a straight memcpy, each color channel will
corrspond to one sampled value (so 4 bytes per pixel). _tight(no-alpha)_
is the better trade-off and the default that uses three bytes per pixel
and permits other data to be encoded in the alpha channel.

The _Metadata_ options specifies what additional data should be encoded in
each transfer (which also depends on which channels that could be used
based on the packing mode). By default, this is set to _Shannon Entropy_
(though the block size that the entropy is calculated on is defined
statically in the sensor currently) being encoded in the alpha channel.
_Full_ simply means that the channel value will be ignored and set to
full-bright (0xff). _Pattern Signal_ means that if the sensor has been
configured to be able to do pattern matching or other kinds of metadata
encoding in the alpha channel, it should be used. This is typically combined
with a shader that has a coloring lookup-table ( palette ) attached.

_Transfer Clock_ hints at the conditions required for an update. This is
a hint in the sense that not every sensor will necessarily follow this.
Using _psense_ as an example, _Buffer Limit_ clock means that a new transfer
will be initiated when the complete buffer has been filled with new data,
(or if the pipe terminates), while _Sliding Window_ means that as soon as
we get new data, the transfer will be initiated.

_Space Mapping_ finally, determines the order in which the packed bytes
should be encoded in the image buffer. This greatly affects how the image
will 'look' and different mapping schemes preserve or emphasize different
properties. _Wrap_ is the easiest one in that the bytes will be stored in
the order which they arrived. This has the problem of the last pixel on
each row being connected data-wise with the first pixel on the next row
even though they will be spatially distant from eachother. _Hilbert_ mapping
scheme instead uses a space filling fractal (the hilbert curve) which
preserves locality better. _Tuple_ mapping uses the byte-values in the
data-stream to determine position (first byte X, second byte Y) to
highlight some specific relationships between a tuple of bytes.

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
