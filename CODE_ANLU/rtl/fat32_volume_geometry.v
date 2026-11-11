// FAT32 volume metadata only. The loader owns sector scheduling; these
// strobes preserve its staged arithmetic so no long combinational mount path
// is added. All metadata is frozen after mounting until the shared reset.
module fat32_volume_geometry (
    input wire clk,rst,capture,is_mbr,
    input wire [8:0] byte_index,input wire [7:0] sector_byte,
    input wire select_partition,prepare,layout_step,count_step,commit,
    output reg [31:0] partition_lba,root_cluster,fat_lba,data_lba,max_cluster,
    output reg [7:0] sectors_per_cluster,
    output reg [3:0] cluster_shift,
    output reg [32:0] volume_end,fat_end,
    output wire signature_ok,direct_bpb,partition_ok,bpb_bad,layout_bad,geometry_bad
);
    reg [31:0] volume_lba,fat_sectors,total_sectors,partition_sectors,data_sectors,cluster_count;
    reg [7:0] partition_type,fat_count;
    reg [15:0] bytes_per_sector,reserved_sectors,signature;
    reg [15:0] root_entries,total_sectors16,fat_sectors16,fat_flags,fs_version;
    reg partitioned;
    reg [33:0] overhead_sectors;
    reg [32:0] fat_base_wide;
    wire [32:0] partition_end={1'b0,partition_lba}+{1'b0,partition_sectors};
    wire valid_cluster_size=sectors_per_cluster==1 || sectors_per_cluster==2 ||
        sectors_per_cluster==4 || sectors_per_cluster==8 || sectors_per_cluster==16 ||
        sectors_per_cluster==32 || sectors_per_cluster==64 || sectors_per_cluster==128;
    assign signature_ok=signature==16'haa55;
    assign direct_bpb=bytes_per_sector==512 && valid_cluster_size && root_cluster>=2;
    assign partition_ok=partition_lba!=0 && partition_sectors!=0 &&
        partition_end<=33'h100000000 && (partition_type==8'h0b || partition_type==8'h0c ||
        partition_type==8'h1b || partition_type==8'h1c);
    assign bpb_bad=!signature_ok || bytes_per_sector!=512 || !valid_cluster_size ||
        reserved_sectors==0 || fat_sectors==0 || (fat_count!=1 && fat_count!=2) || root_cluster<2 ||
        root_entries!=0 || total_sectors16!=0 || fat_sectors16!=0 || total_sectors==0 ||
        fs_version!=0 || (fat_flags[7] && {4'b0,fat_flags[3:0]}>=fat_count);
    assign layout_bad=overhead_sectors>={2'b0,total_sectors} || volume_end>33'h100000000 ||
        (partitioned && total_sectors>partition_sectors);
    assign geometry_bad=cluster_count<65525 || cluster_count>32'h0fffffee ||
        ({7'd0,cluster_count}+39'd2)>{fat_sectors,7'b0} || root_cluster>cluster_count+32'd1;

    always @(posedge clk or posedge rst)begin
        if(rst)begin
            volume_lba<=0;partition_lba<=0;partition_type<=0;fat_lba<=0;data_lba<=0;
            sectors_per_cluster<=0;fat_count<=0;cluster_shift<=0;bytes_per_sector<=0;
            reserved_sectors<=0;signature<=0;fat_sectors<=0;root_cluster<=0;
            total_sectors<=0;partition_sectors<=0;data_sectors<=0;cluster_count<=0;
            max_cluster<=0;root_entries<=0;total_sectors16<=0;fat_sectors16<=0;
            fat_flags<=0;fs_version<=0;partitioned<=0;overhead_sectors<=0;
            volume_end<=0;fat_base_wide<=0;fat_end<=0;
        end else begin
            if(capture)begin
            case (byte_index)
                11: bytes_per_sector[7:0]<=sector_byte;
                12: bytes_per_sector[15:8]<=sector_byte;
                13: sectors_per_cluster<=sector_byte;
                14: reserved_sectors[7:0]<=sector_byte;
                15: reserved_sectors[15:8]<=sector_byte;
                16: fat_count<=sector_byte;
                17: root_entries[7:0]<=sector_byte;
                18: root_entries[15:8]<=sector_byte;
                19: total_sectors16[7:0]<=sector_byte;
                20: total_sectors16[15:8]<=sector_byte;
                22: fat_sectors16[7:0]<=sector_byte;
                23: fat_sectors16[15:8]<=sector_byte;
                32: total_sectors[7:0]<=sector_byte;
                33: total_sectors[15:8]<=sector_byte;
                34: total_sectors[23:16]<=sector_byte;
                35: total_sectors[31:24]<=sector_byte;
                40: fat_flags[7:0]<=sector_byte;
                41: fat_flags[15:8]<=sector_byte;
                42: fs_version[7:0]<=sector_byte;
                43: fs_version[15:8]<=sector_byte;
                36: fat_sectors[7:0]<=sector_byte;
                37: fat_sectors[15:8]<=sector_byte;
                38: fat_sectors[23:16]<=sector_byte;
                39: fat_sectors[31:24]<=sector_byte;
                44: root_cluster[7:0]<=sector_byte;
                45: root_cluster[15:8]<=sector_byte;
                46: root_cluster[23:16]<=sector_byte;
                47: root_cluster[31:24]<=sector_byte;
                450: if(is_mbr) partition_type<=sector_byte;
                454: if(is_mbr) partition_lba[7:0]<=sector_byte;
                455: if(is_mbr) partition_lba[15:8]<=sector_byte;
                456: if(is_mbr) partition_lba[23:16]<=sector_byte;
                457: if(is_mbr) partition_lba[31:24]<=sector_byte;
                458: if(is_mbr) partition_sectors[7:0]<=sector_byte;
                459: if(is_mbr) partition_sectors[15:8]<=sector_byte;
                460: if(is_mbr) partition_sectors[23:16]<=sector_byte;
                461: if(is_mbr) partition_sectors[31:24]<=sector_byte;
                510: signature[7:0]<=sector_byte;
                511: signature[15:8]<=sector_byte;
            endcase
            end
            if(select_partition)begin partitioned<=1;volume_lba<=partition_lba;end
            if(prepare)begin
                overhead_sectors<={18'd0,reserved_sectors} +
                    (fat_count==2 ? {1'b0,fat_sectors,1'b0} : {2'b0,fat_sectors});
                fat_base_wide<={1'b0,volume_lba}+{17'd0,reserved_sectors};
                volume_end<={1'b0,volume_lba}+{1'b0,total_sectors};
                case(sectors_per_cluster)
                    1:cluster_shift<=0;2:cluster_shift<=1;4:cluster_shift<=2;
                    8:cluster_shift<=3;16:cluster_shift<=4;32:cluster_shift<=5;
                    64:cluster_shift<=6;128:cluster_shift<=7;
                endcase
            end
            if(layout_step)begin
                data_sectors<=total_sectors-overhead_sectors[31:0];
                data_lba<=volume_lba+overhead_sectors[31:0];
                fat_lba<=fat_base_wide[31:0] +
                    ((fat_flags[7] && fat_flags[0]) ? fat_sectors : 32'd0);
                fat_end<=fat_base_wide +
                    ((fat_flags[7] && fat_flags[0]) ? {fat_sectors,1'b0} : {1'b0,fat_sectors});
            end
            if(count_step)cluster_count<=data_sectors>>cluster_shift;
            if(commit)max_cluster<=cluster_count+32'd1;
        end
    end
endmodule
