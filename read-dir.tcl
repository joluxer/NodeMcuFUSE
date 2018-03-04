################
# Debugging
set procDebug(Readdir_mcu)           0
set procDebug(Readdir_basic)         0
set procDebug(Readdir)               0
set procDebug(readMcuFiles)          0
set procDebug(coReadMcuFiles)        0
set procDebug(cleanupCoReadMcuFiles) 0

proc Readdir_mcu {context path fileinfo} {
  global mcu_tree_cache

  printDebugCallSite

  set subtree [array names mcu_tree_cache -glob "$path/?*"]
  set plen [string length $path]

  printDebugVars Subtree subtree

  set entries [list "." ".."]

  foreach entry $subtree {
    set entry [lindex [file split [string replace $entry 0 $plen]] 0]
    printDebugVars "'foreach entry'" entry
    if {[lsearch -exact $entries $entry] == -1} {
      lappend entries $entry
    }
  }

  printDebugVars Success entries

  return $entries
}

proc Readdir_basic {context path fileinfo} {
  global basic_tree

  printDebugCallSite

  set subtree {}
  set plen [string length $path]

  if {$path eq "/"} {
    set subtree [array names basic_tree -glob "/?*"]
    lappend subtree "/mcu"
    set plen 0
  } else {
    set subtree [array names basic_tree -glob "$path/?*"]
  }

  if {[llength $subtree] == 0} {
    printDebugVars "SubTree empty"
    return -code error -errorcode [list POSIX ENOENT {}]
  }

  printDebugVars Subtree subtree

  set entries [list "." ".."]

  foreach entry $subtree {
    set entry [lindex [file split [string replace $entry 0 $plen]] 0]
    printDebugVars "'foreach entry'" entry
    if {[lsearch -exact $entries $entry] == -1} {
      lappend entries $entry
    }
  }

  printDebugVars Success entries

  return $entries
}

proc Readdir {context path fileinfo} {
  global basic_tree mcu_tree_cache

  printDebugCallSite

  set subtree {}
  set plen [string length $path]

  if {$path eq "/"} {
    return [Readdir_basic $context $path $fileinfo]
  } elseif {[string match "/mcu*" $path]} {
    checkMcuTreeCache
    return [Readdir_mcu $context $path $fileinfo]
  } else {
    return [Readdir_basic $context $path $fileinfo]
  }
}

proc ReadLink {context path} {
  global basic_tree

  printDebugCallSite

  set name [array names basic_tree -exact $path]

  if {[llength $name] == 0} {
    return -code error -errorcode [list POSIX ENOENT {}]
  }

  set opList $basic_tree($path)

  set stat [dict get $opList stat]
  if {[dict get $stat type] eq "link"} {
    set getter [dict get $opList getter]
    set data [$getter]

    return $data
  } else {
    return -code error -errorcode [list POSIX EACCES {}]
  }
}

proc checkMcuTreeCache {} {
  global mcu_tree_cache

  if {$mcu_tree_cache(dirty)} {
    readMcuFiles
  }
}

proc cleanupCoReadMcuFiles {oldName newName op} {
  global mcu_tree_cache mcuTty
  
  printDebugCallSite

  if {$mcuTty(commTimer) > 0} {
    set mcu_tree_cache(dirty) 0
    after $mcuTty(cacheTime_ms) {set mcu_tree_cache(dirty) 1}
  } else {
    set mcu_tree_cache(dirty) 1
    puts -nonewline $mcuTty(ttyFD) ";\r;\r;\r-- timeout readdir\r"
    flush $mcuTty(ttyFD)
  }
    
  printDebugVars "scheduling end of processFileList"
  set mcuTty(processData) {}
}

proc coReadMcuFiles {} {
  global mcuTty mcu_tree_cache

  printDebugCallSite
  
  set mcuTty(processData) [info coroutine]
  trace add command [info coroutine] delete cleanupCoReadMcuFiles
  restartCommTimeout 3

  set data ""
  array unset mcu_tree_cache /mcu/*
  set mcu_tree_cache(dirty) 1
  
  if {![catch {flush $mcuTty(ttyFD)}]} {
    # TODO: NodeMCU's mit FATFS-Modul (also mehreren Unterverzeichnissen) anders behandeln
    # repeat
    #  local t=file.list()
    #  local l={}
    #  for f,s in pairs(t) do
    #   table.insert(l,string.format("'%s'\t'%d'",f,s))
    #  end
    #  print(string.format('Filelist %04d', #l))
    #  for _,f in ipairs(l) do print(f) end
    # until true
    set txCmds {}
    lappend txCmds "pcall(function()"
    lappend txCmds "local t=file.list()"
    lappend txCmds "local l={}"
    lappend txCmds "for f,s in pairs(t) do"
    lappend txCmds "table.insert(l,string.format(\"'%s'\t'%d'\",f,s))"
    lappend txCmds "end"
    lappend txCmds "uart.write(0, string.format('Filelist %04d\\r\\n', #l))"
    lappend txCmds "for _,f in ipairs(l) do uart.write(0, f, '\\r\\n') end"
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
    
    set matchString "*Filelist \[0-9\]\[0-9\]\[0-9\]\[0-9\]\r\n*"

    printDebugVars "waiting for length data"
    restartCommTimeout 3
    set data [yield]
    # Datenverarbeitung
    # echo übergehen, auf Tabellenstart warten
    while {![string match $matchString $data]} {
      printDebugVars "collecting length data" data
      set datLen [string length $data]
      if {$datLen > 20} {
        set data [string replace $data 0 [expr $datLen - 21]]
      }
      restartCommTimeout 3
      append data [yield ""]
    }

    set cutEnd [expr [string last "Filelist " $data] - 1]
    set data [string replace $data 0 $cutEnd]
    printDebugVars "cutting data" cutEnd data

    # Zeilenanzahl lesen
    if {[scan $data "Filelist %d\r\n%n" tableLength nextData] == 2} {
      set data [string range $data $nextData end]
      printDebugVars "list length" tableLength data

      set fileDict {}

      # Tabellenzeilen einlesen
      for {set i 0} {$i < $tableLength} {incr i} {
        while 1 {
          restartCommTimeout 3
          append data [yield ""]

          set snum [scan $data " '%\[^\r\n\t'\]' '%d'%*\[\r\]%*\[\n\]%n" filename filesize nextData]
          printDebugVars "collecting data" data snum

          if {$snum == 3} {
            set data [string range $data $nextData end]
            printDebugVars "table line" filename filesize
            dict set fileDict $filename $filesize
            break
          }
        }
      }

      if {$tableLength} {
        # Tabellenzeilen interpretieren
        # TODO: NodeMCU's mit FATFS-Modul (also mehreren Unterverzeichnissen) anders behandeln
        printDebugVars "file dict" fileDict

        dict for {filename filesize} $fileDict {
          printDebugVars "filling mcu_tree_cache" filename filesize
          set mcu_tree_cache(/mcu/$filename) [dict create type "file" mode 0644 nlink 1 size $filesize mtime [clock seconds] ctime [clock seconds]]
        }
      }
      dict set mcu_tree_cache(/mcu) mtime [clock seconds]
    }

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

proc readMcuFiles {} {
  global mcuTty

  printDebugCallSite
  
  printDebugVars "waiting for processFileList slot" mcuTty(processData)

  while {($mcuTty(processData) ne "") && ($mcuTty(processData) ne "::processFileList")} {
    vwait mcuTty(processData)
  }

  if {$mcuTty(processData) eq ""} {
    coroutine processFileList coReadMcuFiles
  }

  printDebugVars "waiting for end of processFileList" mcuTty(processData)

  if {$mcuTty(processData) ne ""} then {
    vwait mcuTty(processData)
  }
  printDebugVars "reached end of processFileList" mcuTty(processData)
}
