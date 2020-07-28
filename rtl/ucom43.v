/* verilator lint_off UNUSED */
/* verilator lint_off CASEINCOMPLETE */

module ucom43(
  input clk,
  input reset,
  input _INT,

  // ports
  input [3:0] prtAI,
  input [3:0] prtBI,
  input [3:0] prtCI,
  input [3:0] prtDI,
  output [3:0] prtC,
  output [3:0] prtD,
  output [3:0] prtE,
  output [3:0] prtF,
  output [3:0] prtG,
  output [3:0] prtH,
  output [2:0] prtI,

  input clk_sys,
  input rom_init,
  input [7:0] rom_init_data,
  input [11:0] rom_init_addr
);

// input ports
wire [3:0] i_ports[3:0];

assign i_ports[0] = prtAI;
assign i_ports[1] = prtBI;
assign i_ports[2] = prtCI;
assign i_ports[3] = prtDI;


// output ports (AB unconnected)CDEFGHI
reg [3:0] o_ports[8:0];

assign prtC = o_ports[2];
assign prtD = o_ports[3];
assign prtE = o_ports[4];
assign prtF = o_ports[5];
assign prtG = o_ports[6];
assign prtH = o_ports[7];
assign prtI = o_ports[8][2:0];

parameter
  PORT_C = 4'd2,
  PORT_D = 4'd3,
  PORT_E = 4'd4;

// FSM states
parameter
  FTC = 2'b00, // fetch/execute
  PRM = 2'b01, // fetch parameter
  SKP = 2'b10, // skip
  WRI = 2'b11; // write ram

reg [1:0] clk_cnt;
always @(posedge clk)
  clk_cnt <= clk_cnt + 2'b1;

wire clk_mcu = clk_cnt == 2'b0;

reg  [2:0]  pcf        ; // pc field register
reg  [7:0]  pcc        ; // pc counter
reg  [2:0]  dph        ; // data pointer high
reg  [3:0]  dpl        ; // data pointer low
reg  [7:0]  rdat       ; // rom data
reg         c     , cs ; // carry & carry save
reg  [3:0]  acc        ; // accumulator
reg  [1:0]  state      ; // fsm state
reg  [7:0]  opc        ; // hold ram data (opcode) during PRM state
reg  [10:0] stack [2:0]; // stack
reg  [1:0]  sp         ; // stack pointer
reg  [5:0]  bcount     ; // timer binary counter
reg  [5:0]  pcount     ; // timer polynomial counter
reg         tm         ; // TM F/F timer flag
reg         irq        ; // interrupt request
reg         ien        ; // interrupt enable
wire [6:0]  dp         ; // data pointer
wire [10:0] pc         ; // pc
reg  [3:0]  mask       ; // bit mask

assign dp = { dph, dpl };
assign pc = { pcf, pcc };

// ROM
reg [7:0] rom[2047:0];

always @(posedge clk_sys)
  if (rom_init)
    rom[rom_init_addr] <= rom_init_data;

always @(posedge clk)
  rdat <= rom[pc];

// timer
always @(posedge clk) begin
  if (clk_mcu) begin
	  if (opc == 8'b0001_0100 && state == PRM) begin // stm cycle #2
      pcount <= 6'b0;
      bcount <= rdat[5:0];
      tm <= 1'b0;
	  end
	  else if (~tm) begin
      if (pcount == 6'b111111) begin
        if (bcount == 6'b0) tm <= 1'b1; // stop
        bcount <= bcount - 6'b1;
      end
      pcount <= pcount + 6'b1;
	  end
  end
end

// flags & work registers
reg [3:0] wr[6:0];

parameter
  F_REG = 7'h79,
  Z_REG = 7'h7a,
  W_REG = 7'h7b,
  S_REG = 7'h7c,
  R_REG = 7'h7d,
  Y_REG = 7'h7e,
  X_REG = 7'h7f;

// direct read access to registers
wire [3:0] F, Z, W, S, R, Y, X;
assign F = wr[0];
assign Z = wr[1];
assign W = wr[2];
assign S = wr[3];
assign R = wr[4];
assign Y = wr[5];
assign X = wr[6];

// RAM
reg  [3:0] ram  [95:0]; // 96 x 4-bit
reg  [3:0] mdat       ; // memory data
reg  [3:0] din        ; // ram data in
reg  [6:0] waddr      ; // ram write address
reg        we         ; // write enable, active low
wire [6:0] daddr      ; // decoded ram write address
wire       sel        ;

// ram address decoder
assign sel = waddr < 7'h79 ? 1'b0 : 1'b1;
assign daddr = waddr[6] == 1'b1 ? (waddr & 7'b1011111) : waddr;

always @(posedge clk)
  mdat <= dp < 7'h79 ? ram[dp[6] == 1'b1 ? dp & 7'b1011111 : dp] : wr[dp[2:0]-1];

// write ram & registers
always @(posedge clk)
  if (~we) begin
    if (~sel) ram[daddr] <= din;
    else wr[daddr[2:0]-1] <= din;
  end

// ALU
reg [2:0] alu_op;
reg [3:0] alu_a;
reg [3:0] alu_b;
reg [3:0] alu_r;
reg alu_c;
always @* begin
  alu_c = 1'b0;
  alu_r = 4'b0;
  case (alu_op)
    0: { alu_c, alu_r } = alu_a + alu_b;
    1: { alu_c, alu_r } = alu_a + alu_b + { 3'b0, c };
    2: { alu_c, alu_r } = alu_a + 4'b1;
    3: { alu_c, alu_r } = alu_a - 4'b1;
    4: alu_r = alu_a ^ alu_b;
    5: alu_c = (alu_a & mask) != 0 ? 1'b1 : 1'b0;
    6: alu_r = alu_a + 4'd6;
    7: alu_r = alu_a + 4'd10;
  endcase
end

// alu_a
always @*
  casez (rdat)
    8'b0001_11?1, // inm dem
    8'b0101_10??: alu_a = mdat; // tmb
    8'b0001_0000, // cma
    8'b0000_11?1, // inc dec
    8'b000?_100?, // ad ads adc exl
    8'b0000_0110, // daa
    8'b0000_1010, // das
    8'b0010_01??: alu_a = acc; // tab
    8'b0001_0001: alu_a = ~acc; // cia
    8'b001?_11??, // xmd xmi
    8'b00?1_0011: alu_a = dpl; // ded ind
    8'b0010_00??, // fbf
    8'b0101_11??: alu_a = F; // fbt
    8'b0101_00??: alu_a = i_ports[dpl[1:0]]; // tpb
    8'b0101_01??: alu_a = prtAI; // tpa
    default: alu_a = 4'b0;
  endcase

// alu_b
always @*
  casez (rdat)
    8'b0001_0000: alu_b = 4'hf; // cma
    8'b000?_100?: alu_b = mdat; // ad ads adc exl
    default: alu_b = 4'b0;
  endcase

// alu_op
// 0: add, 1: adc, 2: inc, 3: dec
// 4: xor, 5: bit, 6: daa, 7: das
always @*
  casez (rdat)
    8'b0000_1000: alu_op = 3'd0; // ad
    8'b000?_1001: alu_op = 3'd1; // ads adc
    8'b0011_11??, // xmi
    8'b0011_0011, // ind
    8'b0001_0001, // cia
    8'b000?_1101: alu_op = 3'd2; // inm
    8'b0010_11??, // xmd
    8'b0001_0011, // ded
    8'b000?_1111: alu_op = 3'd3; // dec dem
    8'b0001_?000: alu_op = 3'd4; // cma exl
    8'b0101_00??, // tpb
    8'b0101_01??, // tpa
    8'b0101_1???, // tmb fbt
    8'b0010_0???: alu_op = 3'd5; // tab fbf
    8'b0000_0110: alu_op = 3'd6; // daa
    8'b0000_1010: alu_op = 3'd7; // das
    default: alu_op = 3'd0;
  endcase

// ram write address
always @(posedge clk)
  if (clk_mcu)
    if (state == FTC)
      casez (rdat)
        8'b011?_11??: waddr <= F_REG; // sfb rfb
        8'b0100_?010: waddr <= Z_REG; // xaz taz
        8'b0100_?011: waddr <= W_REG; // xaw taw
        8'b0100_1100: waddr <= S_REG; // xls
        8'b0100_1101: waddr <= R_REG; // xhr
        8'b0100_?110: waddr <= Y_REG; // xly tly
        8'b0100_?111: waddr <= X_REG; // xhx thx
        default: waddr <= dp;
      endcase


// ram we
always @(posedge clk) begin
  we <= 1'b1;
  if (clk_mcu)
    case (state)
      FTC:
      casez (rdat)
        8'b0001_11?1, // inm dem
        8'b0000_0010, // s
        8'b0010_1???, // xm xmd
        8'b0011_11??, // xmi
        8'b0100_??1?, // 8 T&X (ZWYX)
        8'b0100_110?, // xhr xls
        8'b011?_1???: we <= 1'b0; // smb rmb sfb rfb
        default: we <= 1'b1;
      endcase
    endcase
end

// ram din
always @(posedge clk)
  if (clk_mcu)
    if (state == FTC)
      casez	(rdat)
        8'b0001_1101, // inm
        8'b0001_1111: din <= alu_r; // dem
        8'b0000_0010, // s
        8'b0010_10??, // xm
        8'b001?_11??, // xmi xmd
        8'b0100_101?, // xaz xaw
        8'b0100_001?: din <= acc; // taz taw
        8'b0100_?111, // xhx thx
        8'b0100_1101: din <= { 1'b0, dph }; // xhr
        8'b0100_?110, // xly tly
        8'b0100_1100: din <= dpl; // xls
        8'b0111_10??: din <= mdat | mask; // smb
        8'b0111_11??: din <= F | mask; // sfb
        8'b0110_10??: din <= mdat & ~mask; // rmb
        8'b0110_11??: din <= F & ~mask; // rfb
        default: din <= 4'b0;
      endcase

// dph
always @(posedge clk)
  if (clk_mcu)
    case (state)
      PRM:
        if (opc == 8'b0001_0101) // ldi
          dph <= rdat[6:4];
      FTC:
        casez (rdat)
          8'b001?_1???: dph[1:0] <= dph[1:0] ^ rdat[1:0]; // l lm x xm xd xmd xi xmi
          8'b1000_????: dph <= 0; // ldz
          8'b0100_1111: dph <= X[2:0]; // xhx
          8'b0100_1101: dph <= R[2:0]; // xhr
        endcase
    endcase

// dpl
always @(posedge clk)
  if (clk_mcu)
    case (state)
      PRM:
        if (opc == 8'b0001_0101) // ldi
          dpl <= rdat[3:0];
      FTC:
        casez (rdat)
          8'b001?_11??, // xd xmd xi xmi
          8'b00?1_0011: dpl <= alu_r; // ded ind
          8'b1000_????: dpl <= rdat[3:0]; // ldz
          8'b0100_1110: dpl <= Y; // xly
          8'b0000_0111: dpl <= acc; // tal
          8'b0100_1100: dpl <= S; // xls
        endcase
    endcase


// accumulator, carry & carry save
always @(posedge clk)
  if (clk_mcu)
    case (state)
      FTC:
        casez (rdat)
          8'b0000_1011: c <= 0; // clc
          8'b0001_1011: c <= 1; // stc
          8'b0001_0000, // cma
          8'b0001_0001, // cia
          8'b0000_11?1, // inc dec
          8'b0000_0110, // daa
          8'b0000_1010, // das
          8'b0000_1000, // ad
          8'b0001_1000: acc <= alu_r; // exl
          8'b0001_1010: { c, cs } <= { cs, c }; // xc
          8'b0011_0000: { acc, c } <= { c, acc }; // rar
          8'b000?_1001: { c, acc } <= { alu_c, alu_r }; // ads adc
          8'b1001_????: // cla & li
            if (opc[7:4] != rdat[7:4]) // skip consecutive
              acc <= rdat[3:0];
          8'b0011_10??, // l lm
          8'b0010_10??, // x xm
          8'b0010_11??, // xd xmd
          8'b0011_11??: acc <= mdat; // xi xmi
          8'b0001_0010: acc <= dpl; // tla
          8'b0100_1010: acc <= Z; // xaz
          8'b0100_1011: acc <= W; // xaw
          8'b0100_0000: acc <= prtAI; // ia
          8'b0011_0010: // ip
            if (dpl[3:2] == 2'b0)
              acc <= i_ports[dpl[1:0]];
            else
              acc <= o_ports[dpl];
        endcase
    endcase

// stack
always @(posedge clk)
  if (clk_mcu) begin
    case (state)
      FTC:
        casez (rdat)
          8'b1011_????: stack[sp] <= pc + 11'd1; // czp
          8'b1010_1???: stack[sp] <= pc + 11'd2; // cal
        endcase
    endcase
    if (~_INT && ien && irq) stack[sp] <= pc + 11'b1;
  end

always @*
  case (rdat[1:0])
    2'd0: mask = 4'b0001;
    2'd1: mask = 4'b0010;
    2'd2: mask = 4'b0100;
    2'd3: mask = 4'b1000;
  endcase

// ports
always @(posedge clk)
  if (clk_mcu)
    if (state == PRM && opc == 8'b0001_1110) // ocd
     { o_ports[PORT_D], o_ports[PORT_C] } <= rdat;
    else if (state == FTC)
     casez (rdat)
      8'b0111_01??: o_ports[PORT_E] <= o_ports[PORT_E] | mask; // seb
      8'b0110_01??: o_ports[PORT_E] <= o_ports[PORT_E] & ~mask; // reb
      8'b0111_00??: o_ports[dpl] <= o_ports[dpl] | mask; // spb
      8'b0110_00??: o_ports[dpl] <= o_ports[dpl] & ~mask; // rpb
      8'b0100_0100: o_ports[PORT_E] <= acc; // oe
      8'b0000_1110: o_ports[dpl] <= acc; // op
     endcase

// FSM
always @(posedge clk)
  if (clk_mcu) begin
    state <= FTC;
    case (state)

      PRM: begin
        casez (opc)
          8'b0001_0111: if (acc == rdat[3:0]) state <= SKP; // ci
          8'b0001_0110: if (dpl == rdat[3:0]) state <= SKP; // cli
          8'b0100_1001: state <= SKP; // rts
        endcase
      end

      FTC: begin
        casez (rdat)
          8'b0000_11?1, // inc dec
          8'b0001_11?1, // inm dem
          8'b0000_100?, // ad ads
          8'b00?1_0011, // ded ind
          8'b001?_11??, // xd xmd xi xmi
          8'b0101_10??, // tmb
          8'b0101_01??, // tpa
          8'b0010_01??, // tab
          8'b0101_00??, // tpb
          8'b0101_11??: if (alu_c) state <= SKP; // fbt
          8'b0010_00??: if (~alu_c) state <= SKP; // fbf
          8'b0100_110?, // xls xhr
          8'b0100_001?, // taz taw
          8'b0100_101?, // xaz xaw
          8'b0100_011?, // thx tly
          8'b0100_111?: state <= WRI; // xhx xly
          8'b0011_01??: if ((mdat & mask) == (acc & mask)) state <= SKP;
          8'b0000_1100: if (acc == mdat) state <= SKP; // cm
          8'b0000_0100: if (c) state <= SKP; // tc
          8'b0000_0101: if (tm) state <= SKP; // ttm
          8'b0000_0011: if (irq) state <= SKP; // tit
          8'b1010_1???, // cal
          8'b0100_100?, // rt rts
          8'b0100_0001, // jpa
          8'b1010_0???, // jmp
          8'b0001_011?, // ci cli
          8'b0001_1110, // ocd
          8'b0001_0100, // stm
          8'b0001_0101: state <= PRM; // ldi
        endcase
      end

    endcase
  end

// stack pointer
always @(posedge clk)
  if (clk_mcu) begin
    case (state)
      PRM:
        case (opc)
          8'b0100_1001, // rts
          8'b0100_1000: // rt
            case (sp)
              2'd0: sp <= 2'd2;
              2'd1: sp <= 2'd0;
              2'd2: sp <= 2'b1;
            endcase
        endcase
      FTC:
        casez (rdat)
          8'b1011_????, // czp
          8'b1010_1???: // cal
            case (sp)
              2'd0: sp <= 2'd1;
              2'd1: sp <= 2'd2;
              2'd2: sp <= 2'd0;
            endcase
        endcase
    endcase
    if (~_INT && ien && irq) sp <= sp + 2'b1;
  end

// opc
always @(posedge clk)
  if (clk_mcu)
    if (state == FTC) opc <= rdat;

// ien
always @(posedge clk)
  if (clk_mcu)
    if (state == FTC)
     case (rdat)
      8'b0011_0001: ien <= 1'b1;
      8'b0000_0001: ien <= 1'b0;
     endcase

// irq
always @(posedge clk) begin
  if (_INT) irq <= 1'b1;
  if (~_INT && ien && irq) irq <= 1'b0;
  if (state == FTC && rdat == 8'b0000_0011) irq <= 1'b0;
end


// pc
always @(posedge clk)
  if (clk_mcu && ~reset) begin

    pcc <= pcc + 8'd1;

    case (state)
      PRM:
        casez (opc)
          8'b0100_1001, // rts
          8'b0100_1000: { pcf, pcc } <= stack[sp == 2'b0 ? 2'b10 : sp-1]; // rt
          8'b1010_1???, // cal
          8'b1010_0???: { pcf, pcc } <= { opc[2:0], rdat }; // jmp
          8'b0100_0001: pcc[5:0] <= { acc, 2'b0 }; // jpa
        endcase
      SKP:
        casez (rdat)
          8'b0001_01?1, // ldi ci
          8'b0001_?110, // cli ocd
          8'b1010_????, // jmp cal
          8'b0001_0100: pcc <= pcc + 8'd2; // stm
          default: pcc <= pcc + 8'd1;
        endcase
      FTC:
        casez (rdat)
          8'b0100_?01?, // xaz xaw taz taw
          8'b0100_011?, // thx tly
          8'b0100_11??, // xhx xly xhr xls
          8'b0100_100?: // rt rts
            pcc <= pcc; // do not increment
          8'b11??_????: pcc[5:0] <= rdat[5:0]; // jcp
          8'b1011_????: { pcf, pcc } <= { 5'b0, rdat[3:0], 2'b0}; // czp
        endcase
    endcase

    if (~_INT && ien && irq) { pcf, pcc } <= 11'h3c;

  end

  else if (reset) { pcf, pcc } <= 11'b0;

endmodule