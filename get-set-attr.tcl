################
# Debugging
set procDebug(Getattr_mcu)   0
set procDebug(Getattr_basic) 0
set procDebug(Getattr)       0
set procDebug(Chmod)         0
set procDebug(Chown)         0

proc Getattr_mcu {context path} {
  global mcu_tree_cache

  printDebugCallSite

  set stat $mcu_tree_cache($path)

  if {![dict exists $stat mtime]} {
    dict append stat mtime [clock seconds]
  }

  return $stat
}

proc Getattr_basic {context path} {
  global basic_tree

  printDebugCallSite

  set opList $basic_tree($path)

  set stat [dict get $opList stat]
  if {![dict exists $stat mtime]} {
    dict append stat mtime [clock seconds]
  }
  if {[dict get $stat type] eq "file"} {
    set getter [dict get $opList getter]
    dict append stat size [string length [$getter]]
  }

  return $stat
}

proc Getattr {context path {fileinfo {} } } {
  global basic_tree mcu_tree_cache

  printDebugCallSite

  if {[string match "/mcu*" $path]} {
    # check mcu_tree_cache
    checkMcuTreeCache
    set name [array names mcu_tree_cache -exact $path]

    if {[llength $name] == 0} {
      # nichts im mcu_tree_cache
      return -code error -errorcode [list POSIX ENOENT {}]
    }

    # gib die Attribute aus dem mcu_tree_cache
    return [Getattr_mcu $context $path]
  } else {
    set name [array names basic_tree -exact $path]
    if {[llength $name] == 0} {
      # nichts im basic_tree
      return -code error -errorcode [list POSIX ENOENT {}]
    }
    
    # gib die Attribute aus dem basic_tree
    return [Getattr_basic $context $path]
  }
  
  return -code error -errorcode [list POSIX ENOENT {}]
}

proc Chmod {context path perm} {
  global basic_tree mcu_tree_cache
  
  printDebugCallSite
  
  if {[string match "/mcu*" $path]} {
    # check mcu_tree_cache
    checkMcuTreeCache
    set name [array names mcu_tree_cache -exact $path]

    if {[llength $name] == 0} {
      # nichts im mcu_tree_cache
      return -code error -errorcode [list POSIX ENOENT {}]
    }

    # act on files only
    if {[dict get $mcu_tree_cache($path) type] ne "file"} {
      return -code error -errorcode [list POSIX EACCES {}]
    }

    # set mode entry in mcu_tree_cache
    dict set mcu_tree_cache($path) mode $perm
    dict set mcu_tree_cache($path) ctime [clock seconds]
    return 
  } else {
    set name [array names basic_tree -exact $path]
    if {[llength $name] == 0} {
      # nichts im basic_tree
      return -code error -errorcode [list POSIX ENOENT {}]
    }
    
    # act on files only
    if {[dict get $basic_tree($path) stat type] ne "file"} {
      return -code error -errorcode [list POSIX EACCES {}]
    }

    # set mode in basic_tree
    dict set basic_tree($path) stat mode $perm
    dict set basic_tree($path) ctime [clock seconds]
    return 
  }

  return -code error -errorcode [list POSIX ENOENT {}]
}

proc Chown {context path owner group} {
  global basic_tree mcu_tree_cache
  
  printDebugCallSite
  
  if {[string match "/mcu*" $path]} {
    # check mcu_tree_cache
    checkMcuTreeCache
    set name [array names mcu_tree_cache -exact $path]

    if {[llength $name] == 0} {
      # nichts im mcu_tree_cache
      return -code error -errorcode [list POSIX ENOENT {}]
    }

    # set owser and group entry in mcu_tree_cache
    dict set mcu_tree_cache($path) uid $owner
    dict set mcu_tree_cache($path) gid $group
    dict set mcu_tree_cache($path) ctime [clock seconds]
    return 
  } else {
    set name [array names basic_tree -exact $path]
    if {[llength $name] == 0} {
      # nichts im basic_tree
      return -code error -errorcode [list POSIX ENOENT {}]
    }
    
    # act on files only
    if {[dict get $basic_tree($path) stat type] ne "file"} {
      return -code error -errorcode [list POSIX EACCES {}]
    }

    # set mode in basic_tree
    dict set basic_tree($path) stat uid $owner
    dict set basic_tree($path) stat gid $group
    dict set basic_tree($path) ctime [clock seconds]
    return 
  }

  return -code error -errorcode [list POSIX ENOENT {}]
}

proc Utimens {context path atime mtime} {
  global basic_tree mcu_tree_cache
  
  printDebugCallSite
  
  if {[string match "/mcu*" $path]} {
    # check mcu_tree_cache
    checkMcuTreeCache
    set name [array names mcu_tree_cache -exact $path]

    if {[llength $name] == 0} {
      # nichts im mcu_tree_cache
      return -code error -errorcode [list POSIX ENOENT {}]
    }

    # set owser and group entry in mcu_tree_cache
    dict set mcu_tree_cache($path) mtime $mtime
    dict set mcu_tree_cache($path) atime $atime
    dict set mcu_tree_cache($path) ctime [clock seconds]
    return 
  } else {
    set name [array names basic_tree -exact $path]
    if {[llength $name] == 0} {
      # nichts im basic_tree
      return -code error -errorcode [list POSIX ENOENT {}]
    }
    
    # act on files only
    if {[dict get $basic_tree($path) stat type] ne "file"} {
      return -code error -errorcode [list POSIX EACCES {}]
    }

    # set mode in basic_tree
    dict set basic_tree($path) stat mtime $mtime
    dict set basic_tree($path) stat atime $atime
    dict set basic_tree($path) ctime [clock seconds]
    return 
  }

  return -code error -errorcode [list POSIX ENOENT {}]
}
