const std = @import("std");
const Allocator = std.mem.Allocator;
const token_capacity = 512;
const buffer_capacity = 512;
const op_map = blk: {
    var m: u256 = 0;
    m |= @as(u256, 1) << '|'; // 124
    m |= @as(u256, 1) << '>';
    m |= @as(u256, 1) << '<';
    m |= @as(u256, 1) << ';';
    m |= @as(u256, 1) << '(';
    m |= @as(u256, 1) << ')';
    m |= @as(u256, 1) << '&';
    break :blk m;
};
const esc_map = blk: {
    var m: 256 = 0;
    m |= @as(u256, 1) << '\n';
    m |= @as(u256, 1) << '$';
    m |= @as(u256, 1) << '\'';
    m |= @as(u256, 1) << '"';
    m |= @as(u256, 1) << '`';
    break :blk m;
};

const fd_map = blk: {
    var m: 256 = 0;
    m |= @as(u256, 1) << '0';
    m |= @as(u256, 1) << '1';
    m |= @as(u256, 1) << '2';
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
    t_re_out, // >
    t_re_app, // >>
    t_re_out_and_err, // &>, >&
    t_re_err_out, // 2>
    t_re_err_app, // 2>>
    t_re_err_to_out, // 2>&1
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
fn append_to_buf(allocator: Allocator, c: u8, l: *Lexar) !void {
    if (l.len >= l.buffer_capacity - 1) {
        l.buffer_capacity *= 2;
        try allocator.realloc(l.buffer, buffer_capacity);
    }
    l.buffer[l.pos ++ 1] = c; // idk if this right
}

// emits token
fn emit_token(allocator: Allocator, tok_type: TokenType, l: *Lexar) !void {
    if (l.token_count <= l.token_capacity - 1) {
        l.token_capacity *= 2;
        try allocator.realloc(l.tokens, l.token_capacity);
    }

    const token: Token = .{
        .type = tok_type,
        .value = l.buffer,
        .pos = l.pos,
    };
    l.token_capacity[l.token_count ++ 1] = token;
}

// emits buffer
fn emit_buf(allocator: Allocator, tok_type: TokenType, l: *Lexar) void {
    l.buffer[l.buffer_len] = null;
    emit_token(allocator, tok_type, l);
    l.buffer_len = 0;
}

// check if char is an operator
inline fn is_op(c: u8) bool {
    return ((op_map >> c) & 1) == 1;
}

// check if char is is an escape char
inline fn is_esc(c: u8) bool {
    return ((esc_map >> c) & 1) == 1;
}

//
inline fn is_fd(c: u8) bool {
    return ((esc_map >> c) & 1) == 1;
}

// begins lexar loop
fn lex(allocator: Allocator, l: *Lexar) !void {
    while (l.pos < l.len) {
        const c = l.input[l.pos];
        const ahead = l.input[l.pos + 1];

        switch (l.state) {
            .s_start => {
                if (c == ' ') {
                    l.pos += 1;
                    continue;
                }

                const redir = -1;

                if (is_fd(c)) {
                    var future = l.pos + 1;
                    while (future < l.len and is_fd(l.input[future])) {
                        future += 1;
                    }

                    if (l.pos + 1 < l.len and (ahead == '<' or ahead == '>')) {
                        redir = 0;
                    }
                }

                switch (c) {
                    ' ' => {
                        l.pos += 1;
                        continue;
                    },
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
                    '|' => {
                        switch (c) {
                            (ahead < l.len and ahead == '|') => {
                                emit_token(allocator, .t_or, l);
                                l.pos += 2;
                                break;
                            },
                            _ => {
                                emit_token(allocator, .t_pipe, l);
                                l.pos += 1;
                                break;
                            },
                        }
                        break;
                    },
                    '&' => {
                        switch (c) {
                            (ahead < l.len and ahead == '&') => {
                                emit_token(allocator, .t_and, l);
                                l.pos += 2;
                                break;
                            },
                            (ahead < l.len and ahead == '>') => {
                                emit_token(allocator, .t_re_out_and_err, l);
                                l.pos += 2;
                                break;
                            },
                            _ => {
                                emit_token(allocator, .t_background, l);
                                l.pos += 1;
                                break;
                            },
                        }
                        break;
                    },
                    ';' => {
                        emit_token(allocator, .t_semicolan, l);
                        l.pos += 1;
                        break;
                    },
                    '(' => {
                        emit_token(allocator, .t_semicolan, l);
                        l.pos += 1;
                        break;
                    },
                    ')' => {
                        emit_token(allocator, .t_semicolan, l);
                        l.pos += 1;
                        break;
                    },
                    '<' => {
                        emit_token(allocator, .t_re_in, l);
                        l.pos += 1;
                        break;
                    },
                    '>' => {
                        switch (c) {
                            (ahead < l.len and ahead == '<') => {
                                emit_token(allocator, .t_re_app, l);
                                l.pos += 1;
                                break;
                            },
                            (ahead < l.len and ahead == '&') => {
                                emit_token(allocator, .t_re_out_and_err, l);
                                l.pos += 2;
                                break;
                            },
                            _ => {
                                emit_token(allocator, .t_re_out, l);
                                l.pos += 1;
                                break;
                            },
                        }
                        break;
                    },
                    // todo: stderr redirects
                    // // 2>
                    // // 2>>
                    // // 2>&1
                    // 2>&1
                    '2' => {
                        switch (c) {
                            (ahead < l.len and ahead == '>') => {
                                switch (c) {
                                    (l.pos + 2 < l.len and l.input[l.pos + 2] == '>') => {
                                        emit_token(allocator, .t_re_err_app, l);
                                        l.pos += 2;
                                        break;
                                    },
                                    (l.pos + 2 < l.len and l.input[l.pos + 2] == '>') => {
                                        emit_token(allocator, .t_re_err_app, l);
                                        l.pos += 2;
                                        break;
                                    },
                                    _ => {
                                        emit_token(allocator, .t_re_err_out, l);
                                        l.pos += 1;
                                        break;
                                    },
                                }
                            },
                        }
                        break;
                    },
                }
                break;
            },

            .s_word => {
                switch (c) {
                    (' ' || is_op(c)) => {
                        emit_buf(allocator, .t_word, l);
                        l.state = .s_start;
                        break;
                    },
                    '\\' => {
                        l.state = .s_esc;
                        l.pos += 1;
                        break;
                    },
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
                    _ => {
                        append_to_buf(allocator, c, l);
                        l.pos += 1;
                        break;
                    },
                }
                break;
            },
            .s_single_quote => {
                switch (c) {
                    '\'' => {
                        l.state = .s_word;
                        l.pos += 1;
                        break;
                    },
                    _ => {
                        append_to_buf(allocator, c, l);
                        l.pos += 1;
                        break;
                    },
                }
                break;
            },
            .s_double_quote => {
                switch (c) {
                    '"' => {
                        l.state = .s_word;
                        l.pos += 1;
                        break;
                    },
                    '\\' => {
                        l.state = .s_esc_dqote;
                        l.pos += 1;
                        break;
                    },
                    _ => {
                        append_to_buf(allocator, c, l);
                        l.pos += 1;
                        break;
                    },
                }
                break;
            },
            .s_esc => {
                switch (c) {
                    is_esc(c) => append_to_buf(allocator, c, l),
                    _ => {
                        append_to_buf(allocator, '\\', l);
                        append_to_buf(allocator, c, l);
                    },
                }
                l.pos += 1;
                l.state = .s_double_quote;
                break;
            },
            .s_esc_dqote => {
                break;
            },
            .s_op => {
                break;
            },
        }
    }
}

test "basic lex functionality" {
    // try std.testing.expect(add(3, 7) == 10);
}
