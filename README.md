About
=====
NOTE: CURRENTLY UNDERGOING SERIOUS REFACTORING, THE MASTER BRANCH IS NOT IN
A WORKING STATE. PLEASE STICK TO THE 1bab4b9c60ad43302e460a24de14a0ac136bea7f
COMMIT FOR WORKING WITH THE ARCAN 0.5.2 VERSION.

Senseye is a toolsuite for dynamic visual binary analysis and debugging,
assist in monitoring, analysing and grasping large data feeds e.g. static
files, dynamic streams and live memory. It is also powerful as part of a
build-test-refine loop when developing parsers and reversing file formats.

Senseye uses the [Arcan](https://arcan-fe.com) display server for drawing and
for IPC, along with the associated [Durden](http://durden.arcan-fe.com) desktop
environment for window management and user interface controls.

It current runs on Linux/BSDs and OSX. IRC chat @ #arcan on irc.freenode.net.

Compiling
======

First make sure that you have a working build of arcan and that it can start
durden. Familiarize yourself with the UI input and window management scheme
before moving further.

The short version for building arcan on a system that has native graphics
already is something like:

The short version for building arcan:

    git clone https://github.com/letoram/arcan.git
    mkdir arcan/build ; cd arcan/external/git; ./clone.sh ; cd ../../build
    cmake -DVIDEO_PLATFORM=sdl -DSTATIC_FREETYPE=ON -DSTATIC_SQLITE3=ON
          -DSTATIC_OPENAL=ON ../src
    make -j 12
    sudo make install

For starting durden:

    git clone https://github.com/letoram/durden.git
    /usr/local/bin/arcan /path/to/durden/durden

When you are the stage where Arcan is up and running, durden has started,
you can spawn a terminal (default: meta1+enter) window. These terminals
will have the environment setup for the senseye sensors to connect and
start providing data.

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

Components
=====

Senseye is divided up into UI tool scripts, sensors and translators.

## UI-Tool scripts

Copy or symlink the tools/senseye.lua and the subfolder tools/senseye into the
corresponding durden/durden/tools/senseye.lua and durden/durden/tools/senseye.

If you have durden active while you do it, you can rescan/reload the scripts
by going into the global menu (meta1+g), pick system and then reset.

These scripts hook into the 'target window' menu for windows that have
identified as senseye data sources and take aggressive control over the
settings and behavior of the window.

The current toolscripts are:

### Color-LUT

### Histogram

### Point Cloud

### Distance Tracker

### Pattern Matching / Searching

### Picture Tuner

## Sensors
samples input data and packages it in a form where the UI can make sense of it.

The current sensors are:

### sense_file

This sensor works with a static file. The default window that popups up is a
preview visualization of the contents of the file, optionally with some
rudimentary statistical analysis.

Double-click (or hit ENTER) to spawn a new data window at the cursor position
in the preview window.

### sense_mfile

This sensor works with multiple files that you want to visually diff, along
with the option to apply some other transformation, e.g. a XOR b = c.
Double-clicking on a tile will lock stepping.

### sense_pipe

This sensor works with streaming input.

## Translators

Translators are windowed- parsers that take an incoming data stream and provide
some kind of non-native representation of the contents of the data stream. This
output comes in two forms, a separate data- window, and a controlable overlay
that is presented on top of the visualization of the incoming data source in
itself.

The current translators are:

### xlt_image

### xlt_text

### xlt_disassembly

