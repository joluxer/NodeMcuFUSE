################
# Debugging
set procDebug(Unlink_mcu)             0
set procDebug(UnlinkFile)             0
set procDebug(cleanupCoUnlinkMcuFile) 0
set procDebug(coUnlinkMcuFile)        0
set procDebug(unlinkMcuFile)          0

proc Unlink_mcu {context path} {
  global mcu_tree_cache
  
  printDebugCallSite

  set name [array names mcu_tree_cache -exact $path]

  set stat $mcu_tree_cache($path)
  
  if {[dict get $stat type] eq "file"} {
    regsub "/mcu/" $path "" mcuPath

    unlinkMcuFile $mcuPath
  } else {
    return -code error -errorcode [list POSIX EACCES {}]
  }

  return 
}

proc UnlinkFile {context path} {
  global basic_tree mcu_tree_cache

  printDebugCallSite

  if {[llength [array names fileOpenCount $path]] > 0} {
    if {$fileOpen($path) > 0} {
      # file in use
      return -code error -errorcode [list POSIX EBUSY {}]
    }
  }
  
  if {[string match "/mcu/*" $path]} {
    # check mcu_tree_cache
    checkMcuTreeCache
    set name [array names mcu_tree_cache -exact $path]
    
    if {[llength $name] == 0} {
      # nichts im mcu_tree_cache
      return -code error -errorcode [list POSIX ENOENT {}]
    }
    
    # work on MCU data
    Unlink_mcu $context $path
  } else {
    # check basic_tree
    return -code error -errorcode [list POSIX EROFS {}]
  }

  return
}

proc cleanupCoUnlinkMcuFile {oldName newName op} {
  global mcuTty
  
  printDebugCallSite
  
  if {$mcuTty(commTimer) <= 0} {
    set mcu_tree_cache(dirty) 1
    puts -nonewline $mcuTty(ttyFD) ";\r;\r;\r-- timeout unlink\r"
    flush $mcuTty(ttyFD)
  }
  
  printDebugVars "scheduling end of unlinkFile"
  set mcuTty(processData) {}
}

proc coUnlinkMcuFile {path} {
  global mcuTty mcu_tree_cache
  
  printDebugCallSite

  set data ""
  set mcuTty(processData) [info coroutine]
  
  trace add command [info coroutine] delete cleanupCoUnlinkMcuFile
  
  if {![catch "flush $mcuTty(ttyFD)"]} {
  
    # repeat
    #  file.remove('init.lua'); 
    #  print('UNLINK DONE')
    # until true
    set stopString "UNLINK DONE"
    set txCmds {}
    lappend txCmds "repeat"
    lappend txCmds "file.remove('$path')"
    lappend txCmds "print('$stopString')"
    lappend txCmds "until true"

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
    # echo übergehen, auf Ende-Meldung warten
    while 1 {
      restartCommTimeout 3
      append data [yield ""]

      set dataend [string last "$stopString\r\n" $data]
      
      printDebugVars "skipping echo for data end" data dataend
  
      if {$dataend >= 0} {
        incr dataend [string length $stopString]
        incr dataend 2
        set data [string range $data $dataend end]
        
        break
      }
      
      set datLen [string length $data]
      if {$datLen > 20} {
        set data [string replace $data 0 [expr $datLen - 21]]
      }
    }
    
    array unset mcu_tree_cache /mcu/$path
    dict set mcu_tree_cache(/mcu) mtime [clock seconds]

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

proc unlinkMcuFile {path} {
  global mcuTty

  printDebugCallSite
  
  printDebugVars "waiting for unlinkFile slot" mcuTty(processData)
  
  while {$mcuTty(processData) ne ""} {
    vwait mcuTty(processData)
  }

  coroutine processFileList coUnlinkMcuFile $path
  printDebugVars "waiting for end of unlinkFile" mcuTty(processData)

  if {$mcuTty(processData) ne ""} then {
    vwait mcuTty(processData)
  }
  printDebugVars "reached end of unlinkFile" mcuTty(processData)
}
