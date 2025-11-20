const std = @import("std");
const Allocator = std.mem.Allocator;
const token_capacity = 512;
const buffer_capacity = 512;

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

const Token = struct {
    type: TokenType,
    value: []const u8,
    pos: u8,
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

fn init(allocator: Allocator, input: []const u8) !Lexar {
    const l: Lexar = allocator.create(Lexar);
    l.tokens = try allocator.alloc(Token, token_capacity);
    l.buffer = try allocator.alloc(u8, buffer_capacity);
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

fn fweee(allocator: Allocator, l: *Lexar) void {
    for (l.tokens) |token| {
        allocator.destroy(token);
    }
    allocator.free(l.tokens);
    allocator.free(l.buffer);
    allocator.destroy(l);
}

fn lex(allocator: Allocator, l: *Lexar) void {
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
