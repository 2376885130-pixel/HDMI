create_clock -name sys_clk -period 20 [get_ports sys_clk]
derive_clocks

# SD reply slots: payload is held until capture acknowledgement returns.
# Each published bit traverses two destination registers before consumption.
# Bound payload/control flight to 20ns; waive only asynchronous entry hold.
# All synchronizer stage-to-stage and local queue paths retain normal timing.
set_max_delay -datapath_only 20 -from [get_regs -hier {u_sd_cdc/response_held*}] -to [get_regs -hier {u_sd_cdc/data* u_sd_cdc/valid* u_sd_cdc/done*}]
set_false_path -hold -from [get_regs -hier {u_sd_cdc/response_held*}] -to [get_regs -hier {u_sd_cdc/data* u_sd_cdc/valid* u_sd_cdc/done*}]
set_max_delay -datapath_only 20 -from [get_regs -hier {u_sd_cdc/published*}] -to [get_regs -hier {u_sd_cdc/publish_meta*}]
set_false_path -hold -from [get_regs -hier {u_sd_cdc/published*}] -to [get_regs -hier {u_sd_cdc/publish_meta*}]
set_max_delay -datapath_only 20 -from [get_regs -hier {u_sd_cdc/acknowledged*}] -to [get_regs -hier {u_sd_cdc/ack_meta*}]
set_false_path -hold -from [get_regs -hier {u_sd_cdc/acknowledged*}] -to [get_regs -hier {u_sd_cdc/ack_meta*}]
set_max_delay -datapath_only 20 -through [get_nets {u_sd_cdc/overflow}] -to [get_regs -hier {u_sd_cdc/overflow_sync*}]
set_false_path -hold -through [get_nets {u_sd_cdc/overflow}] -to [get_regs -hier {u_sd_cdc/overflow_sync*}]

# Picture parameters: acknowledged held bundle, captured after 2FF request.
set_max_delay -datapath_only 20 -from [get_regs -hier {u_picture_commit/u_snapshot/held*}] -to [get_regs -hier {u_picture_commit/u_snapshot/dst_data*}]
set_false_path -hold -from [get_regs -hier {u_picture_commit/u_snapshot/held*}] -to [get_regs -hier {u_picture_commit/u_snapshot/dst_data*}]
set_max_delay -datapath_only 20 -through [get_nets {u_picture_commit/u_snapshot/request}] -to [get_regs -hier {u_picture_commit/u_snapshot/request_sync*}]
set_false_path -hold -through [get_nets {u_picture_commit/u_snapshot/request}] -to [get_regs -hier {u_picture_commit/u_snapshot/request_sync*}]
set_max_delay -datapath_only 20 -through [get_nets {u_picture_commit/u_snapshot/ack}] -to [get_regs -hier {u_picture_commit/u_snapshot/ack_sync*}]
set_false_path -hold -through [get_nets {u_picture_commit/u_snapshot/ack}] -to [get_regs -hier {u_picture_commit/u_snapshot/ack_sync*}]

# Diagnostic four-phase mailbox: held data stays unchanged until ack returns.
# Destination captures after two request synchronizers and a further edge.
# Bound payload flight; only the asynchronous payload hold relation is waived.
set_max_delay -datapath_only 20 -from [get_regs -hier {u_preview_fault_snapshot/held*}] -to [get_regs -hier {u_preview_fault_snapshot/dst_data*}]
set_false_path -hold -from [get_regs -hier {u_preview_fault_snapshot/held*}] -to [get_regs -hier {u_preview_fault_snapshot/dst_data*}]
# Through-source filtering selects only the asynchronous synchronizer entry;
# request_sync[0]->[1] and ack_sync[0]->[1] remain normally timed.
set_max_delay -datapath_only 20 -through [get_nets {u_preview_fault_snapshot/request}] -to [get_regs -hier {u_preview_fault_snapshot/request_sync*}]
set_false_path -hold -through [get_nets {u_preview_fault_snapshot/request}] -to [get_regs -hier {u_preview_fault_snapshot/request_sync*}]
set_max_delay -datapath_only 20 -through [get_nets {u_preview_fault_snapshot/ack}] -to [get_regs -hier {u_preview_fault_snapshot/ack_sync*}]
set_false_path -hold -through [get_nets {u_preview_fault_snapshot/ack}] -to [get_regs -hier {u_preview_fault_snapshot/ack_sync*}]

# Thumbnail four-phase mailboxes: held payload is stable until a returned ack.
# Capture occurs after the two request stages and one destination clock edge.
# Bound physical payload flight to 20ns; only these handshake payloads have no
# same-edge hold relationship. Synchronous paths remain fully timed.
set_max_delay -datapath_only 20 -from [get_regs -hier {u_thumbnails/u_visible/held*}] -to [get_regs -hier {u_thumbnails/u_visible/dst_data*}]
set_false_path -hold -from [get_regs -hier {u_thumbnails/u_visible/held*}] -to [get_regs -hier {u_thumbnails/u_visible/dst_data*}]
set_max_delay -datapath_only 20 -from [get_regs -hier {u_thumbnails/u_pixel_control/held*}] -to [get_regs -hier {u_thumbnails/u_pixel_control/dst_data*}]
set_false_path -hold -from [get_regs -hier {u_thumbnails/u_pixel_control/held*}] -to [get_regs -hier {u_thumbnails/u_pixel_control/dst_data*}]
set_max_delay -datapath_only 20 -from [get_regs -hier {u_thumbnails/u_memory_control/held*}] -to [get_regs -hier {u_thumbnails/u_memory_control/dst_data*}]
set_false_path -hold -from [get_regs -hier {u_thumbnails/u_memory_control/held*}] -to [get_regs -hier {u_thumbnails/u_memory_control/dst_data*}]
# Only async input paths into stage zero, not stage-to-stage paths.
set_max_delay -datapath_only 20 -through [get_nets {u_thumbnails/u_visible/request}] -to [get_regs -hier {u_thumbnails/u_visible/request_sync*}]
set_false_path -hold -through [get_nets {u_thumbnails/u_visible/request}] -to [get_regs -hier {u_thumbnails/u_visible/request_sync*}]
set_max_delay -datapath_only 20 -through [get_nets {u_thumbnails/u_visible/ack}] -to [get_regs -hier {u_thumbnails/u_visible/ack_sync*}]
set_false_path -hold -through [get_nets {u_thumbnails/u_visible/ack}] -to [get_regs -hier {u_thumbnails/u_visible/ack_sync*}]
set_max_delay -datapath_only 20 -through [get_nets {u_thumbnails/u_pixel_control/request}] -to [get_regs -hier {u_thumbnails/u_pixel_control/request_sync*}]
set_false_path -hold -through [get_nets {u_thumbnails/u_pixel_control/request}] -to [get_regs -hier {u_thumbnails/u_pixel_control/request_sync*}]
set_max_delay -datapath_only 20 -through [get_nets {u_thumbnails/u_pixel_control/ack}] -to [get_regs -hier {u_thumbnails/u_pixel_control/ack_sync*}]
set_false_path -hold -through [get_nets {u_thumbnails/u_pixel_control/ack}] -to [get_regs -hier {u_thumbnails/u_pixel_control/ack_sync*}]
set_max_delay -datapath_only 20 -through [get_nets {u_thumbnails/u_memory_control/request}] -to [get_regs -hier {u_thumbnails/u_memory_control/request_sync*}]
set_false_path -hold -through [get_nets {u_thumbnails/u_memory_control/request}] -to [get_regs -hier {u_thumbnails/u_memory_control/request_sync*}]
set_max_delay -datapath_only 20 -through [get_nets {u_thumbnails/u_memory_control/ack}] -to [get_regs -hier {u_thumbnails/u_memory_control/ack_sync*}]
set_false_path -hold -through [get_nets {u_thumbnails/u_memory_control/ack}] -to [get_regs -hier {u_thumbnails/u_memory_control/ack_sync*}]

# Reset requests assert asynchronously; each domain releases reset after three clocks.
# Animation completion is held in mem_clk until zoom_enable is withdrawn via
# the acknowledged control mailbox. Only stage zero samples this CDC level;
# stages one/two remain fully timed in sys_clk. Bound the source flight to
# 20 ns, using the source net filter to exclude inter-stage paths.
set_max_delay -datapath_only 20 -through [get_nets {u_thumbnails/u_builder/zoom_done}] -to [get_regs -hier {u_thumbnails/zoom_done_sync[0]}]
set_false_path -hold -through [get_nets {u_thumbnails/u_builder/zoom_done}] -to [get_regs -hier {u_thumbnails/zoom_done_sync[0]}]

# Limit exceptions to the request nets entering the reset synchronizers.
# Their shift-register data paths and all downstream reset paths remain timed.
set_false_path -through [get_nets {ready_clock}] -to [get_regs {sd_reset_pipe*}]
set_false_path -through [get_nets {video_ready}] -to [get_regs {video_reset_pipe*}]

# BGM four-phase mailboxes hold data until acknowledgement returns. Destination
# captures only after two request synchronizers and a further local edge.
# Bound the payload flight to one shortest (20 ns) clock; same-edge hold does
# not apply to this handshake. Do not exempt the surrounding synchronous logic.
set_max_delay -datapath_only 20 -from [get_regs -hier {u_bgm/selection/held*}] -to [get_regs -hier {u_bgm/selection/dst_data*}]
set_false_path -hold -from [get_regs -hier {u_bgm/selection/held*}] -to [get_regs -hier {u_bgm/selection/dst_data*}]
set_max_delay -datapath_only 20 -from [get_regs -hier {u_bgm/audio_stats/held*}] -to [get_regs -hier {u_bgm/audio_stats/dst_data*}]
set_false_path -hold -from [get_regs -hier {u_bgm/audio_stats/held*}] -to [get_regs -hier {u_bgm/audio_stats/dst_data*}]
# Gray buses are registered at the producer and received by preserved 2FFs.
# Flight must be shorter than the source update period (write 20ns/read 40ns).
set_max_delay -datapath_only 20 -from [get_regs -hier {u_bgm/pcm/fifo/wg*}] -to [get_regs -hier {u_bgm/pcm/fifo/ws1*}]
set_false_path -hold -from [get_regs -hier {u_bgm/pcm/fifo/wg*}] -to [get_regs -hier {u_bgm/pcm/fifo/ws1*}]
set_max_delay -datapath_only 40 -from [get_regs -hier {u_bgm/pcm/fifo/rg*}] -to [get_regs -hier {u_bgm/pcm/fifo/rs1*}]
set_false_path -hold -from [get_regs -hier {u_bgm/pcm/fifo/rg*}] -to [get_regs -hier {u_bgm/pcm/fifo/rs1*}]

# The diagnostic mailbox and committed displayed index capture on the falling
# sys_clk edge after synchronized notification. Keep their hold checks timed.

# Only asynchronous control nets entering the first synchronizer stage.
# Through-source filtering excludes stage 1 -> stage 2 timing.
set_max_delay -datapath_only 20 -through [get_nets {u_osd_control_snapshot/ack}] -to [get_regs -hier {u_osd_control_snapshot/ack_sync*}]
set_false_path -hold -through [get_nets {u_osd_control_snapshot/ack}] -to [get_regs -hier {u_osd_control_snapshot/ack_sync*}]
set_max_delay -datapath_only 20 -through [get_nets {u_volume_snapshot/ack}] -to [get_regs -hier {u_volume_snapshot/ack_sync*}]
set_false_path -hold -through [get_nets {u_volume_snapshot/ack}] -to [get_regs -hier {u_volume_snapshot/ack_sync*}]
set_max_delay -datapath_only 20 -through [get_nets {u_subtitle_commit/ack}] -to [get_regs -hier {u_subtitle_commit/ack_sync*}]
set_false_path -hold -through [get_nets {u_subtitle_commit/ack}] -to [get_regs -hier {u_subtitle_commit/ack_sync*}]
set_max_delay -datapath_only 20 -through [get_nets {present_toggle}] -to [get_regs -hier {present_sys_sync*}]
set_false_path -hold -through [get_nets {present_toggle}] -to [get_regs -hier {present_sys_sync*}]
set_max_delay -datapath_only 20 -from [get_regs -hier {u_present/u_transition/g_effect$state*}] -to [get_regs -hier {transition_busy_sync*}]
set_false_path -hold -from [get_regs -hier {u_present/u_transition/g_effect$state*}] -to [get_regs -hier {transition_busy_sync*}]

# SPI mode 3 at 12.5 MHz samples 50 ns after internal falling SCLK.
# Budget: SCLK register-to-pad <=5 ns, card tCO <=14 ns, board round trip
# allowance <=2 ns, MISO pad-to-register <=8 ns: <=29 ns, 21 ns reserve.
# Board/card allowance is an explicit design assumption, not a measurement.
# These are maximum datapath bounds, not false paths or extra cycle waivers.
set_max_delay -datapath_only 5 -to [get_ports sd_dclk]
set_max_delay -datapath_only 8 -from [get_ports sd_miso] -to [get_regs -hier {u_sd_transport/spi_master_m0/MISO_shift*}]
# Bound command and chip-select outputs as well as the returned data path.
# With a 40 ns half period, <=8 ns output paths leave >=32 ns before
# the following internal sampling edge (before board/card setup allowance).
set_max_delay -datapath_only 8 -to [get_ports sd_mosi]
set_max_delay -datapath_only 8 -to [get_ports sd_ncs]

# u_theme_audio_command: held until acknowledged; capture after synchronizer.
set_max_delay -datapath_only 20 -from [get_regs -hier {u_theme_audio_command/held*}] -to [get_regs -hier {u_theme_audio_command/dst_data*}]
set_false_path -hold -from [get_regs -hier {u_theme_audio_command/held*}] -to [get_regs -hier {u_theme_audio_command/dst_data*}]
set_max_delay -datapath_only 20 -through [get_nets {u_theme_audio_command/request}] -to [get_regs -hier {u_theme_audio_command/request_sync*}]
set_false_path -hold -through [get_nets {u_theme_audio_command/request}] -to [get_regs -hier {u_theme_audio_command/request_sync*}]
set_max_delay -datapath_only 20 -through [get_nets {u_theme_audio_command/ack}] -to [get_regs -hier {u_theme_audio_command/ack_sync*}]
set_false_path -hold -through [get_nets {u_theme_audio_command/ack}] -to [get_regs -hier {u_theme_audio_command/ack_sync*}]

# u_theme_audio_result: held until acknowledged; capture after synchronizer.
set_max_delay -datapath_only 20 -from [get_regs -hier {u_theme_audio_result/held*}] -to [get_regs -hier {u_theme_audio_result/dst_data*}]
set_false_path -hold -from [get_regs -hier {u_theme_audio_result/held*}] -to [get_regs -hier {u_theme_audio_result/dst_data*}]
set_max_delay -datapath_only 20 -through [get_nets {u_theme_audio_result/request}] -to [get_regs -hier {u_theme_audio_result/request_sync*}]
set_false_path -hold -through [get_nets {u_theme_audio_result/request}] -to [get_regs -hier {u_theme_audio_result/request_sync*}]
set_max_delay -datapath_only 20 -through [get_nets {u_theme_audio_result/ack}] -to [get_regs -hier {u_theme_audio_result/ack_sync*}]
set_false_path -hold -through [get_nets {u_theme_audio_result/ack}] -to [get_regs -hier {u_theme_audio_result/ack_sync*}]

# u_theme_video: held until acknowledged; capture after synchronizer.
set_max_delay -datapath_only 20 -from [get_regs -hier {u_theme_video/held*}] -to [get_regs -hier {u_theme_video/dst_data*}]
set_false_path -hold -from [get_regs -hier {u_theme_video/held*}] -to [get_regs -hier {u_theme_video/dst_data*}]
set_max_delay -datapath_only 20 -through [get_nets {u_theme_video/request}] -to [get_regs -hier {u_theme_video/request_sync*}]
set_false_path -hold -through [get_nets {u_theme_video/request}] -to [get_regs -hier {u_theme_video/request_sync*}]
set_max_delay -datapath_only 20 -through [get_nets {u_theme_video/ack}] -to [get_regs -hier {u_theme_video/ack_sync*}]
set_false_path -hold -through [get_nets {u_theme_video/ack}] -to [get_regs -hier {u_theme_video/ack_sync*}]

# u_theme_audio_error: held until acknowledged; capture after synchronizer.
set_max_delay -datapath_only 20 -from [get_regs -hier {u_theme_audio_error/held*}] -to [get_regs -hier {u_theme_audio_error/dst_data*}]
set_false_path -hold -from [get_regs -hier {u_theme_audio_error/held*}] -to [get_regs -hier {u_theme_audio_error/dst_data*}]
set_max_delay -datapath_only 20 -through [get_nets {u_theme_audio_error/request}] -to [get_regs -hier {u_theme_audio_error/request_sync*}]
set_false_path -hold -through [get_nets {u_theme_audio_error/request}] -to [get_regs -hier {u_theme_audio_error/request_sync*}]
set_max_delay -datapath_only 20 -through [get_nets {u_theme_audio_error/ack}] -to [get_regs -hier {u_theme_audio_error/ack_sync*}]
set_false_path -hold -through [get_nets {u_theme_audio_error/ack}] -to [get_regs -hier {u_theme_audio_error/ack_sync*}]





# P rebase: held payload captured after 2FF request, stable until returned ack.
set_max_delay -datapath_only 20 -from [get_regs -hier {u_rover_snapshot/held*}] -to [get_regs -hier {u_rover_snapshot/dst_data*}]
set_false_path -hold -from [get_regs -hier {u_rover_snapshot/held*}] -to [get_regs -hier {u_rover_snapshot/dst_data*}]
set_max_delay -datapath_only 20 -through [get_nets {u_rover_snapshot/request}] -to [get_regs -hier {u_rover_snapshot/request_sync*}]
set_false_path -hold -through [get_nets {u_rover_snapshot/request}] -to [get_regs -hier {u_rover_snapshot/request_sync*}]
set_max_delay -datapath_only 20 -through [get_nets {u_rover_snapshot/ack}] -to [get_regs -hier {u_rover_snapshot/ack_sync*}]
set_false_path -hold -through [get_nets {u_rover_snapshot/ack}] -to [get_regs -hier {u_rover_snapshot/ack_sync*}]
