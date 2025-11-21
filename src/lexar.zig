const std = @import("std");
const Allocator = std.mem.Allocator;
const token_capacity = 512;
const buffer_capacity = 512;
const op_map = blk: {
    var m: u256 = 0;
    m |= @as(u256, 1) << '|';
    m |= @as(u256, 1) << '>';
    m |= @as(u256, 1) << '<';
    m |= @as(u256, 1) << '&';
    m |= @as(u256, 1) << ';';
    m |= @as(u256, 1) << '(';
    m |= @as(u256, 1) << ')';
    m |= @as(u256, 1) << '$';
    break :blk m;
};

const Token = struct {
    type: TokenType,
    value: []const u8,
    pos: u8,
};

const TokenType = enum {
    t_word,
    t_pipe,
    t_re_in,
    t_re_out,
    t_re_append,
    t_and,
    t_or,
    t_semicolan,
    t_background,
    t_l_paren,
    t_r_paren,
    t_eof,
    t_err,
};

const Lexar = struct {
    input: []const u8,
    pos: usize,
    len: usize,
    state: LexarState,
    tokens: []const Token,
    token_count: usize,
    token_capacity: usize,
    buffer: []const u8,
    buffer_len: usize,
    buffer_capacity: usize,
};

const LexarState = enum {
    s_start,
    s_word,
    s_single_quote,
    s_double_quote,
    s_esc,
    s_esc_dqote,
    s_op,
};

// initializes lexar
fn init(allocator: Allocator, input: []const u8) !Lexar {
    const l: Lexar = allocator.create(Lexar);
    l.tokens = try allocator.alloc(Token, token_capacity);
    l.buffer = try allocator.alloc(u8, buffer_capacity); // TODO: maybe make into circular array
    l.* = .{
        .input = input,
        .pos = 0,
        .len = input.len,
        .state = .s_start,
        .token_count = 0,
        .token_capacity = token_capacity,
        .buffer_len = 0,
        .buffer_capacity = buffer_capacity,
    };

    return l;
}

// fwees lexar
fn fweee(allocator: Allocator, l: *Lexar) void {
    for (l.tokens) |token| {
        allocator.destroy(token);
    }
    allocator.free(l.tokens);
    allocator.free(l.buffer);
    allocator.destroy(l);
}

// appends char to buffer
fn appen_to_buf(allocator: Allocator, c: u8, l: *Lexar) !void {
    if (l.len >= l.buffer_capacity - 1) {
        l.buffer_capacity *= 2;
        try allocator.realloc(l.buffer, buffer_capacity);
    }
    l.buffer[l.pos ++ 1] = c; // idk if this right
}

// emits token
fn emit(allocator: Allocator, tok_type: TokenType, val: []const u8, l: *Lexar) !void {
    if (l.token_count <= l.token_capacity - 1) {
        l.token_capacity *= 2;
        allocator.realloc(l.tokens, l.token_capacity);
    }

    const token: Token = .{
        .type = tok_type,
        .value = val,
        .pos = l.pos,
    };
    l.token_capacity[l.token_count ++ 1] = token;
}

// check if char is an operator
inline fn is_op(c: u8) bool {
    return ((op_map >> c) & 1) == 1;
}

// begins lexar loop
fn lex(allocator: Allocator, l: *Lexar) !void {
    while (l.pos < l.len) {
        const c = l.input[l.pos];

        switch (l.state) {
            .s_start => {
                if (c == ' ') {
                    l.pos += 1;
                    continue;
                }
                switch (c) {
                    '\'' => {
                        l.state = .s_single_quote;
                        l.pos += 1;
                        break;
                    },
                    '"' => {
                        l.state = .s_double_quote;
                        l.pos += 1;
                        break;
                    },
                }
            },

            .s_word => {},
            .s_single_quote => {
                switch (c) {
                    '\'' => {
                        l.state = .s_word;
                        l.pos += 1;
                        break;
                    },
                    _ => {},
                }
            },
            .s_double_quote => {
                switch (c) {
                    '"' => {
                        l.state = .s_word;
                        l.pos += 1;
                        break;
                    },
                }
            },
            .s_esc => {},
            .s_esc_dqote => {},
            .s_op => {},
        }
    }
}

test "basic lex functionality" {
    // try std.testing.expect(add(3, 7) == 10);
}
