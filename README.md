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

Senseye uses [Capstone engine](http://www.capstone-engine.org), so Capstone
must be installed beforehand. See more instructions at 
http://capstone-engine.org/download.html, or build it from source like
followings:

    git clone https://github.com/aquynh/capstone.git
    cd capstone
    ./make.sh
    sudo ./make.sh install

Senseye also requires an arcan build to be present / installed, e.g. (assuming all
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
     -DARCAN_SOURCE_DIR=../arcan/src ../senses
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

    ./sense_file ../tests/test.bin &
    cat ../tests/test.bin | ./sense_pipe 1> /dev/null &

and optionally one or more translators.

    ./xlt_ascii &
    ./xlt_dpipe /usr/bin/file - &
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
be worthwhile.

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
        code for the main sensors and translators , primarily data acquisition
        (sense_file,mem,pipe.c) with some minor statistics and
        translation done in rwstat.c and event-loop management in sense_supp.c
    res\
        (mostly cherry-picked from the arcan codebase)
        shared resources, fonts, support scripts for UI features, window
        management etc. cherry picked from the arcan repository.
