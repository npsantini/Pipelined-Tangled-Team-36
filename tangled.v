// Multi-cycle Tangled Implementation

// basic sizes of things
`define WORD	[15:0]
`define	STATE	[3:0] // some state numbers are OPs
`define REGSIZE	[7:0]
`define MEMSIZE	[65535:0]

// field placements and values
`define Op0	[15:12] // opcode field
`define	Reg0	[11:8]  // register number field
`define DestReg [7:4]
`define SourceReg [3:0]
`define DATA	[15:0]
`define REGS	[15:0]
`define SECOND4 `Reg0
`define BOTTOM8 [7:0]
`define TOP8    [15:8]
`define THIRD4  [7:4]
`define FOURTH4 [3:0]

// op codes
`define SYSCALL 16'b0

`define OPsys      4'h0

`define OPoneReg   4'h1
`define OPjumpr    4'h0
`define OPneg      4'h1
`define OPnegf     4'h2
`define OPnot      4'h3

`define OPbrf      4'h2
`define OPbrt      4'h3
`define OPlex      4'h4
`define OPlhi      4'h5

`define OPnorms    4'h6
`define OPadd      4'h0
`define OPmul      4'h1
`define OPslt      4'h2
`define OPand      4'h3
`define OPor	   4'h4
`define OPxor      4'h5
`define OPshift    4'h6

`define OPfloats   4'h7
`define OPaddf     4'h0
`define OPmulf     4'h1
`define OPsltf     4'h2
`define OPrecip    4'h4
`define OPfloat    4'h8
`define OPint      4'h9

`define OPmem      4'h7
`define OPcopy     4'ha
`define OPload     4'hb
`define OPstore    4'hc

`define Decode     4'h8

`define OPsingleQ  4'h9
`define OPnotQ     4'h0
`define OPoneQ     4'h1
`define OPzeroQ    4'h2

`define OPhadQ     4'ha

`define OPtwoQ     4'hb
`define OPcnotQ    4'h0
`define OPswapQ    4'h1

`define OPthreeQ   4'hc
`define OPccnotQ   4'h0
`define OPcswapQ   4'h1
`define OPandQ     4'h3
`define OPorQ      4'h4
`define OPxorQ     4'h5

`define Start      4'hd

`define OPmeasQ    4'he

`define OPnextQ    4'hf

// Floating point Verilog modules for CPE480
// Created February 19, 2019 by Henry Dietz, http://aggregate.org/hankd
// Distributed under CC BY 4.0, https://creativecommons.org/licenses/by/4.0/

// Field definitions
`define	WORD	[15:0]	// generic machine word size
`define	INT	signed [15:0]	// integer size
`define FLOAT	[15:0]	// half-precision float size
`define FSIGN	[15]	// sign bit
`define FEXP	[14:7]	// exponent
`define FFRAC	[6:0]	// fractional part (leading 1 implied)
`define NOTSIGN [14:0]  //portion of the float that isnt the sign

// Constants
`define	FZERO	16'b0	  // float 0
`define F32767  16'h46ff  // closest approx to 32767, actually 32640
`define F32768  16'hc700  // -32768

// Count leading zeros, 16-bit (5-bit result) d=lead0s(s)
module lead0s(d, s);
output wire [4:0] d;
input wire `WORD s;
wire [4:0] t;
wire [7:0] s8;
wire [3:0] s4;
wire [1:0] s2;
assign t[4] = 0;
assign {t[3],s8} = ((|s[15:8]) ? {1'b0,s[15:8]} : {1'b1,s[7:0]});
assign {t[2],s4} = ((|s8[7:4]) ? {1'b0,s8[7:4]} : {1'b1,s8[3:0]});
assign {t[1],s2} = ((|s4[3:2]) ? {1'b0,s4[3:2]} : {1'b1,s4[1:0]});
assign t[0] = !s2[1];
assign d = (s ? t : 16);
endmodule

// Float set-less-than, 16-bit (1-bit result) torf=a<b
module fslt(torf, a, b);
output wire torf;
input wire `FLOAT a, b;
assign torf = (a `FSIGN && !(b `FSIGN)) ||
	      (a `FSIGN && b `FSIGN && (a[14:0] > b[14:0])) ||
	      (!(a `FSIGN) && !(b `FSIGN) && (a[14:0] < b[14:0]));
endmodule

// Floating-point addition, 16-bit r=a+b
module fadd(r, a, b);
output wire `FLOAT r;
input wire `FLOAT a, b;
wire `FLOAT s;
wire [8:0] sexp, sman, sfrac;
wire [7:0] texp, taman, tbman;
wire [4:0] slead;
wire ssign, aegt, amgt, eqsgn;
assign r = ((a == 0) ? b : ((b == 0) ? a : s));
assign aegt = (a `FEXP > b `FEXP);
assign texp = (aegt ? (a `FEXP) : (b `FEXP));
assign taman = (aegt ? {1'b1, (a `FFRAC)} : ({1'b1, (a `FFRAC)} >> (texp - a `FEXP)));
assign tbman = (aegt ? ({1'b1, (b `FFRAC)} >> (texp - b `FEXP)) : {1'b1, (b `FFRAC)});
assign eqsgn = (a `FSIGN == b `FSIGN);
assign amgt = (taman > tbman);
assign sman = (eqsgn ? (taman + tbman) : (amgt ? (taman - tbman) : (tbman - taman)));
lead0s m0(slead, {sman, 7'b0});
assign ssign = (amgt ? (a `FSIGN) : (b `FSIGN));
assign sfrac = sman << slead;
assign sexp = (texp + 1) - slead;
assign s = (sman ? (sexp ? {ssign, sexp[7:0], sfrac[7:1]} : 0) : 0);
endmodule

// Floating-point multiply, 16-bit r=a*b
module fmul(r, a, b);
output wire `FLOAT r;
input wire `FLOAT a, b;
wire [15:0] m; // double the bits in a fraction, we need high bits
wire [7:0] e;
wire s;
assign s = (a `FSIGN ^ b `FSIGN);
assign m = ({1'b1, (a `FFRAC)} * {1'b1, (b `FFRAC)});
assign e = (((a `FEXP) + (b `FEXP)) -127 + m[15]);
assign r = (((a == 0) || (b == 0)) ? 0 : (m[15] ? {s, e, m[14:8]} : {s, e, m[13:7]}));
endmodule

// Floating-point reciprocal, 16-bit r=1.0/a
// Note: requires initialized inverse fraction lookup table
module frecip(r, a);
output wire `FLOAT r;
input wire `FLOAT a;
reg [6:0] look[127:0];
initial $readmemh("reciprocalLookup.mem", look);
assign r `FSIGN = a `FSIGN;
assign r `FEXP = 253 + (!(a `FFRAC)) - a `FEXP;
assign r `FFRAC = look[a `FFRAC];
endmodule

// Floating-point shift, 16 bit
// Shift +left,-right by integer
module fshift(r, f, i);
output wire `FLOAT r;
input wire `FLOAT f;
input wire `INT i;
assign r `FFRAC = f `FFRAC;
assign r `FSIGN = f `FSIGN;
assign r `FEXP = (f ? (f `FEXP + i) : 0);
endmodule

// Integer to float conversion, 16 bit
module i2f(f, i);
output wire `FLOAT f;
input wire `INT i;
wire [4:0] lead;
wire `WORD pos;
assign pos = (i[15] ? (-i) : i);
lead0s m0(lead, pos);
assign f `FFRAC = (i ? ({pos, 8'b0} >> (16 - lead)) : 0);
assign f `FSIGN = i[15];
assign f `FEXP = (i ? (128 + (14 - lead)) : 0);
endmodule

// Float to integer conversion, 16 bit
// Note: out-of-range values go to -32768 or 32767
module f2i(i, f);
output wire `INT i;
input wire `FLOAT f;
wire `FLOAT ui;
wire tiny, big;
fslt m0(tiny, f, `F32768);
fslt m1(big, `F32767, f);
assign ui = {1'b1, f `FFRAC, 16'b0} >> ((128+22) - f `FEXP);
assign i = (tiny ? 0 : (big ? 32767 : (f `FSIGN ? (-ui) : ui)));
endmodule

// Floating-point negative, 16-bit r=-a
// Note: requires initialized inverse fraction lookup table
module negf(r, a);
output wire `FLOAT r;
input wire `FLOAT a;
assign r = {!(a `FSIGN), a `NOTSIGN};
endmodule

// Field definitions
`define	WORD	[15:0]	// generic machine word size

module processor(halt, reset, clk);
  output reg halt;
  input reset, clk;
  reg `DATA r `REGS;	// register file [15:0]

  reg `WORD text `MEMSIZE; // instruction memory
  reg `WORD data `MEMSIZE; // data memory
  reg `WORD pc = 0;
  reg `WORD ir;
  reg `WORD nextInstruction;
  reg `WORD sltCheck;
  reg `STATE s, s2;

  wire `FLOAT addfRes, multfRes, sltfRes, recipRes, floatRes, intRes, negfRes;
  fadd myFAdd(addfRes, r[ir `THIRD4], r[ir `FOURTH4]);
  fmul myFMul(multfRes,r[ir `THIRD4], r[ir `FOURTH4]);
  fslt myFSLT(sltfRes, r[ir `THIRD4], r[ir `FOURTH4]);
  frecip myFRec(recipRes, r[ir `THIRD4]);
  f2i myFloToInt(intRes ,r[ir `THIRD4]);
  i2f myIntToFlo(floatRes, r[ir `THIRD4]); 
  negf myNegF(negfRes,    r[ir `THIRD4]);

  always @(posedge reset) begin
    halt <= 0;
    pc <= 0;
    s <= `Start;
    $readmemh("testAssembly.text", text);
    $readmemh("testAssembly.data", data);
    r[15] = 16'hffff; // initialize stack pointer
  end

  always @(posedge clk) begin
    case (s)
      `Start: 
        begin 
          ir <= text[pc]; 
          nextInstruction <= text[pc + 1];
          s <= `Decode;
        end 
      
      `Decode: 
        begin
          pc <= pc + 1;
          s <= ir `Op0;
          s2 <= ir `Reg0;
        end

      `OPsys: 
        begin
          halt <= 1;
          s <= `Start;
        end
        
      // Start Qat
      `OPsingleQ:
        begin
          case (s2)
            `OPnotQ: begin s <= `OPsys; end
            `OPoneQ: begin s <= `OPsys; end
            `OPzeroQ: begin s <= `OPsys; end
          endcase
        end

      `OPhadQ: begin s <= `OPsys; end

      `OPtwoQ:
        begin
          pc <= pc + 1;
          case (s2)
            `OPcnotQ: begin s <= `OPsys; end
            `OPswapQ: begin s <= `OPsys; end
          endcase
        end

      `OPthreeQ:
        begin
          pc <= pc + 1;
          case (s2)
            `OPccnotQ: begin s <= `OPsys; end
            `OPcswapQ: begin s <= `OPsys; end
            `OPandQ: begin s <= `OPsys; end
            `OPorQ: begin s <= `OPsys; end
            `OPxorQ: begin s <= `OPsys; end
          endcase
        end

      `OPmeasQ: begin s <= `OPsys; end

      `OPnextQ: begin s <= `OPsys; end
      // End Qat

      `OPoneReg: 
        begin
          case (s2)
            `OPjumpr: begin pc <= r[ir `DestReg]; s <= `Start; end
            `OPneg:   begin r[ir `DestReg] <= -r[ir `DestReg]; s <= `Start; end
            `OPnegf:  begin r[ir `DestReg] <= negfRes; s <= `Start; end 
            `OPnot:   begin r[ir `DestReg] <= ~r[ir `DestReg]; s <= `Start; end
          endcase
        end

      `OPbrf: begin pc <= pc + ((|r[ir `SECOND4]) ? (16'b0) : ((ir[7]) ? {{8{1'b1}}, (ir `BOTTOM8)} - 1 : ir `BOTTOM8 - 1)); s <= `Start; end // subtract 1 to offset incrementing the pc in Decode
      `OPbrt: begin pc <= pc + ((~|r[ir `SECOND4]) ? (16'b0) : ((ir[7]) ? {{8{1'b1}}, (ir `BOTTOM8)} - 1 : ir `BOTTOM8 - 1)); s <= `Start; end // subtract 1 to offset incrementing the pc in Decode

      `OPlex: 
      begin 
        r[ir `SECOND4] <= {{8{ir[7]}}, ir `BOTTOM8}; s <= `Start; 
      end

      `OPlhi: begin r[ir `SECOND4] `TOP8 <= ir `BOTTOM8; s <= `Start; end 

      `OPnorms: 
        begin
          case (s2)
            `OPadd: begin r[ir `DestReg] <= r[ir `DestReg] + r[ir `SourceReg]; s <= `Start; end
            `OPmul: begin r[ir `DestReg] <= r[ir `DestReg] * r[ir `SourceReg]; s <= `Start; end
            `OPslt: 
            begin 
              // r[ir `DestReg] <= (r[ir `DestReg] < r[ir `SourceReg] ? 16'b1 : 16'b0); s <= `Start; 
              sltCheck = r[ir `DestReg] - r[ir `SourceReg];
              r[ir `DestReg] <= ((sltCheck[15]) ? 16'b1 : 16'b0); s <= `Start; 
            end
            `OPand: begin r[ir `DestReg] <= r[ir `DestReg] & r[ir `SourceReg]; s <= `Start; end
            `OPor:  begin r[ir `DestReg] <= r[ir `DestReg] | r[ir `SourceReg]; s <= `Start; end
            `OPxor: begin r[ir `DestReg] <= r[ir `DestReg] ^ r[ir `SourceReg]; s <= `Start; end
            `OPshift: begin r[ir `DestReg] <= ((r[ir `SourceReg][15] == 0) ? (r[ir `DestReg] << r[ir `SourceReg]) : (r[ir `DestReg] >> -r[ir `SourceReg])); s <= `Start;
            end
          endcase
        end
   
      `OPfloats:
        begin
          case (s2)
            `OPaddf:  begin r[ir `DestReg] <= addfRes; s <= `Start; end
            `OPmulf:  begin r[ir `DestReg] <= multfRes; s <= `Start; end
            `OPsltf:  begin r[ir `DestReg] <= sltfRes; s <= `Start; end
            `OPrecip: begin r[ir `DestReg] <= recipRes; s <= `Start; end
            `OPfloat: begin r[ir `DestReg] <= floatRes; s <= `Start; end
            `OPint:   begin r[ir `DestReg] <= intRes; s <= `Start; end
            `OPcopy: begin r[ir `DestReg] <= r[ir `SourceReg]; s <= `Start; end
            `OPstore: begin data[r[ir `SourceReg]] <= r[ir `DestReg]; s <= `Start; end
            `OPload: begin r[ir `DestReg] <= data[r[ir `SourceReg]]; s <= `Start; end
          endcase
        end
    endcase
  end
endmodule

module testbench;
reg reset = 0;
reg clk = 0;
wire halted;
processor PE(halted, reset, clk);
initial begin
  $dumpfile("dump.txt");
  $dumpvars(1, PE.pc, PE.r[0], PE.r[1], PE.r[2], PE.r[15], PE.data[0], PE.data[1], PE.data[2], PE.s, PE.s2, PE.ir, PE.halt, PE.nextInstruction); // would normally trace 0, PE
  #1 reset = 1;
  #1 reset = 0;
  while (!halted) begin
    #1 clk = 1;
    #1 clk = 0;
  end
  $finish;
end
endmodule
