const std = @import("std");
const hack = @import("util/hack.zig");

// funcs is an array or tuple of .{ string, fn }
fn validate_backend(comptime BackendT: type, comptime funcs: anytype) void {
    inline for (funcs) |func| {
        if (!hack.has_func(BackendT, func[0], func[1])) {
            @compileError(@typeName(BackendT) ++ " is missing function '" ++
                func[0] ++ "' with signature " ++ @typeName(func[1]));
        }
    }
}

pub fn Window(BackendT: type, BackendErrorT: type) type {
    validate_backend(BackendT, .{
        .{ "init", fn () BackendErrorT!BackendT },
        .{ "proc_event", fn (*BackendT) bool },
        .{ "deinit", fn (*BackendT) void },
    });

    return struct {
        backend: BackendT,

        pub fn init() !@This() {
            return @This(){ .backend = try BackendT.init() };
        }

        pub fn deinit(self: *@This()) void {
            self.backend.deinit();
        }

        pub fn proc_event(self: *@This()) bool {
            return self.backend.proc_event();
        }
    };
}
