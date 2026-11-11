// One immutable transmitting packet plus per-kind pending snapshots.
// Pending replacements are coalesced with an explicit OVERFLOW indication.
// No backpressure is ever applied to the multimedia system.
module uart_system_events(
 input wire clk,rst_n,system_ready,home,input wire [1:0] theme,
 input wire image_presented,input wire [4:0] presented_index,input wire demo_active,
 output wire valid,output reg [7:0] data,input wire ready
);
 reg boot_sent,old_home,old_demo,old_present;reg [1:0] old_theme;reg [4:0] old_index;
 reg [3:0] pending;reg [4:0] theme_payload,image_payload;reg demo_payload;
 reg overflow;
 reg [7:0] head;reg transmitting;reg [3:0] byte_index;
 wire [2:0] kind=head[7:5];
 wire [5:0] number={1'b0,head[4:0]}+6'd1;
 wire [7:0] tens=number>=30?"3":number>=20?"2":number>=10?"1":"0";
 wire [5:0] ones=number>=30?number-30:number>=20?number-20:number>=10?number-10:number;
 wire [3:0] last=kind==0?8:kind==1?13:kind==2?12:kind==3?10:12;
 assign valid=transmitting;
 wire pop=valid&&ready&&byte_index==last;
 wire space=!transmitting||pop;
 reg [2:0] choice;reg [7:0] incoming;
 always @* begin
  choice=4;incoming={3'd4,5'd0};
  if(pending[0])begin choice=0;incoming=0;end
  else if(pending[1])begin choice=1;incoming={3'd1,theme_payload};end
  else if(pending[2])begin choice=2;incoming={3'd2,image_payload};end
  else if(pending[3])begin choice=3;incoming={3'd3,4'd0,demo_payload};end
 end
 wire push=space&&((|pending)||overflow);
 // EV BOOT / EV THEME <1..4> <H|T> / EV IMAGE <01..32> / EV DEMO <0|1>.
 // Packet fields are captured before queueing, not read live while transmitting.
 always @* begin
  data=32;
  if(byte_index==0)data="E";
  else if(byte_index==1)data="V";
  else if(byte_index==last-1)data=13;
  else if(byte_index==last)data=10;
  else case(kind)
   0:case(byte_index)3:data="B";4:data="O";5:data="O";6:data="T";endcase
   1:case(byte_index)3:data="T";4:data="H";5:data="E";6:data="M";7:data="E";
     9:data=8'd49+{6'd0,head[1:0]};11:data=head[2]?"H":"T";endcase
   2:case(byte_index)3:data="I";4:data="M";5:data="A";6:data="G";7:data="E";
     9:data=tens;10:data=8'd48+ones;endcase
   3:case(byte_index)3:data="D";4:data="E";5:data="M";6:data="O";8:data=head[0]?"1":"0";endcase
   4:case(byte_index)3:data="O";4:data="V";5:data="E";6:data="R";7:data="F";8:data="L";9:data="O";10:data="W";endcase
  endcase
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   boot_sent<=0;old_home<=1;old_demo<=0;old_present<=0;old_theme<=0;old_index<=0;
   pending<=0;theme_payload<=0;image_payload<=0;demo_payload<=0;overflow<=0;
   head<=0;transmitting<=0;byte_index<=0;
  end else begin
   old_home<=home;old_theme<=theme;old_demo<=demo_active;
   old_present<=image_presented;old_index<=presented_index;
   if(push)begin
    head<=incoming;transmitting<=1;
    if(choice<4)pending[choice]<=0;else overflow<=0;
   end
   if(pop&&!push)transmitting<=0;
   if(valid&&ready)begin if(pop)byte_index<=0;else byte_index<=byte_index+1'b1;end
   if(!boot_sent&&system_ready)begin
    boot_sent<=1;pending[0]<=1;pending[1]<=1;theme_payload<={2'b0,home,theme};
   end
   if(home!=old_home||theme!=old_theme)begin
    if(pending[1]&&!(push&&choice==1))overflow<=1;
    pending[1]<=1;theme_payload<={2'b0,home,theme};
   end
   if(image_presented&&(!old_present||presented_index!=old_index))begin
    if(pending[2]&&!(push&&choice==2))overflow<=1;
    pending[2]<=1;image_payload<=presented_index;
   end
   if(demo_active!=old_demo)begin
    if(pending[3]&&!(push&&choice==3))overflow<=1;
    pending[3]<=1;demo_payload<=demo_active;
   end
  end
 end
endmodule
