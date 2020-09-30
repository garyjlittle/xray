#!/bin/tclsh
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
diset tpcc mssqls_count_ware 500
diset tpcc mssqls_num_vu 32
print dict
buildschema
wait_to_complete
vwait forever
