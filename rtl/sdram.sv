
module sdram
(
   input             init,        // reset to initialize RAM
   input             clk,         // clock ~100MHz
                                  //
                                  // SDRAM_* - signals to the MT48LC16M16 chip                       //
   input       [1:0] wtbt,        // 16bit mode:  bit1 - write high byte, bit0 - write low byte,
                                  // 8bit mode:  2'b00 - use addr[0] to decide which byte to write
                                  // Ignored while reading.
                                  //
   input      [19:0] addr,        // 25 bit address for 8bit mode. addr[0] = 0 for 16bit mode for correct operations.
   output     [7:0] dout,        // data output to cpu
   input      [7:0] din,         // data input from cpu
   input             we,          // cpu requests write
   input             rd         // cpu requests read
);


reg [7:0] memory[1048575:0];


always @(posedge clk) begin
  if (rd) dout <= memory[addr];
  if (we) memory[addr] <= din;
end

endmodule
