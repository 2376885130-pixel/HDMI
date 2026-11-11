// Four logical frame regions; one arbitrated SDRAM application port.
// SDRAM IP accepts a contiguous burst as in the board reference design.
// No per-word ready exists: grant only at a burst boundary, then drain fully.
module quad_frame_store #(
 parameter FRAME_WIDTH=640, FRAME_HEIGHT=480, BURST=128,
 parameter RETURN_TIMEOUT=4096, parameter DRAIN_CYCLES=16,THUMBNAILS=0
)(
 input wire mem_clk,rst,load_enable,
 input wire memory_initialized,memory_busy,memory_refresh,
 output wire app_rd_en,output reg [20:0] app_rd_addr,
 input wire rd_valid,input wire [31:0] rd_data,
 output wire app_wr_en,output reg [20:0] app_wr_addr,
 output wire [31:0] app_wr_data,output wire [3:0] app_wr_mask,
 input wire write_clk,write_req,input wire [1:0] write_slot,
 output reg write_ack,output reg write_finish,
 input wire pixel_valid,input wire [31:0] pixel_data,
 input wire read_clk,read_req,input wire [1:0] read_slot,
 output reg read_ack,input wire read_en,output wire [31:0] read_data,
 output wire read_primed,output reg read_underflow,
 output wire memory_fault,output wire writer_reset,
 input wire read_preview,read_bank,
 input wire dma_req,dma_write,input wire [20:0] dma_addr,input wire [31:0] dma_wdata,
 output reg dma_accept,dma_done,output wire dma_valid,output wire [31:0] dma_rdata,
 output wire [6:0] dma_word
);
 localparam WORDS=FRAME_WIDTH*FRAME_HEIGHT;
 localparam IDLE=0,WRITE=1,WRITE_DRAIN=2,READ=3,READ_DRAIN=4,FAULT=5,
 DMA_PREP=6,DMA_WRITE=7,DMA_WDRAIN=8,DMA_READ=9,DMA_RDRAIN=10;
 reg [3:0] state;
 reg [7:0] burst_count;
 reg [8:0] returns_left;
 reg dma_owner;
 reg [20:0] saved_rd,saved_wr;
 reg [1:0] preview_meta,preview_sync;
 wire [31:0] writer_data;
 assign app_wr_data=state==DMA_WRITE ? dma_wdata : writer_data;
 assign dma_word=state==DMA_WRITE ? burst_count[6:0]+1'b1 : 7'd0;
 assign dma_valid=rd_valid && dma_owner && returns_left!=0;
 assign dma_rdata=rd_data;
 reg [15:0] timeout_count;
 reg [7:0] drain_count;
 reg [20:0] written,read_sent;
 reg [9:0] write_x;
 reg writer_active,reader_active;
 reg write_clear,read_clear;
 reg [3:0] write_release,read_release;
 reg fatal_read,fatal_write;
 (* preserve=1,keep=1 *) reg [2:0] wreq_sync,rreq_sync,enable_sync;
 reg [1:0] wslot_meta,wslot_sync,rslot_meta,rslot_sync;
 wire [8:0] write_used,read_used,read_available;
 wire write_full,read_full,read_empty;
 reg source_overflow;
 (* preserve=1,keep=1 *) reg [1:0] overflow_sync;
 wire fifo_write_reset=rst|write_clear;
 wire fifo_read_reset=rst|read_clear;
 assign writer_reset=fifo_write_reset;
 assign app_wr_mask=0;
 assign app_wr_en=state==WRITE || state==DMA_WRITE;
 assign app_rd_en=state==READ || state==DMA_READ;
 assign memory_fault=fatal_read|fatal_write;
 assign read_primed=!fifo_read_reset && read_available>=BURST && !read_underflow;
 function [20:0] base;
 input [1:0] slot;
 begin case(slot)
  0:base=0;1:base=WORDS;2:base=WORDS*2;default:base=WORDS*3;
 endcase end endfunction
 // synthesis translate_off
 initial if(BURST<1 || BURST>128 || WORDS%BURST || FRAME_WIDTH%BURST ||
            WORDS*4>2097152 || RETURN_TIMEOUT>65535 || DRAIN_CYCLES>255)
  $fatal(1,"Unsupported quad frame geometry/burst/timeout");
 // synthesis translate_on
 wfifo_32_32_512 write_fifo(.clkw(write_clk),.clkr(mem_clk),.rst(fifo_write_reset),
  .we(pixel_valid && !fifo_write_reset),.di(pixel_data),.re(state==WRITE),
  .dout(writer_data),.full_flag(write_full),.rdusedw(write_used));
 rfifo_32_32_512 read_fifo(.clkw(mem_clk),.clkr(read_clk),.rst(fifo_read_reset),
  .we(rd_valid && returns_left!=0 && !dma_owner && !fatal_read && !read_full),.di(rd_data),
  .re(read_en && !read_underflow),.dout(read_data),.full_flag(read_full),
  .empty_flag(read_empty),.wrusedw(read_used),.rdusedw(read_available));
 always @(posedge write_clk or posedge fifo_write_reset)
  if(fifo_write_reset)source_overflow<=0;
  else if(pixel_valid && write_full)source_overflow<=1;
 always @(posedge read_clk or posedge fifo_read_reset)
  if(fifo_read_reset)read_underflow<=0;
  else if(read_en && read_empty)read_underflow<=1;
 always @(posedge mem_clk or posedge rst)begin
  if(rst)begin
   wreq_sync<=0;rreq_sync<=0;enable_sync<=0;overflow_sync<=0;
   wslot_meta<=0;wslot_sync<=0;rslot_meta<=0;rslot_sync<=0;preview_meta<=0;preview_sync<=0;
  end else begin
   wreq_sync<={wreq_sync[1:0],write_req};rreq_sync<={rreq_sync[1:0],read_req};
   enable_sync<={enable_sync[1:0],load_enable};overflow_sync<={overflow_sync[0],source_overflow};
   wslot_meta<=write_slot;wslot_sync<=wslot_meta;
   rslot_meta<=read_slot;rslot_sync<=rslot_meta;
   preview_meta<={read_preview,read_bank};preview_sync<=preview_meta;
  end
 end
 always @(posedge mem_clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;burst_count<=0;returns_left<=0;timeout_count<=0;drain_count<=0;
   written<=0;read_sent<=0;write_x<=0;writer_active<=0;reader_active<=0;
   write_clear<=1;read_clear<=1;write_release<=0;read_release<=0;
   write_ack<=0;read_ack<=0;write_finish<=0;fatal_read<=0;fatal_write<=0;
   app_wr_addr<=0;app_rd_addr<=0;dma_accept<=0;dma_done<=0;dma_owner<=0;saved_rd<=0;saved_wr<=0;
  end else begin
   write_finish<=0;dma_accept<=0;dma_done<=0;
   if(overflow_sync[1])fatal_write<=1;
   // All accepted read commands must return before switching regions or writing.
   if(rd_valid && returns_left!=0)returns_left<=returns_left-1'b1;
   if(rd_valid && (returns_left==0 || (!dma_owner && read_full)))begin fatal_read<=1;state<=FAULT;end
   case(state)
    IDLE:begin
     burst_count<=0;timeout_count<=0;drain_count<=0;
     // Cancel only the writer. An accepted burst has already drained here.
     if(!enable_sync[2] || overflow_sync[1] || fatal_write)begin
      writer_active<=0;write_clear<=1;write_release<=0;write_ack<=0;
     end else if(wreq_sync[2])begin
      write_clear<=1;write_release<=0;write_ack<=1;writer_active<=1;
      written<=0;write_x<=0;app_wr_addr<=base(wslot_sync)+(FRAME_HEIGHT-1)*FRAME_WIDTH;
     end else if(write_clear)begin
      write_ack<=0;write_clear<=0;write_release<=8;
     end else if(write_release!=0)write_release<=write_release-1'b1;
     if(rreq_sync[2])begin
      read_ack<=1;read_clear<=1;read_release<=0;reader_active<=1;
      read_sent<=0;app_rd_addr<=THUMBNAILS && preview_sync[1] ? (preview_sync[0] ? WORDS*5 : WORDS*4) : base(rslot_sync);
     end else if(read_clear)begin read_ack<=0;read_clear<=0;read_release<=8;end
     else if(read_release!=0)read_release<=read_release-1'b1;
     // Read priority while fewer than 256 words are buffered. A 128-word
     // write consumes at most ~90 display pixels including the drain gap.
     if(memory_initialized && !memory_busy && !memory_refresh && !fatal_read &&
        !rd_valid && !rreq_sync[2] && !wreq_sync[2])begin
      if(reader_active && !read_clear && read_release==0 && read_used<256)begin
       state<=READ;returns_left<=BURST;
      end else if(writer_active && enable_sync[2] && !overflow_sync[1] && !fatal_write &&
                  !write_clear && write_release==0 && write_used>=BURST)begin
       state<=WRITE;
      end else if(THUMBNAILS && dma_req)begin
       dma_accept<=1;dma_owner<=1;saved_rd<=app_rd_addr;saved_wr<=app_wr_addr;
       if(dma_write)begin app_wr_addr<=dma_addr;state<=DMA_PREP;end
       else begin app_rd_addr<=dma_addr;state<=DMA_READ;returns_left<=BURST;end
      end
     end
    end
    WRITE:begin
     app_wr_addr<=write_x==FRAME_WIDTH-1 ? app_wr_addr-(2*FRAME_WIDTH-1) : app_wr_addr+1'b1;
     write_x<=write_x==FRAME_WIDTH-1 ? 10'd0 : write_x+1'b1;
     if(burst_count==BURST-1)begin
      written<=written+BURST;state<=WRITE_DRAIN;drain_count<=0;
     end else burst_count<=burst_count+1'b1;
    end
    WRITE_DRAIN:begin
     timeout_count<=timeout_count+1'b1;
     if(drain_count<DRAIN_CYCLES)drain_count<=drain_count+1'b1;
     else if(!memory_busy && !memory_refresh)begin
      state<=IDLE;
      if(written==WORDS)begin
       writer_active<=0;
       if(enable_sync[2] && !overflow_sync[1] && !fatal_write)write_finish<=1;
      end
     end
     if(timeout_count==RETURN_TIMEOUT-1)begin fatal_write<=1;state<=FAULT;end
    end
    READ:begin
     app_rd_addr<=app_rd_addr+1'b1;
     if(burst_count==BURST-1)begin
      read_sent<=read_sent+BURST;state<=READ_DRAIN;timeout_count<=0;drain_count<=0;
     end else burst_count<=burst_count+1'b1;
    end
    READ_DRAIN:begin
     if(drain_count<DRAIN_CYCLES)drain_count<=drain_count+1'b1;
     if(returns_left==0 && drain_count>=DRAIN_CYCLES && !memory_busy)begin
      state<=IDLE;if(read_sent==WORDS)reader_active<=0;
     end else if(timeout_count==RETURN_TIMEOUT-1)begin
      fatal_read<=1;state<=FAULT;reader_active<=0;
     end else timeout_count<=timeout_count+1'b1;
    end
    DMA_PREP:state<=DMA_WRITE;
    DMA_WRITE:begin
     app_wr_addr<=app_wr_addr+1'b1;
     if(burst_count==BURST-1)begin state<=DMA_WDRAIN;drain_count<=0;timeout_count<=0;end
     else burst_count<=burst_count+1'b1;
    end
    DMA_READ:begin
     app_rd_addr<=app_rd_addr+1'b1;
     if(burst_count==BURST-1)begin state<=DMA_RDRAIN;drain_count<=0;timeout_count<=0;end
     else burst_count<=burst_count+1'b1;
    end
    DMA_WDRAIN,DMA_RDRAIN:begin
     if(drain_count<DRAIN_CYCLES)drain_count<=drain_count+1'b1;
     if(drain_count>=DRAIN_CYCLES && !memory_busy && !memory_refresh && returns_left==0)begin
      app_rd_addr<=saved_rd;app_wr_addr<=saved_wr;dma_owner<=0;dma_done<=1;state<=IDLE;
     end else if(timeout_count==RETURN_TIMEOUT-1)begin fatal_read<=1;state<=FAULT;end
     else timeout_count<=timeout_count+1'b1;
    end
    // Unknown late returns cannot be assigned to a new epoch safely. Fail
    // closed until global reset; never mark a partly written frame valid.
    FAULT:begin writer_active<=0;reader_active<=0;write_ack<=0;read_ack<=0;end
    default:state<=FAULT;
   endcase
   if(rd_valid && (returns_left==0 || (!dma_owner && read_full)))begin fatal_read<=1;state<=FAULT;end
  end
 end
endmodule
