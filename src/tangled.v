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
    initial $readmemh0(look);
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
    output wire `WORD_SIZE out,
    input wire `ALUOP_SIZE op,
    input wire `WORD_SIZE a,
    input wire `WORD_SIZE b
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
    fneg myfneg(fnegout, a, b);

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
`define WB_SOURCE_VAL       2



module tangled (
    output wire halt,
    input wire reset,
    input wire clk
);
    
    // ---------- Pipeline Stage 0 - Load ----------

    reg `WORD_SIZE text `IMEM_SIZE;         // Instruction memory
    reg `IMEM_INDEX_SIZE pc;                // Program counter

    // Used to determine if current instruction is from PC or a branch/jump
    // (Assigned in Stage 2)
    wire shouldBrJmp;
    wire `WORD_SIZE brJmpTarget;

    // Current cycle's instruction
    wire `WORD_SIZE instr;
    assign instr = text[shouldBrJmp ? brJmpTarget : pc];

    reg ps0_halt;                           // Halts stage 0

    // Handle async reset logic
    always @(posedge reset) begin
        ps0_halt <= 0;
        ps <= 0;
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
            pc <=   pc + (is2WordFrmt(instr) ? 2 : 1);
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
    reg psr12_branchTarget;                 // Target pc if instruction is a branch
    reg psr12_brf;                          // Is bracnh false
    reg psr12_brt;                          // Is branch true
    reg psr12_jumpr;                        // Is jump
    reg psr12_halt;                         // Halts stage 2


    function isStore;
        input `WORD_SIZE instr;
        isMemWrite =    (instr `FA_FIELD == `FA_FIELD_F1to4) &&
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
                        (instr `F1_OPB_JUMPR);
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

            case (ir `FA_FIELD)
                `FA_FIELD_F0: isWriteBack = (f0Op == F0_OP_LEX) ||
                                            (f0Op == F0_OP_LHI) ||
                                            (f0Op == F0_OP_MEAS) ||
                                            (f0Op == F0_OP_NEXT);
                `FA_FIELD_F1to4:
                    case (ir`FB_FIELD)
                        `FB_FIELD_F1: 
                            case (ir`F1_OPA_FIELD)
                                `F1_OPA_FIELD_ALU: isWriteBack = 1;
                                `F1_OPA_FIELD_OPB: isWriteBack =    (ir `F1_OPB_FIELD == `F1_OPB_LOAD) ||
                                                                    (ir `F1_OPB_FIELD == `F1_OPB_COPY);
                            endcase
                        default: isWriteBack = 0;
                    endcase
            endcase
        end
    endfunction

    // Sign extend the 8-bit immediate
    wire `WORD_SIZE sxi;
    assign sxi = {8{psr01_ir `IR_IMM8_MSB_FIELD}, psr01_ir `IR_IMM8_FIELD};

    // Rd value straight from regfile
    wire `WORD_SIZE regfile_rdValue;
    assign regfile_rdValue = regfile[psr01_ir `IR_RD_FIELD];

    always @(posedge clk) begin
        if (!psr01_halt) begin
            psr12_rdIndex <= psr01_ir `IR_RD_FIELD;
            psr12_rsIndex <= psr01_ir `IR_RS_FIELD;
            psr12_rdValue <=    isLex(psr01_ir) ? sxi :
                                {isLhi(psr01_ir) psr01_ir `IR_IMM8_FIELD ? regfile_rdValue `WORD_HIGH_FIELD, regfile_rdValue `WORD_LOW_FIELD};
            psr12_rsValue <= regfile[psr01_ir `IR_RS_FIELD];
            psr12_aluOp <= psr01_ir `IR_ALU_OP_FIELD;
            psr12_memWrite <= isStore(psr01_ir);
            psr12_writeBack <= isWriteBack(psr01_ir);
            psr12_wbSource <=   usesALU(psr01_ir) ? `WB_SOURCE_ALU :
                                isLoad(psr01_ir) ? `WB_SOURCE_MEM : `WB_SOURCE_VAL;
            psr12_branchTarget <= pc + sxi;
        end

        psr12_halt <= psr01_halt;
    end


    // ---------- Pipeline Stage 2 - Execute ----------

    reg `WORD_SIZE data `DMEM_SIZE;         // Data memory
    reg ps2_bubble;                         // Bubbles this stage in next clock cycle

    // Stage 2-to-3 Registers
    reg psr23_writeBack;                    // Write-back to regfile flag
    reg `REGFILE_INDEX_SIZE psr23_wbIndex;
    reg `WORD_SIZE psr23_wbValue;
    reg psr23_bubble;                       // Bubbles stage 3
    reg psr23_halt;                         // Halts stage 3

    // Handle value-forwarding 
    wire `WORD_SIZE ps2_rdValue;
    assign ps2_rdValue = psr23_writeBack && (psr12_rdIndex == psr23_wbIndex) ? psr23_wbValue;
    wire `WORD_SIZE ps2_rsValue;
    assign ps2_rsValue = psr23_writeBack && (psr12_rsIndex == psr23_rdIndex) ? psr23_wbValue;

    // Instantiate the ALU
    wire `WORD_SIZE aluOut;
    ALU alu(.out(aluOut), .op(psr12_aluOp), .x(ps2_rdValue), .y(ps2_rsValue));

    // Determine if a branch/jump should be taken, and if so, the target.
    // (Wires defined in stage 0).
    assign shouldBrJmp =    (psr12_brf && (ps2_rdValue == 0)) ||
                            (psr12_brt && (ps2_rdValue != 0)) ||
                            psr12_jumpr;
    assign brJmpTarget = psr12_jumpr ? ps2_rdValue : psr12_branchTarget;

    always @(posedge clk) begin
        if (ps2_bubble) begin
            psr23_bubble <= 1;  // Stage 2 is bubbling -> make stage 3 bubble in next clock cycle.
            ps2_bubble <= 0;    // Only bubble for one clock cycle.

        end else begin

            if (!psr12_halt)
                psr23_writeBack <= psr12_writeBack;
                psr23_wbIndex <= psr12_rdIndex;
                
                case (psr12_wbSource)
                    `WB_SOURCE_ALU: psr23_wbValue <= aluOut;
                    `WB_SOURCE_MEM: psr23_wbValue <= data[ps2_rsValue];
                    `WB_SOURCE_VAL: psr23_wbValue <= ps2_rdValue;
                endcase

                if (psr12_memWrite) begin
                    data[ps2_rsValue] <= ps2_rdValue;
                end

                // If a branch or jump is about to be taken, then the instruction in stage 1 is invalid,
                // so stage 2 should bubble in the next clock cycle. 
                ps2_bubble <= shouldBrJmp;
            end

            psr23_bubble <= 0;
            psr23_halt <= psr12_halt;
        end
    end


    // ---------- Pipeline Stage 3 - Write-back ----------

    always @(posedge clk) begin
        if (!psr23_bubble) begin
            // Bubble for a clock cycle

            if (!psr23_halt) begin
                // No bubble or halt, so proceed as normal
                if (psr23_writeBack == 1) begin
                    regfile[psr23_wbIndex] <= psr23_wbValue;
                end
            end
        end
    end


    // ---------- Halt Logic ----------

    assign halt = ps0_halt && psr23_halt;


endmodule


