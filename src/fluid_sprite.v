module fluid_sprite #(
    parameter MAX_SPRITES = 8   
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        video_active,
    input  wire [9:0]  pix_x,
    input  wire [9:0]  pix_y,
    input  wire        vsync,
    input  wire  [5:0] address,
    input  wire [31:0] data_in,
    input  wire  [1:0] data_write_n,
    input  wire  [1:0] data_read_n,
    output reg  [31:0] data_out,
    output reg         data_ready,
    output wire        user_interrupt,
    output wire        sprite_pixel_on
);

    // 8-bit-wide, 63 usable bytes - last addr reserved.
    reg [7:0] sprite_ram [0:63];

    // Host interface (identical from earlier)
    always @(posedge clk) begin
        if (!rst_n) begin
            // Optionally clear RAM here;
        end else if (data_write_n != 2'b11 && address < 63) begin
            if      (data_write_n == 2'b00) sprite_ram[address]     <= data_in[7:0];
            else if (data_write_n == 2'b01 && (address < 62))
                {sprite_ram[address+1], sprite_ram[address]}         <= data_in[15:0];
            else if (data_write_n == 2'b10 && (address < 60))
                {sprite_ram[address+3], sprite_ram[address+2], sprite_ram[address+1], sprite_ram[address]} <= data_in[31:0];
        end
    end

    always @* begin
        data_ready = (data_read_n != 2'b11);
        data_out = 32'b0;
        if (data_read_n == 2'b00) data_out[7:0]   = sprite_ram[address];
        else if (data_read_n == 2'b01) data_out[15:0] = {sprite_ram[address+1], sprite_ram[address]};
        else if (data_read_n == 2'b10) data_out[31:0] = {sprite_ram[address+3], sprite_ram[address+2], sprite_ram[address+1], sprite_ram[address]};
    end

    assign user_interrupt = 1'b0;

    // Object unpack Macros
    localparam OBJ_BYTES = 4;
    integer spr_idx;
    reg pix_hit;

    always @ (*) begin
        pix_hit = 1'b0;
        for (spr_idx = 0; spr_idx < MAX_SPRITES; spr_idx = spr_idx + 1) begin : SPRITES
            reg [7:0] x, y, bitmap_offset, size_byte;
            reg [3:0] width, height;
            reg [3:0] spr_x, spr_y;
            integer bit_offset, byte_addr, bit_in_byte;
            reg [7:0] bmp_byte;
            reg bmp_bit;

            x = sprite_ram[spr_idx*OBJ_BYTES + 0];
            y = sprite_ram[spr_idx*OBJ_BYTES + 1];
            bitmap_offset = sprite_ram[spr_idx*OBJ_BYTES + 2];
            size_byte = sprite_ram[spr_idx*OBJ_BYTES + 3];
            width  = size_byte[7:4] + 1;
            height = size_byte[3:0] + 1;

            if (    video_active
                && (pix_x >= x) && (pix_x < x + width)
                && (pix_y >= y) && (pix_y < y + height)) begin
                spr_x = pix_x - x;
                spr_y = pix_y - y;
                bit_offset = spr_y * width + spr_x;
                byte_addr = bitmap_offset + (bit_offset >> 3); // each byte = 8 bits
                bit_in_byte = bit_offset % 8;
                if (byte_addr < 63) begin
                    bmp_byte = sprite_ram[byte_addr];
                    bmp_bit = bmp_byte[bit_in_byte];
                    pix_hit = pix_hit | bmp_bit;
                end
            end
        end
    end

    assign sprite_pixel_on = pix_hit;

endmodule
