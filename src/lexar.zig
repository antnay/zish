const std = @import("std");
const Allocator = std.mem.Allocator;
// const un256 = std.meta.Int(.unsigned, 256);
const token_capacity = 512;
const buffer_capacity = 512;

const op_map = blk: {
    var m: u256 = 0;
    m |= @as(u256, 1) << '|';
    m |= @as(u256, 1) << '>';
    m |= @as(u256, 1) << '<';
    m |= @as(u256, 1) << ';';
    m |= @as(u256, 1) << '(';
    m |= @as(u256, 1) << ')';
    m |= @as(u256, 1) << '&';
    break :blk m;
};
const esc_map = blk: {
    var m: u256 = 0;
    m |= @as(u256, 1) << '\n';
    m |= @as(u256, 1) << '$';
    m |= @as(u256, 1) << '\'';
    m |= @as(u256, 1) << '"';
    m |= @as(u256, 1) << '`';
    break :blk m;
};

const fd_map = blk: {
    var m: u256 = 0;
    m |= @as(u256, 1) << '0';
    m |= @as(u256, 1) << '1';
    m |= @as(u256, 1) << '2';
    break :blk m;
};

const Token = struct {
    type: TokenType,
    value: []const u8,
    pos: usize,
    src_redir: i8,
    des_redir: i8,
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
    tokens: []Token,
    token_count: usize,
    token_capacity: usize,
    buffer: []u8,
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
    s_redir,
};

// initializes lexar
fn init(allocator: Allocator, input: []const u8) !*Lexar {
    const l = try allocator.create(Lexar);
    l.* = .{
        .tokens = try allocator.alloc(Token, token_capacity),
        .buffer = try allocator.alloc(u8, buffer_capacity), // TODO: maybe make into circular array
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
    // for (l.tokens) |token| {
    //     allocator.destroy(token);
    // }
    allocator.free(l.tokens);
    allocator.free(l.buffer);
    allocator.destroy(l);
}

// appends char to buffer
fn append_to_buf(allocator: Allocator, c: u8, l: *Lexar) !void {
    if (l.len >= l.buffer_capacity - 1) {
        l.buffer_capacity *= 2;
        l.buffer = try allocator.realloc(l.buffer, l.buffer_capacity);
    }
    l.pos += 1;
    l.buffer[l.pos] = c;
}

// emits token
fn emit_token(allocator: Allocator, tok_type: TokenType, l: *Lexar) !void {
    std.debug.print("emitting token\n", .{});
    if (l.token_count <= l.token_capacity - 1) {
        l.token_capacity *= 2;
        l.tokens = try allocator.realloc(l.tokens, l.token_capacity);
    }

    const token: Token = .{
        .type = tok_type,
        .value = l.buffer,
        .pos = l.pos,
        .src_redir = -1,
        .des_redir = -1,
    };
    l.token_count += 1;
    l.tokens[l.token_count] = token;
}

// emits token during redirection
fn emit_token_redir(allocator: Allocator, tok_type: TokenType, src: u8, des: u8, l: *Lexar) !void {
    if (l.token_count <= l.token_capacity - 1) {
        l.token_capacity *= 2;
        l.tokens = try allocator.realloc(l.tokens, l.token_capacity);
    }

    const token: Token = .{
        .type = tok_type,
        .value = l.buffer,
        .pos = l.pos,
        .src_redir = src,
        .des_redir = des,
    };
    l.token_count += 1;
    l.tokens[l.token_count] = token;
}

// emits buffer
fn emit_buf(allocator: Allocator, tok_type: TokenType, l: *Lexar) !void {
    try emit_token(allocator, tok_type, l);
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
        var c = l.input[l.pos];

        switch (l.state) {
            .s_start => {
                if (c == ' ') {
                    l.pos += 1;
                    continue;
                }

                var redir: i16 = -1;

                // loop if c in {0,1,2} for redirects
                if (is_fd(c)) {
                    var future = l.pos + 1;
                    while (future < l.len and is_fd(l.input[future])) {
                        future += 1;
                    }

                    if (l.pos + 1 < l.len and (l.input[future] == '<' or l.input[future] == '>')) {
                        redir = 0;
                        while (l.pos < future) {
                            redir = redir * 10 + (l.input[l.pos] - '0');
                            l.pos += 1;
                        }
                    }

                    l.state = .s_redir;
                    c = l.input[l.pos];
                } else {
                    l.state = .s_word;
                    try append_to_buf(allocator, c, l);
                    l.pos += 1;
                    break;
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
                        if (l.input[l.pos + 1] < l.len and l.input[l.pos + 1] == '|') {
                            try emit_token(allocator, .t_or, l);
                            l.pos += 2;
                            break;
                        } else {
                            try emit_token(allocator, .t_pipe, l);
                            l.pos += 1;
                            break;
                        }
                        break;
                    },
                    '&' => {
                        if (l.input[l.pos + 1] < l.len and l.input[l.pos + 1] == '&') {
                            try emit_token(allocator, .t_and, l);
                            l.pos += 2;
                            break;
                        } else if (l.input[l.pos + 1] < l.len and l.input[l.pos + 1] == '>') {
                            try emit_token(allocator, .t_re_out_and_err, l);
                            l.pos += 2;
                            break;
                        } else {
                            try emit_token(allocator, .t_background, l);
                            l.pos += 1;
                            break;
                        }
                        break;
                    },
                    ';' => {
                        try emit_token(allocator, .t_semicolan, l);
                        l.pos += 1;
                        break;
                    },
                    '(' => {
                        try emit_token(allocator, .t_semicolan, l);
                        l.pos += 1;
                        break;
                    },
                    ')' => {
                        try emit_token(allocator, .t_semicolan, l);
                        l.pos += 1;
                        break;
                    },
                    '<' => {
                        if (redir > -1) {}
                        try emit_token(allocator, .t_re_in, l);
                        l.pos += 1;
                        break;
                    },
                    '>' => {
                        if (l.input[l.pos + 1] < l.len and l.input[l.pos + 1] == '<') {
                            try emit_token(allocator, .t_re_app, l);
                            l.pos += 1;
                            break;
                        } else if (l.input[l.pos + 1] < l.len and l.input[l.pos + 1] == '&') {
                            try emit_token(allocator, .t_re_out_and_err, l);
                            l.pos += 2;
                            break;
                        } else {
                            try emit_token(allocator, .t_re_out, l);
                            l.pos += 1;
                            break;
                        }
                        break;
                    },
                    '2' => {
                        if (l.input[l.pos + 1] < l.len and l.input[l.pos + 1] == '>') {
                            if (l.pos + 2 < l.len and l.input[l.pos + 2] == '>') {
                                try emit_token(allocator, .t_re_err_app, l);
                                l.pos += 2;
                                break;
                            } else if (l.pos + 2 < l.len and l.input[l.pos + 2] == '>') {
                                try emit_token(allocator, .t_re_err_app, l);
                                l.pos += 2;
                                break;
                            } else {
                                try emit_token(allocator, .t_re_err_out, l);
                                l.pos += 1;
                                break;
                            }
                        }
                    },
                    else => break,
                }
            },
            .s_word => {
                if (is_op(c) or c == ' ') {
                    try emit_buf(allocator, .t_word, l);
                    l.state = .s_start;
                    break;
                }
                switch (c) {
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
                    else => {
                        try append_to_buf(allocator, c, l);
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
                    else => {
                        try append_to_buf(allocator, c, l);
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
                    else => {
                        try append_to_buf(allocator, c, l);
                        l.pos += 1;
                        break;
                    },
                }
                break;
            },
            .s_esc => {
                if (is_esc(c)) {
                    try append_to_buf(allocator, c, l);
                } else {
                    try append_to_buf(allocator, '\\', l);
                    try append_to_buf(allocator, c, l);
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
            .s_redir => {
                break;
            },
        }
    }
}

test "basic lex functionality" {
    const cases: [1][]const u8 = .{
        "cd foo/",
        // "ls | grep -i \"bar\"",
        // "find . > foo.txt",
        // "ls >> foo.txt",
        // "grep bar < bar.md",
        // "command 2>&1",
        // "command 2>error.log",
        // "command >output.txt 2>&1",
        // "command &>all.log",
        // "command 2>&1 | grep foo",
        // "command 3>&2",
        // "command 2>&-",
        // "command 1>&2 2>&1",
        // "command >>file 2>&1",
    };

    for (cases) |case| {
        const a = std.testing.allocator;
        const l = try init(a, case);
        defer fweee(a, l);
        try lex(a, l);

        for (l.tokens) |t| {
            std.debug.print("{s}\n", .{t.value});
        }
        std.debug.print("\n", .{});
    }
}
