cd [file dirname [file normalize [info script]]]
import_device eagle_s20.db -package EG4S20BG256
open_project TF_IMAGE.al
import_db ../../reports/route/final.db
update_timing -mode final
check_timing -verbose -file ../../reports/review/check_timing.rpt
report_clock_summary -file ../../reports/review/clocks.rpt
report_timing_exception -file ../../reports/review/timing_exceptions.rpt
report_timing_status -file ../../reports/review/final_timing.rpt
set uart_nets {}
foreach name {u_subtitle_uart/theme_command u_subtitle_uart/demo_command u_subtitle_uart/events/transmitting u_rover_control/remote_demo u_rover_control/combo_inhibit} {
 set resolved [get_nets $name]
 if {[llength $resolved]==0} {error "Missing UART control net: $name"}
 foreach net $resolved {lappend uart_nets $net}
}
puts "UART_REVIEW_NETS: $uart_nets"
report_timing_path -report_type max -through $uart_nets -ep_num 16 -file ../../reports/review/uart_setup.rpt
report_timing_path -report_type min -through $uart_nets -ep_num 16 -file ../../reports/review/uart_hold.rpt
puts {UART_REVIEW_COMPLETE}
exit
