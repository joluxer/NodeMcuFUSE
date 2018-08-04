################
# Debugging
set procDebug(Statfs)                 0
set procDebug(readMcuFsinfo)          0
set procDebug(coReadMcuFsinfo)        0
set procDebug(cleanupCoReadMcuFsinfo) 0

###############################
# VFS infos about distinct subdirs
set vfsinfo(/) [dict create statvfs [dict create bsize 0 frsize 0 blocks 0 bfree 0 bavail 0 files 0 ffree 0 favail 0 fsid 0 flag 0 namemax 255]]
set vfsinfo(/mcu) [dict create statvfs [dict create bsize 1 frsize 1 blocks 0 bfree 0 bavail 0 files 1024 ffree 0 favail 0 fsid 0 flag 0 namemax 255] updater readMcuFsinfo]

proc Statfs {context path} {
  global basic_tree vfsinfo

  printDebugCallSite
  
  # shorten the path step by step, until a match in the vfsinfo is found
  set path_list [file split $path]
  while 1 {
    set chkpath [file normalize [eval file join $path_list]]
    printDebugVars "" chkpath
    if {[llength [array names vfsinfo -exact $chkpath]] == 1} {
      set path $chkpath
      break
    }
    # remove last element
    set path_list [lreplace $path_list end end]
    if {[llength $path_list] == 0} {
      # nothing in mcu_tree_cache
      return -code error -errorcode [list POSIX ENOENT {}]
    }
  }
  
  if {[dict exists $vfsinfo($path) updater]} {
    set updater [dict get $vfsinfo($path) updater]
    printDebugVars "calling updater" path updater
    $updater $path
  }
  
  return [dict get $vfsinfo($path) statvfs]
}

proc cleanupCoReadMcuFsinfo {oldName newName op} {
  global mcuTty
  
  printDebugCallSite
  
  if {$mcuTty(commTimer) <= 0} {
    set mcu_tree_cache(dirty) 1
    puts -nonewline $mcuTty(ttyFD) ";\r;\r;\r-- timeout fsinfo\r"
    flush $mcuTty(ttyFD)
  }
  
  printDebugVars "scheduling end of processFsinfo"
  set mcuTty(processData) {}
}

proc coReadMcuFsinfo {path} {
  global mcuTty vfsinfo

  printDebugCallSite

  set mcuTty(processData) [info coroutine]
  
  set data ""
  
  trace add command [info coroutine] delete cleanupCoReadMcuFsinfo

  if {![catch "flush $mcuTty(ttyFD)"]} {
    # TODO: NodeMCU's mit FATFS-Modul anders behandeln, weil evtl. andere Einheiten (kBytes) zurückgegeben werden
    set startString "FSINFO BEGIN"
    set stopString "FSINFO DONE"
    set txCmds {}
    lappend txCmds "pcall(function()"
    lappend txCmds "print('$startString')"
    lappend txCmds "print(file.fsinfo())"
    lappend txCmds "print('$stopString')"
    lappend txCmds "end)"

    set cnt [llength $txCmds]
    foreach cmd $txCmds {
      puts -nonewline $mcuTty(ttyFD) "$cmd\r\n"
      flush $mcuTty(ttyFD)
      incr cnt -1
      
      printDebugVars "sent cmd" cmd
      if {$cnt == 0} {
        break
      }
      printDebugVars "waiting for intermediate prompt" data
            
      restartCommTimeout 3
      append data [yield ""]
      
      while {![string match "*> " $data]} {
        restartCommTimeout 3
        append data [yield ""]
        printDebugVars "waiting for intermediate prompt (while)" data
      }
    }
    
    # Datenverarbeitung
    # echo übergehen, auf Datenstart warten
    while {![string match "*$startString\r\n*" $data]} {
      printDebugVars "skipping echo for data begin" data
      set datLen [string length $data]
      if {$datLen > 20} {
        set data [string replace $data 0 [expr $datLen - 21]]
      }
      restartCommTimeout 3
      append data [yield ""]
    }
    
    set cutEnd [expr [string last "$startString\r\n" $data] + [string length $startString] + 2 ]
    set data [string replace $data 0 $cutEnd]
    printDebugVars "cutting data" cutEnd data
    
    while 1 {
      set dataend [expr [string last "\r\n$stopString\r\n" $data] - 1]
      printDebugVars "collecting data" data dataend

      if {$dataend >= 0} {
        set fsinfodata [string range $data 0 $dataend]
        incr dataend [string length $stopString]
        incr dataend 5
        set data [string range $data $dataend end]
        printDebugVars "fsinfo data" fsinfodata
        scan $fsinfodata " %u %u %u" freebytes usedbytes totalbytes
        printDebugVars "fsinfo value" freebytes usedbytes totalbytes
        
        # filedata an Aufrufer exportieren via upvar
        dict set vfsinfo($path) statvfs bsize 1
        dict set vfsinfo($path) statvfs blocks $totalbytes
        dict set vfsinfo($path) statvfs bfree $freebytes
        dict set vfsinfo($path) statvfs bavail $freebytes
        
        break
      }

      restartCommTimeout 3
      append data [yield ""]
    }

    if {![string match "> *" $data]} {
      printDebugVars "try to catch final prompt" data
      # try to catch the final prompt
      after 100
      restartCommTimeout 3
      append data [yield ""]
    }
  }
  
  # try to consume the final prompt to not to clutter the user's terminal experience
  if {[string match "> *" $data]} {
    set data [string replace $data 0 1]
  }

  return $data
}

proc readMcuFsinfo {path} {
  global mcuTty mcu_tree_cache vfsinfo

  printDebugCallSite
  
  checkMcuTreeCache
  set filecount [llength [array names mcu_tree_cache "/mcu/*"]]
  dict set vfsinfo($path) statvfs ffree [expr 1024 - $filecount]
  dict set vfsinfo($path) statvfs favail 8

  printDebugVars "waiting for processFsinfo slot" mcuTty(processData)

  while {($mcuTty(processData) ne "") && ($mcuTty(processData) ne "::processFileList")} {
    vwait mcuTty(processData)
  }

  if {$mcuTty(processData) eq ""} {
    coroutine processFileList coReadMcuFsinfo $path
  }

  printDebugVars "waiting for end of processFsinfo" mcuTty(processData)

  if {$mcuTty(processData) ne ""} then {
    vwait mcuTty(processData)
  }
  printDebugVars "reached end of processFsinfo" mcuTty(processData)
}
