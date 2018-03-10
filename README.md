About
=====
NOTE: CURRENTLY UNDERGOING SERIOUS REFACTORING, THE MASTER BRANCH IS NOT IN
A WORKING STATE. PLEASE STICK TO THE 1bab4b9c60ad43302e460a24de14a0ac136bea7f
COMMIT FOR WORKING WITH THE ARCAN 0.5.2 VERSION.

Senseye is a set of data providers, parsers that work with the
[Arcan](https://arcan-fe.com) display servers IPC subsystem, and as a set of
extension script for the [Durden](http://durden.arcan-fe.com) desktop
environment/window management scheme.

It current runs on Linux/BSDs and OSX. IRC chat @ #arcan on irc.freenode.net.

Compiling
======

First make sure that you have a working build of arcan and durden. Familiarize
yourself with the UI input and window management scheme before moving further.

On voidlinux, most of this is packaged, you can simply go from the linux
console (won't cooperate with Xorg, for that you need to rebuild with an SDL
based backend):

    xbps-install durden
		durden

Senseye itself and its support scripts have not yet been included in the same
packaging. Simply do this:

    ln -s /path/to/senseye/senseye $HOME/.arcan/appl/durden/tools
		ln /path/to/senseye/senseye.lua $HOME/.arcan/appl/durden/tools/senseye.lua

And either restart or activate global/system/reset=yes. You can then find the
different analysis tools under the target/senseye path, though the set of
options and features will vary with the source you are using it on.

The individual senses should work fine with any other Arcan based window
management system though, and the scripts themselves should require little
repurposing.

For other settings, you can wait for the project to mature enough to be packaged
in your environment, and be brave and install/build from source.

The short version for building arcan on a system that has native graphics
already is something like:

    git clone https://github.com/letoram/arcan.git
    mkdir arcan/build ; cd arcan/external/git; ./clone.sh ; cd ../../build
    cmake -DVIDEO_PLATFORM=sdl -DSTATIC_FREETYPE=ON -DSTATIC_SQLITE3=ON
          -DSTATIC_OPENAL=ON ../src
    make -j 12
    sudo make install

This one requires libsdl1.2-dev (or whatever the package is called on your
system).

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

### Mapping Window

Missing:
 [ ] Create a mapping window that allows zoom / etc.
 [ ] Use a vertex shader or LUT based approach
 [ ] Alpha channel only- shader
 [ ] Save buffer

### Histogram

A histogram window is created via target/senseye/histogram. By default, it will
be capped to 256x256 linear sampled version of the source window in order to not
make the UI responsive in the event of a big source.

In the histogram window, you have the following options:

- Imposition-mode (merge, full) : if r,g,b channels should be averaged or separated
- Size-mode (capped, full) :

Missing:
 [ ] define reference histogram and pause or log on match
 [ ] mouse / pattern selection feedback into mapping window
 [ ] counter in titlebar
 [ ] keyboard input

### Point Cloud

Missing:
 [ ] Mapping window but with 3D navigation options (rotate/zoom/step point-sz)

### Pattern Matching / Searching
 [ ] Basic feature, use browser to load reference
 [ ] trigger action

### Picture Tuner
 [ ] Basic Feature
 [ ] Color space management

## Sensors
samples input data and packages it in a form where the UI can make sense of it.

The current sensors are:

### sense_file
### sense_mfile
### sense_pipe
### sense_mem

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

