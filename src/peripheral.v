/*
 * Copyright (c) 2025 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Change the name of this module to something that reflects its functionality and includes your name for uniqueness
// For example tqvp_yourname_spi for an SPI peripheral.
// Then edit tt_wrapper.v line 41 and change tqvp_example to your chosen module name.
module tqvp_tiny_sprite_engine (
    input  wire        clk,          // Clock - the TinyQV project clock is normally set to 64MHz.
    input  wire        rst_n,        // Reset_n - low to reset.

    input  wire  [7:0] ui_in,        // The input PMOD, always available.  Note that ui_in[7] is normally used for UART RX.
                                     // The inputs are synchronized to the clock, note this will introduce 2 cycles of delay on the inputs.

    output wire  [7:0] uo_out,       // The output PMOD.  Each wire is only connected if this peripheral is selected.
                                     // Note that uo_out[0] is normally used for UART TX.

    input  wire  [5:0] address,      // Address within this peripheral's address space
    input  wire [31:0] data_in,      // Data in to the peripheral, bottom 8, 16 or all 32 bits are valid on write.

    // Data read and write requests from the TinyQV core.
    input  wire  [1:0] data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input  wire  [1:0] data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits

    output wire [31:0] data_out,     // Data out from the peripheral, bottom 8, 16 or all 32 bits are valid on read when data_ready is high.
    output wire        data_ready,

    output wire        user_interrupt  // Dedicated interrupt request for this peripheral
);


    reg [7:0] spx_a, spy_a, spx_b, spy_b, spx_c, spy_c, spx_rc, spy_rc;
    reg [1:0] mode ;
    reg [2:0] priority_order ;
    reg [2:0] sym_id ;
    reg [7:0] repeat_x_coord ;

    reg [11:0]sp_patA [11:0] ;
    reg [11:0]sp_patB [11:0] ;
    reg [11:0]sp_patC [11:0] ;

    
    wire [29:0] wr_en ;

    assign wr_en[0]= (address == 6'h0) && (data_write_n == 2'b01);
    assign wr_en[1]= (address == 6'h2) && (data_write_n == 2'b10);
    assign wr_en[2]= (address == 6'h4) && (data_write_n == 2'b10);
    assign wr_en[3]= (address == 6'h6) && (data_write_n == 2'b10);
    assign wr_en[4]= (address == 6'h8) && (data_write_n == 2'b10);  
    assign wr_en[5]= (address == 6'hA) && (data_write_n == 2'b10);
    assign wr_en[6]= (address == 6'hC) && (data_write_n == 2'b10);
    assign wr_en[7]= (address == 6'hE) && (data_write_n == 2'b10);      
    assign wr_en[8]= (address == 6'h10) && (data_write_n == 2'b10);
    assign wr_en[9]= (address == 6'h12) && (data_write_n == 2'b10);  
    assign wr_en[10]= (address == 6'h14) && (data_write_n == 2'b10);
    assign wr_en[11]= (address == 6'h16) && (data_write_n == 2'b10);
    assign wr_en[12]= (address == 6'h18) && (data_write_n == 2'b10);  
    assign wr_en[13]= (address == 6'h1A) && (data_write_n == 2'b10);
    assign wr_en[14]= (address == 6'h1C) && (data_write_n == 2'b10);
    assign wr_en[15]= (address == 6'h1E) && (data_write_n == 2'b10);
    



//   Modes 
//   | 00 | -> sprite patterns load 
//   | 01 | -> sprite co-ord load
//   | 10 | -> sprite stream

//   Address Map
//   0x00 : {mode[1:0], sp_id[1:0], offset[3:0], sp_patrn[7:0]}
//   0x01 : {spx_a[7:0], spy_a[7:0]}
//   0x02 : {spx_b[7:0], spy_b[7:0]}
//   0x03 : {spx_c[7:0], spy_c[7:0]}
//   0x04 : {spx_d[7:0], spy_d[7:0]}

    always @(posedge clk) begin
        if (!rst_n) begin
            spx_a <= 0;
            spy_a <= 0;
            spx_b <= 0;
            spy_b <= 0;
            spx_c <= 0;
            spy_c <= 0;
            mode   <= 0;
            sp_a_pattern <= 0;
            sp_b_pattern <= 0;
            sp_c_pattern <= 0;
        end else begin

                if (wr_en[0]) {mode,sp_id,offset,repeat_x_coord} <= data_in[15:0];
                if (wr_en[1]) {spx_a,spy_a} <= data_in[15:0];
                if (wr_en[2]) {spx_b,spy_b} <= data_in[15:0];
                if (wr_en[3]) {spx_c,spy_c} <= data_in[15:0];
                if (wr_en[4]) {spx_d,spy_d} <= data_in[15:0];
                if (wr_en[5]) sp_pattern <= data_in[15:0];
            
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin


            sp_patD[0]  <= 16'h0000 ;
            sp_patD[1]  <= 16'h0000 ;
            sp_patD[2]  <= 16'h0000 ;
            sp_patD[3]  <= 16'h0000 ;
            sp_patD[4]  <= 16'h0000 ;
            sp_patD[5]  <= 16'h0000 ;
            sp_patD[6]  <= 16'h0000 ;
            sp_patD[7]  <= 16'h0000 ;
            sp_patD[8]  <= 16'h0000 ;
            sp_patD[9]  <= 16'h0000 ;
            sp_patD[10] <= 16'h0000 ;
            sp_patD[11] <= 16'h0000 ;
            sp_patD[12] <= 16'h0000 ;
            sp_patD[13] <= 16'h0000 ;
            sp_patD[14] <= 16'h0000 ;
            sp_patD[15] <= 16'h0000 ;
        end else begin
            if (mode == 2'b01) begin
                case (sp_id)
                    2'b00 : sp_patA[offset] <= sp_pattern ;
                    2'b01 : sp_patB[offset] <= sp_pattern ;
                    2'b10 : sp_patC[offset] <= sp_pattern ;
                    2'b11 : sp_patD[offset] <= sp_pattern ;
                endcase
            end 
        end
    end  

reg [1:0] ps, ns ;
localparam IDLE = 2'b00 ;
localparam SP_PAT_LOAD = 2'b01 ;
localparam SP_COORD_LOAD = 2'b10 ;
localparam SP_STREAM = 2'b11 ;

always @(posedge clk) begin
    if (!rst_n) begin
        ps <= IDLE ;
    end else begin
        ps <= ns ;
    end 
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        spx_a <= 0; spy_a <= 0;
        spx_b <= 0; spy_b <= 0;
        spx_c <= 0; spy_c <= 0;
        spx_d <= 0; spy_d <= 0;
        sp_id <= 0; offset <= 0;
        sp_pattern <= 0;
        mode <= 0;
    end else begin
        case (ps)
            IDLE: begin
                if (wr_en[0]) begin
                    {mode, sp_id, offset, sp_patrn} <= data_in[15:0];
                end
            end
            SP_PAT_LOAD: begin
                if (wr_en[5]) begin
                    sp_pattern <= data_in[15:0];
                    case (sp_id)
                        2'b00: sp_patA[offset] <= data_in[15:0];
                        2'b01: sp_patB[offset] <= data_in[15:0];
                        2'b10: sp_patC[offset] <= data_in[15:0];
                        2'b11: sp_patD[offset] <= data_in[15:0];
                    endcase
                end
            end
            SP_COORD_LOAD: begin
                if (wr_en[1]) {spx_a, spy_a} <= data_in[15:0];
                if (wr_en[2]) {spx_b, spy_b} <= data_in[15:0];
                if (wr_en[3]) {spx_c, spy_c} <= data_in[15:0];
                if (wr_en[4]) {spx_d, spy_d} <= data_in[15:0];
            end
            SP_STREAM: begin
                // You’ll need to implement streaming behavior here
            end
        endcase
    end
end





endmodule