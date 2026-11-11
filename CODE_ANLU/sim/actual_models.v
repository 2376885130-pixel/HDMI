`timescale 1ns/1ps
// Only board/device boundaries are behavioral. Production FIFOs, arbitration,
// loaders, scaling, cache, OSD, PCM and HDMI symbol encoders remain real RTL.
module sys_pll(input refclk,reset,output extlock,clk0_out,output reg clk1_out=0,output clk2_out,output reg clk3_out=0);
 reg [5:0] count=0;assign extlock=!reset&&count==31;
 assign clk0_out=refclk;always #10 clk1_out=~clk1_out;
 assign clk2_out=~clk1_out;always #5 clk3_out=~clk3_out;
 always @(posedge refclk or posedge reset)if(reset)count<=0;else if(count<31)count<=count+1;
endmodule
module video_pll(input refclk,reset,output extlock,output reg clk0_out=0,clk1_out=0);
 reg [5:0] count=0;assign extlock=!reset&&count==31;
 // Serializer is already a behavioral boundary in this test; no logic consumes
 // clk0_out. Avoid scheduling unused 125MHz edges. Pixel/media clocks unchanged.
 always #20 clk1_out=~clk1_out;
 always @(posedge refclk or posedge reset)if(reset)count<=0;else if(count<31)count<=count+1;
endmodule
module hdmi_phy_wrapper #(parameter DEVICE="EG")(
 input I_pixel_clk,I_serial_clk,I_rst,input[9:0]I_tmds_channel_0,I_tmds_channel_1,I_tmds_channel_2,I_tmds_channel_clk,
 output O_tmds_ch0_p,O_tmds_ch1_p,O_tmds_ch2_p,O_tmds_clk_p);
 assign O_tmds_ch0_p=I_tmds_channel_0[0];assign O_tmds_ch1_p=I_tmds_channel_1[0];
 assign O_tmds_ch2_p=I_tmds_channel_2[0];assign O_tmds_clk_p=I_pixel_clk;
endmodule
module sdram(input Clk,Clk_sft,Rst,App_wr_en,input[20:0]App_wr_addr,input[3:0]App_wr_dm,input[31:0]App_wr_din,
 input App_rd_en,input[20:0]App_rd_addr,output Sdr_init_done,Sdr_init_ref_vld,Sdr_busy,Sdr_rd_en,output[31:0]Sdr_rd_dout);
 reg [31:0] memory[0:2097151];reg [19:0] valid_pipe=0;reg [31:0] data_pipe[0:19];
 integer init_count=0,refresh_count=0,j,writes=0,reads=0;
 assign Sdr_init_done=!Rst&&init_count==37;
 assign Sdr_init_ref_vld=refresh_count<8;assign Sdr_busy=Sdr_init_ref_vld;
 assign Sdr_rd_en=valid_pipe[19];assign Sdr_rd_dout=data_pipe[19];
 always @(posedge Clk)begin
  if(Rst)begin init_count<=0;valid_pipe<=0;refresh_count<=0;end
  else begin
   if(init_count<37)init_count<=init_count+1;
   refresh_count<=refresh_count==389?0:refresh_count+1;
   valid_pipe<={valid_pipe[18:0],App_rd_en};
   if(App_rd_en)begin data_pipe[0]<=memory[App_rd_addr];reads=reads+1;end
   for(j=1;j<20;j=j+1)data_pipe[j]<=data_pipe[j-1];
   if(App_wr_en)begin memory[App_wr_addr]<=App_wr_din;writes=writes+1;end
   if(App_wr_en&&App_rd_en)$fatal(1,"memory read/write overlap");
  end
 end
endmodule
module sd_card_top #(parameter SPI_LOW_SPEED_DIV=123,SPI_HIGH_SPEED_DIV=0)(
 input clk,rst,SD_MISO,input sd_sec_read,input[31:0]sd_sec_read_addr,
 input sd_sec_write,input[31:0]sd_sec_write_addr,input[7:0]sd_sec_write_data,
 output SD_nCS,SD_DCLK,SD_MOSI,output sd_init_done,output reg[7:0]sd_sec_read_data,
 output reg sd_sec_read_data_valid=0,sd_sec_read_end=0,output sd_sec_write_data_req,sd_sec_write_end);

 `include "actual_card_config.vh"
 reg [7:0] actual_bytes[0:ACTUAL_BYTES-1];
 reg [31:0] actual_lbas[0:ACTUAL_COUNT-1];
 integer fd,n,index=0,phase=0,requests=0;
 integer match_index,lo,hi,mid;
 reg active=0;reg [31:0] address;
 assign sd_init_done=~rst;assign SD_nCS=!active;assign SD_DCLK=clk;assign SD_MOSI=0;
 assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
 initial begin
  $readmemh("media/actual_lbas.hex",actual_lbas);
  fd=$fopen("media/actual_sectors.bin","rb");if(!fd)$fatal(1,"missing actual volume sectors");
  n=$fread(actual_bytes,fd);$fclose(fd);if(n!=ACTUAL_BYTES)$fatal(1,"short actual volume snapshot");
 end
 function [7:0] cardbyte(input integer sec,pos);
  cardbyte=actual_bytes[match_index*512+pos];
 endfunction
 always @(negedge clk)begin
  sd_sec_read_data_valid=0;sd_sec_read_end=0;
  if(rst)begin active=0;index=0;phase=0;end
  else if(sd_sec_read&&!active)begin address=sd_sec_read_addr;active=1;index=0;phase=0;requests=requests+1;
   lo=0;hi=ACTUAL_COUNT-1;match_index=-1;
   while(lo<=hi)begin
    mid=(lo+hi)/2;
    if(actual_lbas[mid]==address)begin match_index=mid;lo=hi+1;end
    else if(actual_lbas[mid]<address)lo=mid+1;else hi=mid-1;
   end
   if(match_index<0)$fatal(1,"read outside captured actual clusters lba=%d",address);
end
  else if(active)begin
   // 1 byte / 640 ns = 12.5 Mbit/s SPI payload cadence.
   if(phase==63)begin
    phase=0;
    if(index<512)begin sd_sec_read_data=cardbyte(address,index);sd_sec_read_data_valid=1;index=index+1;end
    else begin active=0;sd_sec_read_end=1;end
   end else phase=phase+1;
  end
 end
endmodule
