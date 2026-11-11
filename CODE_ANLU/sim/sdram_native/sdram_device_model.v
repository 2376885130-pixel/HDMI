`timescale 1ns/1ps
// Review-only JEDEC SDR SDRAM functional device. Not a vendor timing model.
// Models 4 banks x 2048 rows x 256 columns, mode-register burst/CAS,
// active/precharge, byte masks, read/write burst termination and tAC.
module EG_PHY_SDRAM_2M_32 #(parameter TAC=5)(
 input clk,ras_n,cas_n,we_n,input[10:0]addr,input[1:0]ba,
 inout[31:0]dq,input cs_n,dm0,dm1,dm2,dm3,cke);
 reg[31:0] memory[0:2097151];reg[10:0]rows[0:3];reg[3:0]active=0;
 reg[31:0]dq_out;reg drive=0;assign dq=drive?dq_out:32'bz;
 integer length=1,caslat=3,rleft=0,wleft=0,col=0,bank=0;
 integer read_col=0,read_bank=0,writes=0,reads=0,cmds=0;
 reg[3:0]valid_pipe=0;reg[31:0]data_pipe[0:3];integer k,ad;
 reg ap=0;reg[3:0]mask;
 always @(posedge clk)if(cke)begin
  drive<=#TAC valid_pipe[caslat-1];dq_out<=#TAC data_pipe[caslat-1];
  for(k=3;k>0;k=k-1)begin valid_pipe[k]<=valid_pipe[k-1];data_pipe[k]<=data_pipe[k-1];end
  valid_pipe[0]<=0;
  if(!cs_n)begin
   case({ras_n,cas_n,we_n})
    3'b000:begin length=(addr[2:0]==7)?256:(1<<addr[2:0]);caslat=addr[6:4];end
    3'b011:begin rows[ba]=addr;active[ba]=1;end
    3'b010:begin if(addr[10])active=0;else active[ba]=0;rleft=0;wleft=0;end
    3'b110:begin rleft=0;wleft=0;end
    3'b101:begin
     if(!active[ba])$fatal(1,"READ without active bank");
     read_col=addr[7:0];read_bank=ba;rleft=length;wleft=0;ap=addr[10];cmds=cmds+1;
    end
    3'b100:begin
     if(!active[ba])$fatal(1,"WRITE without active bank");
     col=addr[7:0];bank=ba;wleft=length;rleft=0;ap=addr[10];cmds=cmds+1;
    end
   endcase
  end
  if(rleft>0)begin
   ad={rows[read_bank],read_bank[1:0],read_col[7:0]};
   valid_pipe[0]<=1;data_pipe[0]<=memory[ad];reads=reads+1;
   read_col=(read_col+1)%256;rleft=rleft-1;if(rleft==0&&ap)active[read_bank]=0;
  end
  if(wleft>0)begin
   ad={rows[bank],bank[1:0],col[7:0]};mask={dm3,dm2,dm1,dm0};
   for(k=0;k<4;k=k+1)if(!mask[k])memory[ad][k*8+:8]=dq[k*8+:8];
   writes=writes+1;col=(col+1)%256;wleft=wleft-1;if(wleft==0&&ap)active[bank]=0;
  end
 end
endmodule
