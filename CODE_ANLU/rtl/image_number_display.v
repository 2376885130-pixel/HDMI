// HX4S20C: common-anode segments (active low), PNP digit selects active low.
// Eight positions, left to right: "01 OF 32". No valid images: "00 OF 00".
module image_number_display #(
 parameter integer FOLLOW_DISPLAY_INDEX=0,
 parameter integer SLOT_CYCLES=50000,
 parameter integer BLANK_CYCLES=100,
 parameter integer STATUS_UI=0,
 parameter integer DIAGNOSTIC_UI=0,
 parameter integer NOTICE_CYCLES=100000000,
 parameter integer TIMED_SECONDS=0
)(input wire clk,reset_n,input wire [4:0] image_index,
 input wire [5:0] total_count,
 output reg [7:0] seg_n=8'hff,output reg [7:0] digit_en=8'hff,
 input wire image_shown,input wire [3:0] load_status,
 input wire [1:0] interval_setting,input wire auto_mode,input wire reverse_direction,
 input wire [3:0] fault_stage,input wire fault_display,input wire [31:0] fault_code);
 localparam integer NOTICE_BITS=(NOTICE_CYCLES<2)?1:$clog2(NOTICE_CYCLES+1);
 reg [NOTICE_BITS-1:0] notice_count=0;
 reg [2:0] shown_sync=0;
 reg [3:0] status_meta=0,status_sync=0,status_stable=0;
 reg [3:0] previous_settings=0;
 reg [4:0] displayed_index=0;
 reg display_valid=0;
 reg [1:0] page_latched=0; // 0=count, 1=loading, 2=error, 3=period
 reg [5:0] value_latched=0;
 reg [3:0] fault_stage_latched=0;
 reg fault_display_meta=0;
 reg [31:0] fault_code_meta=0;
 always @(negedge clk or negedge reset_n)begin
  if(!reset_n)begin shown_sync[0]<=0;status_meta<=0;end
  else begin
   shown_sync[0]<=image_shown;status_meta<=load_status;
   fault_display_meta<=fault_display;fault_code_meta<=fault_code;
  end
 end
 wire [3:0] settings={auto_mode,reverse_direction,interval_setting};
 wire [5:0] period_sec=TIMED_SECONDS!=0?TIMED_SECONDS:interval_setting==0?6'd2:interval_setting==1?6'd5:interval_setting==2?6'd10:6'd20;
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin
   shown_sync[2:1]<=0;status_sync<=0;status_stable<=0;
   previous_settings<=0;notice_count<=0;displayed_index<=0;display_valid<=0;
  end else begin
   shown_sync[2:1]<=shown_sync[1:0];
   status_sync<=status_meta;
   if(status_meta==status_sync)status_stable<=status_sync;
   previous_settings<=settings;
   if((FOLLOW_DISPLAY_INDEX && shown_sync[2]) || (shown_sync[1] && !shown_sync[2]))begin displayed_index<=image_index;display_valid<=1;end
   if(total_count==0)display_valid<=0;
   if(TIMED_SECONDS!=0&&!auto_mode)notice_count<=0;
   else if(settings!=previous_settings)notice_count<=NOTICE_CYCLES;
   else if(notice_count!=0)notice_count<=notice_count-1'b1;
  end
 end
 reg [15:0] count=0;
 reg [2:0] digit=0;
 reg [5:0] image_latched=0,total_latched=0;
 wire [3:0] fault_symbol=fault_code_meta >> ((7-digit)*4);
 wire [3:0] symbol=fault_display_meta ? fault_symbol : (STATUS_UI && page_latched!=0) ?
  (digit==0 ? (page_latched==1?4'd12:page_latched==2?4'd13:4'd14) :
   (DIAGNOSTIC_UI && page_latched==2 && digit==3) ? 4'd5 :
   (DIAGNOSTIC_UI && page_latched==2 && digit==4) ? fault_stage_latched :
   digit==6 ? value_latched/10 : digit==7 ? value_latched%10 : 4'd15) :
  pick_symbol(digit,image_latched,total_latched);
 function [7:0] encode;
  input [3:0] value;
  begin case(value)
   0:encode=8'hc0;1:encode=8'hf9;2:encode=8'ha4;
   3:encode=8'hb0;4:encode=8'h99;5:encode=8'h92;
   6:encode=8'h82;7:encode=8'hf8;8:encode=8'h80;9:encode=8'h90;
   10:encode=8'hc0; // O
   11:encode=8'h8e; // F
   12:encode=8'hc7; // L: loading target
   13:encode=8'h86; // E: error
   14:encode=8'h8c; // P: slideshow period in seconds
   default:encode=8'hff;
  endcase end
 endfunction
 // Error-stage digit is hexadecimal. The normal page still uses O/F/L/E/P.
 function [7:0] encode_fault;
  input [3:0] value;
  begin case(value)
   10:encode_fault=8'h88;11:encode_fault=8'h83;12:encode_fault=8'hc6;
   13:encode_fault=8'ha1;14:encode_fault=8'h86;15:encode_fault=8'h8e;
   default:encode_fault=encode(value);
  endcase end
 endfunction
 function [3:0] pick_symbol;
  input [2:0] position;
  input [5:0] image_number,total_number;
  begin case(position)
   0:pick_symbol=image_number/10;
   1:pick_symbol=image_number%10;
   3:pick_symbol=10;
   4:pick_symbol=11;
   6:pick_symbol=total_number/10;
   7:pick_symbol=total_number%10;
   default:pick_symbol=15;
  endcase end
 endfunction
 always @(posedge clk or negedge reset_n) begin
  if(!reset_n) begin count<=0;digit<=0;seg_n<=8'hff;digit_en<=8'hff;image_latched<=0;total_latched<=0;page_latched<=0;value_latched<=0;fault_stage_latched<=0;end
  else begin
   if(count==SLOT_CYCLES-1) begin count<=0;digit<=digit+1'b1;end
   else count<=count+1'b1;
   if(count==0)begin
    digit_en<=8'hff;
    if(digit==0)begin
     image_latched<=total_count==0 ? 6'd0 : STATUS_UI ?
       (display_valid ? {1'b0,displayed_index}+1'b1 : 6'd0) : {1'b0,image_index}+1'b1;
     total_latched<=total_count;
     fault_stage_latched<=fault_stage;
     if(STATUS_UI && status_stable>=10)begin page_latched<=2;value_latched<={2'b0,status_stable};end
     else if(STATUS_UI && !shown_sync[2] && !display_valid)begin page_latched<=1;value_latched<=total_count==0?0:{1'b0,image_index}+1'b1;end
     else if(STATUS_UI && notice_count!=0)begin page_latched<=3;value_latched<=period_sec;end
     else begin page_latched<=0;value_latched<=0;fault_stage_latched<=0;end
    end
   end
   // Break before make: disable old digit, change segments, enable next digit.
   if(count==BLANK_CYCLES/2)seg_n<=fault_display_meta ? encode_fault(symbol) :
     STATUS_UI && DIAGNOSTIC_UI && page_latched==2 && digit==4 ? encode_fault(symbol) : encode(symbol);
   if(count==BLANK_CYCLES)digit_en<=~(8'b1<<digit);
  end
 end
endmodule

// Diagnostic-only first-error registers. Independent of transport recovery so
// the earliest evidence survives later SD resets. Code bytes, left to right:
// {WAV parse nibble, SD error nibble}, audio FS error, image stage/status,
// one-based image number in hexadecimal. Zero means no error captured there.
module preview_first_fault(input clk,reset_n,armed,bus_done,input [7:0] bus_error,audio_status,audio_parse,
 input [3:0] loader_status,loader_stage,input [4:0] job_index,
 input source_req,source_ack,source_ok,output wire [32:0] record);
 reg bus_seen,audio_seen,image_seen;
 reg [3:0] sd_code,parse_code;
 reg [7:0] fs_code,image_code,image_number;
 assign record={bus_seen|audio_seen|image_seen,parse_code,sd_code,fs_code,image_code,image_number};
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin bus_seen<=0;audio_seen<=0;image_seen<=0;sd_code<=0;parse_code<=0;fs_code<=0;image_code<=0;image_number<=0;end
  else if(armed)begin
   if(!bus_seen && bus_done && bus_error!=0)begin bus_seen<=1;sd_code<=bus_error[3:0];end
   if(!audio_seen && (audio_status>=8'h10 || audio_parse!=0))begin
    audio_seen<=1;fs_code<=audio_status;parse_code<=audio_parse[3:0];
   end
   if(!image_seen && (loader_status>=10 || (source_req && source_ack && !source_ok)))begin
    image_seen<=1;image_number<={3'd0,job_index}+8'd1;
    image_code<=loader_status>=10 ? {loader_stage,loader_status} : 8'hef;
   end
  end
 end
endmodule

module preview_fault_digits #(parameter SLOT_CYCLES=50000,BLANK_CYCLES=100)(
 input clk,reset_n,fault,input [31:0] code,input [7:0] normal_seg,normal_digit,
 output wire [7:0] seg_n,digit_en);
 reg [15:0] count;reg [2:0] digit;reg active;reg [31:0] held;
 reg [7:0] segments,enables;
 wire [3:0] nibble=held >> ((7-digit)*4);
 function [7:0] hex_segments;input [3:0] n;begin
  case(n)
   0:hex_segments=8'hc0;1:hex_segments=8'hf9;2:hex_segments=8'ha4;3:hex_segments=8'hb0;
   4:hex_segments=8'h99;5:hex_segments=8'h92;6:hex_segments=8'h82;7:hex_segments=8'hf8;
   8:hex_segments=8'h80;9:hex_segments=8'h90;10:hex_segments=8'h88;11:hex_segments=8'h83;
   12:hex_segments=8'hc6;13:hex_segments=8'ha1;14:hex_segments=8'h86;15:hex_segments=8'h8e;
  endcase
 end endfunction
 assign seg_n=active?segments:normal_seg;
 assign digit_en=active?enables:normal_digit;
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin count<=0;digit<=0;active<=0;held<=0;segments<=8'hff;enables<=8'hff;end
  else begin
   if(count==SLOT_CYCLES-1)begin count<=0;digit<=digit+1'b1;end else count<=count+1'b1;
   if(count==0)begin
    enables<=8'hff;
    if(digit==0)begin active<=fault;held<=code;end
   end
   if(count==BLANK_CYCLES/2)segments<=hex_segments(nibble);
   if(count==BLANK_CYCLES)enables<=~(8'b1<<digit);
  end
 end
endmodule
