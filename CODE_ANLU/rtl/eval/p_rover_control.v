// One owner for the experiment state and physical input routing.
// Educational energy values, not calibrated lunar hardware predictions.
module p_rover_control #(parameter FILTER=750000, SETTLE=4000000, SECOND=50000000)(
 input wire clk,rst_n,home,sw3_up,sw4_up,key2_n,key3_n,key4_n,
 output wire active,blocked,output wire main_key2_n,main_key3_n,main_key4_n,
 output wire main_sw3_up,main_sw4_up,output wire [63:0] state,
 input wire [1:0] model_id,
 input wire uart_demo_valid,uart_demo_enable);
 localparam DB=FILTER<2?1:$clog2(FILTER),SB=SETTLE<2?1:$clog2(SETTLE),TB=SECOND<2?1:$clog2(SECOND);
 (* async_reg="true",preserve=1,keep=1 *) reg [4:0] meta,sync;
 reg [4:0] stable,old;reg [DB-1:0] db[0:4];
 reg [SB-1:0] settle_count;reg [1:0] switches;
 reg active_q,guard,switch_guard;reg [1:0] selected,load_setting,mission;
 reg [4:0] angle_index;reg [6:0] battery;reg [TB-1:0] seconds;
 reg [1:0] previous_model;reg [4:0] secondary;
 wire combo=!stable[4]&&!stable[3];
 reg remote_demo,combo_inhibit;
 assign active=!home&&(remote_demo||(combo&&!combo_inhibit));
 // Capture the combination before the existing, slower menu debouncers.
 // After leaving, all three keys must be released before main actions resume.
 assign blocked=!home&&(active||guard||(!combo_inhibit&&!sync[4]&&!sync[3]));
 assign main_key2_n=blocked?1'b1:key2_n;
 assign main_key3_n=blocked?1'b1:key3_n;
 assign main_key4_n=blocked?1'b1:key4_n;
 assign main_sw3_up=(active||blocked||home||switch_guard)?1'b1:switches[0];
 assign main_sw4_up=(active||blocked||home||switch_guard)?1'b1:switches[1];
 reg [6:0] angle,eff;reg [7:0] dx,dy;reg [4:0] power;
 wire [4:0] load=load_setting==0?5'd4:load_setting==1?5'd10:5'd18;
 always @* begin
  angle=0;eff=100;dx=144;dy=0;power=20;
  case(angle_index)
   1:begin angle=5;eff=100;dx=143;dy=13;power=20;end
   2:begin angle=10;eff=98;dx=142;dy=25;power=20;end
   3:begin angle=15;eff=97;dx=139;dy=37;power=19;end
   4:begin angle=20;eff=94;dx=135;dy=49;power=19;end
   5:begin angle=25;eff=91;dx=131;dy=61;power=18;end
   6:begin angle=30;eff=87;dx=125;dy=72;power=17;end
   7:begin angle=35;eff=82;dx=118;dy=83;power=16;end
   8:begin angle=40;eff=77;dx=110;dy=93;power=15;end
   9:begin angle=45;eff=71;dx=102;dy=102;power=14;end
   10:begin angle=50;eff=64;dx=93;dy=110;power=13;end
   11:begin angle=55;eff=57;dx=83;dy=118;power=11;end
   12:begin angle=60;eff=50;dx=72;dy=125;power=10;end
   13:begin angle=65;eff=42;dx=61;dy=131;power=8;end
   14:begin angle=70;eff=34;dx=49;dy=135;power=7;end
   15:begin angle=75;eff=26;dx=37;dy=139;power=5;end
   16:begin angle=80;eff=17;dx=25;dy=142;power=3;end
   17:begin angle=85;eff=9;dx=13;dy=143;power=2;end
   18:begin angle=90;eff=0;dx=0;dy=144;power=0;end
   default:begin end
  endcase
 end
 // Reserved low bits keep the documented bundle layout stable.
 // Commit the model tag on the same edge as its reset/default parameters.
 // Directly using model_id could label the previous model's state for one cycle.
 assign state={previous_model,active,selected,angle,eff,power,load,battery,mission,dx,dy,secondary,5'd0};
 integer i;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   meta<=31;sync<=31;stable<=31;old<=31;for(i=0;i<5;i=i+1)db[i]<=0;
   switches<=3;settle_count<=0;active_q<=0;guard<=0;switch_guard<=0;
   selected<=0;angle_index<=6;load_setting<=1;battery<=50;mission<=0;seconds<=0;
   previous_model<=0;secondary<=0;
   remote_demo<=0;combo_inhibit<=0;
  end else begin
   if(home)begin remote_demo<=0;combo_inhibit<=0;end
   else begin
    if(!combo && (sync[4]||sync[3]))combo_inhibit<=0;
    if(uart_demo_valid==1'b1)begin
     remote_demo<=uart_demo_enable;
     if(!uart_demo_enable)combo_inhibit<=1;
    end
   end
   meta<={sw4_up,sw3_up,key4_n,key3_n,key2_n};sync<=meta;old<=stable;active_q<=active;
   for(i=0;i<5;i=i+1)begin
    if(sync[i]==stable[i])db[i]<=0;
    else if(db[i]==FILTER-1)begin stable[i]<=sync[i];db[i]<=0;end
    else db[i]<=db[i]+1'b1;
   end
   if(stable[4:3]==switches)settle_count<=0;
   else if(settle_count==SETTLE-1)begin switches<=stable[4:3];settle_count<=0;end
   else settle_count<=settle_count+1'b1;
   if(active!=active_q)guard<=1;
   else if(stable[2:0]==7&&sync[2:0]==7)guard<=0;
   if(!home && uart_demo_valid==1'b1 && active!=uart_demo_enable)guard<=1;
   if(active)switch_guard<=1;
   else if(stable[4:3]==3)switch_guard<=0;
   previous_model<=model_id;
   if(model_id!=previous_model)begin
    selected<=0;angle_index<=6;secondary<=0;load_setting<=1;mission<=0;battery<=50;guard<=1;
   end
   else if(home)begin selected<=0;mission<=0;guard<=0;end
   else if(active&&active_q&&!guard)begin
    // KEY4 wins over simultaneous +/-; simultaneous +/- cancels.
    if(old[2]&&!stable[2])selected<=selected==(model_id==0?2:1)?0:selected+1'b1;
    else if((old[0]&&!stable[0])^(old[1]&&!stable[1]))begin
     case(selected)
      0:if(old[1]&&!stable[1])begin if(angle_index<18)angle_index<=angle_index+1'b1;end
        else if(angle_index>0)angle_index<=angle_index-1'b1;
      1:if(model_id==0)begin
         if(old[1]&&!stable[1])begin if(load_setting<2)load_setting<=load_setting+1'b1;end
         else if(load_setting>0)load_setting<=load_setting-1'b1;
        end else begin
         if(old[1]&&!stable[1])begin if(secondary<18)secondary<=secondary+1'b1;end
         else if(secondary>0)secondary<=secondary-1'b1;
        end
      2:if(old[1]&&!stable[1])begin if(mission<2)mission<=mission+1'b1;end else if(mission>0)mission<=mission-1'b1;
     endcase
    end
   end
   // Battery holds outside demo; integrate one teaching-model step per second.
   if(model_id!=previous_model)seconds<=0;
   else if(!active)seconds<=0;
   else if(seconds==SECOND-1)begin
    seconds<=0;
    if(power>load&&battery<100)battery<=battery+1'b1;
    else if(power<load&&battery>0)battery<=battery-1'b1;
   end else seconds<=seconds+1'b1;
  end
 end
endmodule
