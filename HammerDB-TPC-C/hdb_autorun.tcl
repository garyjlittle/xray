#!/bin/tclsh
proc runtimer { seconds } { }
proc runtimer { seconds } {
  set x 0
  set timerstop 0
  while {!$timerstop} {
    incr x
    after 1000
    if { ![ expr {$x % 60} ] } {
      set y [ expr $x / 60 ]
      puts "Timer: $y minutes elapsed"
    }
    update
    if { [ vucomplete ] || $x eq $seconds } { set timerstop 1 }
  }
  return
}
puts "SETTING CONFIGURATION"
global complete
proc wait_to_complete {} {
  global complete
  set complete [vucomplete]
  if {!$complete} { after 5000 wait_to_complete } else { exit }
}
dbset db mssqls
dbset bm TPC-C
diset connection mssqls_server (local)
diset connection mssqls_pass nutanix/4u
diset tpcc mssqls_driver timed
diset tpcc mssqls_count_ware 500
diset tpcc mssqls_num_vu 32
diset tpcc mssqls_duration 30
diset tpcc mssqls_rampup 3
print dict
loadscript
puts "SEQUENCE STARTED"
foreach z { 32 } {
  puts "$z VU TEST"
  vuset vu $z
  vucreate
  vurun
  # Runtimer in seconds must exceed rampup + duration
  runtimer 2000
  vudestroy
  after 5000
}
puts "TEST SEQUENCE COMPLETE"