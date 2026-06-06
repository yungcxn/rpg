const std = @import("std");
const ContainerLayout = std.builtin.Type.ContainerLayout;
const StructField = std.builtin.Type.StructField;
const Endian = std.builtin.Endian;

fn comptime_assert(comptime cond: bool, comptime msg: []const u8) void {
    if (!cond) @compileError(msg);
}

pub fn has_func(
    comptime T: type,
    comptime name: []const u8,
    comptime Fn: type,
) bool {
    if (!@hasDecl(T, name)) return false;
    return @TypeOf(@field(T, name)) == Fn;
}

fn StructFromFields(
    comptime layout: ContainerLayout,
    comptime fields: []const StructField,
) type {
    var names: [fields.len][]const u8 = undefined;
    var types: [fields.len]type = undefined;
    var attrs: [fields.len]StructField.Attributes = undefined;
    inline for (fields, 0..) |field, i| {
        names[i] = field.name;
        types[i] = field.type;
        attrs[i] = .{
            .@"comptime" = field.is_comptime,
            .@"align" = field.alignment,
            .default_value_ptr = field.default_value_ptr,
        };
    }
    return @Struct(layout, null, &names, &types, &attrs);
}

pub fn SubStruct(
    comptime T: type,
    comptime slicestart: ?usize,
    comptime sliceend: ?usize,
    layout: ContainerLayout,
) type {
    const fields = @typeInfo(T).@"struct".fields;
    const s_start = slicestart orelse 0;
    const s_end = sliceend orelse fields.len;

    comptime_assert(s_start <= s_end, "slice start <= slice end");
    comptime_assert(s_end <= fields.len, "slice end <= field count");

    const sliced_f = fields[s_start..s_end];

    return StructFromFields(layout, sliced_f);
}

pub fn PSubStruct(
    comptime T: type,
    comptime slicestart: ?usize,
    comptime sliceend: ?usize,
) type {
    return SubStruct(T, slicestart, sliceend, .@"packed");
}

pub fn ESubStruct(
    comptime T: type,
    comptime slicestart: ?usize,
    comptime sliceend: ?usize,
) type {
    return SubStruct(T, slicestart, sliceend, .@"extern");
}

pub fn StructMix(
    comptime A: type,
    comptime B: type,
    layout: ContainerLayout,
) type {
    const fa = @typeInfo(A).@"struct".fields;
    const fb = @typeInfo(B).@"struct".fields;
    const all = fa ++ fb;

    return StructFromFields(layout, all);
}

pub fn PStructMix(comptime A: type, comptime B: type) type {
    return StructMix(A, B, .@"packed");
}

pub fn EStructMix(comptime A: type, comptime B: type) type {
    return StructMix(A, B, .@"extern");
}

pub fn tupled_init(comptime T: type, args: anytype) T {
    const fields = @typeInfo(T).@"struct".fields;
    const arg_fields = @typeInfo(@TypeOf(args)).@"struct".fields;

    comptime_assert(arg_fields.len <= fields.len, "too many arguments");

    var result: T = undefined;

    inline for (fields) |field| {
        if (field.default_value_ptr != null) {
            const dv: *const field.type = @ptrCast(@alignCast(field.default_value_ptr.?));
            @field(result, field.name) = dv.*;
        }
    }

    comptime var arg_i = 0;
    inline for (fields) |field| {
        if (field.default_value_ptr == null) {
            if (arg_i >= arg_fields.len)
                @compileError("not enough arguments for field '" ++
                    field.name ++ "'");
            @field(result, field.name) = args[arg_i];
            arg_i += 1;
        }
    }

    return result;
}

pub fn PrefFatPtr(comptime L: type, comptime E: type) type {
    return struct {
        pub const is_pref_fat_ptr = true; // for reflection

        len: L,
        ptr: [*]const E,

        pub fn LenType() type {
            return L;
        }
        pub fn ElemType() type {
            return E;
        }

        pub fn slice(self: @This()) []const E {
            return self.ptr[0..self.len];
        }
    };
}

pub fn is_preffatptr(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => @hasDecl(T, "is_pref_fat_ptr"),
        else => false,
    };
}

pub fn complex_parsetostruct(
    cursor: *[]const u8,
    comptime T: type,
    endian: Endian,
) T {
    const inner = struct {
        fn read_next(comptime I: type, sc: *[]const u8, en: Endian) I {
            const readfunc = switch (@typeInfo(I)) {
                .int => std.mem.readInt,
                .float => std.mem.readFloat,
                .bool => std.mem.readInt, // bools are stored as u8
                else => @compileError(
                    "unsupported type for parsing: " ++ @typeName(I),
                ),
            };

            const size = @sizeOf(I);
            comptime var to_read: type = I;
            if (@typeInfo(I) == .bool) {
                to_read = u8;
            }
            const value = readfunc(to_read, sc.*[0..size], en);
            sc.* = sc.*[size..];
            return value;
        }
    };

    var toret: T = undefined;
    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (comptime is_preffatptr(field.type)) {
            const LenT = field.type.LenType();
            const len = inner.read_next(LenT, cursor, endian);
            @field(toret, field.name) = .{
                .len = len,
                .ptr = cursor.ptr,
            };
            cursor.* = cursor.*[len..];
        } else {
            @field(toret, field.name) = inner.read_next(field.type, cursor, endian);
        }
    }
    return toret;
}
