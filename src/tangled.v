/*
* 
*      Authors: Cain Hubbard, Collin Lebanik, Nick Satini, Tristan Barnes
*         File: tangled.v
*      Project: Assignment 3 - "Pipelined Tangled"
*      Created: 5 November 2020
* 
*  Description: Implements a Pipelined Tangled Processor design.
*           
*/



// The following macros should be set using the -D flag when invoking iverilog
// from the command line in order to specify testbench text and data vmem files
// and the name of the output vcd file. 
//`define TEST_TEXT_VMEM      "set/using/the/-D/flag/on/cmdline/test.text.vmem"
//`define TEST_DATA_VMEM      "set/using/the/-D/flag/on/cmdline/test.text.vmem"
//`define TEST_VCD            "set/using/the/-D/flag/on/cmdline/test.vcd"



// ROM used by the frecip Floaty module.
`define FRECIP_LOOKUP_VMEM  "src/frecipLookup.vmem"



// Generic Tangled word size
`define WORD_SIZE           [15:0]
`define WORD_HIGH_FIELD     [15:8]
`define WORD_LOW_FIELD      [7:0]



// *****************************************************************************
// ********************************** FLOATY ***********************************
// *****************************************************************************



// Floating point Verilog modules for CPE480
// Created February 19, 2019 by Henry Dietz, http://aggregate.org/hankd
// Distributed under CC BY 4.0, https://creativecommons.org/licenses/by/4.0/

// Fields
`define INT_SIZE signed     [15:0]      // integer size
`define FLOAT_SIZE          [15:0]      // half-precision float size

// Fields
`define FSIGN_FIELD         [15]        // sign bit
`define FEXP_FIELD          [14:7]      // exponent
`define FFRAC_FIELD         [6:0]       // fractional part (leading 1 implied)

// Constants
`define FZERO               16'b0       // float 0
`define F32767              16'h46ff    // closest approx to 32767, actually 32640
`define F32768              16'hc700    // -32768
`define FNAN                16'hffc0    // Floating point Not-a-Number
`define INAN                16'h8000    // Integer value for float-to-int from NaN

// Masks
`define FSIGN_M             16'h8000    // Floating point sign bit mask



// Count leading zeros, 16-bit (5-bit result) d=lead0s(s)
module lead0s(d, s);
    output wire [4:0] d;
    input wire `INT_SIZE s;
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
module fslt(result, a, b);
    output wire result;
    input wire `FLOAT_SIZE a, b;
    wire torf;
    assign torf =   (a `FSIGN_FIELD && !(b `FSIGN_FIELD)) ||
                    (a `FSIGN_FIELD && b `FSIGN_FIELD && (a[14:0] > b[14:0])) ||
                    (!(a `FSIGN_FIELD) && !(b `FSIGN_FIELD) && (a[14:0] < b[14:0]));
    assign result = (a == `FNAN || b == `FNAN) ? `FNAN : torf;
endmodule



// Floating-point addition, 16-bit r=a+b
module fadd(result, a, b);
    output wire `FLOAT_SIZE result;
    input wire `FLOAT_SIZE a, b;
    wire `FLOAT_SIZE r;
    wire `FLOAT_SIZE s;
    wire [8:0] sexp, sman, sfrac;
    wire [7:0] texp, taman, tbman;
    wire [4:0] slead;
    wire ssign, aegt, amgt, eqsgn;
    assign aegt = (a `FEXP_FIELD > b `FEXP_FIELD);
    assign texp = (aegt ? (a `FEXP_FIELD) : (b `FEXP_FIELD));
    assign taman = (aegt ? {1'b1, (a `FFRAC_FIELD)} : ({1'b1, (a `FFRAC_FIELD)} >> (texp - a `FEXP_FIELD)));
    assign tbman = (aegt ? ({1'b1, (b `FFRAC_FIELD)} >> (texp - b `FEXP_FIELD)) : {1'b1, (b `FFRAC_FIELD)});
    assign eqsgn = (a `FSIGN_FIELD == b `FSIGN_FIELD);
    assign amgt = (taman > tbman);
    assign sman = (eqsgn ? (taman + tbman) : (amgt ? (taman - tbman) : (tbman - taman)));
    lead0s m0(slead, {sman, 7'b0});
    assign ssign = (amgt ? (a `FSIGN_FIELD) : (b `FSIGN_FIELD));
    assign sfrac = sman << slead;
    assign sexp = (texp + 1) - slead;
    assign s = (sman ? (sexp ? {ssign, sexp[7:0], sfrac[7:1]} : 0) : 0);
    assign r = ((a == 0) ? b : ((b == 0) ? a : s));
    assign result = (a == `FNAN || b == `FNAN) ? `FNAN : r;
endmodule



// Floating-point multiply, 16-bit r=a*b
module fmul(result, a, b);
    output wire `FLOAT_SIZE result;
    input wire `FLOAT_SIZE a, b;
    wire `FLOAT_SIZE r;
    wire [15:0] m; // double the bits in a fraction, we need high bits
    wire [7:0] e;
    wire s;
    assign s = (a `FSIGN_FIELD ^ b `FSIGN_FIELD);
    assign m = ({1'b1, (a `FFRAC_FIELD)} * {1'b1, (b `FFRAC_FIELD)});
    assign e = (((a `FEXP_FIELD) + (b `FEXP_FIELD)) -127 + m[15]);
    assign r = (((a == 0) || (b == 0)) ? 0 : (m[15] ? {s, e, m[14:8]} : {s, e, m[13:7]}));
    assign result = (a == `FNAN || b == `FNAN) ? `FNAN : r;
endmodule



// Floating-point reciprocal, 16-bit r=1.0/a
// Note: requires initialized inverse fraction lookup table
module frecip(result, a);
    output wire `FLOAT_SIZE result;
    input wire `FLOAT_SIZE a;
    wire `FLOAT_SIZE r;
    reg [6:0] look[127:0];
    initial $readmemh(`FRECIP_LOOKUP_VMEM, look);
    assign r `FSIGN_FIELD = a `FSIGN_FIELD;
    assign r `FEXP_FIELD = 253 + (!(a `FFRAC_FIELD)) - a `FEXP_FIELD;
    assign r `FFRAC_FIELD = look[a `FFRAC_FIELD];
    assign result = (a == `FNAN) ? `FNAN : r;
endmodule



// Floating-point shift, 16 bit
// Shift +left,-right by integer
module fshift(result, f, i);
    output wire `FLOAT_SIZE result;
    input wire `FLOAT_SIZE f;
    input wire `INT_SIZE i;
    wire `FLOAT_SIZE r;
    assign r `FFRAC_FIELD = f `FFRAC_FIELD;
    assign r `FSIGN_FIELD = f `FSIGN_FIELD;
    assign r `FEXP_FIELD = (f ? (f `FEXP_FIELD + i) : 0);
    assign result = (f == `FNAN) ? `FNAN : r;
endmodule



// Integer to float conversion, 16 bit
module i2f(f, i);
    output wire `FLOAT_SIZE f;
    input wire `INT_SIZE i;
    wire [4:0] lead;
    wire `INT_SIZE pos;
    assign pos = (i[15] ? (-i) : i);
    lead0s m0(lead, pos);
    assign f `FFRAC_FIELD = (i ? ({pos, 8'b0} >> (16 - lead)) : 0);
    assign f `FSIGN_FIELD = i[15];
    assign f `FEXP_FIELD = (i ? (128 + (14 - lead)) : 0);
endmodule



// Float to integer conversion, 16 bit
// Note: out-of-range values go to -32768 or 32767
module f2i(result, f);
    output wire `INT_SIZE result;
    input wire `FLOAT_SIZE f;
    wire `FLOAT_SIZE ui;
    wire tiny, big;
    wire `INT_SIZE i;
    fslt m0(tiny, f, `F32768);
    fslt m1(big, `F32767, f);
    assign ui = {1'b1, f `FFRAC_FIELD, 16'b0} >> ((128+22) - f `FEXP_FIELD);
    assign i = (tiny ? 0 : (big ? 32767 : (f `FSIGN_FIELD ? (-ui) : ui)));
    assign result = (f == `FNAN) ? `INAN : i;
endmodule



// Float negate
module fneg(result, f);
    output wire `FLOAT_SIZE result;
    input wire `FLOAT_SIZE f;
    assign result = (f == `FNAN) ? `FNAN : (f ^ `FSIGN_M);
endmodule



// *****************************************************************************
// ************************************ ALU ************************************
// *****************************************************************************



//ALU OPs
`define ALUOP_SIZE          [3:0]
`define ALUOP_NOT           4'h0
`define ALUOP_FLOAT         4'h1
`define ALUOP_INT           4'h2
`define ALUOP_NEG           4'h3
`define ALUOP_NEGF          4'h4
`define ALUOP_RECIP         4'h5
`define ALUOP_ADD           4'h6
`define ALUOP_MUL           4'h7
`define ALUOP_SLT           4'h8
`define ALUOP_AND           4'h9
`define ALUOP_OR            4'ha
`define ALUOP_SHIFT         4'hb
`define ALUOP_XOR           4'hc
`define ALUOP_ADDF          4'hd
`define ALUOP_MULF          4'he
`define ALUOP_SLTF          4'hf



module ALU (
    output reg `WORD_SIZE out,
    input wire `ALUOP_SIZE op,
    input wire signed `WORD_SIZE a,
    input wire signed `WORD_SIZE b
);
    wire fsltout;
    wire `WORD_SIZE faddout, fmulout, frecipout, i2fout, f2iout, fnegout;

    // Instantiate floating point modules
    fslt myfslt(fsltout, a, b);
    fadd myfadd(faddout, a, b);
    fmul myfmul(fmulout, a, b);
    frecip myfrecip(frecipout, a);
    i2f myi2f(i2fout, a);
    f2i myf2i(f2iout, a);
    fneg myfneg(fnegout, a);

    // assign output based on op
    always @* begin
        case (op)
            `ALUOP_NOT: out = ~a;
            `ALUOP_FLOAT: out = i2fout;
            `ALUOP_INT: out = f2iout;
            `ALUOP_NEG: out = -a;
            `ALUOP_NEGF: out = fnegout;
            `ALUOP_RECIP: out = frecipout;
            `ALUOP_ADD: out = a + b;
            `ALUOP_MUL: out = a * b;
            `ALUOP_SLT: out = a < b;
            `ALUOP_AND: out = a & b;
            `ALUOP_OR: out = a | b;
            `ALUOP_SHIFT: out = ((b < 32768) ? (a << b) : (a >> -b));
            `ALUOP_XOR: out = a ^ b;
            `ALUOP_ADDF: out = faddout;
            `ALUOP_MULF: out = fmulout;
            `ALUOP_SLTF: out = fsltout;
        endcase
    end
endmodule



// *****************************************************************************
// ***************************** Pipelined Tangled *****************************
// *****************************************************************************



// Memory array sizes & their index sizes
`define IMEM_SIZE           [2**16 - 1 : 0] // Instruction memory size
`define IMEM_INDEX_SIZE     [15:0]
`define DMEM_SIZE           [2**16 - 1 : 0] // Data memory size
`define REGFILE_SIZE        [2**4 - 1 : 0]  // The size of the regfile (i.e. 16 regs)
`define REGFILE_INDEX_SIZE  [3:0]


// Format A field & values
`define FA_FIELD            [15]
`define FA_SIZE             [0:0]
`define FA_FIELD_F0         1
`define FA_FIELD_F1to4      0

// Format B field & values
`define FB_FIELD            [14:13]
`define FB_SIZE             [1:0]
`define FB_FIELD_F1         1
`define FB_FIELD_F2         2
`define FB_FIELD_F3         3
`define FB_FIELD_F4         0

// Format 0 Op codes
`define F0_OP_FIELD_HIGH    [14:13]
`define F0_OP_FIELD_LOW     [8]
`define F0_OP_SIZE          [2:0]
`define F0_OP_LEX           0
`define F0_OP_LHI           1
`define F0_OP_BRF           2
`define F0_OP_BRT           3
`define F0_OP_MEAS          4
`define F0_OP_NEXT          5
`define F0_OP_HAD           6

// Format 1 Op codes
`define F1_OPA_FIELD        [8]
`define F1_OPA_FIELD_ALU    0
`define F1_OPA_FIELD_OPB    1
`define F1_OPB_FIELD        [7:4]
`define F1_OPB_JUMPR        0
`define F1_OPB_LOAD         8
`define F1_OPB_STORE        9
`define F1_OPB_COPY         10

// Format 2 Op Codes
`define F2_OP_FIELD         [12:8]
`define F2_OP_ONE           0
`define F2_OP_ZERO          1
`define F2_OP_NOT           2

// Format 3 Op Codes
`define F3_OP_FIELD         [12:8]
`define F3_OP_CCNOT         0
`define F3_OP_CSWAP         1
`define F3_OP_AND           2
`define F3_OP_OP            3
`define F3_OP_XOR           4
`define F3_OP_SWAP          16
`define F3_OP_CNOT          17

// Define instruction operand fields & size
`define IR_RD_FIELD         [12:9]
`define IR_RS_FIELD         [3:0]
`define IR_ALU_OP_FIELD     [7:4]
`define IR_IMM8_FIELD       [7:0]
`define IR_IMM8_MSB_FIELD   [7]
`define IR_QA_FIELD         [7:0]
`define IR2_QB_FIELD        [7:0]
`define IR2_QC_FIELD        [15:8]

// Write-back Sources
`define WB_SOURCE_SIZE      [1:0]
`define WB_SOURCE_ALU       0
`define WB_SOURCE_MEM       1
`define WB_SOURCE_RD        2
`define WB_SOURCE_RS        3



module Tangled (
    output wire halt,
    input wire reset,
    input wire clk
);
    
    // ---------- Pipeline Stage 0 - Load ----------

    reg `WORD_SIZE text `IMEM_SIZE;         // Instruction memory
    reg `IMEM_INDEX_SIZE pc;                // Program counter register
    wire `IMEM_INDEX_SIZE pc_eff;           // Effective program counter for current instruction
    assign pc_eff = shouldBrJmp ? brJmpTarget : pc;

    // Used to determine if current instruction is from PC or a branch/jump
    // (Assigned in Stage 2)
    wire shouldBrJmp;
    wire `WORD_SIZE brJmpTarget;

    // Current cycle's instruction
    wire `WORD_SIZE instr;
    assign instr = text[pc_eff];

    reg ps0_halt;                           // Halts stage 0

    // Handle async reset logic
    always @(posedge reset) begin
        psr01_ir <= 0;               
        psr01_halt <= 1;

        psr12_rdIndex <= 0;
        psr12_rsIndex <= 0;
        psr12_rdValue <= 0;
        psr12_rsValue <= 0;
        psr12_aluOp <= 0;
        psr12_memWrite <= 0;                   
        psr12_writeBack <= 0;                    
        psr12_wbSource <= 0;     
        psr12_branchTarget <= 0;                 
        psr12_brf <= 0;                          
        psr12_brt <= 0;                          
        psr12_jumpr <= 0; 
        psr12_halt <= 1;
        
        psr23_writeBack <= 0;                 
        psr23_wbIndex <= 0;
        psr23_wbValue <= 0;                  
        psr23_halt <= 1;                     

        ps0_halt <= 0;
        pc <= 0;
    end

    // Stage 0-to-1 Registers
    reg `WORD_SIZE psr01_ir;                // Next cycle's instruction
    reg psr01_halt;                         // Halts stage 1

    function is2WordFrmt;
        input `WORD_SIZE instr;
        is2WordFrmt = (instr `FA_FIELD == `FA_FIELD_F1to4) && (instr `FB_FIELD == `FB_FIELD_F3);
    endfunction

    function isSysOrQat;
        input `WORD_SIZE instr;
        isSysOrQat = (instr `FA_FIELD == `FA_FIELD_F1to4) && (instr `FB_FIELD != `FB_FIELD_F1);
    endfunction

    always @(posedge clk) begin
        // It is possible that a sys/qat occurs immediately after a branch/jump,
        // but the jump WILL skip over it and a branch may, so in the case that
        // stage 2 says to branch/jump, do it regardless of the instruction in
        // stage 1.
        if (!ps0_halt || shouldBrJmp) begin
            pc <= pc_eff + (is2WordFrmt(instr) ? 2 : 1);
            psr01_ir <= instr;
            psr01_halt <= isSysOrQat(instr);
            ps0_halt <= isSysOrQat(instr);
        end 
    end


    // ---------- Pipeline Stage 1 - Decode ----------

    reg `WORD_SIZE regfile `REGFILE_SIZE;   // Register File

    // Stage 1-to-2 Registers
    reg `REGFILE_INDEX_SIZE psr12_rdIndex;
    reg `REGFILE_INDEX_SIZE psr12_rsIndex;
    reg `WORD_SIZE psr12_rdValue;
    reg `WORD_SIZE psr12_rsValue;
    reg `ALUOP_SIZE psr12_aluOp;
    reg psr12_memWrite;                     // Memory write flag
    reg psr12_writeBack;                    // Write-back to regfile flag
    reg `WB_SOURCE_SIZE psr12_wbSource;     // Write-back source
    reg `WORD_SIZE psr12_branchTarget;      // Target pc if instruction is a branch
    reg psr12_brf;                          // Is bracnh false
    reg psr12_brt;                          // Is branch true
    reg psr12_jumpr;                        // Is jump
    reg psr12_halt;                         // Halts stage 2


    function isStore;
        input `WORD_SIZE instr;
        isStore =       (instr `FA_FIELD == `FA_FIELD_F1to4) &&
                        (instr `FB_FIELD == `FB_FIELD_F1) &&
                        (instr `F1_OPA_FIELD == `F1_OPA_FIELD_OPB) &&
                        (instr `F1_OPB_FIELD == `F1_OPB_STORE);
    endfunction

    function isLoad;
        input `WORD_SIZE instr;
        isLoad =        (instr `FA_FIELD == `FA_FIELD_F1to4) &&
                        (instr `FB_FIELD == `FB_FIELD_F1) &&
                        (instr `F1_OPA_FIELD == `F1_OPA_FIELD_OPB) &&
                        (instr `F1_OPB_FIELD == `F1_OPB_LOAD);
    endfunction

    function isCopy;
        input `WORD_SIZE instr;
        isCopy =        (instr `FA_FIELD == `FA_FIELD_F1to4) &&
                        (instr `FB_FIELD == `FB_FIELD_F1) &&
                        (instr `F1_OPA_FIELD == `F1_OPA_FIELD_OPB) &&
                        (instr `F1_OPB_FIELD == `F1_OPB_COPY);
    endfunction

    function isLex;
        input `WORD_SIZE instr;
        isLex =         (instr `FA_FIELD == `FA_FIELD_F0) &&
                        ({instr `F0_OP_FIELD_HIGH, instr `F0_OP_FIELD_LOW} == `F0_OP_LEX);
    endfunction

    function isLhi;
        input `WORD_SIZE instr;
        isLhi =         (instr `FA_FIELD == `FA_FIELD_F0) &&
                        ({instr `F0_OP_FIELD_HIGH, instr `F0_OP_FIELD_LOW} == `F0_OP_LHI);
    endfunction

    function isBrf;
        input `WORD_SIZE instr;
        isBrf =         (instr `FA_FIELD == `FA_FIELD_F0) &&
                        ({instr `F0_OP_FIELD_HIGH, instr `F0_OP_FIELD_LOW} == `F0_OP_BRF);
    endfunction

    function isBrt;
        input `WORD_SIZE instr;
        isBrt =         (instr `FA_FIELD == `FA_FIELD_F0) &&
                        ({instr `F0_OP_FIELD_HIGH, instr `F0_OP_FIELD_LOW} == `F0_OP_BRT);
    endfunction

    function isJumpr;
        input `WORD_SIZE instr;
        isJumpr =       (instr `FA_FIELD == `FA_FIELD_F1to4) &&
                        (instr `FB_FIELD == `FB_FIELD_F1) &&
                        (instr `F1_OPA_FIELD == `F1_OPA_FIELD_OPB) &&
                        (instr `F1_OPB_FIELD == `F1_OPB_JUMPR);
    endfunction

    function usesALU;
        input `WORD_SIZE instr;
        usesALU =       (instr `FA_FIELD == `FA_FIELD_F1to4) &&
                        (instr `FB_FIELD == `FB_FIELD_F1) &&
                        (instr `F1_OPA_FIELD == `F1_OPA_FIELD_ALU);
    endfunction

    function isWriteBack;
        input `WORD_SIZE instr;
        reg `F0_OP_SIZE f0Op;
        begin 
            f0Op = {instr `F0_OP_FIELD_HIGH, instr `F0_OP_FIELD_LOW};

            case (instr `FA_FIELD)
                `FA_FIELD_F0: isWriteBack = (f0Op == `F0_OP_LEX) ||
                                            (f0Op == `F0_OP_LHI) ||
                                            (f0Op == `F0_OP_MEAS) ||
                                            (f0Op == `F0_OP_NEXT);
                `FA_FIELD_F1to4:
                    case (instr`FB_FIELD)
                        `FB_FIELD_F1: 
                            case (instr`F1_OPA_FIELD)
                                `F1_OPA_FIELD_ALU: isWriteBack = 1;
                                `F1_OPA_FIELD_OPB: isWriteBack =    (instr `F1_OPB_FIELD == `F1_OPB_LOAD) ||
                                                                    (instr `F1_OPB_FIELD == `F1_OPB_COPY);
                            endcase
                        default: isWriteBack = 0;
                    endcase
            endcase
        end
    endfunction

    // Sign extend the 8-bit immediate
    wire `WORD_SIZE sxi;
    assign sxi = {{8{psr01_ir `IR_IMM8_MSB_FIELD}}, psr01_ir `IR_IMM8_FIELD};

    // Rd value straight from regfile
    wire `WORD_SIZE regfile_rdValue;
    assign regfile_rdValue = regfile[psr01_ir `IR_RD_FIELD];

    // The effective Rd and Rs values from the regfile with value-forwarding
    // consideration.
    // (Ideally, value-forwarding should not have to consider the halt status of
    // any stage (any instruction that halts should technically not write-back).
    // However, since Qat instructions (some of which "should" write-back) are
    // supposd to halt for this assignment, this consideration is necessary.)
    wire `WORD_SIZE ps1_regfile_rdValue_eff;
    assign ps1_regfile_rdValue_eff =    (!psr12_halt && !ps2_bubble && psr12_writeBack && (psr01_ir `IR_RD_FIELD == psr12_rdIndex)) ? ps2_wbValue : 
                                        (!psr23_halt && psr23_writeBack && (psr01_ir `IR_RD_FIELD == psr23_wbIndex)) ? psr23_wbValue :
                                        regfile[psr01_ir `IR_RD_FIELD];
    wire `WORD_SIZE ps1_regfile_rsValue_eff;
    assign ps1_regfile_rsValue_eff =    (!psr12_halt && !ps2_bubble && psr12_writeBack && (psr01_ir `IR_RS_FIELD == psr12_rdIndex)) ? ps2_wbValue : 
                                        (!psr23_halt && psr23_writeBack && (psr01_ir `IR_RS_FIELD == psr23_wbIndex)) ? psr23_wbValue :
                                        regfile[psr01_ir `IR_RS_FIELD];

    always @(posedge clk) begin
        psr12_rdIndex <= psr01_ir `IR_RD_FIELD;
        psr12_rsIndex <= psr01_ir `IR_RS_FIELD;
        psr12_rdValue <=    isLex(psr01_ir) ? sxi :
                            {isLhi(psr01_ir) ? psr01_ir `IR_IMM8_FIELD : ps1_regfile_rdValue_eff `WORD_HIGH_FIELD, ps1_regfile_rdValue_eff `WORD_LOW_FIELD};
        psr12_rsValue <= ps1_regfile_rsValue_eff;
        psr12_aluOp <= psr01_ir `IR_ALU_OP_FIELD;
        psr12_memWrite <= isStore(psr01_ir);
        psr12_writeBack <= isWriteBack(psr01_ir);
        psr12_wbSource <=   usesALU(psr01_ir) ? `WB_SOURCE_ALU :
                            isLoad(psr01_ir) ? `WB_SOURCE_MEM : 
                            isCopy(psr01_ir) ? `WB_SOURCE_RS :
                            `WB_SOURCE_RD;
        psr12_branchTarget <= pc + sxi;
        psr12_brf <= isBrf(psr01_ir);  
        psr12_brt <= isBrt(psr01_ir);  
        psr12_jumpr <= isJumpr(psr01_ir);

        psr12_halt <= psr01_halt;
    end


    // ---------- Pipeline Stage 2 - Execute ----------

    reg `WORD_SIZE data `DMEM_SIZE;         // Data memory
    reg ps2_bubble;                         // Bubbles this stage in next clock cycle

    // Stage 2-to-3 Registers
    reg psr23_writeBack;                    // Write-back to regfile flag
    reg `REGFILE_INDEX_SIZE psr23_wbIndex;
    reg `WORD_SIZE psr23_wbValue;
    reg psr23_halt;                         // Halts stage 3

    // Instantiate the ALU
    wire `WORD_SIZE aluOut;
    ALU alu(.out(aluOut), .op(psr12_aluOp), .a(psr12_rdValue), .b(psr12_rsValue));

    // Determine if a branch/jump should be taken, and if so, the target.
    // (Wires defined in stage 0).
    // Be sure to de-assert shouldBrJmp during a bubble
    assign shouldBrJmp =    !ps2_bubble &&
                            ((psr12_brf && (psr12_rdValue == 0)) ||
                            (psr12_brt && (psr12_rdValue != 0)) ||
                            psr12_jumpr);
    assign brJmpTarget = psr12_jumpr ? psr12_rdValue : psr12_branchTarget;

    // Determine write-back value
    // (Combinatorial logic)
    // (Simply using `@*` takes iverilog a while to resolve, so the appropriate
    // signals have been listed explicitly in the sensitivity list.)
    reg `WORD_SIZE ps2_wbValue;
    always @(psr12_wbSource or aluOut or data[psr12_rsValue] or psr12_rdValue or psr12_rsValue) begin
        case (psr12_wbSource)
            `WB_SOURCE_ALU: ps2_wbValue = aluOut;
            `WB_SOURCE_MEM: ps2_wbValue = data[psr12_rsValue];
            `WB_SOURCE_RD: ps2_wbValue = psr12_rdValue;
            `WB_SOURCE_RS: ps2_wbValue = psr12_rsValue;
        endcase
    end

    always @(posedge clk) begin
        if (!ps2_bubble) begin
            psr23_writeBack <= psr12_writeBack;
            psr23_wbIndex <= psr12_rdIndex;
            
            psr23_wbValue <= ps2_wbValue;

            if (psr12_memWrite) begin
                data[psr12_rsValue] <= psr12_rdValue;
            end

            psr23_halt <= psr12_halt;
        end

        // If a branch or jump is about to be taken, then the instruction in
        // stage 1 is invalid, so stage 2 should bubble in the next clock cycle.
        // (shouldBrJmp is never asserted if this stage is currently in a
        // bubble, so the following statement will also force stage 2 bubbles to
        // only occur for a single clock cycle). 
        ps2_bubble <= shouldBrJmp;
    end


    // ---------- Pipeline Stage 3 - Write-back ----------

    always @(posedge clk) begin
        // Ideally, this stage should not have to be gated based on the halt
        // signal. However, due to the fact that some Qat instructions should
        // technically write-back, but Qat instructions are supposed to halt the
        // processor (like sys) in this assignment (and therefore, do not
        // actually perform any operations that would produce meaningful values
        // to write-back to the regfile), this stage (for this assignment) must
        // be careful to not write to the regfile if the instruction is a Qat
        // that "should" write-back.
        if (!psr23_halt) begin
            if (psr23_writeBack == 1) begin
                regfile[psr23_wbIndex] <= psr23_wbValue;
            end
        end
    end


    // ---------- Halt Logic ----------

    assign halt = ps0_halt && psr23_halt;


endmodule




// *****************************************************************************
// ********************************* Testbench *********************************
// *****************************************************************************



module Testbench;
    integer i;
    reg reset = 0;
    reg clk = 0;
    wire halted;

    Tangled uut(halted, reset, clk);

    initial begin
        // Initialize regfile
        for (i = 0; i < 16; i = i + 1) begin
            uut.regfile[i] = 0;
        end

        $readmemh(`TEST_TEXT_VMEM, uut.text);
        $readmemh(`TEST_DATA_VMEM, uut.data);
        $dumpfile(`TEST_VCD); //$dumpfile("testing/testCases.vcd");
        $dumpvars(0, uut);

        // Reset to known states before start
        #10 reset = 1;
        #10 reset = 0;

        // Run until the processor is halted
        while (!halted) begin
            #10 clk = 1;
            #10 clk = 0;
        end

        $finish;
    end

endmodule


