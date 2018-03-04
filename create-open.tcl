################
# Debugging
set procDebug(Open)                   0
set procDebug(Create)                 0
set procDebug(ReleaseFile)            0
set procDebug(cleanupCoCreateMcuFile) 0
set procDebug(coCreateMcuFile)        0
set procDebug(createMcuFile)          0

array set fileOpenCount {}

proc Open {context path fileinfo} {
  global basic_tree mcu_tree_cache fileOpenCount

  printDebugCallSite

  if {[string match "/mcu/*" $path]} {
    # check mcu_tree_cache
    checkMcuTreeCache
    set name [array names mcu_tree_cache -exact $path]

    if {[llength $name] == 0} {
      # nichts im mcu_tree_cache
      return -code error -errorcode [list POSIX ENOENT {}]
    }
    
    # TODO: there is room for improvement, so we could ask the MCU, if the file exists, if we want to replace the file list call (checkMcuTreeCache) from above
    
    # im MCU ist alles lesbar und schreibbar
    if {[llength [array name fileOpenCount -exact $path]] == 0} {
      set fileOpenCount($path) 0
    }
    incr fileOpenCount($path)
    return ;# must be explicit. if a number is returned, then it becomes the file descriptor.
  } else {
    set name [array names basic_tree -exact $path]
    if {[llength $name] == 0} {
      # nichts im basic_tree
      return -code error -errorcode [list POSIX ENOENT {}]
    }
  }

  # teste die Attribute aus dem basic_tree
  
  set opList $basic_tree($path)
  set flags [dict get $fileinfo flags]

  if {("RDWR" in $flags) && !([dict exists $opList getter] && [dict exists $opList setter])} {
    return -code error -errorcode [list POSIX EACCES {}]
  }

  if {("WRONLY" in $flags) && ![dict exists $opList setter]} {
    return -code error -errorcode [list POSIX EACCES {}]
  }

  if {("RDONLY" in $flags) && ![dict exists $opList getter]} {
    return -code error -errorcode [list POSIX EACCES {}]
  }

  if {[llength [array name fileOpenCount -exact $path]] == 0} {
    set fileOpenCount($path) 0
  }
  incr fileOpenCount($path)
  return ;# must be explicit. if a number is returned, then it becomes the file descriptor.
}

proc Create {context path fileinfo perm} {
  global basic_tree mcu_tree_cache fileOpenCount

  printDebugCallSite

  if {[string match "/mcu/*" $path]} {
    # check mcu_tree_cache
    checkMcuTreeCache
    set name [array names mcu_tree_cache -exact $path]

    if {[llength $name] == 0} {
      # make a 'touch' in MCU
      regsub "/mcu/" $path "" mcuPath
      createMcuFile $mcuPath
      dict set mcu_tree_cache(/mcu) mtime [clock seconds]; # TODO: handle NodeMCU images with subdirectories (FATFS) different, i.e. strip final path component and change mtime of resulting DIR
    } 
      
    # im MCU ist alles lesbar und schreibbar
    if {[llength [array name fileOpenCount -exact $path]] == 0} {
      set fileOpenCount($path) 0
    }
    incr fileOpenCount($path)
    return ;# must be explicit. if a number is returned, then it becomes the file descriptor.
  } else {
    set name [array names basic_tree -exact $path]
    if {[llength $name] == 0} {
      # nothing in basic_tree, do not allow creation
      return -code error -errorcode [list POSIX EACCES {}]
    }
  }

  # teste die Attribute aus dem basic_tree
  
  set opList $basic_tree($path)
  set flags [dict get $fileinfo flags]

  if {("RDWR" in $flags) && !([dict exists $opList getter] && [dict exists $opList setter])} {
    return -code error -errorcode [list POSIX EACCES {}]
  }

  if {("WRONLY" in $flags) && ![dict exists $opList setter]} {
    return -code error -errorcode [list POSIX EACCES {}]
  }

  if {("RDONLY" in $flags) && ![dict exists $opList getter]} {
    return -code error -errorcode [list POSIX EACCES {}]
  }

  if {[llength [array name fileOpenCount -exact $path]] == 0} {
    set fileOpenCount($path) 0
  }
  incr fileOpenCount($path)
  return ;# must be explicit. if a number is returned, then it becomes the file descriptor.
}

proc ReleaseFile {context path fileinfo} {
  global basic_tree mcu_tree_cache fileOpenCount

  printDebugCallSite

  if {[llength [array name fileOpenCount -exact $path]] > 0} {
    if {$fileOpenCount($path) > 0} {
      incr fileOpenCount($path) -1
    }
  }
  
  return
}

proc cleanupCoCreateMcuFile {oldName newName op} {
  global mcuTty
  
  printDebugCallSite
  
  if {$mcuTty(commTimer) <= 0} {
    set mcu_tree_cache(dirty) 1
    puts -nonewline $mcuTty(ttyFD) ";\r;\r;\r-- timeout create\r"
    flush $mcuTty(ttyFD)
  }
  
  printDebugVars "scheduling end of createFile"
  set mcuTty(processData) {}
}

proc coCreateMcuFile {path} {
  global mcuTty mcu_tree_cache
  
  printDebugCallSite

  set data ""
  set mcuTty(processData) [info coroutine]
  
  trace add command [info coroutine] delete cleanupCoCreateMcuFile
  
  if {![catch "flush $mcuTty(ttyFD)"]} {
  
    # repeat
    #  local fd=file.open('init.lua','a+'); 
    #  fd:close(); 
    #  print('CREATE DONE')
    # until true
    set stopString "CREATE DONE"
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
      
    set mcu_tree_cache(/mcu/$path) [dict create type "file" mode 0644 nlink 1 size 0 mtime [clock seconds] ctime [clock seconds]]

    if {![string match "> *" $data]} {
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

proc createMcuFile {path} {
  global mcuTty

  printDebugCallSite
  
  printDebugVars "waiting for createFile slot" mcuTty(processData)
  
  while {$mcuTty(processData) ne ""} {
    vwait mcuTty(processData)
  }

  coroutine processFileList coCreateMcuFile $path
  printDebugVars "waiting for end of createFile" mcuTty(processData)

  vwait mcuTty(processData)
  printDebugVars "reached end of createFile" mcuTty(processData)
}
