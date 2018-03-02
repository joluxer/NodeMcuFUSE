


if {$globalNoDebug} {
  proc printDebugCallSite {} {}
  proc printDebugVars {args} {}
  
} else {
  
  proc printDebugCallSite {} {
    global globalDoDebug procDebug

    if {![catch {info level -1} procInfo]} {
      set procName [lindex $procInfo 0]
    } else {
      set procName "unknown"
      set procInfo "$argv0 $argv"
    }
  
    if {$globalDoDebug || ([llength [array names procDebug -exac $procName]] && $procDebug($procName))} {
      puts stderr "Call to: $procInfo"
    }
  }
  
  proc printDebugVars {tag args} {
    global globalDoDebug procDebug
  
    if {![catch {info level -1} procInfo]} {
      set procName [lindex $procInfo 0]
    } else {
      set procName "unknown"
    }
  
    if {$globalDoDebug || ([llength [array names procDebug -exac $procName]] && $procDebug($procName))} {
      if {$args eq ""} {
        puts stderr "$procName: $tag"
      } else {
        foreach a $args {
          upvar $a arg
          puts stderr "$procName: $tag: $a = '$arg'"
        }
      }
    }
  }
  
}
