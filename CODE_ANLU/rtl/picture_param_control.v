// SW4 down reserves KEY2/3/4. A held key never leaks across menu boundaries.
module picture_param_control #(parameter integer DEBOUNCE_CYCLES=1000000)(
 input wire clk,rst_n,sw4_up,key2_n,key3_n,key4_n,
 output wire reserved,output wire pass_key2_n,pass_key3_n,pass_key4_n,
 output reg menu_active,selected_contrast,
 output reg signed [7:0] brightness,output reg [7:0] contrast
);
 localparam CB=DEBOUNCE_CYCLES<2?1:$clog2(DEBOUNCE_CYCLES);
 (* preserve=1,keep=1 *) reg [3:0] meta,sync;
 reg [3:0] stable,previous;
 reg [CB-1:0] count[0:3];
 reg [2:0] pass_armed,menu_armed;
 wire [2:0] press=previous[2:0] & ~stable[2:0] & menu_armed;
 // Reserve as soon as the synchronized switch goes down, before debounce.
 assign reserved=!sync[3] || !stable[3] || menu_active;
 assign pass_key2_n=reserved || !pass_armed[0] || sync[0];
 assign pass_key3_n=reserved || !pass_armed[1] || sync[1];
 assign pass_key4_n=reserved || !pass_armed[2] || sync[2];
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   meta<=15;sync<=15;stable<=15;previous<=15;
   for(i=0;i<4;i=i+1)count[i]<=0;
   pass_armed<=0;menu_armed<=0;menu_active<=0;selected_contrast<=0;
   brightness<=0;contrast<=128;
  end else begin
   meta<={sw4_up,key4_n,key3_n,key2_n};sync<=meta;previous<=stable;
   for(i=0;i<4;i=i+1)begin
    if(sync[i]==stable[i])count[i]<=0;
    else if(count[i]==DEBOUNCE_CYCLES-1)begin stable[i]<=sync[i];count[i]<=0;end
    else count[i]<=count[i]+1'b1;
   end
   if(reserved)pass_armed<=0;
   else pass_armed<=pass_armed | (stable[2:0] & sync[2:0]);
   menu_active<=!stable[3];
   if(!menu_active)begin menu_armed<=0;selected_contrast<=0;end
   else begin
    menu_armed<=menu_armed | (stable[2:0] & sync[2:0]);
    if(!stable[3])begin
     if(press[2])selected_contrast<=~selected_contrast;
     // Conflicting keys and a simultaneous item change do not alter values.
     if(!press[2] && (press[0]^press[1]))begin
      if(selected_contrast)begin
       if(press[0])contrast<=contrast>247?8'd255:contrast+8'd8;
       else contrast<=contrast<8?8'd0:contrast-8'd8;
      end else begin
       if(press[0])brightness<=brightness>119?8'sd127:brightness+8'sd8;
       else brightness<=brightness< -120?8'sh80:brightness-8'sd8;
      end
     end
    end
   end
  end
 end
endmodule
