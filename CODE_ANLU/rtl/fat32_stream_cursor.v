// Shared directory/file FAT-chain cursor and file-stream byte offset.
// The loader schedules physical sector requests and decides where BMP payload
// ends; this module owns cluster traversal, FAT entry assembly and stream
// position. Header probes reset only the byte offset, preserving the directory
// cursor. A catalog selection starts a fresh file chain.
module fat32_stream_cursor (
    input wire clk,rst,mount,load_file,clear_hops,probe_begin,step_sector,step_chain,
    input wire data_valid,fat_valid,input wire [8:0] byte_index,
    input wire [7:0] sector_byte,input wire [31:0] root_cluster,file_cluster,max_cluster,
    output reg [31:0] current_cluster,next_cluster,file_position,
    output reg [7:0] cluster_sector,output wire chain_end,chain_bad
);
    reg [15:0] chain_hops;
    wire [8:0] fat_byte_offset={current_cluster[6:0],2'b00};
    assign chain_end=next_cluster>=32'h0ffffff8;
    assign chain_bad=next_cluster<2 || next_cluster>max_cluster || next_cluster>=32'h0ffffff0 ||
        next_cluster==current_cluster || chain_hops==65535;
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            current_cluster<=0;next_cluster<=0;file_position<=0;cluster_sector<=0;chain_hops<=0;
        end else begin
            if(data_valid)file_position<=file_position+1'b1;
            if(fat_valid)begin
                if(byte_index==fat_byte_offset)next_cluster[7:0]<=sector_byte;
                if(byte_index==fat_byte_offset+1)next_cluster[15:8]<=sector_byte;
                if(byte_index==fat_byte_offset+2)next_cluster[23:16]<=sector_byte;
                if(byte_index==fat_byte_offset+3)next_cluster[31:24]<={4'b0,sector_byte[3:0]};
            end
            if(mount)begin current_cluster<=root_cluster;cluster_sector<=0;end
            if(probe_begin)file_position<=0;
            if(load_file)begin current_cluster<=file_cluster;cluster_sector<=0;file_position<=0;end
            if(clear_hops)chain_hops<=0;
            if(step_sector)cluster_sector<=cluster_sector+1'b1;
            if(step_chain)begin
                current_cluster<=next_cluster;cluster_sector<=0;chain_hops<=chain_hops+1'b1;
            end
        end
    end
endmodule
