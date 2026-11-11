// Root-directory entry decoder and validated BMP catalog. Candidate header
// validation belongs to the BMP loader. Re-read/resume allows probing each
// candidate without storing an entire directory sector, including fragmented
// root directories. Outputs and catalog are valid only after the relevant event.
module fat32_directory_catalog #(
    parameter integer SELECT_BY_NAME=0,AUTO_SCAN=0
)(
    input wire clk,rst,byte_valid,
    input wire [8:0] byte_index,input wire [7:0] sector_byte,
    input wire [31:0] sector_lba,max_cluster,input wire [4:0] image_index,
    input wire probe_begin,probe_done,header_ok,resume_clear,scan_finish,select_file,load_ack,
    output reg found_file,directory_end,
    output reg [31:0] first_cluster,file_size,directory_lba,
    output reg [5:0] image_total,output reg catalog_valid,
    output reg [87:0] image_name,output wire [31:0] selected_cluster
);
    reg entry_live,extension_b,extension_m,extension_p,name_matches;
    reg [7:0] entry_attr;
    reg [31:0] entry_cluster,entry_size;
    // Synchronous BRAM metadata saves scarce MSlices. The loader inserts a
    // SELECT_PREFETCH cycle before select_file, including the 31 -> 32 case.
    (* ram_style="bram" *) reg [151:0] catalog[0:31];
    reg [151:0] selected_metadata;
    reg [87:0] entry_name,candidate_name;
    reg [8:0] resume_byte;
    reg resume_valid;
    wire entry_after_resume=!resume_valid || byte_index>resume_byte;
    wire [4:0] selected_index=image_index;
    wire theme_name=entry_name[87:80]=="T" && entry_name[79:72]>="1" && entry_name[79:72]<="4" &&
      entry_name[71:64]=="P" && entry_name[63:56]=="0" && entry_name[55:48]>="1" && entry_name[55:48]<="8" && entry_name[47:24]==24'h202020;
    wire [1:0] candidate_theme=candidate_name[79:72]-8'h31;
    wire [2:0] candidate_picture=candidate_name[55:48]-8'h31;
    wire [4:0] candidate_slot={candidate_theme,candidate_picture};
    reg [31:0] seen;
    assign selected_cluster=selected_metadata[151:120];
    always @(posedge clk)begin
        selected_metadata<=catalog[selected_index];
        if(!rst && probe_done && header_ok)
            catalog[candidate_slot]<={first_cluster,file_size,candidate_name};
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            seen<=0;found_file<=0;directory_end<=0;first_cluster<=0;file_size<=0;directory_lba<=0;
            image_total<=0;catalog_valid<=0;image_name<={11{8'h20}};
            entry_name<=0;candidate_name<=0;resume_byte<=0;resume_valid<=0;
            name_matches<=0;entry_live<=0;extension_b<=0;extension_m<=0;extension_p<=0;
            entry_attr<=0;entry_cluster<=0;entry_size<=0;
        end else begin
            if(byte_valid)begin
            // FAT short names arrive in order: shift eleven bytes into the
            // same big-endian name, avoiding a variable-position write mux.
            if(byte_index[4:0]<=10)entry_name<={entry_name[79:0],sector_byte};
            case (byte_index[4:0])
                0: begin
                    name_matches<=sector_byte=="P";
                    entry_live<=sector_byte!=0 && sector_byte!=8'he5;
                    if (sector_byte==0 && entry_after_resume) directory_end<=1;
                    entry_cluster<=0; entry_size<=0;
                end
                1: name_matches<=name_matches && sector_byte=="I";
                2: name_matches<=name_matches && sector_byte=="C";
                3: name_matches<=name_matches && sector_byte=="0";
                4: name_matches<=name_matches && sector_byte==(8'h31+{3'b0,image_index});
                5,6,7: name_matches<=name_matches && sector_byte==" ";
                8: extension_b<=sector_byte=="B" || sector_byte=="b";
                9: extension_m<=sector_byte=="M" || sector_byte=="m";
                10: extension_p<=sector_byte=="P" || sector_byte=="p";
                11: entry_attr<=sector_byte;
                20: entry_cluster[23:16]<=sector_byte;
                21: entry_cluster[31:24]<=sector_byte;
                26: entry_cluster[7:0]<=sector_byte;
                27: entry_cluster[15:8]<=sector_byte;
                28: entry_size[7:0]<=sector_byte;
                29: entry_size[15:8]<=sector_byte;
                30: entry_size[23:16]<=sector_byte;
                31: if (!found_file && !directory_end && entry_live &&
                     (!AUTO_SCAN || entry_after_resume) &&
                     extension_b && extension_m && extension_p && theme_name &&
                     (AUTO_SCAN || !SELECT_BY_NAME || name_matches) &&
                     (entry_attr&8'h18)==0 && entry_cluster>=2 && entry_cluster<=max_cluster &&
                     {sector_byte,entry_size[23:0]}>=58) begin
                    found_file<=1; first_cluster<=entry_cluster;candidate_name<=entry_name;
                    file_size<={sector_byte,entry_size[23:0]};
                    if(AUTO_SCAN) begin resume_byte<=byte_index;resume_valid<=1;directory_lba<=sector_lba;end
                end
            endcase
            end
            if(probe_begin)directory_end<=0;
            if(probe_done)begin
                if(header_ok)begin
                    if(!seen[candidate_slot])image_total<=image_total+1'b1;seen[candidate_slot]<=1;
                end
                found_file<=0;directory_end<=0;
            end
            if(resume_clear)resume_valid<=0;
            if(scan_finish)catalog_valid<=1;
            if(select_file)begin
                first_cluster<=selected_metadata[151:120];
                file_size<=selected_metadata[119:88];image_name<=selected_metadata[87:0];
                found_file<=1;
            end
            if(load_ack && !AUTO_SCAN)image_name<=candidate_name;
        end
    end
endmodule
