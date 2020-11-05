// Floating point Verilog modules for CPE480
// Created February 19, 2019 by Henry Dietz, http://aggregate.org/hankd
// Distributed under CC BY 4.0, https://creativecommons.org/licenses/by/4.0/



// Fields
`define INT_SIZE signed [15:0]      // integer size
`define FLOAT_SIZE      [15:0]      // half-precision float size

// Fields
`define FSIGN_FIELD     [15]        // sign bit
`define FEXP_FIELD      [14:7]      // exponent
`define FFRAC_FIELD     [6:0]       // fractional part (leading 1 implied)

// Constants
`define FZERO           16'b0       // float 0
`define F32767          16'h46ff    // closest approx to 32767, actually 32640
`define F32768          16'hc700    // -32768
`define FNAN            16'hffc0    // Floating point Not-a-Number
`define INAN            16'h8000    // Integer value for float-to-int from NaN

// Masks
`define FSIGN_M         16'h8000    // Floating point sign bit mask



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


