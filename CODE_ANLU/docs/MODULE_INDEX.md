# 模块分层索引

层次为功能归属；文件路径保持完赛工程原结构，工程编译顺序没有变化。加密厂商模块与软件生成 ROM 同样属于必要输入。

## 讲解与音频调度

- `rtl/adaptive_progress.v`
- `rtl/audio_diagnostic_snapshot.v`
- `rtl/bgm_audio_player.v`
- `rtl/theme_audio_player.v`

## PCM 与 HDMI 音视频封装

- `rtl/audio/m06_pcm_contract_adapter.v`
- `rtl/audio/pcm_async_fifo.v`
- `rtl/audio/pcm_continuous_output.v`
- `rtl/audio/pcm_media_tone.v`
- `rtl/audio/pcm_source_select.v`
- `rtl/audio/pcm_test_tone.v`
- `rtl/audio/pcm_tick_48k.v`
- `rtl/audio/wav_pcm_stream.v`
- `rtl/audio/wav_riff_parser.v`
- `rtl/hdmi_audio/hdmi_audio_acr_packetizer.v`
- `rtl/hdmi_audio/hdmi_audio_infoframe_packetizer.v`
- `rtl/hdmi_audio/hdmi_audio_packet_scheduler.v`
- `rtl/hdmi_audio/hdmi_audio_sample_packetizer.v`
- `rtl/hdmi_audio/hdmi_audio_symbol_core.v`
- `rtl/hdmi_audio/hdmi_bch8.v`
- `rtl/hdmi_audio/hdmi_data_island_mapper.v`
- `rtl/hdmi_audio/hdmi_data_island_scheduler.v`
- `rtl/hdmi_audio/hdmi_terc4_encoder.v`
- `rtl/hdmi_audio/hdmi_tmds_channel_encoder.v`
- `rtl/integration/media_hdmi_audio_bridge.v`
- `rtl/integration/video_audio_coordinates.v`

## 显示、缩放、转场与缩略图

- `rtl/bilinear_rgb_serial.v`
- `rtl/scale_divider.v`
- `rtl/thumbnail_controller.v`
- `rtl/thumbnail_inputs.v`
- `rtl/thumbnail_page_builder.v`
- `rtl/thumbnail_subsystem.v`
- `rtl/video_fade_transition.v`
- `rtl/video_timing_registered.v`
- `rtl/video_transition_coordinates.v`
- `rtl/video_transition_rgb.v`

## TF 文件系统与媒体读取

- `rtl/bmp24_decoder.v`
- `rtl/bmp24_header.v`
- `rtl/fat32_bgm_stream.v`
- `rtl/fat32_bmp_loader.v`
- `rtl/fat32_directory_catalog.v`
- `rtl/fat32_stream_cursor.v`
- `rtl/fat32_volume_geometry.v`
- `rtl/sd_sector_adapter.v`
- `rtl/sd_sector_arbiter.v`
- `rtl/sd_transport_cdc.v`

## 板级物理输出

- `rtl/board/hdmi_phy_warpper.v`
- `rtl/board/lane_lvds_10_1.v`

## 缓存、存储事务与故障管理

- `rtl/catalog_snapshot_bridge.v`
- `rtl/frame_buffer_pair.v`
- `rtl/frame_cache_manager.v`
- `rtl/frame_commit_guard.v`
- `rtl/frame_present_control.v`
- `rtl/frame_write_reset_guard.v`
- `rtl/media_fault_monitor.v`
- `rtl/media_recovery_policy.v`
- `rtl/memory_load_reset.v`
- `rtl/quad_frame_present.v`
- `rtl/quad_frame_store.v`
- `rtl/quad_slot_allocator.v`

## 输入、主题、模式与前面板控制

- `rtl/display/promax_audio_waveform.v`
- `rtl/image_key_control.v`
- `rtl/image_number_display.v`
- `rtl/key1_mode_control.v`
- `rtl/key_beeper.v`
- `rtl/key_debounce.v`
- `rtl/player_front_panel.v`
- `rtl/sw2_direction_filter.v`
- `rtl/tf_startup_control.v`
- `rtl/theme_control.v`

## 副屏二维扫描与模型交互

- `rtl/eval/p_panel_span.v`
- `rtl/eval/p_rover_control.v`
- `rtl/eval/p_rover_overlay.v`
- `rtl/eval/p_rover_scan.v`
- `rtl/eval/p_rover_video.v`

## 主屏 OSD、字幕与图像调节

- `rtl/image_status_osd.v`
- `rtl/loading_spinner_rgb.v`
- `rtl/osd_compositor.v`
- `rtl/osd_font16.v`
- `rtl/osd_mode_policy.v`
- `rtl/osd_priority_layer.v`
- `rtl/osd_state_snapshot.v`
- `rtl/osd_timebase.v`
- `rtl/picture_adjust_rgb.v`
- `rtl/picture_param_commit.v`
- `rtl/picture_param_control.v`
- `rtl/picture_param_osd.v`
- `rtl/subtitle_frame_commit.v`
- `rtl/subtitle_scroll.v`
- `rtl/theme_osd.v`

## UART 协议、事件与串行收发

- `rtl/subtitle_uart_controller.v`
- `rtl/subtitle_uart_service.v`
- `rtl/uart_rx_byte.v`
- `rtl/uart_system_events.v`
- `rtl/uart_tx_byte.v`

## 系统顶层

- `rtl/tf_image_top.v`

## ROM 与字形资源

- `rtl/theme_rom/ascii.hex`
- `rtl/theme_rom/console_ascii.hex`
- `rtl/theme_rom/console_lines.hex`
- `rtl/theme_rom/console_titles.hex`
- `rtl/theme_rom/cover.hex`
- `rtl/theme_rom/cue.hex`
- `rtl/theme_rom/glyph.hex`
- `rtl/theme_rom/glyph_high.hex`
- `rtl/theme_rom/glyph_low.hex`
- `rtl/theme_rom/palette.hex`
- `rtl/theme_rom/text.hex`
- `rtl/theme_rom/ui.hex`

## 厂商依赖

- `rtl/vendor/enc_file/DVITransmitter.enc.vhd`
- `rtl/vendor/enc_file/SerializerN_1_lvds.enc.vhd`
- `rtl/vendor/enc_file/SerializerN_1_lvds_dat.enc.vhd`
- `rtl/vendor/enc_file/TMDSEncoder.enc.vhd`
- `rtl/vendor/hdmi_tx.vhd`
- `rtl/vendor/tf_reference/include/global_def.v`
- `rtl/vendor/tf_reference/include/sdr_as_ram.enc.v`
- `rtl/vendor/tf_reference/include/sdr_init_ref.enc.v`
- `rtl/vendor/tf_reference/include/sdr_wrrd.enc.v`
- `rtl/vendor/tf_reference/IP/afifo_16_32_256.v`
- `rtl/vendor/tf_reference/IP/afifo_32_16_256.v`
- `rtl/vendor/tf_reference/IP/sys_pll.v`
- `rtl/vendor/tf_reference/SD/frame_fifo_read.v`
- `rtl/vendor/tf_reference/SD/frame_fifo_write.v`
- `rtl/vendor/tf_reference/SD/frame_read_write.v`
- `rtl/vendor/tf_reference/SD/sd_card_cmd.v`
- `rtl/vendor/tf_reference/SD/sd_card_sec_read_write.v`
- `rtl/vendor/tf_reference/SD/sd_card_top.v`
- `rtl/vendor/tf_reference/SD/sdram.v`
- `rtl/vendor/tf_reference/SD/spi_master.v`
- `rtl/vendor/tf_reference/SD/video_delay.v`
