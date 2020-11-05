


`include "Floaty.v"



//ALU OPs
`define ALUOP_SIZE  [3:0]
`define ALUOP_NOT   4'h0
`define ALUOP_FLOAT 4'h1
`define ALUOP_INT   4'h2
`define ALUOP_NEG   4'h3
`define ALUOP_NEGF  4'h4
`define ALUOP_RECIP 4'h5
`define ALUOP_ADD   4'h6
`define ALUOP_MUL   4'h7
`define ALUOP_SLT   4'h8
`define ALUOP_AND   4'h9
`define ALUOP_OR    4'ha
`define ALUOP_SHIFT 4'hb
`define ALUOP_XOR   4'hc
`define ALUOP_ADDF  4'hd
`define ALUOP_MULF  4'he
`define ALUOP_SLTF  4'hf



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


