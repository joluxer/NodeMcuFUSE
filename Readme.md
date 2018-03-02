# NodeMCU FUSE

Characteristics:
- it's a small middleware, which provides access to a NodeMCU device
- present the files inside the NodeMCU as a filesystem in Linux
- provide access to the files with read, write, create, delete, rename, truncate
- access to meta data of the connection to the NodeMCU: baudrate, RTS, DTR, searching for a usable serial port
  device (to overcome USB reconnects and different enumerations)
- self supporting development of the middleware, i.e. by capturing a length limited hexdump record of RX data
- providing terminal access (for using your favorite terminal emulator) to the console of the attached NodeMCU without
  loosing connection on USB reconnect
- support for different configurations
- support for multiple connections to multiple NodeMCU devices at the same time, distinguished by mountpoint

TODO:
- implementation and test with NodeMCU images with FATFS support (requirement driven priority)
- hexdump of TX data (low priority)
- postpone file operations or return EAGAIN or EBUSY, if MCU is not at primary prompt (requirement driven priority)
- execution of a file by any kind of command in the VFS (low priority)
- execution of a file through the GUI (low priority)
- compile files to Lua byte code by any kind of command in the VFS (medium priority)
- compile files to Lua byte code through the GUI (medium priority)
- simple readout of the device ID through the VFS (requirement driven priority)
- display of the device ID through the GUI (requirement driven priority)
- switch to UNIX98 style of pseudoterminal lines (modern Linux distros don't provide easy user access to BSD pseudoterminals, medium priority)
- reimplement in C for performance (very low priority, as the serial port is the real bottleneck)

## Installation

If you have all dependencies ready (see below), just unpack the .tar.gz file to an appropriate location, i.e. `~/Programs/`.
If all went well, there you will find an directory `NodeMcuFUSE` with the main program `nodemcu-mount.tcl`.

To make the start of the mount command more comfortable, place somewhere in your PATH a symlink to `~/Programs/NodeMcuFUSE/nodemcu-mount.tcl`.

I have for such cases a directory `~/bin` in my PATH, i.e. `ln -s ~/Programs/NodeMcuFUSE/nodemcu-mount.tcl ~/bin/nodemcu-mount`.

To check the program, you can run `nodemcu-mount --help`. This checks most of the conditions.

## Getting started

1. make a BSD pseudoterminal master/slave pair available for yourself UID (i.e. `sudo chmod a+rw /dev/ttyp? /dev/ptyp?`)
1. create a mountpoint, where your NodeMCU access shall appear (i.e. `mkdir -p ~/mnt/node`)
1. mount your NodeMCU to your mountpoint: i.e. `nodemcu-mount ~/mnt/node`
1. plug your NodeMCU into your computer
1. optional: start your favourite filemanager: i.e. `thunar ~/mnt/node/mcu &`
1. optional: edit a file, i.e. `init.lua`, using your favourite text editor: i.e. `mousepad ~/mnt/node/mcu/init.lua &`
1. optional: start your favourite terminal emulator: i.e. `picocom ~/mnt/node/io/user/tty`

## Usage

Start the program with the options you want:

    nodemcu-mount [options] mountpoint
        -C cfgDir       configuration directory (default ~/.nodemcufuse)
        -c cfgFile      configuration file
                        (can be absolute or is relative to '-C')
        -T list         comma separated list of TTYs to try to open for NodeMCU
        -t /dev/ttyXXX  try this TTY first, maybe or not part of '-T'
        -b n            use baudrate n
        -o fuse-opt     set mount options for the FUSE mount, see mount.fuse(8),
                        the first '-o' resets the list of default FUSE options
        -h --help       print this help and exit
        mountpoint      where the VFS is mounted (is optional, if you have config file)

The program will usually run in foreground. To terminate the program, just hit Ctrl-C (send signal INT) or kill it by TERM or QUIT.

If you unmount the mount point, the program wont terminate, this is currently a bug in libfuse.

## Dependencies

To run the NudeMcuFUSE middleware, one needs some requisites.

1. a Linux system with support for FUSE and BSD pseudo terminals and serial ports
1. tclsh version 8.6 (earlier versions are not tested yet, later versions as well not tested)
1. Tclx (min. 8.0) module somewhere in your system, where tclsh can find it
1. the tcl-fuse module somewhere in your system, where tclsh can find it, tested is version 1.1
1. libfuse (as a dependency for tcl-fuse), tested is version 2.9.7
1. (not really optional) a NodeMCU device, connected via any kind of serial port device to your linux box; the ELua
   image on the NodeMCU device must provide the math module, the file module, the uart module and the timer module. The
   former three are normally mandatory to the ELua image, the timer module is essential for NodeMcuFUSE to avoid
   watchdog timer resets and more problems. By default, NodeMcuFUSE uses timer 6, but this is configurable through
   the VFS and stored inside the configuration file.

## The story

After being unhappy a lot about ESPlorers deficencies in accesssing the NodeMCU and the fact, that I could not find an 
Lua loader for the NodeMCU, which is really free and really open source, the idea was born, to build a Lua loader myself.

My intent was to manage files on NodeMCU device, so why invent an other filemanager-like thing. It is much better to use one of the good file
managers in Linux. An other intent was, to access the console of NodeMCU devices, therefor I want to use my favourite terminal emulator.

So the new Lua loader must fulfil some simple requirements:
- I want to use my own and favourite source code editor for the programs
- I prefer to use my own update strategy for the files on the target: all, partly, managed, selected files, ...
- easy to use for beginners
- powerful for me
- no special code on the NodeMCU (beside some very small constraints on the capabilities of the Lua image)
- primary communication over serial port
- as far as possible agnostic to USB reconnects and re-enumerations
- supporting a small (micro) GUI for MCU reset an the like (access to the RTS and DTR line), _independent_ of the loader itself
- developed following the good old UN*X strategy: one tool for one task, nothing bloated
- no binding to a special IDE
- no binding to some GUI, must even work on headless systems as well as on full featured developer workstations

After tinkering around with some legacy file manager implementations, which resembled the good old No*ton Commander UI style
and reimplementing some file like access using serial port line to the NodeMCU attached to a USB serial port adapter, 
the idea was born, to replace the legacy file manager code by recent file managers and to access the NodeMCU using the 
FUSE filesystem in Linux. 

So here we are: this middleware presents the NodeMCU files and some properties of it as a virtual filesystem to the user. 

Just use your favourite filemanager to manage the files on the NodeMCU, use your favourite source code editor or IDE for your 
Lua sources and access all this nearly like accessing local files on your hard drive. The transfer runs completely over the serial
port console, somewhat low performance for file access is the fee to pay for the comfort of accessing the NodeMCU as a file system.

And yes, there is no Windows version available, due to the lack of support for FUSE and pseudo terminals. And yes, there will be
never a Windows version supported by me, because I don't support closed systems.

## Configuration file

The NodeMcuFUSE middleware keeps track of settings using a configuration file. I's an ASCII representation of a TCL dict. This
way it is user readable, but it is not intended to be edited by user. Please, use command line arguments and the VFS of the
middleware for changes to the configuration.

By default, configuration file(s) are located in `~/.nodemcufuse`. You can change that on startup of the middleware by command
line switches.

I recommend you to use configuration files named by purpose. After first use of a configuration file, all settings including the
mountpoint are stored there, so further starts of the middleware don't need more than the configuration file itself.

Example:

First start for the project Temperature Logger:
  `nodemcu-mount -c temp-logger -T /dev/ttyUSB4,/dev/ttyUSB5 ~/ESP8266/mnt-temp-logger`
Second and further starts for the project Temperature Logger:
  `nodemcu-mount -c temp-logger`

The default configurations files contain the computers DNS name, to make it possible, to use the middleware on shared directories (i.e.
NFS mounted `/home`). The drawback is, roaming computers (i.e. Laptops) with varying DNS identities will build up a bunch of several
configuration over time, if you do not work with named configurations.

Everey configuration file is just some bytes in size (always below 1000), so space should be no problem.

## Bugs

Keep backups of your files, DO NOT hold them on NodeMCU devices only. Reading files from the NodeMCU should never destroy data on the
device. 

I consider every problem, which occurs reproducible, as a serious bug. But there are also a lot of difficult things and assumptions while
communicating with the NodeMCU device.

Problems can occur, when the NodeMCU device prints spontaneous on the console, because the expected chit-chat with the device may be
disturbed by this.

Other problems occur, when there are open or half open files on the device, left over from broken down transfers without recovering from that.

Before you report problems, please reproduce them in a minimal example; reset your device before reporting (if possible) and give a step
by step report, how to reproduce the problem.
