################
# Debugging
set procDebug(setTTY)             0
set procDebug(setBaudrate)        0
set procDebug(setTryTTYs)         0
set procDebug(setHexdumpPtyState) 0
set procDebug(setRtsState)        0
set procDebug(setDtrState)        0

proc getTTY {} {
  global mcuTty

  return "$mcuTty(activeTTY)\n"
}

proc setTTY {newTTY} {
  global mcuTty mcu_tree_cache basic_tree

  printDebugCallSite

  if {![catch {open $newTTY {RDWR BINARY NOCTTY}} newFD]} {
    if {![catch {fconfigure $newFD -blocking 0 -buffering none -translation binary -mode $mcuTty(baudrate),n,8,1 -handshake none -ttycontrol [list RTS $mcuTty(rtsState) DTR $mcuTty(rtsState)]} dummyvar message]} {
      fileevent $newFD readable [list readMCU $newFD]
      catch {close $mcuTty(ttyFD)}
      set mcuTty(ttyFD) $newFD
      set mcuTty(activeTTY) $newTTY
      dict set basic_tree(/io/device/tty) stat mtime [clock seconds]
      dict set mcu_tree_cache(/mcu) mtime [clock seconds]
      set mcu_tree_cache(dirty) 1
      if {$mcuTty(processData) ne ""} {
        catch {rename $mcuTty(processData) ""}
        set mcuTty(processData) ""
      }
      return 1
    } else {
      printDebugVars "fconfigure error" message
    }
    catch {close $newFD}
  }
  return 0
}

proc getTryTTYs {} {
  global tryTTYs

  set data [join $tryTTYs "\n"]
  append data "\n"
  return $data
}

proc setTryTTYs {data} {
  global tryTTYs

  printDebugCallSite
  
  set newTTYs [split $data "\n"]
  set pos [lsearch -exact $newTTYs {}]
  while {$pos > -1} {
    set newTTYs [lreplace $newTTYs $pos $pos]
    set pos [lsearch -exact $newTTYs {}]
  }
  
  printDebugVars "" newTTYs
  set tryTTYs $newTTYs

  return 1
}

proc truncateTryTTYs {size} {
  set data [getTryTTYs]
  setTryTTYs [string replace $data $size end]
}

proc getBaudrate {} {
  global mcuTty
  set baud 0

  if {0 == [catch {fconfigure $mcuTty(ttyFD) -mode} mode]} {
    set mlist [split $mode ","]
    set baud [lindex $mlist 0]
  }

  # set mcuTty(baudrate) $baud
  return "$baud\n"
}

proc setBaudrate {data} {
  global mcuTty

  set number 115200
  scan $data "%d" number

  if {$number eq ""} {
    set number 115200
  }
  
  if {$number in {150 300 600 1200 2400 4800 9600 14400 19200 38400 56700 115200}} {
    set mcuTty(baudrate) $number
    fconfigure $mcuTty(ttyFD) -mode $mcuTty(baudrate),n,8,1

    return 1
  }
  
  return 0
}

proc getRtsState {} {
  global mcuTty

  return "$mcuTty(rtsState)\n"
}

proc setRtsState {data} {
  global mcuTty

  set number 1
  scan $data "%d" number

  if {$number eq ""} {
    set number 1
  }

  if {$number < 1} {
    set number 0
  } elseif {$number > 1} {
    set number 1
  }

  set mcuTty(rtsState) $number

  printDebugVars "" mcuTty(rtsState)

  fconfigure $mcuTty(ttyFD) -ttycontrol [list RTS $mcuTty(rtsState)]

  return 1
}

proc getDtrState {} {
  global mcuTty

  return "$mcuTty(dtrState)\n"
}

proc setDtrState {data} {
  global mcuTty

  set number 1
  scan $data "%d" number

  if {$number eq ""} {
    set number 1
  }

  if {$number < 1} {
    set number 0
  } elseif {$number > 1} {
    set number 1
  }

  set mcuTty(dtrState) $number

  printDebugVars "" mcuTty(dtrState)

  fconfigure $mcuTty(ttyFD) -ttycontrol [list DTR $mcuTty(dtrState)]

  return 1
}

proc getCacheTime {} {
  global mcuTty

  return "$mcuTty(cacheTime_ms)\n"
}

proc setCacheTime {data} {
  global mcuTty

  set number 1
  scan $data "%d" number

  if {$number eq ""} {
    set number 12000
  }

  if {$number < 100} {
    set number 100
  } elseif {$number > 120000} {
    set number 120000
  }

  set mcuTty(cacheTime_ms) $number

  set mcu_tree_cache(dirty) 1

  return 1
}

proc getUserPty {} {
  global userPty
  return $userPty(SlaveLink)
}

proc readHexdump {} {
  global userPty

  set data [join $userPty(hexdumpBlockBuffer) "\n"]
  return "$data\n"
}

proc readMaxHexdumpLines {} {
  global userPty

  return "$userPty(hexdumpMaxBlockLines)\n"
}

proc setMaxHexdumpLines {data} {
  global userPty

  set number 64
  scan $data "%d" number

  if {$number eq ""} {
    set number 64
  }

  if {$number < 1} {
    set number 1
  } elseif {$number > 4096} {
    set number 4096
  }

  set userPty(hexdumpMaxBlockLines) $number

  return 1
}

proc getHexdumpPtyState {} {
  global userPty

  return "$userPty(printHexdump)\n"
}

proc setHexdumpPtyState {data} {
  global userPty

  set number 1
  scan $data "%d" number

  if {$number eq ""} {
    set number 1
  }

  if {$number < 1} {
    set number 0
  } elseif {$number > 1} {
    set number 1
  }

  set oldState $userPty(printHexdump)
  set userPty(printHexdump) $number

  printDebugVars "Hexdump Switch" oldState number

  if {$number != $oldState} {
    # bei Umschaltung den Zeilenvorschub in Ordnung bringen
    if {$number} {
      catch "puts -nonewline $userPty(MasterFD) \"\r\nHexdump START\r\n\" ; mcuHexdumpData \"\" ; flush $userPty(MasterFD)"
    } else {
      catch "puts -nonewline $userPty(MasterFD) \"\r\nHexdump STOP\r\n\" ; flush $userPty(MasterFD)"
    }
  }

  return 1
}

proc getXferTimer {} {
  global mcuTty

  return "$mcuTty(readWriteTimer)\n"
}

proc setXferTimer {data} {
  global mcuTty

  set number 6
  scan $data "%d" number

  if {$number eq ""} {
    set number 6
  }
  
  if {$number in {0 1 2 3 4 5 6}} {
    set mcuTty(readWriteTimer) $number
    return 1
  }
  
  return 0
}

