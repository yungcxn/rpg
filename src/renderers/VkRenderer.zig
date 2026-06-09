const c = @import("c_vk_glfw");
const std = @import("std");
const builtin = @import("builtin");
const allocator = std.heap.page_allocator; // TODO: better allocator

window: *c.GLFWwindow,
vk_instance: c.VkInstance,

const app = "RPG";

pub const Error = error{
    OOMError,
    VkInitError,
    WindowSetupError,
    RenderError,
};

fn init_window() Error!*c.GLFWwindow {
    _ = c.glfwInit();
    _ = c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    _ = c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);

    const window = c.glfwCreateWindow(500, 500, app, null, null) orelse
        return Error.WindowSetupError;

    return window;
}

fn init_vk_instance() Error!c.VkInstance {
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
        .enabledLayerCount = 0,
    };

    var instance: c.VkInstance = undefined;

    // in macos, we cannot directly create the instance, therefore fix:
    var required_extensions: std.ArrayList([*c]const u8) = .empty;
    defer required_extensions.deinit(allocator);
    if (builtin.os.tag == .macos) {
        for (0..glfw_extension_count) |i| {
            if (i < glfw_extension_count) {
                required_extensions.append(allocator, glfw_extensions[i]) catch {
                    std.log.err("Failed to append required extension name", .{});
                    return Error.OOMError;
                };
            }
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
