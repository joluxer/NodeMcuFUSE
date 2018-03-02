################
# Debugging
set procDebug(Rename_mcu)             0
set procDebug(Rename)                 0
set procDebug(cleanupCoRenameMcuFile) 0
set procDebug(coRenameMcuFile)        0
set procDebug(renameMcuFile)          0

proc Rename_mcu {context path newpath} {
  global mcu_tree_cache
  
  printDebugCallSite

  set name [array names mcu_tree_cache -exact $path]

  set stat $mcu_tree_cache($path)
  
  if {[dict get $stat type] eq "file"} {
    regsub "/mcu/" $path "" mcuPath
    regsub "/mcu/" $newpath "" mcuNewPath

    renameMcuFile $mcuPath $mcuNewPath
  } else {
    return -code error -errorcode [list POSIX EACCES {}]
  }

  return 
}

proc Rename {context path newpath} {
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
    Rename_mcu $context $path $newpath
  } else {
    # check basic_tree
    return -code error -errorcode [list POSIX EROFS {}]
  }

  return
}

proc cleanupCoRenameMcuFile {oldName newName op} {
  global mcuTty
  
  printDebugCallSite

  if {$mcuTty(commTimer) <= 0} {
    set mcu_tree_cache(dirty) 1
    puts -nonewline $mcuTty(ttyFD) ";\r;\r;\r-- timeout rename\r"
    flush $mcuTty(ttyFD)
  }
  
  printDebugVars "scheduling end of unlinkFile"
  set mcuTty(processData) {}
}

proc coRenameMcuFile {path newpath} {
  global mcuTty mcu_tree_cache
  
  printDebugCallSite

  set data ""
  set mcuTty(processData) [info coroutine]
  
  trace add command [info coroutine] delete cleanupCoRenameMcuFile
  
  if {![catch "flush $mcuTty(ttyFD)"]} {
  
    # repeat
    #  file.rename('init.lua','oldinit.lua'); 
    #  print('RENAME DONE')
    # until true
    set stopString "RENAME DONE"
    set txCmds {}
    lappend txCmds "repeat"
    lappend txCmds "if file.exists('$newpath') then"
    lappend txCmds "file.remove('$newpath')"
    lappend txCmds "end"
    lappend txCmds "file.rename('$path','$newpath')"
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
    
    set mcu_tree_cache(/mcu/$newpath) $mcu_tree_cache(/mcu/$path)
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

proc renameMcuFile {path newpath} {
  global mcuTty

  printDebugCallSite
  
  printDebugVars "waiting for unlinkFile slot" mcuTty(processData)
  
  while {$mcuTty(processData) ne ""} {
    vwait mcuTty(processData)
  }

  coroutine processFileList coRenameMcuFile $path $newpath
  printDebugVars "waiting for end of unlinkFile" mcuTty(processData)

  if {$mcuTty(processData) ne ""} then {
    vwait mcuTty(processData)
  }
  printDebugVars "reached end of unlinkFile" mcuTty(processData)
}
