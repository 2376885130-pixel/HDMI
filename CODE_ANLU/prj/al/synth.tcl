cd [file dirname [file normalize [info script]]]
import_device eagle_s20.db -package EG4S20BG256
open_project TF_IMAGE.al
reset_runs syn_1
launch_runs syn_1 -jobs 2
wait_run syn_1
open_run syn_1
report_area -io_info -file ../../reports/synth/area.rpt
write_verilog ../../reports/synth/netlist.v
puts {REBASE_STAGE_COMPLETE}
exit
