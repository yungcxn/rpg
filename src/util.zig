const std = @import("std");
const hack = @import("hack.zig");

pub fn comptime_assert(comptime cond: bool, comptime msg: []const u8) void {
    if (!cond) @compileError(msg);
}

pub const fct = struct {
    fn MapTypeComptime(comptime f: anytype, comptime xs: anytype) type {
        switch (@typeInfo(@TypeOf(xs))) {
            .array => return [xs.len]@TypeOf(f(xs[0])),
            .@"struct" => {
                var fields = std.meta.fields(@TypeOf(xs));
                var types: [fields.len]type = undefined;
                inline for (fields, 0..) |field, i| {
                    types[i] = @TypeOf(f(@field(xs, field.name)));
                }
                return @Tuple(&types);
            },
            else => @compileError("mapping over type " ++ @typeName(@TypeOf(xs)) ++ " is not supported"),
        }
    }

    fn MapTypeForXsType(comptime f: anytype, comptime XsType: type) type {
        return [
            switch (@typeInfo(XsType)) {
                .array => |a| a.len,
                .@"struct" => std.meta.fields(XsType).len,
                else => @compileError("mapping for type " ++ @typeName(XsType) ++ " is not supported"),
            }
        ](@typeInfo(@TypeOf(f)).@"fn".return_type orelse @compileError("expected a function type for the mapping function"));
    }

    fn comptime_map(comptime f: anytype, comptime xs: anytype) MapTypeComptime(f, xs) {
        var ys: MapTypeComptime(f, xs) = undefined;
        inline for (xs, 0..) |x, i| ys[i] = f(x);
        return ys;
    }

    fn map(comptime inl: bool, comptime f: anytype, xs: anytype) MapTypeForXsType(f, @TypeOf(xs)) {
        var ys: MapTypeForXsType(f, @TypeOf(xs)) = undefined;
        if (inl) {
            inline for (xs, 0..) |x, i| ys[i] = f(x);
        } else {
            for (xs, 0..) |x, i| ys[i] = f(x);
        }
        return ys;
    }
};

pub fn dprint(value: anytype) void {
    const T = @TypeOf(value);

    switch (@typeInfo(T)) {
        .int, .comptime_int => std.debug.print("{x}\n", .{value}),
        else => std.debug.print("{s}\n", .{value}),
    }
}

pub fn errprint(err: anytype) void {
    std.debug.print("error: {s}\n", .{@errorName(err)});
}

pub fn str_eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

test "fct.map and fct.comptime_map" {
    const double = struct {
        fn f(x: i32) i32 {
            return x * 2;
        }
    }.f;

    // comptime_map: array with comptime-known values
    {
        const xs = [_]i32{ 1, 2, 3 };
        const ys = fct.comptime_map(double, xs);
        try std.testing.expectEqualSlices(i32, &[_]i32{ 2, 4, 6 }, &ys);
    }

    // comptime_map: tuple with comptime-known values (homogeneous)
    {
        const xs = .{ @as(i32, 1), @as(i32, 2), @as(i32, 3) };
        const ys = fct.comptime_map(double, xs);
        try std.testing.expectEqualSlices(i32, &[_]i32{ 2, 4, 6 }, &ys);
    }

    // comptime_map: tuple with heterogeneous types
    {
        const to_f32 = struct {
            fn f(x: anytype) f32 {
                return @floatFromInt(x);
            }
        }.f;
        const xs = .{ @as(i32, 1), @as(u8, 2), @as(i64, 3) };
        const ys = fct.comptime_map(to_f32, xs);
        try std.testing.expect(@TypeOf(ys) == @TypeOf(.{ @as(f32, 0), @as(f32, 0), @as(f32, 0) }));
        try std.testing.expectEqual(@as(f32, 1.0), ys[0]);
        try std.testing.expectEqual(@as(f32, 2.0), ys[1]);
        try std.testing.expectEqual(@as(f32, 3.0), ys[2]);
    }

    // map (no inline): const array, runtime xs
    {
        const xs = [_]i32{ 10, 20, 30 };
        const ys = fct.map(false, double, xs);
        try std.testing.expectEqualSlices(i32, &[_]i32{ 20, 40, 60 }, &ys);
    }

    // map (no inline): var array, mutated before mapping
    {
        var xs = [_]i32{ 1, 2, 3 };
        xs[1] = 99;
        const ys = fct.map(false, double, xs);
        try std.testing.expectEqualSlices(i32, &[_]i32{ 2, 198, 6 }, &ys);
    }

    // map (inline): const array
    {
        const xs = [_]i32{ 5, 6, 7 };
        const ys = fct.map(true, double, xs);
        try std.testing.expectEqualSlices(i32, &[_]i32{ 10, 12, 14 }, &ys);
    }

    // map (inline): var array
    {
        var xs = [_]i32{ 3, 4, 5 };
        xs[0] = 0;
        const ys = fct.map(true, double, xs);
        try std.testing.expectEqualSlices(i32, &[_]i32{ 0, 8, 10 }, &ys);
    }

    // return type correctness: map produces [N]ReturnType
    {
        const xs = [_]i32{ 1, 2 };
        const ys = fct.map(false, double, xs);
        try std.testing.expect(@TypeOf(ys) == [2]i32);
    }

    // return type correctness: comptime_map on array
    {
        const xs = [_]i32{ 1, 2, 3 };
        const ys = fct.comptime_map(double, xs);
        try std.testing.expect(@TypeOf(ys) == [3]i32);
    }
}
