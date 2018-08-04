################
# Debugging
set procDebug(Read_mcu)                 0
set procDebug(Read_basic)               0
set procDebug(Read)                     0
set procDebug(readMcuFileData)          0
set procDebug(coReadMcuFileData)        0
set procDebug(cleanupCoReadMcuFileData) 0

array set mcu_file_chunk {}

proc Read_mcu {context path fileinfo size offset} {
  global mcu_tree_cache

  printDebugCallSite

  set stat $mcu_tree_cache($path)

  if {[dict get $stat type] eq "file"} {
    set fileSize [dict get $stat size]

    if {$offset < $fileSize} {
      regsub "/mcu/" $path "" path
      set data [readMcuFileData $path $size $offset]
      return $data
    }
  } else {
    return -code error -errorcode [list POSIX EACCES {}]
  }

  return ""
}

proc Read_basic {context path fileinfo size offset} {
  global basic_tree

  printDebugCallSite

  set name [array names basic_tree -exact $path]

  if {[llength $name] == 0} {
    return -code error -errorcode [list POSIX ENOENT {}]
  }

  set opList $basic_tree($path)

  if {[dict get $opList stat type] eq "file"} {
    set getter [dict get $opList getter]
    set data [$getter]
    set len [string length $data]

    if {$offset < $len} {
      set end_ [expr $offset + $size - 1]
      return [string range $data $offset $end_]
    }
  } else {
    return -code error -errorcode [list POSIX EACCES {}]
  }

  return
}

proc Read {context path fileinfo size offset} {
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

    # gib die Daten aus dem mcu_tree_cache
    return [Read_mcu $context $path $fileinfo $size $offset]
  } else {
    # check basic_tree
    set name [array names basic_tree -exact $path]

    if {[llength $name] == 0} {
        return -code error -errorcode [list POSIX ENOENT {}]
    }
    # gib die Daten aus dem basic_tree
    return [Read_basic $context $path $fileinfo $size $offset]
  }

  return -code error -errorcode [list POSIX ENOENT {}]
}

proc cleanupCoReadMcuFileData {oldName newName op} {
  global mcuTty

  printDebugCallSite

  if {$mcuTty(commTimer) <= 0} {
    set mcu_tree_cache(dirty) 1
    puts -nonewline $mcuTty(ttyFD) ";\r;\r;\r-- timeout read\r"
    flush $mcuTty(ttyFD)
    printDebugVars "RX timeout of processFileData"
  }

  printDebugVars "scheduling end of processFileData"
  set mcuTty(processData) {}
}

proc coReadMcuFileData {path size offset} {
  global mcuTty userPty mcu_file_chunk

  printDebugCallSite

  set data ""
  set mcuTty(processData) [info coroutine]
  set mcu_file_chunk("${path}_${offset}_${size}") {}

  trace add command [info coroutine] delete cleanupCoReadMcuFileData

  if {![catch "flush $mcuTty(ttyFD)"]} {

    set startString "DUMP BEGIN\r\n"
    set stopString "\r\nDUMP END"

    # repeat
    #  local fd=file.open('init.lua','r');
    #  fd:seek('set', 0)
    #  local i=55
    #  local startstring='DUMP BEGIN\r\n'
    #  tmr.register(6,125,tmr.ALARM_AUTO,function()
    #   if startstring ~= nil then uart.write(0,startstring); startstring=nil end
    #   local chunk = fd:read(math.min(32, i))
    #   if chunk ~= nil then
    #    chunk:gsub('.', function (c) uart.write(0, string.format('%02X',string.byte(c))) end)
    #   end
    #   i=i-32
    #   if i <= 1 then
    #    tmr.unregister(6)
    #    fd:close();
    #    uart.write(0,'\r\nDUMP END')
    #   end
    #  end)
    #  tmr.start(6)
    # until true
    set txCmds {}
    lappend txCmds "coll={};node.output(function(str) table.insert(coll, str) end)"
    lappend txCmds "pcall(function() local fd=file.open('$path','r')"
    lappend txCmds "fd:seek('set',$offset)"
    lappend txCmds "local i=$size"
    lappend txCmds "local startstring='[string map {\r "\\r" \n "\\n"} $startString]'"
    lappend txCmds "tmr.register($mcuTty(readWriteTimer),120,tmr.ALARM_AUTO,function()"
    lappend txCmds "if startstring ~= nil then uart.write(0,startstring); startstring=nil end"
    lappend txCmds "local chunk=fd:read(math.min(32,i))"
    lappend txCmds "if chunk ~= nil then"
    lappend txCmds "chunk:gsub('.',function (c) uart.write(0,string.format('%02X',string.byte(c))) end)"
    lappend txCmds "i=i-32"
    lappend txCmds "else i=0"
    lappend txCmds "end"
    lappend txCmds "if i <= 1 then"
    lappend txCmds "uart.write(0,'[string map {\r "\\r" \n "\\n"} $stopString]')"
    lappend txCmds "tmr.unregister($mcuTty(readWriteTimer))"
    lappend txCmds "fd:close()"
    lappend txCmds "node.output(nil)"
    lappend txCmds "uart.write(0,table.concat(coll, ''))"
    lappend txCmds "coll=nil"
    lappend txCmds "end"
    lappend txCmds "end)"
    lappend txCmds "tmr.start($mcuTty(readWriteTimer))"
    lappend txCmds "end)"

    after 100

    if {$userPty(atPrompt) != 1} {
      puts -nonewline $mcuTty(ttyFD) "\r"
      flush $mcuTty(ttyFD)

      printDebugVars "waiting for primary prompt" data userPty(atPrompt)

      restartCommTimeout 3
      append data [yield ""]

      while {![string match "*> " $data]} {
        restartCommTimeout 3
        append data [yield ""]
        printDebugVars "waiting for primary prompt (while)" data userPty(atPrompt)
      }
      printDebugVars "got primary prompt" data
      set data ""
    }

    set cnt [llength $txCmds]
    foreach cmd $txCmds {
      puts -nonewline $mcuTty(ttyFD) "$cmd\r"
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
      printDebugVars "got intermediate prompt" data
    }

    # Datenverarbeitung
    # echo übergehen, auf Datenstart warten
    while {![string match "*$startString*" $data]} {
      printDebugVars "skipping echo for data begin" data
      set datLen [string length $data]
      if {$datLen > 20} {
        set data [string replace $data 0 [expr $datLen - 21]]
      }
      restartCommTimeout 3
      append data [yield ""]
    }

    set cutEnd [expr [string last $startString $data] + [string length $startString] ]
    set data [string replace $data 0 $cutEnd]
    printDebugVars "cutting data" cutEnd data

    while 1 {
      set dataend [expr [string last $stopString $data] - 1]
      printDebugVars "collecting data" data dataend

      if {$dataend >= 0} {
        set filehexdata [string range $data 0 $dataend]
        incr dataend [string length $stopString]
        incr dataend
        set data [string range $data $dataend end]
        printDebugVars "file data" filehexdata
        set filedata [binary decode hex $filehexdata]

        # filedata an Aufrufer exportieren via mcu_file_chunk(path offset size)
        set mcu_file_chunk("${path}_${offset}_${size}") $filedata
        break
      }

      restartCommTimeout 3
      append data [yield ""]
    }

    #~ if {![string match "> *" $data]} {
      #~ # try to catch the final prompt
      #~ after 100
      #~ restartCommTimeout 3
      #~ append data [yield ""]
    #~ }
  }

  # try to consume the final prompt to not to clutter the user terminal experience
  printDebugVars "remaining data" data
  set promptClutter "> >> >> >> >> >> >> >> >> >> >> >> >> >> >> >> >> >> >> >> >> >> >> > "
  if {[string match "${promptClutter}*" $data]} {
    set data [string replace $data 0 [expr [string length $promptClutter] - 1 ] ]
  }

  printDebugVars "returned data" data
  return $data
}

proc readMcuFileData {path size offset} {
  global mcuTty mcu_file_chunk

  printDebugCallSite

  if {[array names mcu_file_chunk -exact "${path}_${offset}_${size}"] eq ""} {
    printDebugVars "waiting for processFileData slot: ${path}_${offset}_${size}" mcuTty(processData)

    while {($mcuTty(processData) ne "")} {
      vwait mcuTty(processData)
    }

    coroutine processFileData coReadMcuFileData $path $size $offset
  }

  printDebugVars "waiting for end of processFileData: ${path}_${offset}_${size}" mcuTty(processData)

  if {$mcuTty(processData) ne ""} then {
    vwait mcuTty(processData)
  }
  printDebugVars "reached end of processFileData: ${path}_${offset}_${size}" mcuTty(processData)

  after 10 "array unset mcu_file_chunk \"${path}_${offset}_${size}\""

  return $mcu_file_chunk("${path}_${offset}_${size}")
}
