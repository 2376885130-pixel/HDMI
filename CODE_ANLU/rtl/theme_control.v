// All mechanical controls are debounced once here before routing to menus.
// KEY4 short actions are synthesized on release; long actions never leak.
module theme_control #(parameter CLOCK_HZ=50000000, DEBOUNCE=1000000, SLIDE_SECONDS=3)(
 input wire clk,rst_n,key2_n,key3_n,key4_n,sw1_up,sw3_up,sw4_up,
 input wire reverse_mode,input wire demo_hold,
 input wire ready,preview_hold,menu_reserved,load_error,
 input wire next_event,prev_event,select_valid,input wire [4:0] select_index,
 input wire audio_done,input wire [4:0] audio_id,
 output reg home,output reg [1:0] theme,output reg [4:0] index,
 output wire routed_key2_n,routed_key3_n,routed_key4_n,preview_up,menu_up,
 output wire autoplay,play_enable,output wire [7:0] hold_progress,
 output reg restart_event,output reg manual_effect,
 input wire timed_mode,
 input wire uart_theme_valid,input wire [1:0] uart_theme
);
 localparam DB=DEBOUNCE<2?1:$clog2(DEBOUNCE);
 localparam CB=$clog2(CLOCK_HZ*3+1);
 (* async_reg="true",preserve=1,keep=1 *) reg [5:0] meta,sync;
 reg [5:0] stable,previous;reg [DB-1:0] dbc[0:5];
 reg [CB-1:0] key3_count,key4_count;
 reg key3_fired,key4_fired,key3_armed,sw3_armed,sw4_armed,done_armed;
 reg [DB:0] short_count;
 localparam TIMER_BITS=$clog2(CLOCK_HZ*SLIDE_SECONDS+1);
 reg [TIMER_BITS-1:0] slide_count;
 reg [4:0] timer_index;
 wire slide_running=timed_mode&&!home&&ready&&!demo_hold&&!preview_hold&&!menu_reserved&&preview_up&&menu_up&&!load_error;
 wire k2_press=previous[0]&&!stable[0];
 assign autoplay=!home&&!stable[3];
 assign preview_up=home||!sw3_armed||stable[4];
 assign menu_up=home||!sw4_armed||stable[5];
 assign routed_key2_n=demo_hold||home||stable[0];
 assign routed_key3_n=demo_hold||home||!key3_armed||stable[1];
 assign routed_key4_n=demo_hold||home||short_count==0;
 assign play_enable=autoplay && ready && !preview_hold && preview_up && !load_error;
 // Low cost approximate hold indicator: six 0.5 second steps, not a divider.
 assign hold_progress=home ? (key3_count>=CLOCK_HZ*2 ? 255 : key3_count>=CLOCK_HZ*3/2 ? 192 : key3_count>=CLOCK_HZ ? 128 : key3_count>=CLOCK_HZ/2 ? 64 : 0) :
 (key4_count>=CLOCK_HZ*5/2 ? 224 : key4_count>=CLOCK_HZ*2 ? 192 : key4_count>=CLOCK_HZ*3/2 ? 128 : key4_count>=CLOCK_HZ ? 96 : key4_count>=CLOCK_HZ/2 ? 48 : 0);
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   meta<=63;sync<=63;stable<=63;previous<=63;
   for(i=0;i<6;i=i+1)dbc[i]<=0;
   home<=1;theme<=0;index<=0;key3_count<=0;key4_count<=0;
   key3_fired<=0;key4_fired<=0;key3_armed<=0;sw3_armed<=0;sw4_armed<=0;
   short_count<=0;done_armed<=0;restart_event<=0;manual_effect<=0;
   slide_count<=0;timer_index<=0;
  end else begin
   meta<={sw4_up,sw3_up,sw1_up,key4_n,key3_n,key2_n};sync<=meta;previous<=stable;restart_event<=0;
   timer_index<=index;
   if(!slide_running||timer_index!=index)slide_count<=0;
   else if(slide_count==CLOCK_HZ*SLIDE_SECONDS-1)slide_count<=0;
   else slide_count<=slide_count+1'b1;
   for(i=0;i<6;i=i+1)begin
    if(sync[i]==stable[i])dbc[i]<=0;
    else if(dbc[i]==DEBOUNCE-1)begin stable[i]<=sync[i];dbc[i]<=0;end
    else dbc[i]<=dbc[i]+1'b1;
   end
   if(short_count!=0)short_count<=short_count-1'b1;
   if(stable[1])begin key3_count<=0;key3_fired<=0;if(!home)key3_armed<=1;end
   else if(home&&!key3_fired)begin
    if(uart_theme_valid==1'b1)key3_count<=0;
    else if(key3_count==CLOCK_HZ*2-1)begin
     key3_fired<=1;home<=0;index<={theme,3'd0};key3_armed<=0;
     sw3_armed<=stable[4];sw4_armed<=stable[5];restart_event<=1;done_armed<=0;manual_effect<=0;
    end else key3_count<=key3_count+1'b1;
   end
   if(demo_hold)begin key4_count<=0;key4_fired<=1;short_count<=0;end
   else if(stable[2])begin
    if(!previous[2]&&!key4_fired&&!home)short_count<=DEBOUNCE+16;
    key4_count<=0;key4_fired<=0;
   end else if(!home&&!key4_fired)begin
    if(key4_count==CLOCK_HZ*3-1)begin
     home<=1;key4_fired<=1;short_count<=0;done_armed<=0;restart_event<=1;
    end else key4_count<=key4_count+1'b1;
   end
   if(home)begin
    done_armed<=0;sw3_armed<=0;sw4_armed<=0;
    if(k2_press)theme<=theme+1'b1;
   end else begin
    if(stable[4])sw3_armed<=1;if(stable[5])sw4_armed<=1;
    if(!play_enable)done_armed<=0;
    else if(!audio_done)done_armed<=1;
    if(!demo_hold&&select_valid)begin index<={theme,select_index[2:0]};done_armed<=0;restart_event<=1;manual_effect<=0;end
    else if(!demo_hold&&!preview_hold&&!menu_reserved&&(next_event^prev_event))begin
     index<={theme,next_event ? index[2:0]+3'd1 : index[2:0]-3'd1};done_armed<=0;restart_event<=1;manual_effect<=1;
    end else if(slide_running&&timer_index==index&&slide_count==CLOCK_HZ*SLIDE_SECONDS-1)begin
     index<={theme,index[2:0]+3'd1};done_armed<=0;restart_event<=1;manual_effect<=0;
    end else if(!timed_mode&&play_enable&&done_armed&&audio_done&&audio_id==index)begin
     index<={theme,reverse_mode ? index[2:0]-3'd1 : index[2:0]+3'd1};done_armed<=0;restart_event<=1;manual_effect<=0;
    end
   end
   // UART selects only on the home page. Same owner and priority over KEY2.
   // Cancel a concurrent KEY3 hold so it cannot enter the previous theme.
   if(home && uart_theme_valid==1'b1)begin
    theme<=uart_theme;home<=1;key3_count<=0;key3_fired<=0;
   end
  end
 end
endmodule
