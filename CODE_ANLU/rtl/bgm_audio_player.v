// Independent background lifetime: picture commits do not reset or seek music.
module bgm_audio_player(
 input wire clk,pixel_clk,rst,pixel_rst,mounted,
 input wire[31:0]root_cluster,fat_lba,data_lba,max_cluster,
 input wire[3:0]cluster_shift,input wire[7:0]sectors_per_cluster,
 output wire req,output wire[31:0]lba,input wire busy,valid,done,input wire[7:0]data,error,
 input wire tick,input wire[8:0]volume,output wire selected,sample_valid,
 input wire sample_ready,output wire signed[15:0]sample_left,sample_right,
 output wire[127:0]diagnostics
);
 localparam WAIT=0,PLAY=1,RESET=2,FAILED=3;
 // A parser reset must also rewind its file source. Otherwise a video reset
 // makes mid-file PCM bytes look like a new RIFF header. Assert both resets
 // together and release the storage-side state only on its own clock.
 wire reset_request=rst|pixel_rst;
 (* async_reg="true",preserve=1,keep=1 *) reg [2:0] reset_release;
 always @(posedge clk or posedge reset_request)
  if(reset_request)reset_release<=0;else reset_release<={reset_release[1:0],1'b1};
 wire audio_rst=!reset_release[2];
 reg[1:0]state;reg[5:0]hold_count;reg restart;
 wire found;wire[31:0]size,last_lba;wire[7:0]fs_status,parse_error;
 wire bv,br,last;wire[7:0]bd;wire drained,low;wire[31:0]under,late;
 (* async_reg="true",preserve=1,keep=1 *) reg[1:0]done_sync;
 reg[31:0]read_errors,under_total;reg[7:0]saved_error;
 wire session_n=!(audio_rst||reset_request)&&state==PLAY;
 wire[2:0]control_video;
 osd_state_snapshot #(.WIDTH(3)) selection(clk,!audio_rst,{state==PLAY,parse_error!=0,fs_status>=8'h10},pixel_clk,!pixel_rst,control_video);
 assign selected=control_video[2]&&!control_video[1]&&!control_video[0]&&!drained;
 fat32_bgm_stream file_stream(.clk(clk),.rst(audio_rst),.mounted(mounted),
  .root_cluster(root_cluster),.fat_lba(fat_lba),.data_lba(data_lba),.max_cluster(max_cluster),
  .cluster_shift(cluster_shift),.sectors_per_cluster(sectors_per_cluster),.start(state==PLAY),.restart(restart),.stop(state==FAILED),
  .req(req),.lba(lba),.busy(busy),.valid(valid),.done(done),.data(data),.error(error),
  .byte_valid(bv),.byte_ready(br),.byte_data(bd),.byte_last(last),.found(found),.file_size(size),.status(fs_status),.error_lba(last_lba));
 wav_pcm_stream pcm(.wr_clk(clk),.rd_clk(pixel_clk),.session_rst_n(session_n),.abort(fs_status>=8'h10),.file_size(size),
  .byte_valid(bv),.byte_ready(br),.byte_data(bd),.byte_last(last),.tick(tick),.selected(selected),.volume(volume),
  .sample_valid(sample_valid),.sample_ready(sample_ready),.sample_left(sample_left),.sample_right(sample_right),
  .done(drained),.error(parse_error),.low_water(low),.underflows(under),.late_ticks(late));
 wire[32:0]audio_diag_sd;
 osd_state_snapshot #(.WIDTH(33)) audio_stats(pixel_clk,!pixel_rst,{under,low},clk,!audio_rst,audio_diag_sd);
 wire[31:0]under_sum=under_total+(state==PLAY?audio_diag_sd[32:1]:32'd0);
 assign diagnostics={15'd0,audio_diag_sd[0],last_lba,read_errors,under_sum,saved_error,fs_status};
 always @(posedge clk or posedge audio_rst)begin
  if(audio_rst)begin state<=WAIT;hold_count<=0;restart<=0;done_sync<=0;read_errors<=0;under_total<=0;saved_error<=0;end
  else begin
   done_sync<={done_sync[0],drained};restart<=0;
   if(done&&error!=0&&read_errors!=32'hffffffff)read_errors<=read_errors+1'b1;
   case(state)
    WAIT:if(found)state<=PLAY;
    PLAY:begin
     if(parse_error!=0||fs_status>=8'h10)begin saved_error<=parse_error;state<=FAILED;under_total<=under_sum;end
     else if(done_sync[1])begin state<=RESET;hold_count<=63;under_total<=under_sum;end
    end
    RESET:if(hold_count!=0)hold_count<=hold_count-1'b1;
      else begin state<=PLAY;restart<=1;end
    FAILED:state<=FAILED;
   endcase
  end
 end
endmodule
