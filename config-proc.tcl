################
# Debugging
set procDebug(saveConfig) 0


set configDelay {}
set configDir "~/.nodemcufuse"
set configFile "NodeMcuFUSE-[info hostname].conf"
set configuration {}
array set configPath {}

# this method reads the configuration value, given by key1 and optional more keys
# in to the variable and arranges a trace connection, so that every
# set/write access to this variable is mirrored into the configuration dictionary;
# 10s after the last access to the configuration dictionary the whole dict
# is written to disk
proc configureWith {varName key1 args} {
  global configPath configuration
  upvar $varName workVar
  
  set configPath($varName) $key1
  foreach key $args {
    lappend configPath($varName) $key
  }
  
  if {[eval dict exists \"$configuration\" $configPath($varName)]} {
    set workVar [eval dict get \"$configuration\" $configPath($varName)]
  }
  
  set ops write
  if {[array exists $varName]} {
    lappend ops array
  }
  trace add variable workVar $ops saveConfig
}

proc saveConfig {name1 name2 op} {
  global configPath configuration configDelay
  
  set varName $name1
  if {$name2 ne ""} {
    set varName "${name1}($name2)"
  }

  upvar $varName workVar
  
  printDebugVars "set configuration" configPath($varName) workVar
  
  eval dict set configuration $configPath($varName) \"$workVar\"
  
  if {$configDelay ne ""} {
    after cancel $configDelay
  }
  
  set configDelay [after 10000 writeConfig]
}

proc writeConfig {} {
  global configuration configDelay configDir configFile

  set configDelay ""
  
  set cfgFile [file join $configDir $configFile]
  
  if {[file pathtype $configFile] eq "absolute"} {
    set cfgFile $configFile
  } else {
    # check config file path for existence
    if {![file exists $configDir]} {
      file mkdir $configDir
    }
  }
  
  if {![catch {open $cfgFile "w"} fd]} {
    puts $fd $configuration
    close $fd
  }
}

proc readConfig {} {
  global configuration configDir configFile

  set cfgFile [file join $configDir $configFile]
  
  if {[file pathtype $configFile] eq "absolute"} {
    set cfgFile $configFile
  }
  
  if {![catch {open $cfgFile "r"} fd]} {
    set configuration [read $fd]
    close $fd
  }
}
