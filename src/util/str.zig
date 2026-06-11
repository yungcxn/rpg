const std = @import("std");

// str.zig: yet another string helper

pub fn any_eq(a: anytype, b: anytype) bool {
    const anystr_to_slice = struct {
        fn f(x: anytype) ?[]const u8 {
            const T = @TypeOf(x);
            const info = @typeInfo(T);
            return switch (T) {
                [*c]const u8 => blk: {
                    const p = x orelse return null;
                    break :blk std.mem.span(@as([*:0]const u8, @ptrCast(p)));
                },
                [*:0]const u8 => std.mem.span(x),
                []const u8, []u8 => x,
                else => switch (info) {
                    // [N]u8 or [N:0]u8  (array values)
                    .array => |arr| blk: {
                        if (arr.child != u8)
                            @compileError("Unsupported array element type: " ++
                                @typeName(arr.child));
                        break :blk std.mem.sliceTo(&x, 0); // stop at first null byte
                    },
                    // *const [N]u8, *const [N:0]u8, *[N]u8, *[N:0]u8
                    .pointer => |ptr| blk: {
                        if (ptr.size != .one) @compileError("Unsupported pointer type: " ++ @typeName(T));
                        const child = @typeInfo(ptr.child);
                        if (child != .array) @compileError("Unsupported pointer child type: " ++ @typeName(T));
                        if (child.array.child != u8) @compileError("Unsupported array element type: " ++ @typeName(T));
                        break :blk std.mem.sliceTo(x, 0); // no & here, x is already a pointer
                    },
                    else => @compileError("Unsupported type for anystring_eq: " ++ @typeName(T)),
                },
            };
        }
    }.f;

    const slice_a = anystr_to_slice(a) orelse return false;
    const slice_b = anystr_to_slice(b) orelse return false;
    return std.mem.eql(u8, slice_a, slice_b);
}
