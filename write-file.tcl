################
# Debugging
set procDebug(Write_mcu)                 0
set procDebug(Write_basic)               0
set procDebug(WriteData)                 0
set procDebug(writeMcuFileData)          0
set procDebug(coWriteMcuFileData)        0
set procDebug(cleanupCoWriteMcuFileData) 0

proc Write_mcu {context path fileinfo data offset} {
  global mcu_tree_cache

  printDebugCallSite

  set stat $mcu_tree_cache($path)

  if {[dict get $stat type] eq "file"} {
    set fileSize [dict get $stat size]
    
    if {$offset <= $fileSize} {
      regsub "/mcu/" $path "" mcuPath
      writeMcuFileData $mcuPath $data $offset
      return [string length $data]
    }
  } else {
    return -code error -errorcode [list POSIX EACCES {}]
  }

  return 0
}

proc Write_basic {context path fileinfo data offset} {
  global basic_tree

  printDebugCallSite

  set opList $basic_tree($path)

  if {[dict get $opList stat type] eq "file"} {
    if {[dict exists $opList getter]} {
      set getter [dict get $opList getter]
      set setter [dict get $opList setter]
      set filedata [$getter]
      set filelen [string length $filedata]
      set datalen [string length $data]

      printDebugVars "checking write pos" offset filelen
      
      if {$offset >= $filelen} {
        set cnt [expr $offset - $filelen + 1]
        printDebugVars "appendig dummy data" offset filelen cnt
        append filedata [string repeat " " $cnt]
        incr filelen $cnt
      }
      
      if {$offset < $filelen} {
        set end_ [expr $offset + $datalen - 1]
        printDebugVars "replacing data" filedata offset end_ data
        set newdata [string replace $filedata $offset $end_ $data]
        if {[$setter $newdata]} {
          dict set basic_tree($path) stat mtime [clock seconds]
          return $datalen
        } else {
          return -code error -errorcode [list POSIX EACCES {}]
        }
      }
    } else {
      set setter [dict get $opList setter]
      dict set basic_tree($path) stat mtime [clock seconds]
      return [$setter $data $offset]
    }
  } else {
    return -code error -errorcode [list POSIX EACCES {}]
  }

  return 0
}

proc WriteData {context path fileinfo data offset} {
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

    # write data to the mcu_tree_cache
    return [Write_mcu $context $path $fileinfo $data $offset]
  } else {
    # check basic_tree
    set name [array names basic_tree -exact $path]

    if {[llength $name] == 0} {
        return -code error -errorcode [list POSIX ENOENT {}]
    }
    # write data to the basic_tree
    return [Write_basic $context $path $fileinfo $data $offset]
  }
  
  return -code error -errorcode [list POSIX ENOENT {}]
}

proc cleanupCoWriteMcuFileData {oldName newName op} {
  global mcuTty
  
  printDebugCallSite
  
  if {$mcuTty(commTimer) <= 0} {
    set mcu_tree_cache(dirty) 1
    puts -nonewline $mcuTty(ttyFD) ";\r;\r;\r-- timeout write\r"
    flush $mcuTty(ttyFD)
  }
  
  printDebugVars "scheduling end of writeFileData"
  set mcuTty(processData) {}
}

proc coWriteMcuFileData {path filedata offset} {
  global mcuTty mcu_tree_cache
  
  printDebugCallSite

  set data ""
  set mcuTty(processData) [info coroutine]
  
  trace add command [info coroutine] delete cleanupCoWriteMcuFileData
  
  if {![catch "flush $mcuTty(ttyFD)"]} {
  
    set hexdata [binary encode hex $filedata]
    printDebugVars "prepared" hexdata
    set chunkoffset $offset
    
    # now send in slices of 32 bytes to avoid overflow of the MCU input buffer
    
    while {[string length $hexdata]} {
      set chunkdata1 [string range $hexdata 0 63]; # this is hexdump data, so for slices of 32 use 64 characters
      set chunkdata2 [string range $hexdata 64 127]; # this is hexdump data, so for slices of 32 use 64 characters
      set chunkdata3 [string range $hexdata 128 191]; # this is hexdump data, so for slices of 32 use 64 characters
      set chunkdata4 [string range $hexdata 192 255]; # this is hexdump data, so for slices of 32 use 64 characters
      printDebugVars "prepared (while)" chunkoffset
      printDebugVars "prepared (while)" chunkdata1 chunkdata2 chunkdata3 chunkdata4

      # repeat
      #  tmr.register(6,20,tmr.ALARM_SINGLE,function() print('UPLOAD END') end)
      #  local fd=file.open('init.lua','r+'); 
      #  fd:seek('set', 0); 
      #  local chunk = [===[2d2d2048616c6c6f2057656c74210a]===]"; -- "-- Hallo Welt!\n"
      #  chunk:gsub('[0-9A-Fa-f][0-9A-Fa-f]',function (s) fd:write(string.char(tonumber('0x'..s))) end); 
      #  fd:close(); 
      #  tmr.start(6);
      # until true
      set stopString "UPLOAD DONE"
      set txCmds {}
      lappend txCmds "pcall(function()"
      lappend txCmds "tmr.register($mcuTty(readWriteTimer),100,tmr.ALARM_SINGLE,function() print('$stopString') end)"
      lappend txCmds "local fd=file.open('$path','r+')"
      lappend txCmds "fd:seek('set',$chunkoffset)"
      lappend txCmds "local chunk=\[===\[$chunkdata1"
      lappend txCmds "$chunkdata2"
      lappend txCmds "$chunkdata3"
      lappend txCmds "$chunkdata4\]===\]"
      lappend txCmds "chunk:gsub('%s*(\[0-9A-Fa-f\]\[0-9A-Fa-f\])',function (s) fd:write(string.char(tonumber('0x'..s))) end)"
      lappend txCmds "fd:close()"
      lappend txCmds "tmr.start($mcuTty(readWriteTimer))"
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
        printDebugVars "waiting for intermediate prompt (pre while)" data
        
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
      
      set hexdata [string replace $hexdata 0 255]; # remove the sent part and go over
      incr chunkoffset 128
      printDebugVars "chopped (while)" hexdata chunkoffset
    }
    set xfersize [string length $filedata]
    set oldfilesize [dict get $mcu_tree_cache(/mcu/$path) size]
    set xferend [expr $offset + $xfersize]
    printDebugVars "size calculation" xfersize oldfilesize xferend
    if {$xferend > $oldfilesize} {
      dict set mcu_tree_cache(/mcu/$path) size $xferend
    }
    dict set mcu_tree_cache(/mcu/$path) mtime [clock seconds]
    
    #~ if {![string match "> *" $data]} {
      #~ # try to catch the final prompt
      #~ after 100
      #~ restartCommTimeout 3
      #~ append data [yield ""]
    #~ }
  }

  # try to consume the final prompt to not to clutter the user terminal experience
  if {[string match "> *" $data]} {
    set data [string replace $data 0 1]
  }

  return $data
}

proc writeMcuFileData {path data offset} {
  global mcuTty mcu_file_chunk
  
  printDebugCallSite
  
  printDebugVars "waiting for writeFileData slot" mcuTty(processData)
  
  while {$mcuTty(processData) ne ""} {
    vwait mcuTty(processData)
  }
  
  coroutine processFileList coWriteMcuFileData $path $data $offset
  printDebugVars "waiting for end of writeFileData" mcuTty(processData)

  if {$mcuTty(processData) ne ""} then {
    vwait mcuTty(processData)
  }
  printDebugVars "reached end of writeFileData" mcuTty(processData)

  return
}
