// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
// HAEC FFI Implementation
//
// This module implements the C-compatible FFI declared in src/interface/Abi/Foreign.idr
// All types and layouts must match the Idris2 ABI definitions.
//

const std = @import("std");

// Version information (keep in sync with project)
const VERSION = "0.1.0";
const BUILD_INFO = "HAEC built with Zig " ++ @import("builtin").zig_version_string;

/// Thread-local error storage
threadlocal var last_error: ?[]const u8 = null;

/// Set the last error message
fn setError(msg: []const u8) void {
    last_error = msg;
}

/// Clear the last error
fn clearError() void {
    last_error = null;
}

//==============================================================================
// Core Types (must match src/abi/Types.idr)
//==============================================================================

/// Result codes (must match Idris2 Result type)
pub const Result = enum(c_int) {
    ok = 0,
    @"error" = 1,
    invalid_param = 2,
    busy = 3,
};

/// Public C handle. Its representation is deliberately opaque to callers.
pub const Handle = opaque {};

/// Private state stored behind the opaque C handle.
const HandleState = struct {
    allocator: std.mem.Allocator,
    initialized: bool,
};

fn stateFromHandle(handle: *Handle) *HandleState {
    return @ptrCast(@alignCast(handle));
}

//==============================================================================
// Library Lifecycle
//==============================================================================

/// Initialize the library
/// Returns a handle, or null on failure
pub export fn haec_init() ?*Handle {
    const allocator = std.heap.c_allocator;

    const state = allocator.create(HandleState) catch {
        setError("Failed to allocate handle");
        return null;
    };

    state.* = .{
        .allocator = allocator,
        .initialized = true,
    };

    clearError();
    return @ptrCast(state);
}

/// Free the library handle
pub export fn haec_free(handle: ?*Handle) void {
    const opaque_handle = handle orelse return;
    const state = stateFromHandle(opaque_handle);
    const allocator = state.allocator;

    // Clean up resources
    state.initialized = false;

    allocator.destroy(state);
    clearError();
}

//==============================================================================
// Core Operations
//==============================================================================

/// Process data (example operation)
pub export fn haec_process(handle: ?*Handle, input: u32) Result {
    const opaque_handle = handle orelse {
        setError("Null handle");
        return .invalid_param;
    };
    const state = stateFromHandle(opaque_handle);

    if (!state.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    // Example processing logic
    _ = input;

    clearError();
    return .ok;
}

//==============================================================================
// String Operations
//==============================================================================

/// Get a string result (example)
/// Caller must free the returned string
pub export fn haec_get_string(handle: ?*Handle) ?[*:0]const u8 {
    const opaque_handle = handle orelse {
        setError("Null handle");
        return null;
    };
    const state = stateFromHandle(opaque_handle);

    if (!state.initialized) {
        setError("Handle not initialized");
        return null;
    }

    // Example: allocate and return a string
    const result = state.allocator.dupeZ(u8, "Example result") catch {
        setError("Failed to allocate string");
        return null;
    };

    clearError();
    return result.ptr;
}

/// Free a string allocated by the library
pub export fn haec_free_string(str: ?[*:0]const u8) void {
    const s = str orelse return;
    const allocator = std.heap.c_allocator;

    const slice = std.mem.span(s);
    allocator.free(slice);
}

//==============================================================================
// Array/Buffer Operations
//==============================================================================

/// Process an array of data
pub export fn haec_process_array(
    handle: ?*Handle,
    buffer: ?[*]const u8,
    len: u32,
) Result {
    const opaque_handle = handle orelse {
        setError("Null handle");
        return .invalid_param;
    };
    const state = stateFromHandle(opaque_handle);

    const buf = buffer orelse {
        setError("Null buffer");
        return .invalid_param;
    };

    if (!state.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    // Access the buffer
    const data = buf[0..len];
    _ = data;

    // Process data here

    clearError();
    return .ok;
}

//==============================================================================
// Error Handling
//==============================================================================

/// Get the last error message
/// Returns null if no error. Free a non-null result with haec_free_string.
pub export fn haec_last_error() ?[*:0]const u8 {
    const err = last_error orelse return null;

    // Return caller-owned C storage; release it with haec_free_string.
    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

//==============================================================================
// Version Information
//==============================================================================

/// Get the library version
pub export fn haec_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information
pub export fn haec_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

//==============================================================================
// Callback Support
//==============================================================================

/// Callback function type (C ABI)
pub const Callback = *const fn (u64, u32) callconv(.c) u32;

/// Register a callback
pub export fn haec_register_callback(
    handle: ?*Handle,
    callback: ?Callback,
) Result {
    const opaque_handle = handle orelse {
        setError("Null handle");
        return .invalid_param;
    };
    const state = stateFromHandle(opaque_handle);

    const cb = callback orelse {
        setError("Null callback");
        return .invalid_param;
    };

    if (!state.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    // Store callback for later use
    _ = cb;

    clearError();
    return .ok;
}

//==============================================================================
// Utility Functions
//==============================================================================

/// Check if handle is initialized
pub export fn haec_is_initialized(handle: ?*Handle) u32 {
    const opaque_handle = handle orelse return 0;
    const state = stateFromHandle(opaque_handle);
    return if (state.initialized) 1 else 0;
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle" {
    const handle = haec_init() orelse return error.InitFailed;
    defer haec_free(handle);

    try std.testing.expect(haec_is_initialized(handle) == 1);
}

test "error handling" {
    const result = haec_process(null, 0);
    try std.testing.expectEqual(Result.invalid_param, result);

    const err = haec_last_error() orelse return error.MissingError;
    defer haec_free_string(err);
    try std.testing.expectEqualStrings("Null handle", std.mem.span(err));
}

test "version" {
    const ver = haec_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}
