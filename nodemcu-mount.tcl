#!/usr/bin/env tclsh

package require fuse
package require Tclx 8.0

set PROGDIR [file normalize [file dirname $argv0]]

################
# Debugging
set globalNoDebug 0; # this flag, if set 1, disables all debug procedures by replacing them with empty stubs, i.e. to gain performance for production service
set globalDoDebug 0; # this flag, if set 1, enables all debug output, regardless their local settings, so one could see a full call path and debug data of all instrumented procedures
array set procDebug {}; # members of this array can enable debug output of instrumented procedures: array index is the procedure name, member value must be 1 to enable, else 0
set procDebug(unknown) 0
set mountpoint mnt

################
# global Variables for the whole system

set tryTTYs [list "/dev/ttyUSB0" "/dev/ttyUSB1"]
set mcuTty(activeTTY) "/dev/null"
set mcuTty(ttyFD) ""
set mcuTty(rtsState) 0
set mcuTty(dtrState) 0
set mcuTty(baudrate) 115200
set mcuTty(processData) ""
set mcuTty(cmdBuffer) ""
set mcuTty(commTimer) 0
set mcuTty(cacheTime_ms) 120000
set mcuTty(readWriteTimer) 6

set userPty(MasterFD) ""
set userPty(SlaveFD) ""
set userPty(SlaveLink) "/dev/null"
set userPty(hexdumpHex) ""
set userPty(hexdumpAscii) ""
set userPty(hexdumpLineAddr) 0; # the character number of the first column
set userPty(hexdumpLineCount) 0; # the current count of characters in a hexdump line
set userPty(hexdumpBlockBuffer) ""; # the buffer holding the data for the virtual file
set userPty(hexdumpMaxBlockLines) 64; # the maximum number of hexdump lines in the block buffer
set userPty(printHexdump) 0; # a flag indicating the output mode of the user terminal: 0 (output clear text), 1 (output hexdumped text)

#################
# procedures for executing effects of changes in the virtual file system
source basic-tree-ops.tcl

##########################
# the static part: a virtual file system
set basic_tree(/io/device/try_ttys) [dict create stat [dict create type "file" mode 0644 nlink 1 ctime [clock seconds] mtime [clock seconds]] getter getTryTTYs setter setTryTTYs truncate truncateTryTTYs]
set basic_tree(/io/device/tty) [dict create stat [dict create type "file" mode 0444 nlink 1 ctime [clock seconds] mtime [clock seconds]] getter getTTY]
set basic_tree(/io/device/baudrate) [dict create stat [dict create type "file" mode 0444 nlink 1 ctime [clock seconds] mtime [clock seconds]] getter getBaudrate]
set basic_tree(/io/device/rts) [dict create stat [dict create type "file" mode 0644 nlink 1 ctime [clock seconds] mtime [clock seconds]] getter getRtsState setter setRtsState]
set basic_tree(/io/device/dtr) [dict create stat [dict create type "file" mode 0644 nlink 1 ctime [clock seconds] mtime [clock seconds]] getter getDtrState setter setDtrState]
set basic_tree(/io/device/file_cache_time_ms) [dict create stat [dict create type "file" mode 0644 nlink 1 ctime [clock seconds] mtime [clock seconds]] getter getCacheTime setter setCacheTime]
set basic_tree(/io/device/rw_timer) [dict create stat [dict create type "file" mode 0644 nlink 1 ctime [clock seconds] mtime [clock seconds]] getter getXferTimer setter setXferTimer]
set basic_tree(/io/device) [dict create stat [dict create type "directory" mode 0555 nlink 2 ctime [clock seconds] mtime [clock seconds]]]
set basic_tree(/io/user/tty) [dict create stat [dict create type "link" mode 0777 nlink 1 ctime [clock seconds] mtime [clock seconds]] getter getUserPty]
set basic_tree(/io/user/hexdump) [dict create stat [dict create type "file" mode 0444 nlink 1 ctime [clock seconds] mtime [clock seconds]] getter readHexdump]
set basic_tree(/io/user/hexdump_to_tty) [dict create stat [dict create type "file" mode 0644 nlink 1 ctime [clock seconds] mtime [clock seconds]] getter getHexdumpPtyState setter setHexdumpPtyState]
set basic_tree(/io/user/hexdump_max_lines) [dict create stat [dict create type "file" mode 0644 nlink 1 ctime [clock seconds] mtime [clock seconds]] getter readMaxHexdumpLines setter setMaxHexdumpLines]
set basic_tree(/io/user) [dict create stat [dict create type "directory" mode 0555 nlink 2 ctime [clock seconds] mtime [clock seconds]]]
set basic_tree(/io) [dict create stat [dict create type "directory" mode 0555 nlink 4 ctime [clock seconds] mtime [clock seconds]]]
set basic_tree(/) [dict create stat [dict create type directory mode 0555 nlink 3 ctime [clock seconds] mtime [clock seconds]]]

#####################################################################
# a cache for the stat data of the MCU files, starts empty
set mcu_tree_cache(/mcu) [dict create type directory mode 0555 nlink 2 ctime [clock seconds] mtime [clock seconds]]
set mcu_tree_cache(dirty) 1

################################
# Routinen für die Kommunikation mit dem Terminal und dem ESP8266
source $PROGDIR/tty-proc.tcl

############################
# MCU-Meta-Operationen
source $PROGDIR/comm-timer.tcl

###################################
# FUSE+MCU File-/Dir-Operationen
source $PROGDIR/get-set-attr.tcl
source $PROGDIR/create-open.tcl
source $PROGDIR/read-dir.tcl
source $PROGDIR/statfs-proc.tcl
source $PROGDIR/read-file-proc.tcl
source $PROGDIR/write-file.tcl
source $PROGDIR/truncate-proc.tcl
source $PROGDIR/unlink-proc.tcl
source $PROGDIR/rename-proc.tcl

##################################################
# Configuration
source $PROGDIR/config-proc.tcl

##################################################
# Debug-Routinen
source $PROGDIR/debug-proc.tcl

proc printUSAGE {} {
  global configDir configFile tryTTYs mcuTty FUSEoptions mountpoint
  puts stderr "nodemcu-mount \[options\] mountpoint
    -C cfgDir       configuration directory (default $configDir)
    -c cfgFile      configuration file, can be absolute or is relative to '-C'
                    (default $configFile)
    -T list         comma separated list of TTYs to try to open for NodeMCU
                    (default [join $tryTTYs ","])
    -t /dev/ttyXXX  try this TTY first, maybe or not part of '-T'
                    (default $mcuTty(activeTTY))
    -b n            use baudrate n (default $mcuTty(baudrate))
    -o fuse-opt     set mount options for the FUSE mount, see mount.fuse(8),
                    the first '-o' resets the list of default FUSE options
                    (default: '$FUSEoptions')
    -h --help       print this help and exit
    mountpoint      where the VFS is mounted (default $mountpoint)
"
}

###############################
# System-Setup
proc pullarg {argvar {pos 0}} {
  upvar $argvar progargs
  set a [lindex $progargs $pos]
  set progargs [lreplace $progargs $pos $pos]

  return $a
}
set progargs $argv
set cfg [lsearch $progargs "-C"]
if {$cfg >= 0} {
  pullarg progargs $cfg
  set configDir [pullarg progargs $cfg]
  printDebugVars "opt -C" configDir
}

set cfg [lsearch $progargs "-c"]
if {$cfg >= 0} {
  pullarg progargs $cfg
  set configFile [pullarg progargs $cfg]
    printDebugVars "opt -c" configFile
}

readConfig

configureWith tryTTYs MCU ttyList
configureWith mcuTty(activeTTY) MCU activeTTY
configureWith mcuTty(baudrate) MCU baudrate
configureWith userPty(printHexdump) User printMcuHexdump
configureWith userPty(hexdumpMaxBlockLines) User McuHexdumpLines
configureWith mountpoint mountpoint

set uid [exec id -u]
set gid [exec id -g]

set FUSEoptions [list -o nonempty -o allow_other -o uid=$uid -o gid=$gid -o auto_cache -o max_read=256 -o max_write=256]
set customFUSEoptions 0

####################################################
# evaluate other start parameter
set printHelp 0
while {[llength $progargs] > 0} {
  # pull off the first arg
  set a [pullarg progargs]

  if {$a eq "-T"} {
    # set the TTY list
    set ttys [pullarg progargs]
    set tryTTYs [split $ttys ","]
    printDebugVars "opt -T" tryTTYs
  } elseif {($a eq "-h") || ($a eq "--help")} {
    set printHelp 1
    printDebugVars "opt $a" printHelp
  } elseif {$a eq "-t"} {
    # set the first TTY
    set mcuTty(activeTTY) [pullarg progargs]
    printDebugVars "opt -t" mcuTty(activeTTY) 
  } elseif {$a eq "-b"} {
    # set baudrate
    set number [pullarg progargs]
    if {$number in {150 300 600 1200 2400 4800 9600 14400 19200 38400 56700 115200 230400 460800 921600}} {
      set mcuTty(baudrate) $number
    } else {
      puts stderr "Baudrate: $number not found in list of valid baudrates"
    }
    printDebugVars "opt -b" number
  } elseif {$a eq "-o"} {
    if {!$customFUSEoptions} {
      set customFUSEoptions 1
      set FUSEoptions {}
    }
    lappend FUSEoptions -o [pullarg progargs]
    printDebugVars "opt -o" FUSEoptions
  } else {
    # an argument without switch is interpreted as the mount point
    set mountpoint $a
    printDebugVars "cmd arg" mountpoint
  }
}

if {$printHelp} {
  printUSAGE
  exit 0
}

if {![file exists $mountpoint]} {
  puts stderr "Mountpoint '$mountpoint' does not exist. Exiting..."
  exit 1
}

if {![file isdirectory $mountpoint]} {
  puts stderr "Mountpoint '$mountpoint' is no directory, not usable. Exiting..."
  exit 1
}

proc FuseDestroy {args} {
  global mountpoint

  exec -ignorestderr bash -c "for n in 1 2 3 4 5 6 7 8 9 10; do echo -ne .; fusermount -u [file normalize $mountpoint] && exit; sleep 2; done; echo 'you must unmount $mountpoint manually!'>&2"
  exit
}

signal trap SIGINT  FuseDestroy
signal trap SIGHUP  FuseDestroy
signal trap SIGTERM FuseDestroy
signal trap SIGQUIT FuseDestroy
signal trap SIGABRT FuseDestroy

searchPty
searchMCU
runCommTimeout

fuse create NodeMcuFuse -getattr Getattr -fgetattr Getattr -chmod Chmod -chown Chown -utimens Utimens -statfs Statfs -readdir Readdir -open Open -create Create -unlink UnlinkFile -rename Rename -read Read -readlink ReadLink -write WriteData -truncate TruncateFile
if {[catch {eval NodeMcuFuse $mountpoint $FUSEoptions} msg]} {
  puts stderr "Problem at mountpoint '$mountpoint': $msg"
  exit 1
}

set forever 0
vwait forever
