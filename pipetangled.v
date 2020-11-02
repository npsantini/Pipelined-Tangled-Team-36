// basic sizes of things
`define DATA	[15:0]
`define ADDR	[15:0]
`define SIZE	[65535:0]
`define INST	[15:0]
`define CC	[15:14]
`define OP	[14:9]
`define IORR	[8]
`define RD	[7:4]
`define RN	[3:0]
`define REGS    [15:0]

// CC values
`define AL	0
`define S	1
`define NE	2
`define EQ	3

// opcode values, also state numbers
`define OPPRE		5'h00
`define OPADD		5'h08
`define OPAND		5'h09
`define OPBIC		5'h0a
`define OPEOR		5'h0b
`define OPMUL		5'h0c
`define OPORR		5'h0d
`define OPSHA		5'h0e
`define OPSLT		5'h0f
`define OPSUB		5'h10
`define OPADDF		5'h11
`define OPFTOI		5'h12
`define OPITOF		5'h13
`define OPMULF		5'h14
`define OPRECF		5'h15
`define OPSUBF		5'h16
`define OPMOV		5'h17
`define OPNEG		5'h18
`define OPLDR		5'h19
`define OPSTR		5'h1a
`define OPSYS		5'h1f

//-------------------------------------
//-------------NEW OP CODES------------
//-------------------------------------

`define SYSCALL 16'b0

`define OPsys      5'h0

//`define OPoneReg   5'h1
`define OPjumpr    5'h10
`define OPneg      5'h11
`define OPnegf     5'h12
`define OPnot      5'h13

`define OPbrf      5'h2
`define OPbrt      5'h3
`define OPlex      5'h4
`define OPlhi      5'h5

//`define OPnorms    5'h6
`define OPadd      5'h60
`define OPmul      5'h61
`define OPslt      5'h62
`define OPand      5'h63
`define OPor	   5'h64
`define OPxor      5'h65
`define OPshift    5'h66

//`define OPfloats   5'h7
`define OPaddf     5'h70
`define OPmulf     5'h71
`define OPsltf     5'h72
`define OPrecip    5'h74
`define OPfloat    5'h78
`define OPint      5'h79

//`define OPmem      5'h7
`define OPcopy     5'h7a
`define OPload     5'h7b
`define OPstore    5'h7c

`define Decode     5'h8

//`define OPsingleQ  5'h9
`define OPnotQ     5'h90
`define OPoneQ     5'h91
`define OPzeroQ    5'h92

`define OPhadQ     5'ha

//`define OPtwoQ     5'hb
`define OPcnotQ    5'hb0
`define OPswapQ    5'hb1

//`define OPthreeQ   5'hc
`define OPccnotQ   5'hc0
`define OPcswapQ   5'hc1
`define OPandQ     5'hc3
`define OPorQ      5'hc4
`define OPxorQ     5'hc5

`define Start      5'hd

`define OPmeasQ    5'he

`define OPnextQ    5'hf

//-------------------------------------
//-----------END NEW OP CODES----------
//-------------------------------------


// make NOP (after fetch) an unconditional PRE 0
`define NOP             16'b0

module processor(halt, reset, clk);
output reg halt;
input reset, clk;

reg `DATA r `REGS;	// register file
reg `DATA d `SIZE;	// data memory
reg `INST i `SIZE;	// instruction memory
reg `ADDR pc;		// program counter
reg `ADDR tpc, pc0, pc1;
reg `INST ir;		// instruction register
reg `INST ir0, ir1;
reg `DATA im0, rd1, rn1, res;
reg `ADDR target;	// jump target
reg jump;		// are we jumping?
reg zreg;		// z flag
wire pendz;		// z update pending?
wire pendpc;		// pc update pending?
reg wait1;		// need to stall in stage 1?
reg [11:0] prefix;	// 12-bit prefix value
reg havepre;		// is prefix valid?

always @(reset) begin
  halt = 0;
  pc = 0;
  ir0 = `NOP;
  ir1 = `NOP;
  jump = 0;
  havepre = 0;

// use the following with dollars to initialize
//readmemh0(r); // register file
//readmemh1(d); // data memory
//readmemh2(i); // instruction memory
  $readmemh("testAssembly.text", i);
  $readmemh("testAssembly.data", d);
end

function setsrd;
input `INST inst;
setsrd = ((inst `OP >= `OPADD) && (inst `OP < `OPSTR));
endfunction

function setspc;
input `INST inst;
setspc = ((inst `RD == 15) && setsrd(inst));
endfunction

function setsz;
input `INST inst;
setsz = ((inst `CC == `S) && setsrd(inst));
endfunction

function iscond;
input `INST inst;
iscond = ((inst `CC == `NE) || (inst `CC == `EQ));
endfunction

function usesim;
input `INST inst;
usesim = ((inst `IORR) && (inst `OP <= `OPSTR));
endfunction

function usesrd;
input `INST inst;
usesrd = ((inst `OP == `OPADD) ||
          (inst `OP == `OPADDF) ||
          (inst `OP == `OPAND) ||
          (inst `OP == `OPBIC) ||
          (inst `OP == `OPEOR) ||
          (inst `OP == `OPMUL) ||
          (inst `OP == `OPMULF) ||
          (inst `OP == `OPORR) ||
          (inst `OP == `OPSHA) ||
          (inst `OP == `OPSTR) ||
          (inst `OP == `OPSLT) ||
          (inst `OP == `OPSUB) ||
          (inst `OP == `OPSUBF));
endfunction

function usesrn;
input `INST inst;
usesrn = ((!(inst `IORR)) && (inst `OP <= `OPSTR));
endfunction

// pending z update?
assign pendz = (setsz(ir0) || setsz(ir1));

// pending PC update?
assign pendpc = (setspc(ir0) || setspc(ir1));

// -----------------------------------------------
// stage 0: instruction fetch and immediate extend
// -----------------------------------------------
always @(posedge clk) begin
  tpc = (jump ? target : pc);

  if (wait1) begin
    // blocked by stage 1, so should not have a jump, but...
    pc <= tpc;
  end else begin
    // not blocked by stage 1
    ir = i[tpc];

    if (pendpc || (iscond(ir) && pendz)) begin
      // waiting... pc doesn't change
      ir0 <= `NOP;
      pc <= tpc;
    end else begin
      if (ir[13:12] == 0) begin
        // PRE operation
        havepre <= 1;
        prefix <= ir[11:0];
        ir0 <= `NOP;
      end else begin
        if (usesim(ir)) begin
          // extend immediate
          im0 <= {(havepre ? prefix : {12{ir[3]}}), ir `RN};
          havepre <= 0;
        end
        ir0 <= ir;
      end
      pc <= tpc + 1;
    end

    pc0 <= tpc;
  end
end

// -----------------------------------------------
// stage 1: register read
// -----------------------------------------------
always @(posedge clk) begin
  if ((ir0 != `NOP) &&
      setsrd(ir1) &&
      ((usesrd(ir0) && (ir0 `RD == ir1 `RD)) ||
       (usesrn(ir0) && (ir0 `RN == ir1 `RD)))) begin
    // stall waiting for register value
    wait1 = 1;
    ir1 <= `NOP;
  end else begin
    // all good, get operands (even if not needed)
    wait1 = 0;
    rd1 <= ((ir0 `RD == 15) ? pc0 : r[ir0 `RD]);
    rn1 <= (usesim(ir0) ? im0 :
            ((ir0 `RN == 15) ? pc0 : r[ir0 `RN]));
    ir1 <= ir0;
  end
end

// ---------------------------------------------------
// stage 2: ALU, data memory access, store in register
// ---------------------------------------------------
always @(posedge clk) begin
  if ((ir1 == `NOP) ||
      ((ir1 `CC == `EQ) && (zreg == 0)) ||
      ((ir1 `CC == `NE) && (zreg == 1))) begin
    // condition says nothing happens
    jump <= 0;
  end else begin
    // let the instruction execute
    case (ir1 `OP)
      `OPPRE:  begin end // do nothing
      `OPADD:  res = rd1 + rn1;
      `OPAND:  res = rd1 & rn1;
      `OPBIC:  res = rd1 & ~rn1;
      `OPEOR:  res = rd1 ^ rn1;
      `OPMUL:  res = rd1 * rn1;
      `OPORR:  res = rd1 | rn1;
      `OPSHA:  res = ((rn1 > 0) ? (rd1 << rn1) : (rd1 >> -rn1));
      `OPSLT:  res = (rd1 < rn1);
      `OPSUB:  res = rd1 - rn1;
      `OPMOV:  res = rn1;
      `OPNEG:  res = -rn1;
      `OPLDR:  res = d[rn1];
      `OPSTR:  begin res = rd1; d[rn1] <= res; end
      default: halt <= 1; // make it stop
    endcase

    // update z flag if we should
    if (setsz(ir1)) zreg <= (res == 0);

    // put result in rd if we should
    if (setsrd(ir1)) begin
      if (ir1 `RD == 15) begin
        jump <= 1;
        target <= res;
      end else begin
        r[ir1 `RD] <= res;
        jump <= 0;
      end
    end else jump <= 0;
  end
end
endmodule

// -----------------------------------------------
// INSERT STAGE 4: REGISTER WRITE BELOW
// -----------------------------------------------


// -----------------------------------------------
// TEST BENCH
// -----------------------------------------------
module testbench;
reg reset = 0;
reg clk = 0;
wire halted;
processor PE(halted, reset, clk);
initial begin
  $dumpfile("dump.txt");
  $dumpvars(0, PE);
  #10 reset = 1;
  #10 reset = 0;
  while (!halted) begin
    #10 clk = 1;
    #10 clk = 0;
  end
  $finish;
end
endmodule
