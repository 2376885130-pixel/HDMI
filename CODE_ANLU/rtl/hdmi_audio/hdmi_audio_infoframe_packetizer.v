`timescale 1ns/1ps

module hdmi_audio_infoframe_packetizer (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         emit,
    output reg          packet_valid,
    input  wire         packet_ready,
    output wire [23:0]  packet_header,
    output wire [7:0]   packet_header_ecc,
    output wire [223:0] packet_body,
    output wire [31:0]  packet_body_ecc
);
    reg avi_pending;
    wire [7:0] ecc0, ecc1, ecc2, ecc3;

    // Low byte is HB0. Audio InfoFrame: type 0x84, version 1, length 10.
    assign packet_header = avi_pending ? 24'h0d0282 : 24'h0a0184;
    // PB0 checksum=0x70, PB1.CC=1 means two channels. Coding type,
    // sample frequency/size and channel allocation refer to the stream.
    // AVI v2: RGB, 4:3 picture aspect, VIC 1 (640x480), checksum 0x5e.
    assign packet_body = avi_pending ? {184'd0,8'h01,8'h00,8'h10,8'h00,8'h5e} : {208'd0,8'h01,8'h70};

    hdmi_bch8 #(.DATA_BYTES(3)) u_header_bch (
        .data(packet_header), .ecc(packet_header_ecc)
    );
    hdmi_bch8 #(.DATA_BYTES(7)) u_body0_bch (
        .data(packet_body[55:0]), .ecc(ecc0)
    );
    hdmi_bch8 #(.DATA_BYTES(7)) u_body1_bch (
        .data(packet_body[111:56]), .ecc(ecc1)
    );
    hdmi_bch8 #(.DATA_BYTES(7)) u_body2_bch (
        .data(packet_body[167:112]), .ecc(ecc2)
    );
    hdmi_bch8 #(.DATA_BYTES(7)) u_body3_bch (
        .data(packet_body[223:168]), .ecc(ecc3)
    );
    assign packet_body_ecc = {ecc3, ecc2, ecc1, ecc0};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)begin packet_valid<=0;avi_pending<=0;end
        else if(packet_valid && packet_ready)begin
            if(!avi_pending)begin avi_pending<=1;packet_valid<=1;end
            else begin avi_pending<=0;packet_valid<=0;end
        end else if(!packet_valid && emit)begin packet_valid<=1;avi_pending<=0;end
    end
endmodule
