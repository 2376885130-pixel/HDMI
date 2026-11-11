cd [file dirname [file normalize [info script]]]
import_device eagle_s20.db -package EG4S20BG256
open_project TF_IMAGE.al
reset_runs phy_1
set_param place seed 12 -run phy_1
get_param place seed -run phy_1
launch_runs phy_1 -step route -jobs 2
wait_run phy_1
open_run phy_1
set_param place hold_fix high
fix_hold -clock_opt -eco
update_timing -mode final
report_timing_status -file ../../reports/route/final_timing.rpt
report_timing_summary -file ../../reports/route/timing_summary.rpt
report_timing_exception -file ../../reports/route/timing_exceptions.rpt
report_route_status -drc -file ../../reports/route/route_drc.rpt
export_db ../../reports/route/final.db
report_area -io_info -file ../../reports/route/area.rpt
puts {REBASE_STAGE_COMPLETE}
exit
