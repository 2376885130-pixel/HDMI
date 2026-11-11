// Automatically indexed FAT32/BMP -> embedded SDRAM -> existing video transmitter.
// KEY1(A2): short release switches mode; hold 2s resets. HDMI_A and HDMI_B both output video and 48 kHz image-linked audio.
module tf_image_top #(parameter TRANSITION_FRAMES=12,TRANSITION_MODE=4,LEGACY_CONTROLS=0) (
    input wire sys_clk, input wire sys_rst_n,
    input wire key_next_n, key_prev_n, key_auto_n,
    input wire [1:0] interval_switch,
    input wire direction_switch,parameter_switch,
    output wire [7:0] seg_n,digit_en,
    output wire buzzer_n,
    output wire HDMI_CLK_P, HDMI_D0_P, HDMI_D1_P, HDMI_D2_P,
    output wire HDMI_CLK_P1, HDMI_D0_P1, HDMI_D1_P1, HDMI_D2_P1,
    output wire sd_ncs, sd_dclk, sd_mosi, input wire sd_miso,
    input wire uart_rx,output wire uart_tx
);
    wire system_reset_n,pll_reset_n,basic_request,basic_video;
    key1_mode_control #(.POR_CYCLES(16),.FILTER(8),.LONG_CYCLES(200)) u_key1(.clk(sys_clk),.key1_n(sys_rst_n),
        .reset_n(system_reset_n),.basic_request(basic_request),.short_event(),.pll_reset_n(pll_reset_n));
    assign buzzer_n=1'b1;
    wire pixel_clk, serial_clk, video_lock;
    wire sd_clk, spi_clk, mem_clk, mem_clk_shift, memory_lock;
    video_pll u_video_pll (.refclk(sys_clk),.reset(~pll_reset_n),
        .extlock(video_lock),.clk0_out(serial_clk),.clk1_out(pixel_clk));
    sys_pll u_memory_pll (.refclk(sys_clk),.reset(~pll_reset_n),
        .extlock(memory_lock),.clk0_out(sd_clk),.clk1_out(mem_clk),.clk2_out(mem_clk_shift),.clk3_out(spi_clk));

    // Internal reset asserts on power-on or qualified long KEY1; control logic leaves reset on sys_clk only.
    (* preserve = 1, keep = 1 *) reg [2:0] control_reset_pipe=0;
    always @(posedge sys_clk or negedge system_reset_n)
        if(!system_reset_n) control_reset_pipe<=0;
        else control_reset_pipe<={control_reset_pipe[1:0],1'b1};
    wire control_reset_n=control_reset_pipe[2];
    // A single held mode bit returns from video; inter-stage paths remain timed.
    (* async_reg="true",preserve=1,keep=1 *) reg [1:0] basic_sync=3;
    // Video rising edges align with board-clock rising edges. Capture the
    // stable mode on the falling edge first, then on the rising edge, retaining
    // two stages and a timed half-cycle instead of a short cross-clock hold path.
    always @(negedge sys_clk or negedge control_reset_n)
        if(!control_reset_n)basic_sync[0]<=1;else basic_sync[0]<=basic_video;
    always @(posedge sys_clk or negedge control_reset_n)
        if(!control_reset_n)basic_sync[1]<=1;else basic_sync[1]<=basic_sync[0];
    // Loss of either PLL is immediate; a stable lock is qualified in sys_clk.
    wire clocks_ready=system_reset_n & video_lock & memory_lock;
    (* preserve = 1, keep = 1 *) reg [2:0] lock_pipe=0;
    always @(posedge sys_clk or negedge clocks_ready)
        if(!clocks_ready) lock_pipe<=0;
        else lock_pipe<={lock_pipe[1:0],1'b1};
    wire clocks_ready_sys=lock_pipe[2];

    wire [3:0] load_status,loader_status,loader_stage,cache_status,cache_stage,diagnostic_stage,fault_code,fault_stage;
    wire memory_fault;
    reg [1:0] memory_fault_sync;
    assign load_status=memory_fault_sync[1] ? 4'd14 : cache_status;
    assign diagnostic_stage=memory_fault_sync[1] ? 4'd6 : cache_stage;
    wire recovery_next,manual_restart,retry_exhausted;
    (* keep = 1 *) wire [4:0] fault_image;
    (* keep = 1 *) wire [31:0] fault_lba;
    wire fault_event,recovery_stopped;
    wire image_ready;
    wire sd_rst,video_rst;
    wire write_req,write_ack,pixel_valid,write_finish;
    wire [4:0] image_index;
    wire [5:0] catalog_total;
    wire catalog_valid;
    wire [87:0] image_name;
    wire [5:0] image_total;
    wire [1:0] stable_interval;
    wire stable_direction;
    // Same physical switch synchronizer; SW2 now selects timed forward slides.
    wire sw2_reverse;
    sw2_direction_filter u_sw2_direction(.clk(sys_clk),.rst_n(control_reset_n),
        .sw2_up(interval_switch[1]),.reverse_mode(sw2_reverse));
    // Hold the completed catalog snapshot through each per-image reset.
    catalog_snapshot_bridge u_catalog_snapshot(.source_clk(sd_clk),.control_clk(sys_clk),
        .reset_n(system_reset_n),.catalog_valid(catalog_valid),.catalog_total(catalog_total),
        .image_total(image_total),.catalog_event());
    wire run_reset_n;
    wire job_start,job_cancel,writer_enable,writer_reset,transport_reset;
    wire [4:0] job_index,cache_present_index;
    wire [1:0] cache_present_slot;
    wire [87:0] cache_present_name;
    wire cache_present_toggle,cache_present_ack;
    (* preserve = 1, keep = 1 *) reg [1:0] load_error_sync=0;
    wire auto_mode;
    wire [8:0] transition_gain;
    wire transition_busy,reveal_active;
    wire [1:0] transition_kind;
    (* preserve=1,keep=1 *) reg [2:0] transition_busy_sync;
    always @(posedge sys_clk or negedge clocks_ready)
        if(!clocks_ready)transition_busy_sync<=0;
        else transition_busy_sync<={transition_busy_sync[1:0],transition_busy};
    wire show_image,transaction_presented,frame_valid,present_commit;
    wire [4:0] displayed_index_video;
    wire [87:0] displayed_name_video;
    wire [1:0] display_slot,load_slot,read_slot;
    wire [3:0] slot_valid;
    reg present_toggle;
    (* preserve=1,keep=1 *) reg [2:0] present_sys_sync;
    reg [4:0] displayed_index_sys;
    (* preserve=1,keep=1 *) reg [1:0] show_image_sync;
    always @(negedge sys_clk or negedge clocks_ready)
        if(!clocks_ready)show_image_sync[0]<=0;else show_image_sync[0]<=show_image;
    always @(posedge sys_clk or negedge clocks_ready)
        if(!clocks_ready)show_image_sync[1]<=0;else show_image_sync[1]<=show_image_sync[0];
    assign transaction_presented=show_image_sync[1] && displayed_index_sys==image_index && run_reset_n;

    always @(posedge pixel_clk or posedge video_rst)
        if(video_rst)present_toggle<=0;else if(present_commit)present_toggle<=~present_toggle;
    always @(posedge sys_clk or negedge clocks_ready)begin
        if(!clocks_ready)begin present_sys_sync<=0;end
        else begin
            present_sys_sync<={present_sys_sync[1:0],present_toggle};
        end
    end
    // The index is held until the next frame commit. Capture after the toggle
    // traverses 2FFs, on the opposite edge to avoid related-clock hold skew.
    always @(negedge sys_clk or negedge clocks_ready)
        if(!clocks_ready)displayed_index_sys<=0;
        else if(present_sys_sync[2]!=present_sys_sync[1])displayed_index_sys<=displayed_index_video;
    // Physical pins retained: interval_switch[0]=SW1, [1]=SW2; direction_switch=SW3.
    // SW3 down enters thumbnails; KEY4 selects there, controls volume otherwise.
    wire preview_hold,thumb_select,thumb_switch,key4_press,next_event,prev_event;
    wire [4:0] thumb_index;
    wire visible_preview,visible_bank,preview_request,read_preview,read_bank;
    wire zoom_active_video,page_zoom,visible_zoom,builder_busy;
    wire [9:0] builder_progress,load_progress_rows;
    wire [2:0] visible_page,requested_page,page_number;
    wire [3:0] visible_valid,page_valid;
    wire [4:0] target_index,source_index;
    wire [1:0] focus_video,source_slot;
    wire [1:0] focus_frame;
    wire page_toggle,page_bank,page_ack,source_req,source_ack,source_ok;
    wire dma_req,dma_write,dma_accept,dma_done,dma_valid;
    wire [20:0] dma_addr;wire [31:0] dma_wdata,dma_rdata;wire [6:0] dma_word;
    wire panel_auto_enable;
    wire [2:0] volume_level_sys,volume_level_video;
    wire [8:0] volume_audio=volume_level_video<=4 ? {volume_level_video,6'b0} : 9'd128;
    wire volume_key_n;
    wire [9:0] x,y;
    wire menu_reserved,menu_active,menu_selected,key2_pass,key3_pass,key4_pass;
    wire [7:0] brightness_sys,contrast_sys;
    wire menu_frame,selected_frame;
    wire [7:0] brightness_frame,contrast_frame;
    wire theme_home,theme_play_enable,theme_autoplay,theme_manual_effect,manual_transition;
    wire [19:0] theme_video;
    wire [1:0] theme_id;wire [7:0] theme_hold_progress;
    wire theme_key2_n,theme_key3_n,theme_key4_n,theme_preview_up,theme_menu_up;
    wire theme_audio_done;wire [4:0] theme_audio_id;
    wire demo_active,demo_blocked,demo_key2,demo_key3,demo_key4,demo_sw3,demo_sw4;
    wire [63:0] demo_state_sys,demo_mailbox;
    reg [63:0] demo_state_video;
    wire uart_theme_valid,uart_demo_valid,uart_demo_enable;wire [1:0] uart_theme;
    p_rover_control #(.FILTER(8),.SETTLE(32)) u_rover_control(.clk(sys_clk),.rst_n(control_reset_n),.home(theme_home),.model_id(theme_id),
        .sw3_up(direction_switch),.sw4_up(parameter_switch),.key2_n(key_next_n),.key3_n(key_prev_n),.key4_n(key_auto_n),
        .active(demo_active),.blocked(demo_blocked),.main_key2_n(demo_key2),.main_key3_n(demo_key3),.main_key4_n(demo_key4),
        .main_sw3_up(demo_sw3),.main_sw4_up(demo_sw4),.state(demo_state_sys),
        .uart_demo_valid(uart_demo_valid),.uart_demo_enable(uart_demo_enable));
    osd_state_snapshot #(.WIDTH(64)) u_rover_snapshot(sys_clk,control_reset_n,demo_state_sys,pixel_clk,~video_rst,demo_mailbox);
    always @(posedge pixel_clk or posedge video_rst)
        if(video_rst)demo_state_video<=0;
        else if(x==0&&y==480)demo_state_video<=demo_mailbox;
    theme_control #(.CLOCK_HZ(1000),.DEBOUNCE(8)) u_theme(.clk(sys_clk),.rst_n(control_reset_n),.demo_hold(demo_blocked),
        .key2_n(demo_key2),.key3_n(demo_key3),.key4_n(demo_key4),
        .sw1_up(interval_switch[0]),.sw3_up(demo_sw3),.sw4_up(demo_sw4),
        .reverse_mode(1'b0),.timed_mode(sw2_reverse),
        .ready(transaction_presented && !transition_busy_sync[2]),.preview_hold(preview_hold),.menu_reserved(menu_reserved),.load_error(load_error_sync[1]),
        .next_event(next_event),.prev_event(prev_event),.select_valid(thumb_select),.select_index(thumb_index),
        .audio_done(theme_audio_done),.audio_id(theme_audio_id),.home(theme_home),.theme(theme_id),.index(image_index),
        .routed_key2_n(theme_key2_n),.routed_key3_n(theme_key3_n),.routed_key4_n(theme_key4_n),
        .preview_up(theme_preview_up),.menu_up(theme_menu_up),.autoplay(theme_autoplay),.play_enable(theme_play_enable),
        .hold_progress(theme_hold_progress),.restart_event(manual_restart),.manual_effect(theme_manual_effect),
        .uart_theme_valid(uart_theme_valid),.uart_theme(uart_theme));
    assign run_reset_n=control_reset_n;
    assign stable_interval=2'd1;assign stable_direction=1'b0;assign auto_mode=theme_autoplay;
    key_debounce theme_next(sys_clk,control_reset_n,key2_pass,next_event);
    key_debounce theme_prev(sys_clk,control_reset_n,key3_pass,prev_event);
    picture_param_control u_picture_control(.clk(sys_clk),.rst_n(control_reset_n),
        .sw4_up(theme_menu_up),.key2_n(theme_key2_n),.key3_n(theme_key3_n),.key4_n(theme_key4_n),
        .reserved(menu_reserved),.menu_active(menu_active),.selected_contrast(menu_selected),
        .pass_key2_n(key2_pass),.pass_key3_n(key3_pass),.pass_key4_n(key4_pass),
        .brightness(brightness_sys),.contrast(contrast_sys));
    picture_param_commit u_picture_commit(.src_clk(sys_clk),.src_rst_n(control_reset_n),
        .menu_active(menu_active),.selected_contrast(menu_selected),.brightness(brightness_sys),.contrast(contrast_sys),
        .pixel_clk(pixel_clk),.pixel_rst(video_rst),.frame_start(x==0 && y==0),
        .menu_frame(menu_frame),.selected_frame(selected_frame),.brightness_frame(brightness_frame),.contrast_frame(contrast_frame));
    thumbnail_inputs u_thumbnail_inputs(.clk(sys_clk),.rst_n(control_reset_n),.enabled(!LEGACY_CONTROLS),
        .sw3_up(theme_preview_up),.key4_n(key4_pass),.preview_hold(preview_hold),
        .switch_down(thumb_switch),.key4_press(key4_press),.volume_key_n(volume_key_n));
    player_front_panel u_front_panel(.clk(sys_clk),.rst_n(control_reset_n),
        .sw1_up(interval_switch[0]),.key_volume_n(volume_key_n),
        .autoplay_enable(panel_auto_enable),.volume_level(volume_level_sys));
    osd_state_snapshot #(.WIDTH(3)) u_volume_snapshot(
        .src_clk(sys_clk),.src_rst_n(control_reset_n),.src_data(volume_level_sys),
        .dst_clk(pixel_clk),.dst_rst_n(~video_rst),.dst_data(volume_level_video));
    wire [32:0] preview_fault_sd,preview_fault_sys;
    image_number_display #(.TIMED_SECONDS(3),.STATUS_UI(1),.DIAGNOSTIC_UI(1),.FOLLOW_DISPLAY_INDEX(1)) u_image_number (.clk(sys_clk),.reset_n(control_reset_n),
        .image_index(show_image_sync[1] ? displayed_index_sys : image_index),.total_count(image_total),.seg_n(seg_n),.digit_en(digit_en),
        .image_shown(show_image_sync[1]),.load_status(load_status),.interval_setting(stable_interval),
        .auto_mode(sw2_reverse),.reverse_direction(stable_direction),.fault_stage(fault_stage),
        .fault_display(preview_fault_sys[32]),.fault_code(preview_fault_sys[31:0]));
    // Read-only instrumentation: it never resets or controls any media block.
    osd_state_snapshot #(.WIDTH(33)) u_preview_fault_snapshot(
        .src_clk(sd_clk),.src_rst_n(system_reset_n),.src_data(preview_fault_sd),
        .dst_clk(sys_clk),.dst_rst_n(control_reset_n),.dst_data(preview_fault_sys));
    wire startup_done;
    (* preserve = 1, keep = 1 *) reg [1:0] ready_sys_sync=0;
    reg has_loaded=0,video_started=0;
    always @(negedge sys_clk or negedge control_reset_n)
        if(!control_reset_n)ready_sys_sync[0]<=0;else ready_sys_sync[0]<=image_ready;
    always @(posedge sys_clk or negedge control_reset_n) begin
        if(!control_reset_n) begin ready_sys_sync[1]<=0;has_loaded<=0;video_started<=0;end
        else begin
            ready_sys_sync[1]<=ready_sys_sync[0];
            if(ready_sys_sync[1]) has_loaded<=1;
            if(!clocks_ready_sys) begin video_started<=0;has_loaded<=0;end
            else if(startup_done) video_started<=1;
        end
    end
    always @(negedge sys_clk or negedge control_reset_n)
        if(!control_reset_n)load_error_sync[0]<=0;else load_error_sync[0]<=load_status>=10;
    always @(posedge sys_clk or negedge control_reset_n)
        if(!control_reset_n)load_error_sync[1]<=0;else load_error_sync[1]<=load_error_sync[0];
    tf_startup_control #(.POWER_WAIT_CYCLES(64)) u_startup (.clk(sys_clk),.reset_n(control_reset_n),
        .locked(clocks_ready_sys),.load_error(load_error_sync[1] && image_total==0),
        .run_enable(startup_done),.fast_start(1'b0),
        .load_success(ready_sys_sync[1]),.exhausted_pulse(retry_exhausted));
    // Reset timing stays in startup_control. This policy only selects a new file.
    media_recovery_policy u_recovery (.clk(sys_clk),.reset_n(control_reset_n),
        .image_shown(transaction_presented),.manual_restart(manual_restart),
        .exhausted_pulse(retry_exhausted | fault_event),.fault_code(fault_code),.fault_stage(fault_stage),
        .image_total(image_total),.next_pulse(recovery_next),.stopped(recovery_stopped));
    (* keep = 1 *) wire ready_clock=system_reset_n & startup_done & video_lock & memory_lock;
    // Asynchronous assertion, three-clock synchronous release per domain.
    // tf_image.sdc exempts only asynchronous requests entering these synchronizers.
    (* preserve = 1, keep = 1 *) reg [2:0] sd_reset_pipe=0,video_reset_pipe=0;
    always @(posedge sd_clk or negedge ready_clock)
        if(!ready_clock) sd_reset_pipe<=0;else sd_reset_pipe<={sd_reset_pipe[1:0],1'b1};
    wire mem_rst;
    wire memory_power_ready=system_reset_n & video_lock & memory_lock;
    memory_load_reset u_memory_reset(.clk(mem_clk),.power_ready(memory_power_ready),
        .load_enable(1'b1),.rst(mem_rst));
    (* keep = 1 *) wire video_ready=system_reset_n & video_started & video_lock & memory_lock;
    always @(posedge pixel_clk or negedge video_ready)
        if(!video_ready) video_reset_pipe<=0;else video_reset_pipe<={video_reset_pipe[1:0],1'b1};
    assign sd_rst=~sd_reset_pipe[2];
    assign video_rst=~video_reset_pipe[2];
    always @(posedge sd_clk or negedge memory_power_ready)
        if(!memory_power_ready)memory_fault_sync<=0;
        else memory_fault_sync<={memory_fault_sync[0],memory_fault};
    wire sector_req,sector_valid,sector_end,sd_ready;
    wire [31:0] sector_lba;
    wire [7:0] sector_byte;
    wire sector_busy;
    wire [7:0] sector_error;
    wire reader_req,reader_valid,reader_done;
    wire [31:0] reader_lba;
    wire [7:0] reader_byte;
    wire bus_req,bus_busy,bus_valid,bus_done,arb_recover;
    wire[31:0]bus_lba;wire[7:0]bus_error;
    wire bgm_req,bgm_busy,bgm_valid,bgm_done;wire[31:0]bgm_lba;wire[7:0]bgm_error;
    wire[31:0]audio_root,audio_fat,audio_data,audio_max;
    wire[3:0]audio_shift;wire[7:0]audio_spc;
    wire wav_selected,wav_valid,wav_ready,audio_tick;
    wire signed[15:0]wav_left,wav_right;wire[127:0]audio_diag_sd,audio_diag_sys;
    reg bgm_boot_complete;
    // First-load failures must be captured too, before the first picture/audio.
    preview_first_fault u_preview_first_fault(.clk(sd_clk),.reset_n(system_reset_n),.armed(!sd_rst),
        .bus_done(bus_done),.bus_error(bus_error),.audio_status(audio_diag_sd[7:0]),.audio_parse(audio_diag_sd[15:8]),
        .loader_status(loader_status),.loader_stage(loader_stage),.job_index(job_index),
        .source_req(source_req),.source_ack(source_ack),.source_ok(source_ok),.record(preview_fault_sd));
    sd_sector_arbiter u_sector_arbiter(.clk(sd_clk),.rst(sd_rst|transport_reset),
        .cancel_image(job_cancel),.ready(sd_ready),.image_req(sector_req),.image_lba(sector_lba),
        .image_busy(sector_busy),.image_valid(sector_valid),.image_done(sector_end),.image_error(sector_error),
        .audio_req(bgm_req),.audio_lba(bgm_lba),.audio_busy(bgm_busy),.audio_valid(bgm_valid),.audio_done(bgm_done),.audio_error(bgm_error),
        .request(bus_req),.lba(bus_lba),.busy(bus_busy),.valid(bus_valid),.done(bus_done),.error(bus_error),.recover(arb_recover));
    wire sd_response_fault;
    sd_sector_adapter u_sector_service (
        .clk(sd_clk),.rst(sd_rst | transport_reset | arb_recover),.sd_ready(sd_ready),
        .sector_req(bus_req),.sector_lba(bus_lba),.sector_busy(bus_busy),
        .sector_valid(bus_valid),.sector_byte(sector_byte),.sector_byte_index(),
        .sector_done(bus_done),.sector_error(bus_error),
        .reader_req(reader_req),.reader_lba(reader_lba),.reader_valid(reader_valid),
        .reader_byte(reader_byte),.reader_done(reader_done),.reader_fault(sd_response_fault));
    // Start music only after the first frame has reached the display. Latch
    // this once per storage session so later picture switches do not stop BGM.
    (* preserve=1,keep=1 *) reg [1:0] bgm_shown_sync;
    always @(posedge sd_clk or posedge sd_rst)begin
        if(sd_rst)begin bgm_shown_sync<=0;bgm_boot_complete<=0;end
        else begin
            bgm_shown_sync<={bgm_shown_sync[0],show_image};
            if(bgm_shown_sync[1])bgm_boot_complete<=1;
        end
    end
    // Give the audio consumer its own registered sector bundle. Image parsing
    // keeps the already-validated service byte cadence; audio cannot extend
    // the combinational path from the transport data into the image loader.
    reg bgm_valid_q,bgm_done_q;reg [7:0]bgm_data_q,bgm_error_q;
    always @(posedge sd_clk or posedge sd_rst)begin
        if(sd_rst)begin bgm_valid_q<=0;bgm_done_q<=0;bgm_data_q<=0;bgm_error_q<=0;end
        else if(transport_reset)begin bgm_valid_q<=0;bgm_done_q<=0;bgm_data_q<=0;bgm_error_q<=0;end
        else begin
            bgm_valid_q<=bgm_valid;bgm_done_q<=bgm_done;
            if(bgm_valid)bgm_data_q<=sector_byte;
            if(bgm_done)bgm_error_q<=bgm_error;
        end
    end
    wire [6:0] theme_audio_command,theme_audio_result;
    wire narration_done,narration_playing,narration_basic;wire [4:0] narration_id;wire [31:0] narration_frames;
    osd_state_snapshot #(.WIDTH(7)) u_theme_audio_command(sys_clk,control_reset_n,{basic_sync[1],theme_play_enable,image_index},sd_clk,~sd_rst,theme_audio_command);
    osd_state_snapshot #(.WIDTH(7)) u_theme_audio_result(sd_clk,~sd_rst,{narration_basic,narration_done,narration_id},sys_clk,control_reset_n,theme_audio_result);
    assign theme_audio_done=theme_audio_result[5]&&!theme_audio_result[6]&&!basic_sync[1];
    assign theme_audio_id=theme_audio_result[4:0];
    theme_audio_player u_bgm(.clk(sd_clk),.pixel_clk(pixel_clk),.rst(sd_rst|transport_reset),.pixel_rst(video_rst),
        .play_enable(theme_audio_command[5]),.play_id(theme_audio_command[4:0]),
        .basic_mode(theme_audio_command[6]),.session_basic(narration_basic),
        .finished(narration_done),.session_id(narration_id),.played_frames(narration_frames),.playing_video(narration_playing),
        .mounted(catalog_valid && bgm_boot_complete),.root_cluster(audio_root),.fat_lba(audio_fat),.data_lba(audio_data),.max_cluster(audio_max),
        .cluster_shift(audio_shift),.sectors_per_cluster(audio_spc),
        .req(bgm_req),.lba(bgm_lba),.busy(bgm_busy),.valid(bgm_valid_q),.done(bgm_done_q),.data(bgm_data_q),.error(bgm_error_q),
        .tick(audio_tick),.volume(volume_audio),.selected(wav_selected),.sample_valid(wav_valid),.sample_ready(wav_ready),
        .sample_left(wav_left),.sample_right(wav_right),.diagnostics(audio_diag_sd));
    audio_diagnostic_snapshot u_audio_diagnostics(.src_clk(sd_clk),.src_rst_n(~sd_rst),.src_data(audio_diag_sd),
        .dst_clk(sys_clk),.dst_rst_n(control_reset_n),.dst_data(audio_diag_sys));
    wire spi_rst,spi_req,spi_valid,spi_done,spi_ready;
    wire [31:0] spi_lba;
    wire [7:0] spi_byte;
    sd_transport_cdc u_sd_cdc(.service_clk(sd_clk),.spi_clk(spi_clk),
        .rst(sd_rst | transport_reset | arb_recover),.request(reader_req),.lba(reader_lba),
        .ready(sd_ready),.valid(reader_valid),.data(reader_byte),.done(reader_done),.response_fault(sd_response_fault),
        .spi_reset(spi_rst),.spi_request(spi_req),.spi_lba(spi_lba),
        .spi_ready(spi_ready),.spi_valid(spi_valid),.spi_done(spi_done),.spi_data(spi_byte));
    // C3 is 100 MHz: initialize at 200 kHz, read at conservative 12.5 MHz.
    sd_card_top #(.SPI_LOW_SPEED_DIV(248),.SPI_HIGH_SPEED_DIV(2)) u_sd_transport (
        .clk(spi_clk),.rst(spi_rst),.SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),
        .SD_MOSI(sd_mosi),.SD_MISO(sd_miso),.sd_init_done(spi_ready),
        .sd_sec_read(spi_req),.sd_sec_read_addr(spi_lba),
        .sd_sec_read_data(spi_byte),.sd_sec_read_data_valid(spi_valid),
        .sd_sec_read_end(spi_done),.sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),
        .sd_sec_write_data(8'd0),.sd_sec_write_data_req(),.sd_sec_write_end());

    wire memory_initialized,memory_refresh,memory_busy;
    reg [1:0] memory_init_sync;
    always @(posedge sd_clk or posedge sd_rst)
        if(sd_rst) memory_init_sync<=0;
        else memory_init_sync<={memory_init_sync[0],memory_initialized};
    reg [2:0] write_ack_sync;
    always @(posedge sd_clk or posedge sd_rst)
        if(sd_rst) write_ack_sync<=0;
        else write_ack_sync<={write_ack_sync[1:0],write_ack};
    wire [31:0] pixel_data;
    reg finish_toggle;
    always @(posedge mem_clk or posedge mem_rst)
        if(mem_rst) finish_toggle<=0;
        else if(write_finish) finish_toggle<=~finish_toggle;
    fat32_bmp_loader #(.AUTO_SCAN(1),.REUSE_CATALOG(1)) u_loader (
        .load_progress_rows(load_progress_rows),
        .clk(sd_clk),.rst(sd_rst),.sd_ready(sd_ready),.memory_ready(memory_init_sync[1]),
        .sector_req(sector_req),.sector_lba(sector_lba),.sector_byte(sector_byte),
        .sector_valid(sector_valid),.sector_end(sector_end),
        .sector_busy(sector_busy),.sector_error(sector_error),
        .write_req(write_req),.write_ack(write_ack_sync[2]),.pixel_valid(pixel_valid),
        .pixel_data(pixel_data),.write_finish_toggle(finish_toggle),
        .image_ready(image_ready),.status(loader_status),.image_index(job_index),
        .image_total(catalog_total),.catalog_valid(catalog_valid),.image_name(image_name),
        .diagnostic_stage(loader_stage),.load_start(job_start),.load_cancel(job_cancel),
        .audio_root_cluster(audio_root),.audio_fat_lba(audio_fat),.audio_data_lba(audio_data),.audio_max_cluster(audio_max),
        .audio_cluster_shift(audio_shift),.audio_sectors_per_cluster(audio_spc));
    // Foreground loads remain enabled. Background neighbor prefetch is disabled
    // for this release: it can contend with the live frame/audio workload and
    // raise the global SDRAM fault latch after the first image is already shown.
    frame_cache_manager #(.THUMBNAILS(!LEGACY_CONTROLS),.PREFETCH_ENABLE(0)) u_cache(.clk(sd_clk),.rst(sd_rst),.requested_index(image_index),
        .aux_req(source_req),.aux_index(source_index),.aux_ack(source_ack),.aux_ok(source_ok),.aux_slot(source_slot),
        .request_enable(run_reset_n && (!theme_home || !show_image_sync[1])),.reverse_direction(stable_direction),
        .catalog_valid(catalog_valid),.image_total(catalog_total),.image_ready(image_ready),.image_name(image_name),
        .loader_status(loader_status),.loader_stage(loader_stage),.sector_busy(sector_busy),
        .writer_reset(writer_reset),.write_req(write_req),.sector_req(sector_req),
        .job_start(job_start),.job_cancel(job_cancel),.writer_enable(writer_enable),
        .job_index(job_index),.load_slot(load_slot),.transport_reset(transport_reset),
        .present_toggle(cache_present_toggle),.present_slot(cache_present_slot),
        .present_index(cache_present_index),.present_name(cache_present_name),.present_ack(cache_present_ack),
        .ui_status(cache_status),.ui_stage(cache_stage),.slot_valid(slot_valid));
    media_fault_monitor u_fault_monitor (.source_clk(sd_clk),.report_clk(sys_clk),
        .reset_n(system_reset_n),.status(load_status),.stage(diagnostic_stage),
        .image_index(image_index),.sector_lba(sector_lba),.fault_code(fault_code),
        .fault_stage(fault_stage),.fault_image(fault_image),.fault_lba(fault_lba),
        .fault_event(fault_event));

    wire de,hs,vs;
    video_timing_640x480 u_timing (.pixel_clk(pixel_clk),.rst_n(~video_rst),
        .pixel_x(x),.pixel_y(y),.de(de),.hsync(hs),.vsync(vs));
    wire read_ack,read_req,read_primed,read_underflow;
    quad_frame_present #(.RUNTIME_MODE(1),.LIVE_EFFECT(1),.THUMBNAILS(!LEGACY_CONTROLS),.REQUEST_TOGGLE(1),.FADE_FRAMES(TRANSITION_FRAMES),.TRANSITION_MODE(TRANSITION_MODE)) u_present(.clk(pixel_clk),.rst(video_rst),.x(x),.y(y),
        .basic_request(theme_video[19]),.mode_safe(theme_video[18]),.basic_active(basic_video),
        .manual_effect(theme_video[17]),.effect_index(theme_video[13:9]),.manual_transition(manual_transition),
        .page_zoom(page_zoom),.visible_zoom(visible_zoom),
        .requested_focus(focus_video),.visible_focus(focus_frame),
        .preview_request(preview_request),.requested_page(requested_page),.target_index(target_index),
        .page_toggle(page_toggle),.page_bank(page_bank),.page_number(page_number),.page_valid(page_valid),.page_ack(page_ack),
        .read_preview(read_preview),.read_bank(read_bank),.visible_preview(visible_preview),.visible_bank(visible_bank),.visible_page(visible_page),.visible_valid(visible_valid),
        .load_ready(cache_present_toggle),.load_slot(cache_present_slot),.load_index(cache_present_index),.load_name(cache_present_name),
        .read_ack(read_ack),.read_primed(read_primed),.read_underflow(read_underflow),
        .read_req(read_req),.read_slot(read_slot),.show_image(show_image),
        .presented(cache_present_ack),.frame_valid(frame_valid),
        .display_slot(display_slot),.display_index(displayed_index_video),
        .display_name(displayed_name_video),.commit(present_commit),
        .transition_gain(transition_gain),.transition_busy(transition_busy),
        .transition_kind(transition_kind),.reveal_active(reveal_active));
    wire fifo_read_en,delayed_de,delayed_hs,delayed_vs;
    wire [31:0] fifo_pixel;
    wire [23:0] image_rgb;
    wire [24:0] raw_image;
    wire raw_hs,raw_vs,raw_de;
    reg [2:0] adjust_hs,adjust_vs,adjust_de;
    // FIFO request timing remains 21 clocks. Only the outgoing video grows by three.
    video_delay #(.DATA_WIDTH(25)) u_read_latency (.video_clk(pixel_clk),.rst(video_rst),
        .read_en(fifo_read_en),.read_data({fifo_pixel[31:8],fifo_pixel[0]}),.hs(hs),.vs(vs),.de(de),
        .hs_r(raw_hs),.vs_r(raw_vs),.de_r(raw_de),.vout_data(raw_image));
    picture_adjust_rgb u_picture_pixels(.clk(pixel_clk),.rst(video_rst),
        .rgb_in(raw_image[24:1]),.content_valid(raw_image[0]),
        .brightness(brightness_frame),.contrast(contrast_frame),.rgb_out(image_rgb));
    always @(posedge pixel_clk or posedge video_rst)begin
        if(video_rst)begin adjust_hs<=0;adjust_vs<=0;adjust_de<=0;end
        else begin adjust_hs<={adjust_hs[1:0],raw_hs};adjust_vs<={adjust_vs[1:0],raw_vs};adjust_de<={adjust_de[1:0],raw_de};end
    end
    assign delayed_hs=adjust_hs[2];assign delayed_vs=adjust_vs[2];assign delayed_de=adjust_de[2];

    wire app_rd_en,sdram_rd_valid,app_wr_en;
    wire [20:0] app_rd_addr,app_wr_addr;
    wire [31:0] sdram_rd_data,app_wr_data;
    wire [3:0] app_wr_mask;
    // Global memory reset only; each load can abort its writer after burst drain.
    // 50 MHz: retain >=400 ns drain and 102.4 us timeout from the 40 MHz baseline.
    quad_frame_store #(.THUMBNAILS(!LEGACY_CONTROLS),.DRAIN_CYCLES(20),.RETURN_TIMEOUT(5120)) u_frame(.mem_clk(mem_clk),.rst(mem_rst),.load_enable(startup_done & writer_enable),
        .read_preview(read_preview),.read_bank(read_bank),
        .dma_req(dma_req),.dma_write(dma_write),.dma_addr(dma_addr),.dma_wdata(dma_wdata),
        .dma_accept(dma_accept),.dma_done(dma_done),.dma_valid(dma_valid),.dma_rdata(dma_rdata),.dma_word(dma_word),
        .memory_initialized(memory_initialized),.memory_busy(memory_busy),.memory_refresh(memory_refresh),
        .app_rd_en(app_rd_en),.app_rd_addr(app_rd_addr),.rd_valid(sdram_rd_valid),.rd_data(sdram_rd_data),
        .app_wr_en(app_wr_en),.app_wr_addr(app_wr_addr),.app_wr_data(app_wr_data),.app_wr_mask(app_wr_mask),
        .write_clk(sd_clk),.write_req(write_req),.write_slot(load_slot),.write_ack(write_ack),
        .write_finish(write_finish),.pixel_valid(pixel_valid),.pixel_data(pixel_data),
        .read_clk(pixel_clk),.read_req(read_req),.read_slot(read_slot),.read_ack(read_ack),
        .read_en(fifo_read_en & frame_valid),.read_data(fifo_pixel),.read_primed(read_primed),
        .read_underflow(read_underflow),.memory_fault(memory_fault),.writer_reset(writer_reset));
    thumbnail_subsystem #(.ANIMATIONS(!LEGACY_CONTROLS),.RUNTIME_MODE(1)) u_thumbnails(.effect_bypass(basic_sync[1]),.sys_clk(sys_clk),.sys_rst_n(control_reset_n && clocks_ready_sys),
        .zoom_active_video(zoom_active_video),.builder_busy(builder_busy),.builder_progress(builder_progress),.page_zoom(page_zoom),
        .load_error(load_error_sync[1]),.displayed_index(displayed_index_sys),
        .mem_clk(mem_clk),.mem_rst(mem_rst),.pixel_clk(pixel_clk),.video_rst(video_rst),
        .switch_down(thumb_switch),.key4_press(key4_press && !menu_reserved),.next_press(next_event && !menu_reserved),.prev_press(prev_event && !menu_reserved),
        .first_shown(show_image_sync[1] && !theme_home),.full_ready(transaction_presented && !transition_busy_sync[2]),
        .current_index(image_index),.image_total(image_total),.preview_hold(preview_hold),.select_valid(thumb_select),.select_index(thumb_index),
        .visible_preview(visible_preview),.visible_bank(visible_bank),.visible_page(visible_page),.visible_valid(visible_valid),
        .visible_focus(focus_frame),
        .preview_request(preview_request),.requested_page(requested_page),.target_index(target_index),.focus_video(focus_video),
        .source_req(source_req),.source_index(source_index),.source_ack(source_ack),.source_ok(source_ok),.source_slot(source_slot),
        .dma_req(dma_req),.dma_write(dma_write),.dma_addr(dma_addr),.dma_wdata(dma_wdata),
        .dma_accept(dma_accept),.dma_done(dma_done),.dma_valid(dma_valid),.dma_rdata(dma_rdata),.dma_word(dma_word),
        .page_toggle(page_toggle),.page_bank(page_bank),.page_number(page_number),.page_valid(page_valid),.page_ack(page_ack));
    sdram u_sdram (.Clk(mem_clk),.Clk_sft(mem_clk_shift),.Rst(mem_rst),
        .Sdr_init_done(memory_initialized),.Sdr_init_ref_vld(memory_refresh),.Sdr_busy(memory_busy),
        .App_wr_en(app_wr_en),.App_wr_addr(app_wr_addr),.App_wr_dm(app_wr_mask),.App_wr_din(app_wr_data),
        .App_rd_en(app_rd_en),.App_rd_addr(app_rd_addr),.Sdr_rd_en(sdram_rd_valid),.Sdr_rd_dout(sdram_rd_data));

    // UI control and loader status cross as held, acknowledged bundles.
    wire [95:0] subtitle_text_sys,subtitle_text_video;
    wire [3:0] subtitle_length_sys,subtitle_length_video;
    wire subtitle_enable_sys,subtitle_enable_video,subtitle_changed;
    wire [9:0] subtitle_offset;
    subtitle_uart_service u_subtitle_uart(.clk(sys_clk),.rst_n(control_reset_n),.rx(uart_rx),.tx(uart_tx),.audio_diag(audio_diag_sys),
        .system_ready(image_total!=0 && show_image_sync[1] && !load_error_sync[1]),.system_home(theme_home),.system_theme(theme_id),
        .image_presented(transaction_presented),.presented_index(displayed_index_sys),.demo_active(demo_active),
        .theme_command(uart_theme_valid),.command_theme(uart_theme),.demo_command(uart_demo_valid),.command_demo(uart_demo_enable),
        .text(subtitle_text_sys),.length(subtitle_length_sys),.enable(subtitle_enable_sys));
    subtitle_frame_commit u_subtitle_commit(.src_clk(sys_clk),.src_rst_n(control_reset_n),
        .src_text(subtitle_text_sys),.src_length(subtitle_length_sys),.src_enable(subtitle_enable_sys),
        .dst_clk(pixel_clk),.dst_rst_n(~video_rst),.frame_start(x==0 && y==0),
        .dst_text(subtitle_text_video),.dst_length(subtitle_length_video),
        .dst_enable(subtitle_enable_video),.changed(subtitle_changed));
    subtitle_scroll u_subtitle_scroll(.clk(pixel_clk),.rst_n(~video_rst),
        .frame_start(x==0 && y==0),.changed(subtitle_changed),.enable(subtitle_enable_video),
        .length(subtitle_length_video),.offset(subtitle_offset));

    wire [15:0] elapsed_bcd,elapsed_video;
    osd_timebase u_osd_timebase(.clk(sys_clk),.rst_n(control_reset_n),.elapsed_bcd(elapsed_bcd));
    wire [31:0] osd_control;
    wire timed_video;
    wire [4:0] osd_requested_index;
    wire [5:0] osd_total;
    wire osd_auto,osd_direction;
    wire [1:0] osd_interval;
    assign {timed_video,elapsed_video,osd_requested_index,osd_total,osd_auto,osd_interval,osd_direction}=osd_control;
    osd_state_snapshot #(.WIDTH(32)) u_osd_control_snapshot(
        .src_clk(sys_clk),.src_rst_n(control_reset_n),
        .src_data({sw2_reverse,elapsed_bcd,image_index,image_total,auto_mode,stable_interval,stable_direction}),
        .dst_clk(pixel_clk),.dst_rst_n(~video_rst),.dst_data(osd_control));
    wire [3:0] osd_status;
    osd_state_snapshot #(.WIDTH(4)) u_osd_status_snapshot(
        .src_clk(sd_clk),.src_rst_n(~sd_rst),.src_data(load_status),
        .dst_clk(pixel_clk),.dst_rst_n(~video_rst),.dst_data(osd_status));
    reg [3:0] status_frame;
    always @(posedge pixel_clk or posedge video_rst)
        if(video_rst)status_frame<=0;
        else if(x==0 && y==0)status_frame<=osd_status;
    wire [23:0] loading_rgb;
    loading_spinner_rgb u_loading_spinner (.pixel_clk(pixel_clk),.rst_n(~video_rst),
        .pixel_x(x),.pixel_y(y),.de(de),.rgb(loading_rgb));
    wire osd_cover,subtitle_band;
    wire [23:0] osd_rgb;
    image_status_osd #(.COHERENT_INPUTS(1),.EXTRA_OSD(1),.DYNAMIC_SUBTITLE(1)) u_status_osd (
        .pixel_clk(pixel_clk),.rst_n(~video_rst),.x(x),.y(y),.de(de),
        .image_shown(show_image),.load_status(osd_status),
        .image_index(show_image ? displayed_index_video : osd_requested_index),
        .image_total(osd_total),.auto_mode(osd_auto),.interval_setting(osd_interval),
        .reverse_direction(osd_direction),.overlay_active(osd_cover),.rgb(osd_rgb),
        .image_name(displayed_name_video),.present_commit(present_commit),.elapsed_bcd(elapsed_video),
        .subtitle_data(subtitle_text_video),.subtitle_length(subtitle_length_video),
        .subtitle_enable(subtitle_enable_video),.subtitle_offset(subtitle_offset),.subtitle_band(subtitle_band));
    wire [23:0] output_rgb;
    wire [23:0] thumbnail_rgb;
    wire [23:0] transitioned_rgb;
    wire [9:0] transition_x,transition_y;
    video_transition_coordinates #(.LATENCY(24)) u_transition_coordinates(.clk(pixel_clk),.rst(video_rst),
        .x(x),.y(y),.aligned_x(transition_x),.aligned_y(transition_y));
    video_transition_rgb #(.REVEAL_ENABLE(1),.LIVE_EFFECT(1)) u_transition_pixels(.rgb_in(image_rgb),.gain(transition_gain),.manual_transition(manual_transition),
        .rgb_out(transitioned_rgb),.x(transition_x),.y(transition_y),
        .kind(transition_kind),.reveal_active(reveal_active));
    osd_compositor #(.LATENCY(24)) u_osd_compositor(.clk(pixel_clk),.rst(video_rst),
        .glyph_hit(1'b0),.glyph_rgb(osd_rgb),.loading_rgb(loading_rgb),
        .loading_error(status_frame>=10),.show_image(show_image),.frame_valid(frame_valid),
        .image_rgb(visible_preview ? thumbnail_rgb : basic_video ? image_rgb : transitioned_rgb),.subtitle_band(1'b0),.rgb(output_rgb));
    wire [9:0] tile_left=focus_frame[0] ? 10'd352 : 10'd64;
    wire [9:0] tile_top=focus_frame[1] ? 10'd240 : 10'd64;
    wire thumb_border=!visible_zoom && !zoom_active_video && visible_valid[focus_frame] &&
        transition_x>=tile_left-3 && transition_x<tile_left+163 &&
        transition_y>=tile_top-3 && transition_y<tile_top+123 &&
        (transition_x<tile_left || transition_x>=tile_left+160 || transition_y<tile_top || transition_y>=tile_top+120);
    assign thumbnail_rgb=image_rgb;
    wire [9:0] file_progress_video;
    wire [10:0] preview_progress_video;
    osd_state_snapshot #(.WIDTH(10)) u_file_progress(
        .src_clk(sd_clk),.src_rst_n(~sd_rst),.src_data(load_progress_rows),
        .dst_clk(pixel_clk),.dst_rst_n(~video_rst),.dst_data(file_progress_video));
    osd_state_snapshot #(.WIDTH(11)) u_preview_progress(
        .src_clk(mem_clk),.src_rst_n(~mem_rst),.src_data({builder_busy,builder_progress}),
        .dst_clk(pixel_clk),.dst_rst_n(~video_rst),.dst_data(preview_progress_video));
    wire [23:0] enhanced_rgb;
    adaptive_progress u_progress(.clk(pixel_clk),.rst(video_rst),.frame_start(x==0 && y==0),
        .x(transition_x),.y(transition_y),.rgb_in(output_rgb),.preview(visible_preview),.zoom(visible_zoom),
        .loading(1'b0),
        .progress(preview_request?preview_progress_video[9:0]:file_progress_video),.rgb_out(enhanced_rgb));
    // Both HDMI ports share the same video/audio symbols, with separate PHY outputs.
    wire [9:0] audio_x, audio_ch0, audio_ch1, audio_ch2;
    wire audio_line;
    wire audio_sequence_error,audio_overflow,audio_contract_error;
    wire pcm_tap_valid;
    wire signed [15:0] pcm_tap_left;
    osd_state_snapshot #(.WIDTH(20)) u_theme_video(sys_clk,control_reset_n,
      {basic_request,(theme_home||transaction_presented),theme_manual_effect,theme_home,theme_id,image_index,theme_hold_progress,theme_play_enable},pixel_clk,~video_rst,theme_video);
    wire [23:0] theme_rgb;wire info_visible;
    wire foreground_loading,ascii_allowed,chinese_allowed,wave_allowed,audio_warning;
    wire narration_error_video;
    wire [3:0] image_fault;
    wire [23:0] bordered_rgb = visible_preview && thumb_border ? 24'hffff00 : enhanced_rgb;
    osd_mode_policy #(.SIMULTANEOUS_ASCII(1)) u_osd_policy(.clk(pixel_clk),.rst(video_rst),.frame_start(x==0 && y==0),
      .home(theme_video[16]),.guide_requested(osd_auto),.menu(menu_frame),.shown(show_image),
      .preview_request(preview_request),.visible_preview(visible_preview),
      .zoom_active(zoom_active_video),.visible_zoom(visible_zoom),
      .requested_page(requested_page),.visible_page(visible_page),
      .requested_index(theme_video[13:9]),.displayed_index(displayed_index_video),
      .builder_busy(preview_progress_video[10]),.transition_busy(transition_busy),
      .audio_error(narration_error_video),.load_status(status_frame),
      .loading(foreground_loading),.ascii_allowed(ascii_allowed),.chinese_allowed(chinese_allowed),
      .wave_allowed(wave_allowed),.image_fault(image_fault),.audio_warning(audio_warning));
    osd_state_snapshot #(.WIDTH(1)) u_theme_audio_error(sd_clk,~sd_rst,
      audio_diag_sd[15:8]!=0 || audio_diag_sd[7:0]>=8'h10,pixel_clk,~video_rst,narration_error_video);
    theme_osd u_theme_osd(.clk(pixel_clk),.rst(video_rst),.x(x),.y(y),
      .home(theme_video[16]),.theme(theme_video[15:14]),.image_id(displayed_index_video),.hold_progress(theme_video[8:1]),
      .playing(narration_playing && chinese_allowed && !basic_video),.played_frames(narration_frames),.preview(visible_preview),
      .loading(foreground_loading),.load_status(4'd0),
      .audio_error(1'b0),.image_rgb(bordered_rgb),.rgb(theme_rgb),
      .basic_mode(basic_video),.timed_mode(timed_video),.present_commit(present_commit),.info_visible(info_visible));
    wire [23:0] waveform_rgb;
    promax_audio_waveform #(.DISPLAY_GAIN(4),.EXPLICIT_Y(1),.WAVE_X(368),.WAVE_Y(448),.WAVE_WIDTH(256),.WAVE_HEIGHT(32)) u_waveform(
        .clk(pixel_clk),.rst_n(~video_rst),.vsync(delayed_vs),.de(delayed_de),
        .rgb_in(theme_rgb),.pixel_x(audio_x),.pixel_y(transition_y),.enable(narration_playing && wave_allowed),
        .pcm_tap_valid(pcm_tap_valid),.pcm_tap_left(pcm_tap_left),
        .rgb_out(waveform_rgb),.waveform_active());
    wire [23:0] menu_rgb;
    picture_param_osd u_picture_osd(.x(transition_x),.y(transition_y),.active(menu_frame && image_fault==0),.selected(selected_frame),
        .brightness(brightness_frame),.contrast(contrast_frame),.rgb_in(waveform_rgb),.rgb_out(menu_rgb));
    wire [23:0] demo_rgb;
    p_rover_overlay u_rover_overlay(.x(transition_x),.y(transition_y),
        .enable(demo_state_video[61]&&!menu_frame&&!visible_preview&&!theme_video[16]),
        .state(demo_state_video),.rgb_in(menu_rgb),.rgb_out(demo_rgb));
    wire [23:0] priority_rgb;
    osd_priority_layer #(.DEMO_UI(1)) u_priority_osd(.basic_mode(basic_video),.timed_mode(timed_video),.elapsed_bcd(elapsed_video),.clk(pixel_clk),.rst(video_rst),.x(x),.y(y),.de(de),
      .loading(foreground_loading),.ascii_allowed(ascii_allowed),.subtitle_enable(subtitle_enable_video),
      .audio_warning(audio_warning),.image_fault(image_fault),.subtitle_length(subtitle_length_video),
      .subtitle_text(subtitle_text_video),.subtitle_offset(subtitle_offset),
      .progress(preview_request?preview_progress_video[9:0]:file_progress_video),
      .rgb_in(demo_rgb),.rgb_out(priority_rgb),.info_visible(info_visible),.home(theme_video[16]),.image_id(displayed_index_video));
    video_audio_coordinates #(.LATENCY(24)) u_audio_coordinates(.clk(pixel_clk),.rst(video_rst),
        .x(x),.y(y),.aligned_x(audio_x),.active_line(audio_line));
    // Register the complete video bundle after compositing. RGB, sync,
    // coordinates and commit metadata must move together into HDMI encoding.
    reg [23:0] tx_rgb;reg tx_hs,tx_vs,tx_de,tx_line,tx_shown,tx_commit;
    reg [9:0] tx_x;reg [4:0] tx_index;
    always @(posedge pixel_clk or posedge video_rst)begin
        if(video_rst)begin
            tx_rgb<=0;tx_hs<=1;tx_vs<=1;tx_de<=0;tx_line<=0;tx_x<=0;
            tx_shown<=0;tx_commit<=0;tx_index<=0;
        end else begin
            tx_rgb<=priority_rgb;tx_hs<=delayed_hs;tx_vs<=delayed_vs;tx_de<=delayed_de;
            tx_line<=audio_line;tx_x<=audio_x;tx_shown<=show_image;
            tx_commit<=present_commit;tx_index<=displayed_index_video;
        end
    end
    media_hdmi_audio_bridge #(.EXPLICIT_COMMIT(1),.USER_VOLUME(!LEGACY_CONTROLS),.EXTERNAL_PCM(1),.SILENT_FALLBACK(1)) u_audio_bridge(.wav_selected(wav_selected),.wav_valid(wav_valid),.wav_left(wav_left),.wav_right(wav_right),.wav_ready(wav_ready),.audio_tick(audio_tick),
  .pixel_clk(pixel_clk),.pixel_rst_n(~video_rst),
        .video_hsync(tx_hs),.video_vsync(tx_vs),.video_de(tx_de),
        .video_x(tx_x),.video_line_active(tx_line),.video_rgb(tx_rgb),
        .pcm_tap_valid(pcm_tap_valid),.pcm_tap_left(pcm_tap_left),
        .channel0_symbol(audio_ch0),.channel1_symbol(audio_ch1),.channel2_symbol(audio_ch2),
        .sequence_error(audio_sequence_error),.tone_overflow(audio_overflow),.pcm_contract_error(audio_contract_error),
        .image_shown(tx_shown),.displayed_index(tx_index),.present_commit(tx_commit),.volume(volume_audio));
    hdmi_phy_wrapper #(.DEVICE("EG")) u_audio_phy_a(.I_pixel_clk(pixel_clk),.I_serial_clk(serial_clk),
        .I_rst(video_rst),.I_tmds_channel_0(audio_ch0),.I_tmds_channel_1(audio_ch1),
        .I_tmds_channel_2(audio_ch2),.I_tmds_channel_clk(10'b0000011111),
        .O_tmds_ch0_p(HDMI_D0_P),.O_tmds_ch1_p(HDMI_D1_P),.O_tmds_ch2_p(HDMI_D2_P),.O_tmds_clk_p(HDMI_CLK_P));
    wire [9:0] stage2_ch0,stage2_ch1,stage2_ch2;
    p_rover_video u_rover_video(.pixel_clk(pixel_clk),.rst_n(~video_rst),.x(x),.y(y),.de(de),.hs(hs),.vs(vs),
        .state(demo_state_video),.model_id(demo_state_video[63:62]),.channel0(stage2_ch0),.channel1(stage2_ch1),.channel2(stage2_ch2));
    hdmi_phy_wrapper #(.DEVICE("EG")) u_stage2_phy(.I_pixel_clk(pixel_clk),.I_serial_clk(serial_clk),
        .I_rst(video_rst),.I_tmds_channel_0(stage2_ch0),.I_tmds_channel_1(stage2_ch1),
        .I_tmds_channel_2(stage2_ch2),.I_tmds_channel_clk(10'b0000011111),
        .O_tmds_ch0_p(HDMI_D0_P1),.O_tmds_ch1_p(HDMI_D1_P1),.O_tmds_ch2_p(HDMI_D2_P1),.O_tmds_clk_p(HDMI_CLK_P1));
endmodule
