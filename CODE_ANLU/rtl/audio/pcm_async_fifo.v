`timescale 1ns/1ps
// ADDR_BITS >= 2. Both domains share session reset assertion; releases are
// locally synchronized by wav_pcm_stream. Gray registers live in SOURCE domain.
module pcm_async_fifo #(parameter ADDR_BITS=10)(
 input wire wr_clk,wr_rst_n,input wire wr_valid,output wire wr_ready,input wire[32:0]wr_data,
 input wire rd_clk,rd_rst_n,output reg rd_valid,input wire rd_ready,output reg[32:0]rd_data,
 output wire[ADDR_BITS:0] rd_level
);
 reg[32:0] mem[0:(1<<ADDR_BITS)-1];
 reg[ADDR_BITS:0] wp,rp;
 (* preserve=1,keep=1 *) reg[ADDR_BITS:0]wg,rg;
 (* async_reg="true",preserve=1,keep=1 *) reg[ADDR_BITS:0] rs1,rs2,ws1,ws2;
 wire full=wg=={~rs2[ADDR_BITS:ADDR_BITS-1],rs2[ADDR_BITS-2:0]};
 wire empty=rg==ws2;
 wire push=wr_valid&&wr_ready;
 wire fetch=(!rd_valid||rd_ready)&&!empty;
 wire[ADDR_BITS:0] wn=wp+1'b1,rn=rp+1'b1;
 function[ADDR_BITS:0] ungray;input[ADDR_BITS:0]g;integer i;begin
  ungray[ADDR_BITS]=g[ADDR_BITS];for(i=ADDR_BITS-1;i>=0;i=i-1)ungray[i]=ungray[i+1]^g[i];
 end endfunction
 assign wr_ready=!full;
 assign rd_level=ungray(ws2)-rp+rd_valid;
 always @(posedge wr_clk or negedge wr_rst_n)begin
  if(!wr_rst_n)begin wp<=0;wg<=0;rs1<=0;rs2<=0;end
  else begin rs1<=rg;rs2<=rs1;if(push)begin wp<=wn;wg<=(wn>>1)^wn;end end
 end
 always @(posedge wr_clk)if(push && wr_rst_n)mem[wp[ADDR_BITS-1:0]]<=wr_data;
 always @(posedge rd_clk or negedge rd_rst_n)begin
  if(!rd_rst_n)begin rp<=0;rg<=0;ws1<=0;ws2<=0;rd_valid<=0;end
  else begin
   ws1<=wg;ws2<=ws1;
   if(!rd_valid||rd_ready)begin rd_valid<=!empty;if(fetch)begin rp<=rn;rg<=(rn>>1)^rn;end end
  end
 end
 // Synchronous RAM read, no array/output reset, allows dual-clock BRAM inference.
 always @(posedge rd_clk)if(fetch && rd_rst_n)rd_data<=mem[rp[ADDR_BITS-1:0]];
endmodule
