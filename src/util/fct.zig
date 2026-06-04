const std = @import("std");
const hack = @import("hack.zig");

fn MapTypeComptime(comptime f: anytype, comptime xs: anytype) type {
    switch (@typeInfo(@TypeOf(xs))) {
        .array => return [xs.len]@TypeOf(f(xs[0])),
        .@"struct" => {
            const fields = std.meta.fields(@TypeOf(xs));
            var types: [fields.len]type = undefined;
            inline for (fields, 0..) |field, i| {
                types[i] = @TypeOf(f(@field(xs, field.name)));
            }
            return @Tuple(&types);
        },
        else => @compileError("mapping over type " ++ @typeName(@TypeOf(xs)) ++
            " is not supported"),
    }
}

// returns always an array base! unlike its brother above
fn MapTypeForXsType(comptime f: anytype, comptime XsType: type) type {
    return [
        switch (@typeInfo(XsType)) {
            .array => |a| a.len,
            .@"struct" => std.meta.fields(XsType).len,
            else => @compileError("mapping for type " ++ @typeName(XsType) ++
                " is not supported"),
        }
    ](@typeInfo(@TypeOf(f)).@"fn".return_type orelse
        @compileError("expected a function type for the mapping function. " ++
            "Probably returing a comptime-evaluated type. " ++
            "Use comptime_map instead."));
}

// this is for a function f, that has a comptime-evaluated return type.
// - through this, f can return different types for different xs
// - for xs as array, it returns [_]f(xs[0])
// - for xs as a tuple, it constructs a tuple out of everything f returns
//     for every element in xs
pub fn map_comptimef(
    comptime f: anytype,
    comptime xs: anytype,
) MapTypeComptime(f, xs) {
    var ys: MapTypeComptime(f, xs) = undefined;
    inline for (xs, 0..) |x, i| ys[i] = f(x);
    return ys;
}

// this is for a function f with fixed, non-comptime return type
// - it is same for all xs, so it just returns [_]ReturnType
pub fn map(
    comptime inl: bool,
    comptime f: anytype,
    xs: anytype,
) MapTypeForXsType(f, @TypeOf(xs)) {
    var ys: MapTypeForXsType(f, @TypeOf(xs)) = undefined;
    if (inl) {
        inline for (xs, 0..) |x, i| ys[i] = f(x);
    } else {
        for (xs, 0..) |x, i| ys[i] = f(x);
    }
    return ys;
}

fn ElemTypeInHomogSeq(comptime Seq: type) type {
    return switch (@typeInfo(Seq)) {
        .array => |a| a.child,
        .@"struct" => std.meta.fields(Seq)[0].type, // same type asserted above
        else => @compileError("unsupported container type: " ++ @typeName(Seq)),
    };
}

// We assume here, that XsType is either []SomeStructType, or
//   .{SomeStructType, SomeStructType, ...} (tuple of struct), where all the
//   struct types are the same.
fn MapTypeForField(
    comptime XsType: type,
    comptime fieldenumval: std.meta.FieldEnum(ElemTypeInHomogSeq(XsType)),
) type {
    const len = switch (@typeInfo(XsType)) {
        .array => |a| a.len,
        .@"struct" => std.meta.fields(XsType).len,
        else => @compileError("mapping for type " ++ @typeName(XsType) ++
            " is not supported"),
    };

    // somehow @TypeOf(@field(..)) is not working here; manual way:
    inline for (std.meta.fields(ElemTypeInHomogSeq(XsType))) |field| {
        if (std.mem.eql(u8, field.name, @tagName(fieldenumval))) {
            return [len]field.type;
        }
    }
    unreachable; // field name must be found since we have the enum value
}

fn map_forfield(
    xs: anytype, // can be runtime :D
    comptime field: std.meta.FieldEnum(ElemTypeInHomogSeq(@TypeOf(xs))),
) MapTypeForField(@TypeOf(xs), field) {
    var ys: MapTypeForField(@TypeOf(xs), field) = undefined;
    inline for (xs, 0..) |x, i| ys[i] = @field(x, @tagName(field));
    return ys;
}

////////////////////////////////////////////////////////////////////////////////

test "map_comptimef" {
    // for array
    {
        const to_array = struct {
            fn f(x: anytype) [1]@TypeOf(x) {
                return .{x};
            }
        }.f;
        const xs = [_]i32{42};
        const ys = map_comptimef(to_array, xs); // Check: map should not work.
        try std.testing.expect(@TypeOf(ys) == [1][1]i32);
        try std.testing.expectEqualSlices(i32, &[_]i32{42}, &ys[0]);
    }

    // for differently typed elements in a tuple
    {
        const to_array = struct {
            fn f(x: anytype) [1]@TypeOf(x) {
                return .{x};
            }
        }.f;
        const xs = .{ @as(i32, 42), @as(f32, 3.14) };
        const ys = map_comptimef(to_array, xs);
        try std.testing.expect(@TypeOf(ys) == struct { [1]i32, [1]f32 });
        try std.testing.expectEqualSlices(i32, &[_]i32{42}, &ys[0]);
        try std.testing.expectEqualSlices(f32, &[_]f32{3.14}, &ys[1]);
    }
}

test "map, comptime map" {
    const double = struct {
        fn f(x: i32) i32 {
            return x * 2;
        }
    }.f;

    // map (inline and no inline): const array at runtime?
    {
        const xs = [_]i32{ 10, 20, 30 };
        const ys = map(true, double, xs);
        const zs = map(false, double, xs);
        try std.testing.expectEqualSlices(i32, &[_]i32{ 20, 40, 60 }, &ys);
        try std.testing.expectEqualSlices(i32, &[_]i32{ 20, 40, 60 }, &zs);
    }

    // map (inline and no inline): var array at runtime?
    {
        var later_mut_xs = [_]i32{ 10, 20, 30 };
        const ys = map(true, double, later_mut_xs);
        try std.testing.expectEqualSlices(i32, &[_]i32{ 20, 40, 60 }, &ys);
        later_mut_xs[1] = 99; // meaningless; for compiler warning

        var xs = [_]i32{ 1, 2, 3 };
        xs[1] = 99;
        const zs = map(false, double, xs);
        try std.testing.expectEqualSlices(i32, &[_]i32{ 2, 198, 6 }, &zs);
    }

    // map: array with comptime-known values
    {
        const xs = [_]i32{ 1, 2, 3 };
        const ys = comptime map(true, double, xs);
        try std.testing.expectEqualSlices(i32, &[_]i32{ 2, 4, 6 }, &ys);
    }

    // map: tuple with comptime-known values (homogeneous)
    {
        const xs = .{ @as(i32, 1), @as(i32, 2), @as(i32, 3) };
        const ys = comptime map(true, double, xs);
        try std.testing.expectEqualSlices(i32, &[_]i32{ 2, 4, 6 }, &ys);
    }

    // map: tuple with heterogeneous types, for comptime-const and runtime var
    {
        const to_f32 = struct {
            fn f(x: anytype) f32 {
                return @floatFromInt(x);
            }
        }.f;
        const xs = .{ @as(i32, 1), @as(u8, 2), @as(i64, 3) };
        // here we must inline map since xs is heterogeneous
        const ys = comptime map(true, to_f32, xs);
        // comptime is not needed tho. e.g.
        var ys2 = map(true, to_f32, xs);
        // mutate ys2 for compiler warning only
        ys2[0] += 1.0;
        // attention! since this map is not comptimef, it has a function that
        //   returns the same type for all xs, so its not { f32, f32, f32 },
        //   but [3]f32
        try std.testing.expect(@TypeOf(ys) == [3]f32);
        try std.testing.expectEqual(@as(f32, 1.0), ys[0]);
        try std.testing.expectEqual(@as(f32, 2.0), ys[1]);
        try std.testing.expectEqual(@as(f32, 3.0), ys[2]);

        try std.testing.expect(@TypeOf(ys2) == [3]f32);
        try std.testing.expectEqual(@as(f32, 2.0), ys2[0]); // mutated val
        try std.testing.expectEqual(@as(f32, 2.0), ys2[1]);
        try std.testing.expectEqual(@as(f32, 3.0), ys2[2]);
    }
}

test "map_forfield" {

    // for xs as tuple
    {
        const Inner = struct { a: i32, b: f64 };
        const Outer = .{
            Inner{ .a = 1, .b = 2.0 },
            Inner{ .a = 3, .b = 4.0 },
        };
        const ys_a = map_forfield(Outer, .a);
        const ys_b = map_forfield(Outer, .b);
        try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 3 }, &ys_a);
        try std.testing.expectEqualSlices(f64, &[_]f64{ 2.0, 4.0 }, &ys_b);
    }

    // for xs as array
    {
        const Inner = struct { a: i32, b: f64 };
        const Outer = [_]Inner{
            Inner{ .a = 1, .b = 2.0 },
            Inner{ .a = 3, .b = 4.0 },
        };
        const ys_a = map_forfield(Outer, .a);
        const ys_b = map_forfield(Outer, .b);
        try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 3 }, &ys_a);
        try std.testing.expectEqualSlices(f64, &[_]f64{ 2.0, 4.0 }, &ys_b);
    }
}
