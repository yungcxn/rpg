const std = @import("std");
const hack = @import("util/hack.zig");

// all implementations
const VKRenderer = @import("renderers/VkRenderer.zig");

// chosen implementation
const BackendT: type = VKRenderer;
const BackendErrorT: type = VKRenderer.Error;

backend: BackendT,

// funcs is an array or tuple of .{ string, fn }
fn validate_backend(comptime funcs: anytype) void {
    inline for (funcs) |func| {
        if (!hack.has_func(BackendT, func[0], func[1])) {
            @compileError(@typeName(BackendT) ++ " is missing function '" ++
                func[0] ++ "' with signature " ++ @typeName(func[1]));
        }
    }
}

pub fn init() !@This() {
    comptime {
        validate_backend(.{
            .{ "init", fn () BackendErrorT!BackendT },
            .{ "render", fn (*BackendT) bool },
            .{ "deinit", fn (*BackendT) void },
        });
    }

    return @This(){ .backend = try BackendT.init() };
}

pub fn deinit(self: *@This()) void {
    self.backend.deinit();
}

pub fn render(self: *@This()) bool {
    return self.backend.render();
}
