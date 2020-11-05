


`include "ALU.v"



// Generic Tangled word size
`define WORD_SIZE           [15:0]

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

// Define instruction operand sizes
`define IR_ALU_OP_SIZE      [3:0]
`define IR_QX_SIZE          [7:0]



module processor (
    output reg halt,
    input wire reset,
    input wire clk
);

    // Handle async reset logic
    always @(posedge reset) begin
        halt <= 0;
        // TODO
    end


    // ---------- Pipeline Stage 0 - Load ----------

    reg `WORD_SIZE text `IMEM_SIZE;         // Instruction memory
    reg `IMEM_INDEX_SIZE pc;                // Program counter
    wire `WORD_SIZE ir;
    assign ir = text[pc];

    // Stage 0-to-1 Registers
    reg `WORD_SIZE psr01_ir;

    // Determines if an instruction is 2-words in length
    function is2WordFrmt;
        input wire `FA_SIZE fA
        input wire `FB_SIZE fB;
        is2WordFrmt = (fA == `FA_FIELD_F1to4) && (fB == `FB_FIELD_F3);
    endfunction

    always @(posedge clk) begin
        if (~halt) begin
            pc <= pc + ((is2WordFrmt(ir `FA_FIELD, ir `FB_FIELD)) ? 2 : 1); // TODO: branch & jump
        end

        psr01_ir <= ir;
    end


    // ---------- Pipeline Stage 1 - Decode ----------

    reg `WORD_SIZE regfile `REGFILE_SIZE;   // Register File

    // Stage 1-to-2 Registers
    reg `REGFILE_INDEX_SIZE psr12_rdIndex;
    reg `REGFILE_INDEX_SIZE psr12_rsIndex;
    reg `WORD_SIZE psr12_rdValue;
    reg `WORD_SIZE psr12_rsValue;
    reg `IR_ALU_OP_SIZE psr12_aluOp;
    reg psr12_memWrite;                     // Memory write flag
    reg psr12_writeBack;                    // Write-back to regfile flag
    reg `WB_SOURCE_SIZE psr12_wbSource;     // Write-back source
    reg `IR_QX_SIZE psr12_qaIndex;
    // TODO: qbIndex, qcIndex, qatOp?

    function isStore;
        input wire `WORD_SIZE instr;
        isMemWrite =    (instr `FA_FIELD == `FA_FIELD_F1to4) &&
                        (instr `FB_FIELD == `FB_FIELD_F1) &&
                        (instr `F1_OPA_FIELD == `F1_OPA_FIELD_OPB) &&
                        (instr `F1_OPB_STORE);
    endfunction

    function isLoad;
        input wire `WORD_SIZE instr;
        isLoad =        (instr `FA_FIELD == `FA_FIELD_F1to4) &&
                        (instr `FB_FIELD == `FB_FIELD_F1) &&
                        (instr `F1_OPA_FIELD == `F1_OPA_FIELD_OPB) &&
                        (instr `F1_OPB_LOAD);
    endfunction

    function isLex;
        input wire `WORD_SIZE instr;
        isLex =         (instr `FA_FIELD == `FA_FIELD_F0) &&
                        ({instr `F0_OP_FIELD_HIGH, instr `F0_OP_FIELD_LOW} == `F0_OP_LEX);
    endfunction

    function isLhi;
        input wire `WORD_SIZE instr;
        isLhi =         (instr `FA_FIELD == `FA_FIELD_F0) &&
                        ({instr `F0_OP_FIELD_HIGH, instr `F0_OP_FIELD_LOW} == `F0_OP_LHI);
    endfunction

    function isWriteBack;
        input wire `WORD_SIZE instr;
        reg `F0_OP_SIZE f0Op;
        begin 
            f0Op = {instr `F0_OP_FIELD_HIGH, instr `F0_OP_FIELD_LOW};

            case (ir `FA_FIELD)
                `FA_FIELD_F0: isWriteBack = (f0Op == F0_OP_LEX) ||
                                            (f0Op == F0_OP_LHI) ||
                                            (f0Op == F0_OP_MEAS) ||
                                            (f0Op == F0_OP_NEXT);
                `FA_FIELD_F1 to4:
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

    always @(posedge clk) begin
        psr12_rdIndex <= psr01_ir `IR_RD_FIELD;
        psr12_rsIndex <= psr01_ir `IR_RS_FIELD;
        psr12_rdValue <=    isLex(psr01_ir) ? {8{psr01_ir `IR_IMM8_MSB_FIELD}, psr01_ir `IR_IMM8_FIELD} :
                            regfile[psr01_ir `IR_RD_FIELD] & ((isLhi(psr01_ir) ? psr01_ir `IR_IMM8_FIELD : 0'hFF) << 8);
        psr12_rsValue <= regfile[psr01_ir `IR_RS_FIELD];
        psr12_aluOp <= psr01_ir `IR_ALU_OP_FIELD;
        psr12_memWrite <= isStore(psr01_ir);
        psr12_writeBack <= isWriteBack(psr01_ir);
        psr12_wbSource <= isLoad(psr01_ir);
        psr12_qaIndex <= psr01_ir `IR_QA_FIELD;
        // TODO: qbIndex, qcIndex, qatOp?
    end


    // ---------- Pipeline Stage 2 - Execute ----------

    reg `WORD_SIZE data `DMEM_SIZE;         // Data memory

    // Stage 2-to-3 Registers
    reg psr23_writeBack;                    // Write-back to regfile flag
    reg `REGFILE_INDEX_SIZE psr23_wbIndex;
    reg `WORD_SIZE psr23_wbValue;

    // Handle value-forwarding 
    wire `WORD_SIZE ps2_rdValue;
    assign ps2_rdValue = psr23_writeBack && (psr12_rdIndex == psr23_wbIndex) ? psr23_wbValue;
    wire `WORD_SIZE ps2_rsValue;
    assign ps2_rsValue = psr23_writeBack && (psr12_rsIndex == psr23_rdIndex) ? psr23_wbValue;

    // Instantiate the ALU
    wire `WORD_SIZE aluOut;
    ALU alu(.out(aluOut), .op(psr12_aluOp), .a(ps2_rdValue), .b(ps2_rsValue));

    always @(posedge clk) begin
        psr23_writeBack <= psr12_writeBack;
        psr23_wbIndex <= psr12_rdIndex;
        psr23_wbValue <= (psr12_wbSource == 1) ? data[psr12_rdIndex] : aluOut;
    end


    // ---------- Pipeline Stage 3 - Write-back ----------

    always @(posedge clk) begin
        if (psr23_writeBack == 1) begin
            regfile[psr23_wbIndex] <= psr23_wbValue;
        end
    end


endmodule

// -----------------------------------------------
// TEST BENCH
// -----------------------------------------------
module testbench;
reg reset = 0;
reg clk = 0;
wire halted;
processor PE(halted, reset, clk);
initial begin
  $readmemh("testAssembly.text", PE.text);
  $readmemh("testAssembly.data", PE.data);
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
