// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
// HAEC FFI integration tests
//
// These exercise the public ABI surface through its opaque handle rather than
// duplicating the implementation's private state layout.

const std = @import("std");

const Handle = opaque {};
const Result = enum(c_int) {
    ok = 0,
    @"error" = 1,
    invalid_param = 2,
    busy = 3,
};

extern fn haec_init() ?*Handle;
extern fn haec_free(?*Handle) void;
extern fn haec_process(?*Handle, u32) Result;
extern fn haec_get_string(?*Handle) ?[*:0]const u8;
extern fn haec_free_string(?[*:0]const u8) void;
extern fn haec_process_array(?*Handle, ?[*]const u8, u32) Result;
extern fn haec_last_error() ?[*:0]const u8;
extern fn haec_version() [*:0]const u8;
extern fn haec_build_info() [*:0]const u8;
extern fn haec_is_initialized(?*Handle) u32;

test "lifecycle creates an initialized opaque handle" {
    const handle = haec_init() orelse return error.InitFailed;
    defer haec_free(handle);

    try std.testing.expectEqual(@as(u32, 1), haec_is_initialized(handle));
}

test "process accepts a valid handle and rejects a null handle" {
    const handle = haec_init() orelse return error.InitFailed;
    defer haec_free(handle);

    try std.testing.expectEqual(Result.ok, haec_process(handle, 42));
    try std.testing.expectEqual(Result.invalid_param, haec_process(null, 42));

    const message = haec_last_error() orelse return error.MissingError;
    defer haec_free_string(message);
    try std.testing.expectEqualStrings("Null handle", std.mem.span(message));
}

test "array processing validates pointers" {
    const handle = haec_init() orelse return error.InitFailed;
    defer haec_free(handle);

    const input = [_]u8{ 1, 2, 3, 4 };
    try std.testing.expectEqual(
        Result.ok,
        haec_process_array(handle, input[0..].ptr, input.len),
    );
    try std.testing.expectEqual(
        Result.invalid_param,
        haec_process_array(handle, null, 0),
    );
}

test "allocated strings cross the public boundary" {
    const handle = haec_init() orelse return error.InitFailed;
    defer haec_free(handle);

    const result = haec_get_string(handle) orelse return error.MissingString;
    defer haec_free_string(result);
    try std.testing.expectEqualStrings("Example result", std.mem.span(result));
}

test "version and build information are non-empty" {
    try std.testing.expectEqualStrings("0.1.0", std.mem.span(haec_version()));
    try std.testing.expect(std.mem.span(haec_build_info()).len > 0);
}
