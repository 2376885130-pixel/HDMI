// Two pulse-request clients, one outstanding request per client. Ownership is
// immutable through all 512 bytes and completion. Cancel drains in-flight data.
module sd_sector_arbiter(
 input wire clk,rst,cancel_image,ready,
 input wire image_req,input wire[31:0]image_lba,output wire image_busy,
 output wire image_valid,image_done,output wire[7:0]image_error,
 input wire audio_req,input wire[31:0]audio_lba,output wire audio_busy,
 output wire audio_valid,audio_done,output wire[7:0]audio_error,
 output reg request,output reg[31:0]lba,input wire busy,valid,done,input wire[7:0]error,
 output wire recover
);
 reg ip,ap,active,owner,last_owner,killed;reg[31:0]il,al;reg[5:0]reset_count;
 assign recover=reset_count!=0;
 assign image_busy=ip||(active&&!owner);
 assign audio_busy=ap||(active&&owner);
 assign image_valid=active&&!owner&&!killed&&!cancel_image&&valid;
 assign audio_valid=active&&owner&&valid;
 assign image_done=active&&!owner&&!killed&&!cancel_image&&done;
 assign audio_done=active&&owner&&done;
 assign image_error=error;assign audio_error=error;
 always @(posedge clk or posedge rst)begin
  if(rst)begin ip<=0;ap<=0;active<=0;owner<=0;last_owner<=0;killed<=0;il<=0;al<=0;request<=0;lba<=0;reset_count<=0;end
  else begin
   request<=0;if(reset_count!=0)reset_count<=reset_count-1'b1;
   if(image_req&&!image_busy&&!cancel_image)begin ip<=1;il<=image_lba;end
   if(audio_req&&!audio_busy)begin ap<=1;al<=audio_lba;end
   if(cancel_image)begin ip<=0;if(active&&!owner)killed<=1;end
   if(active&&done)begin active<=0;last_owner<=owner;if(error!=0)reset_count<=63;end
   // Fair sector alternation bounds both clients' wait to one other sector.
   if(!active&&!busy&&!recover&&ready)begin
    if(ap && (!ip || !last_owner || cancel_image))begin
     ap<=0;owner<=1;active<=1;killed<=0;lba<=al;request<=1;
    end else if(ip&&!cancel_image)begin
     ip<=0;owner<=0;active<=1;killed<=0;lba<=il;request<=1;
    end
   end
  end
 end
endmodule
