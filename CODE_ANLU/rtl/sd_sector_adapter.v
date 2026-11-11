// One outstanding 512-byte read, in the SD clock domain. The vendor transport
// accepts a request pulse while initialized/idle and has no error output.
// Data is streamed at its original cadence, with one registered cycle of delay.
// A fault blocks further requests until the shared transport/adapter reset;
// late bytes from an abandoned transaction must never enter a subsequent read.
module sd_sector_adapter #(
    parameter integer GAP_TIMEOUT_CYCLES = 25000000,   // 500 ms at 50 MHz
    parameter integer TOTAL_TIMEOUT_CYCLES = 50000000 // 1 s at 50 MHz
)(
    input wire clk, rst, sd_ready,
    input wire sector_req, input wire [31:0] sector_lba,
    output wire sector_busy,
    output reg sector_valid, output reg [7:0] sector_byte,
    output reg [8:0] sector_byte_index,
    output reg sector_done, output reg [7:0] sector_error,
    output reg reader_req, output reg [31:0] reader_lba,
    input wire reader_valid, input wire [7:0] reader_byte,
    input wire reader_done, input wire reader_fault
);
    localparam IDLE=2'd0, ACTIVE=2'd1, FINISH=2'd2, FAULT=2'd3;
    localparam ERR_NOT_READY=8'h01, ERR_SHORT=8'h02, ERR_LONG=8'h03,
               ERR_GAP_TIMEOUT=8'h04, ERR_TOTAL_TIMEOUT=8'h05, ERR_RESPONSE_OVERFLOW=8'h06;
    localparam integer GAP_BITS = GAP_TIMEOUT_CYCLES<=1 ? 1 : $clog2(GAP_TIMEOUT_CYCLES);
    localparam integer TOTAL_BITS = TOTAL_TIMEOUT_CYCLES<=1 ? 1 : $clog2(TOTAL_TIMEOUT_CYCLES);
    reg [1:0] state;
    reg request_armed;
    reg [9:0] byte_count;
    reg [GAP_BITS-1:0] gap_count;
    reg [TOTAL_BITS-1:0] total_count;
    wire [10:0] received_after = {1'b0,byte_count} + (reader_valid ? 11'd1 : 11'd0);
    assign sector_busy = state!=IDLE;

    task fail_read;
        input [7:0] code;
        begin
            sector_error<=code; sector_done<=1; sector_valid<=0;
            state<=FAULT;
        end
    endtask

    always @(posedge clk or posedge rst) begin
        if(rst)begin
            state<=IDLE;request_armed<=1;byte_count<=0;gap_count<=0;total_count<=0;
            sector_valid<=0;sector_byte<=0;sector_byte_index<=0;
            sector_done<=0;sector_error<=0;reader_req<=0;reader_lba<=0;
        end else begin
            sector_valid<=0;sector_done<=0;reader_req<=0;
            if(!sector_req)request_armed<=1;
            else request_armed<=0; // Consume every assertion, including while busy.
            case(state)
                IDLE: if(sector_req && request_armed)begin
                    sector_error<=0;byte_count<=0;gap_count<=0;total_count<=0;
                    reader_lba<=sector_lba;
                    if(!sd_ready)fail_read(ERR_NOT_READY);
                    else begin reader_req<=1;state<=ACTIVE;end
                end
                ACTIVE: begin
                    if(reader_valid && byte_count<512)begin
                        sector_valid<=1;sector_byte<=reader_byte;
                        sector_byte_index<=byte_count[8:0];byte_count<=byte_count+1'b1;
                    end
                    if(reader_valid)gap_count<=0;
                    else if(gap_count<GAP_TIMEOUT_CYCLES-1)gap_count<=gap_count+1'b1;
                    if(total_count<TOTAL_TIMEOUT_CYCLES-1)total_count<=total_count+1'b1;

                    // Completion wins over the timeout at the same clock edge.
                    // Count the final byte even when valid and done coincide.
                    if(reader_fault)fail_read(ERR_RESPONSE_OVERFLOW);
                    else if(reader_valid && byte_count>=512)fail_read(ERR_LONG);
                    else if(reader_done)begin
                        if(received_after!=512)fail_read(ERR_SHORT);
                        else begin sector_done<=1;state<=FINISH;end
                    end else if(total_count==TOTAL_TIMEOUT_CYCLES-1)fail_read(ERR_TOTAL_TIMEOUT);
                    else if(!reader_valid && gap_count==GAP_TIMEOUT_CYCLES-1)fail_read(ERR_GAP_TIMEOUT);
                end
                FINISH: state<=IDLE;
                FAULT: state<=FAULT;
                default: state<=FAULT;
            endcase
        end
    end
endmodule
