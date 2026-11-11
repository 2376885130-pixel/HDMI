// One narration session owns the file cursor, RIFF parser and PCM FIFO.
// Cancellation stops new requests, drains the accepted sector, then resets.
module theme_audio_player(
 input wire clk,pixel_clk,rst,pixel_rst,mounted,play_enable,
 input wire [4:0] play_id,input wire basic_mode,
 input wire [31:0] root_cluster,fat_lba,data_lba,max_cluster,
 input wire [3:0] cluster_shift,input wire [7:0] sectors_per_cluster,
 output wire req,output wire [31:0] lba,input wire busy,valid,done,input wire [7:0] data,error,
 input wire tick,input wire [8:0] volume,output wire selected,sample_valid,
 input wire sample_ready,output wire signed [15:0] sample_left,sample_right,
 output wire [127:0] diagnostics,output wire finished,output reg [4:0] session_id,
 output reg session_basic,
 output wire [31:0] played_frames,output wire playing_video
);
 localparam IDLE=0,LOOKUP=1,PLAY=2,DRAIN=3,CLEAR=4,ENDED=5,FAILED=6,TAIL=7;
 reg [2:0] state;reg [19:0] hold_count;reg inflight;
 wire reset_request=rst|pixel_rst;
 (* async_reg="true",preserve=1,keep=1 *) reg [2:0] reset_release;
 always @(posedge clk or posedge reset_request)
  if(reset_request)reset_release<=0;else reset_release<={reset_release[1:0],1'b1};
 wire audio_rst=!reset_release[2];
 // Mode is part of the immutable file session, just like the image ID.
 // Changing mode drains an accepted sector before clearing the parser/FIFO.
 wire stop_now=!play_enable||play_id!=session_id||basic_mode!=session_basic;
 wire file_rst=audio_rst||state==IDLE||state==CLEAR;
 wire found,bv,br,last,drained,low;
 wire [31:0] size,last_lba,under,late;wire [7:0] bd,fs_status,parse_error;
 wire session_n=!audio_rst&&!reset_request&&(state==PLAY||state==TAIL||state==ENDED)&&!stop_now;
 wire [2:0] control_video;
 osd_state_snapshot #(.WIDTH(3)) selection(clk,!audio_rst,{state==PLAY&&!stop_now,parse_error!=0,fs_status>=8'h10},pixel_clk,!pixel_rst,control_video);
 assign selected=control_video[2]&&!control_video[1]&&!control_video[0]&&!drained;
 assign playing_video=selected;
 wire [7:0] theme_ascii=8'h31+{6'd0,session_id[4:3]};
 wire [7:0] picture_ascii=8'h31+{5'd0,session_id[2:0]};
 wire [87:0] filename=session_basic ? "BASIC48 WAV" :
  {8'h54,theme_ascii,8'h50,8'h30,picture_ascii,24'h202020,24'h574156};
 fat32_bgm_stream #(.SELECTABLE(1)) file_stream(.clk(clk),.rst(file_rst),.mounted(mounted&&state==LOOKUP),
 .filename(filename),.root_cluster(root_cluster),.fat_lba(fat_lba),.data_lba(data_lba),.max_cluster(max_cluster),
 .cluster_shift(cluster_shift),.sectors_per_cluster(sectors_per_cluster),.start(state==PLAY),.restart(1'b0),
 .stop(state==DRAIN||state==FAILED||stop_now),.req(req),.lba(lba),.busy(busy),.valid(valid),.done(done),.data(data),.error(error),
 .byte_valid(bv),.byte_ready(br),.byte_data(bd),.byte_last(last),.found(found),.file_size(size),.status(fs_status),.error_lba(last_lba));
 wav_pcm_stream pcm(.wr_clk(clk),.rd_clk(pixel_clk),.session_rst_n(session_n),.abort(fs_status>=8'h10),.file_size(size),
 .byte_valid(bv),.byte_ready(br),.byte_data(bd),.byte_last(last),.tick(tick),.selected(selected),.volume(volume),
 .sample_valid(sample_valid),.sample_ready(sample_ready),.sample_left(sample_left),.sample_right(sample_right),
 .done(drained),.error(parse_error),.low_water(low),.underflows(under),.late_ticks(late),.played_frames(played_frames));
 wire [32:0] audio_diag_sd;
 osd_state_snapshot #(.WIDTH(33)) audio_stats(pixel_clk,!pixel_rst,{under,low},clk,!audio_rst,audio_diag_sd);
 reg [31:0] read_errors;reg [7:0] saved_error;
 assign diagnostics={15'd0,audio_diag_sd[0],last_lba,read_errors,audio_diag_sd[32:1],saved_error,fs_status};
 // The base demo loops without advancing the image. Only completed narration
 // produces a guide-advance event; SW2 still controls timed slides separately.
 assign finished=state==ENDED&&!session_basic&&!stop_now;
 (* async_reg="true",preserve=1,keep=1 *) reg [2:0] done_sync;
 always @(posedge clk or posedge audio_rst)begin
  if(audio_rst)begin state<=IDLE;hold_count<=0;inflight<=0;session_id<=0;session_basic<=0;done_sync<=0;read_errors<=0;saved_error<=0;end
  else begin
   done_sync<={done_sync[1:0],drained};
   if(req)inflight<=1;if(done)inflight<=0;
   if(done&&error!=0)read_errors<=read_errors+1'b1;
   case(state)
    IDLE:if(play_enable&&mounted)begin session_id<=play_id;session_basic<=basic_mode;state<=CLEAR;hold_count<=127;end
    CLEAR:if(hold_count!=0)begin hold_count<=hold_count-1'b1;saved_error<=0;end
      else if(play_enable)begin session_id<=play_id;session_basic<=basic_mode;state<=LOOKUP;end else state<=IDLE;
    LOOKUP:if(stop_now)state<=DRAIN;
      else if(fs_status>=8'h10)begin saved_error<=fs_status;state<=FAILED;end
      else if(found)state<=PLAY;
    PLAY:if(stop_now)state<=DRAIN;
      else if(parse_error!=0||fs_status>=8'h10)begin saved_error<=parse_error!=0?parse_error:fs_status;state<=FAILED;end
      else if(done_sync[2])begin state<=TAIL;hold_count<=999999;end
    // 20 ms at 50 MHz drains the selector and the bounded HDMI packet FIFO.
    TAIL:if(stop_now)state<=DRAIN;else if(hold_count!=0)hold_count<=hold_count-1'b1;else state<=ENDED;
    ENDED:if(stop_now||session_basic)state<=DRAIN;
    FAILED:if(stop_now)state<=DRAIN;
    DRAIN:if(!busy&&!inflight&&!req&&!valid&&!done)begin state<=CLEAR;hold_count<=127;end
   endcase
  end
 end
endmodule
