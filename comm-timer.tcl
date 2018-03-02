################
# Debugging
set procDebug(runCommTimeout) 0

proc runCommTimeout {} {
  global mcuTty

  # printDebugCallSite

  if {$mcuTty(commTimer) > 0} {
    printDebugVars "count down" mcuTty(commTimer)
    incr mcuTty(commTimer) -1
    if {($mcuTty(commTimer) == 0) && ($mcuTty(processData) ne "")} {
      printDebugVars "deleting coroutine" mcuTty(processData)
      catch "rename $mcuTty(processData) {}"
    } elseif {$mcuTty(processData) eq ""} {
      set mcuTty(commTimer) 0
    }
  } 
  after 100 runCommTimeout
}

proc restartCommTimeout {{t 3}} {
  global mcuTty
  
  set mcuTty(commTimer) [expr int($t * 10)]
}
