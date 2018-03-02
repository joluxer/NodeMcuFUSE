#!/usr/bin/env wish

set fd [open mnt/io/device/rts "r"]
set rtsState [gets $fd]
close $fd

set fd [open mnt/io/device/dtr "r"]
set dtrState [gets $fd]
close $fd

# set rtsSubscriber [open "|mosquitto_sub -t /esp/ctrl/rts" "r"]
# fileevent $rtsSubscriber readable "mqttSubRts $rtsSubscriber"

# set dtrSubscriber [open "|mosquitto_sub -t /esp/ctrl/dtr" "r"]
# fileevent $dtrSubscriber readable "mqttSubDtr $dtrSubscriber"

frame .ctrlFrame

checkbutton .ctrlFrame.buttonRts -text "RTS" -indicatoron 1 -onvalue 1 -offvalue 0 -command rtsToggled -variable rtsState
checkbutton .ctrlFrame.buttonDtr -text "DTR" -indicatoron 1 -onvalue 1 -offvalue 0 -command dtrToggled -variable dtrState
button .ctrlFrame.cmdButtonReset -text "Reset NodeMCU" -command resetNodeMCU

pack .ctrlFrame.buttonRts -anchor nw -fill x -expand 0
pack .ctrlFrame.buttonDtr -anchor nw -fill x -expand 0
pack .ctrlFrame.cmdButtonReset -anchor nw -fill x -expand 1
pack .ctrlFrame -anchor nw -fill none -expand 0

proc rtsToggled {} {
  global rtsState
  set fd [open mnt/io/device/rts "w"]
  puts -nonewline $fd $rtsState
  close $fd
}

proc dtrToggled {} {
  global dtrState
  set fd [open mnt/io/device/dtr "w"]
  puts -nonewline $fd $dtrState
  close $fd
}

proc mqttSubRts {chan} {
  global rtsState
  
  set msg [gets $chan]
  
  if {$msg eq "true"} {
    set rtsState 1
  } else {
    set rtsState 0
  }
  
  rtsToggled
}

proc mqttSubDtr {chan} {
  global dtrState
  
  set msg [gets $chan]
  
  if {$msg eq "true"} {
    set dtrState 1
  } else {
    set dtrState 0
  }
  
  dtrToggled
}

proc resetNodeMCU {} {
  global dtrState rtsState
  
  set rtsState 1; 
  set dtrState 0; 
  dtrToggled
  rtsToggled
  
  after 250 "set rtsState 0; rtsToggled"
}

proc shutdownGui {} {
  global rtsSubscriber dtrSubscriber
  
  catch {close $rtsSubscriber}
  catch {close $dtrSubscriber}
  exit
}

wm protocol . WM_DELETE_WINDOW shutdownGui
