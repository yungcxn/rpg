const c = @import("c_vk_glfw");
const std = @import("std");
const builtin = @import("builtin");
const allocator = std.heap.page_allocator; // TODO: better allocator

const enable_validation_layers: bool = builtin.mode == .Debug;
const validation_layers = [_][*c]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const app = "RPG";

window: *c.GLFWwindow,
vk_instance: c.VkInstance,

pub const Error = error{
    OOMError,
    VkInitError,
    WindowSetupError,
    RenderError,
    ValidationLayerSupportError,
};

// helper; will be moved out of here when used by another module
fn anystring_eq(a: anytype, b: anytype) bool {
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

// fn setup_debug_messenger() void {
//     if (!enable_validation_layers) return;
//     const dbg_create_info = c.VkDebugUtilsMessengerCreateInfoEXT{
//         .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
//         .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT |
//             c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
//             c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
//         .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
//             c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
//             c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
//         .pfnUserCallback = c.debugCallback,
//         .pUserData = null, // Optional
//     };
// }

fn check_validation_layer_support() Error!bool {
    var layers: c_uint = undefined;
    _ = c.vkEnumerateInstanceLayerProperties(&layers, null);

    const available_layers: []c.VkLayerProperties = allocator.alloc(
        c.VkLayerProperties,
        layers,
    ) catch {
        return Error.OOMError;
    };
    defer allocator.free(available_layers);

    _ = c.vkEnumerateInstanceLayerProperties(&layers, available_layers.ptr);

    for (validation_layers) |layer_name| {
        var layer_found = false;

        for (available_layers) |layer_properties| {
            if (anystring_eq(layer_name, layer_properties.layerName)) {
                layer_found = true;
                break;
            }
        }

        if (!layer_found) {
            return false;
        }
    }

    return true;
}

fn init_window() Error!*c.GLFWwindow {
    _ = c.glfwInit();
    _ = c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    _ = c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);

    const window = c.glfwCreateWindow(500, 500, app, null, null) orelse
        return Error.WindowSetupError;

    return window;
}

fn init_vk_instance() Error!c.VkInstance {
    if (enable_validation_layers and !(try check_validation_layer_support())) {
        return Error.ValidationLayerSupportError;
    }

    const app_info: c.VkApplicationInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = app,
        .applicationVersion = c.VK_MAKE_VERSION(0, 1, 0),
        .pEngineName = "No Engine",
        .engineVersion = c.VK_MAKE_VERSION(0, 1, 0),
        .apiVersion = c.VK_API_VERSION_1_0,
    };

    var glfw_extension_count: u32 = 0;
    const glfw_extensions = c.glfwGetRequiredInstanceExtensions(&glfw_extension_count);

    var create_info: c.VkInstanceCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = glfw_extension_count,
        .ppEnabledExtensionNames = glfw_extensions,
        .enabledLayerCount = if (enable_validation_layers) @as(u32, validation_layers.len) else 0,
        .ppEnabledLayerNames = if (enable_validation_layers) &validation_layers else null,
    };

    var instance: c.VkInstance = undefined;

    // in macos, we cannot directly create the instance, therefore fix:
    var required_extensions = std.ArrayList([*c]const u8).empty;
    defer required_extensions.deinit(allocator);
    if (builtin.os.tag == .macos) {
        for (0..glfw_extension_count) |i| {
            required_extensions.append(allocator, glfw_extensions[i]) catch {
                std.log.err("Failed to append required extension name", .{});
                return Error.OOMError;
            };
        }
        required_extensions.append(
            allocator,
            c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,
        ) catch {
            std.log.err("Failed to append portability enumeration extension name", .{});
            return Error.OOMError;
        };

        create_info.enabledExtensionCount = @intCast(required_extensions.items.len);
        create_info.ppEnabledExtensionNames = required_extensions.items.ptr;
        create_info.flags |= c.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    }

    const ret = c.vkCreateInstance(&create_info, null, &instance);
    if (ret != c.VK_SUCCESS) {
        std.log.err("Failed to create Vulkan instance ({})", .{ret});
        return Error.VkInitError;
    }

    return instance;
}

pub fn init() Error!@This() {
    return @This(){
        .window = try init_window(),
        .vk_instance = try init_vk_instance(),
    };
}

pub fn deinit(self: *@This()) void {
    c.vkDestroyInstance(self.vk_instance, null);
    c.glfwDestroyWindow(self.window);
    c.glfwTerminate();
}

// must catch all errors, since this is a subtrait of Renderer.render
// and error union return is expensive for every loop it.
pub fn render(self: *@This()) bool {
    if (c.glfwWindowShouldClose(self.window) == 0) {
        c.glfwPollEvents();
    }
    return true;
}
