// Memory-domain offline nearest-neighbor compositor. All DMA uses the shared
// 128-word service. Two full 640x480 pages occupy slots 4 and 5 of SDRAM.
// Tiles are 160x120 at (64,64),(352,64),(64,240),(352,240).
// Two padded bursts per tile row keep writes contiguous and disjoint.
module thumbnail_page_builder(
 input wire clk,rst,enable,input wire [2:0] requested_page,
 input wire [5:0] image_total,input wire visible_bank,
 output reg source_req,output reg [4:0] source_index,
 input wire source_ack,source_ok,input wire [1:0] source_slot,
 output wire dma_req,output wire dma_write,output reg [20:0] dma_addr,
 input wire dma_accept,dma_done,input wire dma_valid,input wire [31:0] dma_rdata,
 input wire [6:0] dma_word,output wire [31:0] dma_wdata,
 output reg page_toggle,output reg page_bank,output reg [2:0] page_number,
 output reg [3:0] page_valid,input wire page_ack,
 output wire busy,
 input wire zoom_enable,input wire [4:0] zoom_index,
 output reg zoom_done,output wire [9:0] progress_rows,output reg page_zoom
);
 localparam IDLE=0,CLEAR_REQ=1,CLEAR_WAIT=2,SOURCE=3,SOURCE_WAIT=4,
 READ_REQ=5,READ_WAIT=6,WRITE_REQ=7,WRITE_WAIT=8,RELEASE=9,PUBLISH=10,WAIT_ACK=11;
 reg [3:0] state;reg [2:0] building_page;reg bank;
 reg [1:0] tile,slot;reg [6:0] row;reg [2:0] chunk;
 reg write_half;reg [6:0] returned;reg [7:0] sample_index;
 reg [20:0] clear_addr,source_row,dest_row;
 reg [3:0] valid_mask;
 reg have_page;reg [2:0] last_page;
 reg [24:0] line[0:1023];reg [24:0] line_q;
 reg zoom_mode;reg [3:0] zoom_step;reg [2:0] write_chunk;
 reg [8:0] zoom_row;reg [27:0] zoom_y;
 wire [9:0] zoom_width=160+zoom_step*60,zoom_height=120+zoom_step*45;
 // All tile origins are divisible by eight. Divide the constants first,
 // so a 32-bit intermediate multiplier is unnecessary (steps are 0..8).
 wire [3:0] remaining_steps=4'd8-zoom_step;
 // Snapshot once per animation frame, like ratio. Otherwise the address
 // path cascades origin multiplication and mapped_x multiplication in 20ns.
 reg [9:0] origin_x,origin_y;
 function [18:0] zoom_ratio;input [3:0] step;begin
  case(step)
   0:zoom_ratio=262144;1:zoom_ratio=190650;2:zoom_ratio=149796;
   3:zoom_ratio=123361;4:zoom_ratio=104857;5:zoom_ratio=91180;
   6:zoom_ratio=80659;7:zoom_ratio=72315;default:zoom_ratio=65536;
  endcase
 end endfunction
 reg [18:0] ratio;
 wire [9:0] dest_x={write_chunk,dma_word};
 wire [9:0] local_x=dest_x>=origin_x?dest_x-origin_x:10'd0;
 wire [28:0] mapped_x=local_x*ratio;
 wire [27:0] next_zoom_y=zoom_y+ratio;
 assign progress_rows=zoom_mode ? zoom_step*10'd60 : {tile,7'd0}-{tile,3'd0}+row;
 // Prefetch synchronous RAM read one cycle before the DMA write word.
 wire [9:0] line_address=zoom_mode ? mapped_x[25:16] : {2'd0,write_half,dma_word};
 reg line_color;
 always @(posedge clk)begin
  line_q<=line[line_address];
  line_color<=zoom_mode ? (dest_x>=origin_x && dest_x<origin_x+zoom_width) : (!write_half || dma_word<32);
 end
 assign dma_wdata=state==CLEAR_REQ || state==CLEAR_WAIT ? 32'd0 :
                  line_color ? {line_q[24:1],7'd0,line_q[0]} : 32'd0;
 assign dma_req=state==CLEAR_REQ || state==READ_REQ || state==WRITE_REQ;
 assign dma_write=state!=READ_REQ;
 assign busy=state!=IDLE;
 function [20:0] frame_base;input [1:0] s;begin
  case(s)0:frame_base=0;1:frame_base=307200;2:frame_base=614400;default:frame_base=921600;endcase
 end endfunction
 wire [20:0] page_base=bank ? 21'd1536000 : 21'd1228800;
 wire canceled=zoom_mode ? !zoom_enable : (!enable || requested_page!=building_page);
 always @(posedge clk)begin
  if(dma_valid && state==READ_WAIT)begin
   if(zoom_mode)line[{chunk,returned}]<={dma_rdata[31:8],dma_rdata[0]};
   else if(returned[1:0]==0)line[{2'd0,sample_index}]<={dma_rdata[31:8],dma_rdata[0]};
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;source_req<=0;source_index<=0;dma_addr<=0;
   page_toggle<=0;page_bank<=0;page_number<=0;page_valid<=0;
   building_page<=0;bank<=0;tile<=0;slot<=0;row<=0;chunk<=0;
   write_half<=0;returned<=0;sample_index<=0;clear_addr<=0;
   source_row<=0;dest_row<=0;valid_mask<=0;have_page<=0;last_page<=0;
   zoom_mode<=0;zoom_step<=0;zoom_done<=0;write_chunk<=0;zoom_row<=0;zoom_y<=0;page_zoom<=0;
   ratio<=0;origin_x<=0;origin_y<=0;
  end else begin
   if(!zoom_enable)begin zoom_done<=0;zoom_step<=0;end
   if(!enable)have_page<=0;
   if(dma_valid && state==READ_WAIT)begin
    returned<=returned+1'b1;
    if(returned[1:0]==0)sample_index<=sample_index+1'b1;
   end
   case(state)
    IDLE:if(zoom_enable && !zoom_done)begin
     // Geometry is constant for a published animation frame. Register it
     // before clearing/building the inactive page to isolate RAM addressing.
     ratio<=zoom_ratio(zoom_step);
     origin_x<=(zoom_index[0]?10'd44:10'd8)*remaining_steps;
     origin_y<=(zoom_index[1]?10'd30:10'd8)*remaining_steps;
     zoom_mode<=1;building_page<=zoom_index[4:2];bank<=~visible_bank;valid_mask<=4'b0001<<zoom_index[1:0];tile<=zoom_index[1:0];
     clear_addr<=0;dma_addr<=visible_bank?21'd1228800:21'd1536000;state<=CLEAR_REQ;
    end else if(enable && image_total!=0 && (!have_page || requested_page!=last_page))begin
     zoom_mode<=0;
     have_page<=0;
     building_page<=requested_page;bank<=~visible_bank;valid_mask<=0;tile<=0;
     clear_addr<=0;dma_addr<=visible_bank ? 21'd1228800 : 21'd1536000;state<=CLEAR_REQ;
    end
    CLEAR_REQ:if(dma_accept)state<=CLEAR_WAIT;
    CLEAR_WAIT:if(dma_done)begin
     if(canceled)state<=IDLE;
     else if(clear_addr==307200-128)state<=SOURCE;
     else begin clear_addr<=clear_addr+128;dma_addr<=dma_addr+128;state<=CLEAR_REQ;end
    end
    SOURCE:begin
     if(canceled)state<=IDLE;
     else if({building_page,tile}>=image_total)state<=PUBLISH;
     else begin source_index<=zoom_mode?zoom_index:{building_page,tile};source_req<=1;state<=SOURCE_WAIT;end
    end
    SOURCE_WAIT:if(source_ack)begin
     if(!source_ok || canceled)begin source_req<=0;state<=RELEASE;if(zoom_mode && !source_ok)zoom_done<=1;end
     else begin
      slot<=source_slot;row<=0;chunk<=0;sample_index<=0;returned<=0;
      zoom_row<=0;zoom_y<=0;write_chunk<=0;
      source_row<=frame_base(source_slot);dma_addr<=frame_base(source_slot);
      dest_row<=zoom_mode ? page_base+origin_y*21'd640 : page_base+(tile[1] ? 21'd153600 : 21'd40960)+(tile[0] ? 21'd352 : 21'd64);
      state<=READ_REQ;
     end
    end
    READ_REQ:if(dma_accept)begin state<=READ_WAIT;returned<=0;end
    READ_WAIT:if(dma_done)begin
     if(canceled)begin source_req<=0;state<=RELEASE;end
     else if(chunk==4)begin dma_addr<=dest_row;write_half<=0;write_chunk<=0;state<=WRITE_REQ;end
     else begin chunk<=chunk+1'b1;dma_addr<=dma_addr+128;state<=READ_REQ;end
    end
    WRITE_REQ:if(dma_accept)state<=WRITE_WAIT;
    WRITE_WAIT:if(dma_done)begin
     if(canceled)begin source_req<=0;state<=RELEASE;end
     else if(zoom_mode)begin
      if(write_chunk<4)begin write_chunk<=write_chunk+1'b1;dma_addr<=dma_addr+128;state<=WRITE_REQ;end
      else if(zoom_row+1==zoom_height)begin source_req<=0;state<=RELEASE;end
      else begin
       zoom_row<=zoom_row+1'b1;zoom_y<=next_zoom_y;
       dma_addr<=frame_base(slot)+next_zoom_y[27:16]*21'd640;
       dest_row<=dest_row+640;chunk<=0;returned<=0;state<=READ_REQ;
      end
     end
     else if(!write_half)begin write_half<=1;dma_addr<=dest_row+128;state<=WRITE_REQ;end
     else if(row==119)begin valid_mask[tile]<=1;source_req<=0;state<=RELEASE;end
     else begin
      row<=row+1'b1;source_row<=source_row+2560;dma_addr<=source_row+2560;
      dest_row<=dest_row+640;chunk<=0;sample_index<=0;state<=READ_REQ;
     end
    end
    RELEASE:if(!source_ack)begin
     if(canceled)state<=IDLE;
     else if(zoom_mode && zoom_done)state<=IDLE;
     else if(zoom_mode || tile==3)state<=PUBLISH;
     else begin tile<=tile+1'b1;state<=SOURCE;end
    end
    PUBLISH:begin
     page_zoom<=zoom_mode;
     page_bank<=bank;page_number<=building_page;page_valid<=valid_mask;
     page_toggle<=~page_toggle;state<=WAIT_ACK;
    end
    WAIT_ACK:if(page_ack==page_toggle)begin
     // Ack also releases discarded pages. Only a visible page is reusable.
     have_page<=!zoom_mode && enable && requested_page==building_page && visible_bank==bank;
     if(zoom_mode && zoom_enable && visible_bank==bank)begin
      if(zoom_step==8)zoom_done<=1;else zoom_step<=zoom_step+1'b1;
     end
     last_page<=building_page;state<=IDLE;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
