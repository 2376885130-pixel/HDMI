// Read-only fixed 8.3 BGM.WAV root lookup. Geometry comes from the mounted BMP
// volume. A checked sector buffer absorbs the unbackpressurable SD byte burst.
module fat32_bgm_stream #(parameter SELECTABLE=0)(
 input wire [87:0] filename,
 input wire clk,rst,mounted,input wire[31:0]root_cluster,fat_lba,data_lba,max_cluster,
 input wire[3:0]cluster_shift,input wire[7:0]sectors_per_cluster,
 input wire start,restart,stop,
 output reg req,output reg[31:0]lba,input wire busy,valid,done,input wire[7:0]data,error,
 output wire byte_valid,input wire byte_ready,output wire[7:0]byte_data,output wire byte_last,
 output reg found,output reg[31:0]file_size,output reg[7:0]status,
 output reg[31:0]error_lba
);
 localparam IDLE=0,ADDRESS=1,REQUEST=2,RECEIVE=3,FETCH=4,USE=5,NEXT=6,FOUND=7,EOF=8,HALT=9,CHECK_SECTOR=10;
 localparam DIR=0,FAT=1,FILE=2;
 reg[3:0]state;reg[1:0]kind,after_fat;
 reg[31:0]cluster,first_cluster,next_cluster,position;reg[7:0]sec;
 reg[31:0]hops;reg[9:0]received;reg[8:0]index;reg[7:0]buffer[0:511],q;
 reg[7:0]completion_error;
 reg name_ok,eligible;reg[31:0]entry_cluster,entry_size;
 wire[8:0]fat_offset={cluster[6:0],2'b00};
 wire[31:0]entry_size_now={q,entry_size[23:0]};
 assign byte_valid=state==USE&&kind==FILE&&!stop;
 assign byte_data=q;assign byte_last=position==file_size-1;
 function[7:0]upper;input[7:0]c;begin upper=(c>=97&&c<=122)?c-32:c;end endfunction
 function[7:0]name_byte;input[3:0]i;begin
  if(SELECTABLE)name_byte=filename[(10-i)*8+:8];
  else case(i)0:name_byte="B";1:name_byte="G";2:name_byte="M";8:name_byte="W";9:name_byte="A";10:name_byte="V";default:name_byte=32;endcase
 end endfunction
 task fail;input[7:0]code;begin state<=HALT;status<=code;error_lba<=lba;end endtask
 // Address/data/WE travel together. The BRAM commits on the falling edge;
 // FETCH/USE keep their existing rising-edge synchronous-read contract.
 (* preserve=1,keep=1 *) reg buffer_wr_valid;
 (* preserve=1,keep=1 *) reg [8:0] buffer_wr_address;
 (* preserve=1,keep=1 *) reg [7:0] buffer_wr_data;
 always @(posedge clk or posedge rst)begin
  if(rst)begin buffer_wr_valid<=0;buffer_wr_address<=0;buffer_wr_data<=0;end
  else begin
   buffer_wr_valid<=state==RECEIVE&&valid&&received<512;
   buffer_wr_address<=received[8:0];buffer_wr_data<=data;
  end
 end
 always @(negedge clk)if(buffer_wr_valid)buffer[buffer_wr_address]<=buffer_wr_data;
 always @(posedge clk)q<=buffer[index];
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;kind<=DIR;after_fat<=DIR;cluster<=0;first_cluster<=0;next_cluster<=0;
   position<=0;sec<=0;hops<=0;received<=0;completion_error<=0;index<=0;name_ok<=0;eligible<=0;
   entry_cluster<=0;entry_size<=0;req<=0;lba<=0;found<=0;file_size<=0;status<=0;error_lba<=0;
  end else begin
   req<=0;
   case(state)
    IDLE:if(mounted)begin cluster<=root_cluster;sec<=0;kind<=DIR;state<=ADDRESS;status<=1;end
    ADDRESS:begin
     lba<=kind==FAT?fat_lba+(cluster>>7):data_lba+((cluster-2)<<cluster_shift)+sec;
     state<=REQUEST;
    end
    REQUEST:if(!busy)begin req<=1;received<=0;completion_error<=0;state<=RECEIVE;end
    RECEIVE:begin
     // Count actual received beats, saturating at the first excess byte.
     // This prevents a very long malformed transfer wrapping to 512 again.
     if(valid&&received<10'd513)received<=received+10'd1;
     // Separate completion capture from the length decision. The final beat
     // (which may coincide with done) and falling-edge BRAM write commit
     // before CHECK_SECTOR reads the registered count. No combinational
     // received+valid carry chain participates in the completion decision.
     if(done)begin completion_error<=error;state<=CHECK_SECTOR;end
    end
    CHECK_SECTOR:begin
     if(completion_error!=0)fail(8'h20|completion_error);
     else if(received!=10'd512)fail(8'h26);
     else begin index<=0;state<=FETCH;end
    end
    FETCH:state<=USE;
    USE:begin
     if(kind==DIR)begin
      if(index[4:0]==0)begin
       name_ok<=upper(q)==name_byte(0);eligible<=q!=8'he5;
       entry_cluster<=0;entry_size<=0;
       if(q==0)fail(8'h10);
      end else if(index[4:0]<=10)name_ok<=name_ok&&(upper(q)==name_byte(index[3:0]));
      if(index[4:0]==11)eligible<=eligible&&q!=8'h0f&&!q[3]&&!q[4];
      case(index[4:0])
       20:entry_cluster[23:16]<=q;21:entry_cluster[31:24]<={4'b0,q[3:0]};
       26:entry_cluster[7:0]<=q;27:entry_cluster[15:8]<=q;
       28:entry_size[7:0]<=q;29:entry_size[15:8]<=q;30:entry_size[23:16]<=q;
      endcase
      if(index[4:0]==31&&name_ok&&eligible)begin
       if(entry_cluster<2||entry_cluster>max_cluster||entry_size_now<44)fail(8'h11);
       else begin first_cluster<=entry_cluster;file_size<=entry_size_now;found<=1;status<=2;state<=FOUND;end
      end else if(!(index[4:0]==0&&q==0))begin
       if(index==511)state<=NEXT;else begin index<=index+1'b1;state<=FETCH;end
      end
     end else if(kind==FAT)begin
      if(index==fat_offset)next_cluster[7:0]<=q;
      if(index==fat_offset+1)next_cluster[15:8]<=q;
      if(index==fat_offset+2)next_cluster[23:16]<=q;
      if(index==fat_offset+3)next_cluster[31:24]<={4'b0,q[3:0]};
      if(index==511)state<=NEXT;else begin index<=index+1'b1;state<=FETCH;end
     end else if(byte_ready)begin
      position<=position+1'b1;
      if(byte_last)begin state<=EOF;status<=4;end
      else if(index==511)state<=NEXT;else begin index<=index+1'b1;state<=FETCH;end
     end
    end
    NEXT:begin
     if(kind==FAT)begin
      if(next_cluster>=32'h0ffffff8)fail(after_fat==DIR?8'h10:8'h12);
      else if(next_cluster<2||next_cluster>max_cluster||next_cluster>=32'h0ffffff0||next_cluster==cluster||hops>=max_cluster)fail(8'h13);
      else begin cluster<=next_cluster;sec<=0;hops<=hops+1'b1;kind<=after_fat;state<=ADDRESS;end
     end else if(sec+1<sectors_per_cluster)begin sec<=sec+1'b1;state<=ADDRESS;end
     else begin after_fat<=kind;kind<=FAT;state<=ADDRESS;end
    end
    FOUND:if(start)begin cluster<=first_cluster;sec<=0;position<=0;hops<=0;kind<=FILE;state<=ADDRESS;status<=3;end
    EOF:if(restart)begin cluster<=first_cluster;sec<=0;position<=0;hops<=0;kind<=FILE;state<=ADDRESS;status<=3;end
    HALT:state<=HALT;
   endcase
   if(stop)begin state<=HALT;req<=0;end
  end
 end
endmodule
