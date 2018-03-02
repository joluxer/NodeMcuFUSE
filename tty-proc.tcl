################
# Debugging
set procDebug(readMCU)        0
set procDebug(readPTY)        0
set procDebug(mcuHexdumpData) 0
set procDebug(checkForPrompt) 0

set userPty(prompt) ""
set userPty(promptCheckState) ""
set userPty(atPrompt) 1; # 0 - not at prompt, 1 - at primary prompt, 2 - at secondary prompt

#######################
# Hexdumps für die MCU-Daten
proc mcuHexdumpData {outData} {
  global userPty basic_tree

  set data $outData

  while 1 {
    # split in chunks of 16
    set datalen [string length $data]
    printDebugVars "data length" datalen userPty(hexdumpLineCount)
    set n [expr 16 - $userPty(hexdumpLineCount) - 1]
    printDebugVars "line remainder" n
    set s [string range $data 0 $n]
    set outputlen [string length $s]
    printDebugVars "" outputlen

    # shorten data by the extracted amount
    set data [string replace $data 0 [expr [string length $s] - 1]]
    set datalen [string length $data]
    printDebugVars "data length 2" datalen

    # Convert the data to hex and to characters.
    binary scan $s H*@0a* hex ascii
    # Replace non-printing characters in the data.
    regsub -all -- {[^[:graph:] ]} $ascii {.} ascii
    append userPty(hexdumpHex) $hex
    append userPty(hexdumpAscii) $ascii
    set oldLC $userPty(hexdumpLineCount)
    incr userPty(hexdumpLineCount) $outputlen

    # Split the 16 bytes into two 8-byte chunks
    set hex1   [string range $userPty(hexdumpHex)   0 15]
    set hex2   [string range $userPty(hexdumpHex)  16 31]
    set ascii1 [string range $userPty(hexdumpAscii) 0  7]
    set ascii2 [string range $userPty(hexdumpAscii) 8 16]

    # Convert the hex to pairs of hex digits
    regsub -all -- {..} $hex1 {& } hex1
    regsub -all -- {..} $hex2 {& } hex2

    set line [format {%08x  %-24s %-24s %-8s %-8s} $userPty(hexdumpLineAddr) $hex1 $hex2 $ascii1 $ascii2]

    if {$userPty(hexdumpLineCount) >= 16} {
      if {$oldLC == 0} {
        printDebugVars "appending line(16)" line
        lappend userPty(hexdumpBlockBuffer) $line
      } else {
        printDebugVars "replacing line(16)" line
        set userPty(hexdumpBlockBuffer) [lreplace $userPty(hexdumpBlockBuffer) end end $line]
      }
      if {[llength $userPty(hexdumpBlockBuffer)] > $userPty(hexdumpMaxBlockLines)} {
        set userPty(hexdumpBlockBuffer) [lrange $userPty(hexdumpBlockBuffer) end-$userPty(hexdumpMaxBlockLines) end]
      }

      if {$userPty(printHexdump)} {
        puts -nonewline $userPty(MasterFD) "\r$line\n\r"
      }

      incr userPty(hexdumpLineAddr) 16
      set userPty(hexdumpLineCount) 0
      set userPty(hexdumpHex) ""
      set userPty(hexdumpAscii) ""
    } elseif {$userPty(hexdumpLineCount) > 0} {
      if {$oldLC == 0} {
        printDebugVars "appending line" line
        lappend userPty(hexdumpBlockBuffer) $line
      } else {
        printDebugVars "replacing line" line
        set userPty(hexdumpBlockBuffer) [lreplace $userPty(hexdumpBlockBuffer) end end $line]
      }
    }
    
    dict set basic_tree(/io/user/hexdump) stat mtime [clock seconds]

    if {$userPty(printHexdump) && ($userPty(hexdumpLineCount) > 0)} {
      puts -nonewline $userPty(MasterFD) "\r$line"
    }

    if {![string length $data]} \
    break
  }
}

proc checkForPrompt {data} {
  global userPty

  printDebugCallSite

  foreach c [split $data ""] {
    printDebugVars "" userPty(promptCheckState) userPty(prompt) userPty(atPrompt) c

    if {$userPty(promptCheckState) eq ""} {
      # looking for newline
      if {$c eq "\n"} {
        set userPty(promptCheckState) "NL"
      }
      set userPty(atPrompt) 0
    } elseif {$userPty(promptCheckState) eq "NL"} {
      # looking for 1st prompt char
      if {$c eq ">"} {
        set userPty(promptCheckState) ">"
      } else {
        set userPty(promptCheckState) ""
      }
      set userPty(atPrompt) 0
    } elseif {$userPty(promptCheckState) eq ">"} {
      # looking for 2nd prompt char
      if {$c eq ">"} {
        set userPty(promptCheckState) ">>"
      } elseif {$c eq " "} {
        set userPty(prompt) "> "
        set userPty(promptCheckState) ""
        set userPty(atPrompt) 1
      }
      set userPty(atPrompt) 0
    } elseif {$userPty(promptCheckState) eq ">>"} {
      # looking for 3rd prompt char
      set userPty(atPrompt) 0
      if {$c eq " "} {
        set userPty(prompt) ">> "
        set userPty(atPrompt) 2
      }
      set userPty(promptCheckState) ""
    }
  }
  printDebugVars "" userPty(promptCheckState) userPty(prompt) userPty(atPrompt)
}

proc readMCU {chan} {
  global userPty mcuTty

  set data [read $chan]
  printDebugVars raw data

  mcuHexdumpData $data

  # hier die Daten der FUSE-Kommunikation ausschleusen
  if {($mcuTty(processData) ne "") && [llength [info commands $mcuTty(processData)]]} {
    if {[catch {$mcuTty(processData) $data} data]} {
      catch "rename $mcuTty(processData) {}"
      after 1000 {set mcu_tree_cache(dirty) 1}
    }
  }

  # forward remaining data to the user terminal
  if {[catch "eof $userPty(MasterFD)" have_eof]} {
    set have_eof 1
  }
  if {!$userPty(printHexdump)} {
    checkForPrompt $data
    if {!$have_eof} {
      puts -nonewline $userPty(MasterFD) $data
    }
  }
  if {!$have_eof} {
    flush $userPty(MasterFD)
  }

  if {[eof $chan]} {
    fileevent $chan readable {}
    puts stderr "Stopping $mcuTty(activeTTY) because of EOF, starting search for usable TTY"
    after idle searchMCU
  }
}

proc checkForMcuOutput {chan} {
  global mcuTty userPty
  if {$mcuTty(processData) eq ""} {
    # wenn ein Zeilenende im Puffer ist, den Puffer bis dort senden
    set cr [string first "\r" $mcuTty(cmdBuffer)]
    printDebugVars "looking for line end" mcuTty(cmdBuffer) cr

    while {$cr >= 0} {
      set sendData [string range $mcuTty(cmdBuffer) 0 $cr]
      set hexdata [binary encode hex $sendData]
      printDebugVars "sending line to MCU" sendData hexdata

      if {[catch "eof $mcuTty(ttyFD)" have_eof]} {
        set have_eof 1
      }
      if {!$have_eof} {
        puts -nonewline $mcuTty(ttyFD) $sendData
        flush $mcuTty(ttyFD)
      }

      if {[eof $chan]} {
        fileevent $chan readable {}
        after idle searchPty
      }

      set mcuTty(cmdBuffer) [string replace $mcuTty(cmdBuffer) 0 $cr]
      set cr [string first "\r" $mcuTty(cmdBuffer)]
      printDebugVars "looking for line end (while)" mcuTty(cmdBuffer) cr
    }
  } else {
    # retry later
    after 200 "checkForMcuOutput $chan"
  }
}

proc readPTY {chan} {
  global mcuTty userPty

  set data [read $chan]

  set hexdata [binary encode hex $data]
  printDebugVars "input" data hexdata
  
  # doing backspace action
  while {([string index $data 0] in {"\b" "\x7f"}) && ([string length $mcuTty(cmdBuffer)] > 0)} {
    set data [string replace $data 0 0]
    set mcuTty(cmdBuffer) [string replace $mcuTty(cmdBuffer) end end]
    puts -nonewline $chan "\b \b"
    printDebugVars "backspace action" data mcuTty(cmdBuffer)
  }
  # Daten an den Puffer anhängen
  append mcuTty(cmdBuffer) $data

  # Echo ausgeben
  if {!$userPty(printHexdump)} {
    set cr [string first "\r" $data]
    if {$cr >= 0} {
      set data [string replace $data $cr $cr "\r$userPty(prompt)"]
    }
    puts -nonewline $chan $data
  }
  flush $chan

  checkForMcuOutput $chan
}

proc searchPty {} {
  global userPty
  set ptyFD {}
  set success 0
  set ptys [lreverse [glob -directory /dev -nocomplain -types c {pty[p-za-e][0-9a-f]} ]]

  foreach pty $ptys {
    if {![catch {open $pty {RDWR BINARY NOCTTY} } ptyFD]} {
      regsub pty $pty tty slave
      if {![catch {open $slave {RDWR BINARY NOCTTY}} slaveFD]} {
        if {![catch {fconfigure $ptyFD -blocking 0 -buffering none -translation binary}]} {
          fileevent $ptyFD readable [list readPTY $ptyFD]
          set userPty(MasterFD) $ptyFD
          set userPty(SlaveFD) $slaveFD
          set userPty(SlaveLink) $slave
          # puts searchPty:$userPty(MasterFD):$userPty(SlaveFD):$userPty(SlaveLink)
          set success 1
          break
        } else {
          close $slave
          close $ptyFD
        }
      }
      close $pty
    }
  }

  if {!$success} {
    puts stderr "could not find a usable pseudo TTY for forwarding MCU console to the user!"
    after 10000 searchPty
  }
}

proc searchMCU {} {
  global tryTTYs mcuTty
  set success 0

  set searchTTYs $tryTTYs

  # insert old TTY in front of search list
  set pos [lsearch $searchTTYs $mcuTty(activeTTY)]
  if {$pos < 0} {
    set searchTTYs [linsert $searchTTYs 0 $mcuTty(activeTTY)]
  } else {
    # change list order, so old is in front
    set searchTTYs [linsert [lreplace $searchTTYs $pos $pos] 0 $mcuTty(activeTTY)]
    set tryTTYs $searchTTYs
  }

  foreach tty $searchTTYs {
    if {[setTTY $tty]} {
      puts stderr "Opened $tty for communication to MCU"
      set success 1
      break
    }
  }

  if {!$success} {
    after 1000 searchMCU
  }
}
