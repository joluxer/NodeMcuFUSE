################
# Debugging
set procDebug(Truncate_mcu)             0
set procDebug(FtruncateFile)            0
set procDebug(TruncateFile)             0
set procDebug(cleanupCoTruncateMcuFile) 0
set procDebug(coTruncateMcuFile)        0
set procDebug(truncateMcuFile)          0

proc Truncate_mcu {context path} {
  global mcu_tree_cache
  
  printDebugCallSite

  set name [array names mcu_tree_cache -exact $path]

  set stat $mcu_tree_cache($path)
  
  if {[dict get $stat type] eq "file"} {
    regsub "/mcu/" $path "" mcuPath

    truncateMcuFile $mcuPath
  } else {
    return -code error -errorcode [list POSIX EACCES {}]
  }

  return 
}

proc FtruncateFile {context path fileinfo size} {
  global basic_tree mcu_tree_cache

  printDebugCallSite

  if {[string match "/mcu/*" $path]} {
    # check mcu_tree_cache
    checkMcuTreeCache
    set name [array names mcu_tree_cache -exact $path]
    
    if {[llength $name] == 0} {
      # nichts im mcu_tree_cache
      return -code error -errorcode [list POSIX ENOENT {}]
    }
    
    # truncate(n) for n>0 is invalid
    if {$size != 0} {
      # nichts im mcu_tree_cache
      return -code error -errorcode [list POSIX EINVAL {}]
    }

    # work on MCU data
    Truncate_mcu $context $path
  } else {
    # check basic_tree
    set name [array names basic_tree -exact $path]

    if {[llength $name] == 0} {
        return -code error -errorcode [list POSIX ENOENT {}]
    }
    # work on basic_tree
    set opList $basic_tree($path)
  
    if {[dict get $opList stat type] eq "file"} {
      if {[dict exists $opList truncate]} {
        set truncate [dict get $opList truncate]
  
        $truncate $size
      }
    } else {
      return -code error -errorcode [list POSIX EACCES {}]
    }
    
    dict set basic_tree($path) stat mtime [clock seconds]
  }

  return
}

proc TruncateFile {context path size} {
  printDebugCallSite

  FtruncateFile $context $path {} $size
}

proc cleanupCoTruncateMcuFile {oldName newName op} {
  global mcuTty
  
  printDebugCallSite
  
  if {$mcuTty(commTimer) <= 0} {
    set mcu_tree_cache(dirty) 1
    puts -nonewline $mcuTty(ttyFD) ";\r;\r;\r-- timeout truncate\r"
    flush $mcuTty(ttyFD)
  }
  
  printDebugVars "scheduling end of truncateFile"
  set mcuTty(processData) {}
}

proc coTruncateMcuFile {path} {
  global mcuTty mcu_tree_cache
  
  printDebugCallSite

  set data ""
  set mcuTty(processData) [info coroutine]
  
  trace add command [info coroutine] delete cleanupCoTruncateMcuFile
  
  if {![catch "flush $mcuTty(ttyFD)"]} {
  
    # repeat
    #  local fd=file.open('init.lua','w'); 
    #  fd:close(); 
    #  print('TRUNC DONE')
    # until true
    set stopString "TRUNC DONE"
    set txCmds {}
    lappend txCmds "pcall(function()"
    lappend txCmds "local fd=file.open('$path','w')"
    lappend txCmds "fd:close()"
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
    # echo übergehen, auf Ende-Meldung warten
    while 1 {
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

      restartCommTimeout 3
      append data [yield ""]
    }
    
    dict set mcu_tree_cache(/mcu/$path) size 0
    dict set mcu_tree_cache(/mcu/$path) mtime [clock seconds]

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

proc truncateMcuFile {path} {
  global mcuTty

  printDebugCallSite
  
  printDebugVars "waiting for truncateFile slot" mcuTty(processData)
  
  while {$mcuTty(processData) ne ""} {
    vwait mcuTty(processData)
  }

  coroutine processFileList coTruncateMcuFile $path
  printDebugVars "waiting for end of truncateFile" mcuTty(processData)

  if {$mcuTty(processData) ne ""} then {
    vwait mcuTty(processData)
  }
  printDebugVars "reached end of truncateFile" mcuTty(processData)
}
