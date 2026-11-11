cd [file dirname [file normalize [info script]]]
import_device eagle_s20.db -package EG4S20BG256
open_project TF_IMAGE.al
import_db ../../reports/route/final.db
update_timing -mode final
report_timing_status -file ../../reports/candidate/final_timing.rpt
report_area -io_info -file ../../reports/candidate/area.rpt
set f [open ../../reports/candidate/final_timing.rpt r]
set timing [read $f]
close $f
foreach key {SWNS STNS HWNS HTNS} {
 if {![regexp [format {%s:\s*(-?[0-9.]+)ns} $key] $timing matched value]} {error "Missing $key"}
 if {$value < 0} {error "Timing gate failed: $key=$value"}
}
set f [open ../../reports/candidate/area.rpt r]
set area [read $f]
close $f
foreach {key limit} {lut 19600 reg 19600 bram9k 64 bram32k 16 dsp 29} {
 if {![regexp [format {#%s\s+([0-9]+)} $key] $area matched value]} {error "Missing $key"}
 if {$value > $limit} {error "Resource gate failed: $key=$value"}
}
file mkdir ../bitstream
set target ../bitstream/TF_IMAGE_CODE_ANLU_REBUILD.bit
if {[file exists $target]} {error "Refuse to overwrite existing candidate"}
bitgen -bit $target
puts {UART_BIT_COMPLETE}
exit
