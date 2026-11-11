// One outstanding read, slow service clock -> fast SPI clock. The service
// owns timeout/reset. Keep the request asserted until the first response so
// the reference controller can finish CMD16 even if sd_init_done rose early.
// Ordered {done,valid,byte} records use individually acknowledged held slots.
// No BRAM show-ahead/empty/data-latency contract is used on this small channel.
module sd_transport_cdc(
 input wire service_clk,spi_clk,rst,
 input wire request,input wire [31:0] lba,
 output wire ready,output reg valid,output reg [7:0] data,output reg done,
 output wire spi_reset,output reg spi_request,output reg [31:0] spi_lba,
 input wire spi_ready,spi_valid,spi_done,input wire [7:0] spi_data,
 output wire response_fault
);
 (* preserve=1,keep=1 *) reg [2:0] service_release=0,spi_release=0;
 always @(posedge service_clk or posedge rst)
  if(rst)service_release<=0;else service_release<={service_release[1:0],1'b1};
 always @(posedge spi_clk or posedge rst)
  if(rst)spi_release<=0;else spi_release<={spi_release[1:0],1'b1};
 wire service_reset=~service_release[2];
 assign spi_reset=~spi_release[2];
 (* preserve=1,keep=1 *) reg [1:0] ready_sync;
 reg request_toggle;
 (* preserve=1,keep=1 *) reg [31:0] held_lba;
 always @(posedge service_clk or posedge service_reset)begin
  if(service_reset)begin ready_sync<=0;request_toggle<=0;held_lba<=0;end
  else begin
   ready_sync<={ready_sync[0],spi_ready};
   if(request)begin held_lba<=lba;request_toggle<=~request_toggle;end
  end
 end
 assign ready=ready_sync[1] && !service_reset;
 (* preserve=1,keep=1 *) reg [2:0] request_sync;
 always @(posedge spi_clk or posedge spi_reset)begin
  if(spi_reset)begin request_sync<=0;spi_request<=0;spi_lba<=0;end
  else begin
   request_sync<={request_sync[1:0],request_toggle};
   if(request_sync[2]!=request_sync[1])begin spi_lba<=held_lba;spi_request<=1;end
   else if(spi_valid || spi_done)spi_request<=0;
  end
 end
 wire push=!spi_reset && (spi_valid || spi_done);
 // A slot is immutable from publish until acknowledgement returns via 2FF.
 // Consumers visit slots in order. Publication passes 2FF plus capture edge.
 // Payload flight is bounded in SDC; inter-stage paths remain timed.
 // Sixteen slots support adjacent byte/done and sustained 50 MB/s tests.
 // Physical 12.5 MHz SCLK supplies <=1.5625 MB/s; its divider is unchanged.
 (* preserve=1,keep=1 *) reg [159:0] response_held;
 (* preserve=1,keep=1 *) reg [15:0] published,acknowledged;
 (* async_reg="true",preserve=1,keep=1 *) reg [15:0] publish_meta,publish_sync,ack_meta,ack_sync;
 reg [3:0] write_slot,read_slot;
 reg overflow;
 (* async_reg="true",preserve=1,keep=1 *) reg [1:0] overflow_sync;
 wire occupied=published[write_slot]!=ack_sync[write_slot];
 wire available=publish_sync[read_slot]!=acknowledged[read_slot];
 wire [9:0] response=response_held[read_slot*10 +: 10];
 assign response_fault=overflow_sync[1] && !service_reset;
 always @(posedge spi_clk or posedge spi_reset)begin
  if(spi_reset)begin
   response_held<=0;published<=0;write_slot<=0;
   ack_meta<=0;ack_sync<=0;overflow<=0;
  end else begin
   ack_meta<=acknowledged;ack_sync<=ack_meta;
   if(push && !overflow)begin
    if(occupied)overflow<=1;
    else begin
     response_held[write_slot*10 +: 10]<={spi_done,spi_valid,spi_data};
     published[write_slot]<=~published[write_slot];
     write_slot<=write_slot+1'b1;
    end
   end
  end
 end
 always @(posedge service_clk or posedge service_reset)begin
  if(service_reset)begin
   valid<=0;done<=0;data<=0;read_slot<=0;acknowledged<=0;
   publish_meta<=0;publish_sync<=0;overflow_sync<=0;
  end
  else begin
   publish_meta<=published;publish_sync<=publish_meta;
   overflow_sync<={overflow_sync[0],overflow};
   valid<=0;done<=0;
   if(available && !response_fault)begin
    valid<=response[8];done<=response[9];data<=response[7:0];
    acknowledged[read_slot]<=publish_sync[read_slot];
    read_slot<=read_slot+1'b1;
   end
  end
 end
 // No upstream backpressure: an overrun is a sticky explicit fault until the
 // arbiter resets the complete transaction; never drop a byte as success.
endmodule
