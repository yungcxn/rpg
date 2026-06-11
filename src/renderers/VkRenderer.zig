const c = @import("c_vk_glfw");
const std = @import("std");
const builtin = @import("builtin");
const vk_util = @import("vk/util.zig");
const allocator = std.heap.page_allocator; // TODO: better allocator

const enable_validation_layers: bool = builtin.mode == .Debug;
const validation_layers = [_][*c]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const extensions = [_][*c]const u8{
    if (builtin.os.tag == .macos) c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,
    if (enable_validation_layers) c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME,
};

const app = "RPG";

window: *c.GLFWwindow,
vk_instance: c.VkInstance,
debug_messenger: c.VkDebugUtilsMessengerEXT, // only for debug

pub const Error = error{
    OOMError,
    VkInitError,
    WindowSetupError,
    RenderError,
    ValidationLayerSupportError,
    DebugMessengerSetupError,
};

// should only be called when enable_validation_layers!
fn init_debug_messenger(instance: c.VkInstance) Error!c.VkDebugUtilsMessengerEXT {
    var debug_messenger: c.VkDebugUtilsMessengerEXT = undefined;

    var dbg_create_info: c.VkDebugUtilsMessengerCreateInfoEXT =
        vk_util.get_debug_utils_messenger_create_info();

    const retcode = vk_util.create_debug_utils_messenger_ext(
        instance,
        &dbg_create_info,
        null,
        &debug_messenger,
    );

    if (retcode != c.VK_SUCCESS) {
        std.log.err("Failed to set up debug messenger ({})", .{retcode});
        return Error.DebugMessengerSetupError;
    }

    return debug_messenger;
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
    if (enable_validation_layers) {
        const is_sup: bool = vk_util.check_validation_layer_support(
            allocator,
            validation_layers.len,
            validation_layers,
        ) catch return Error.OOMError;

        if (!is_sup) return Error.ValidationLayerSupportError;
    }

    const app_info: c.VkApplicationInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = app,
        .applicationVersion = c.VK_MAKE_VERSION(0, 1, 0),
        .pEngineName = "No Engine",
        .engineVersion = c.VK_MAKE_VERSION(0, 1, 0),
        .apiVersion = c.VK_API_VERSION_1_0,
    };

    const required_extensions = vk_util.alloc_req_extensions(
        allocator,
        extensions.len,
        extensions,
    ) catch return Error.OOMError;
    defer allocator.free(required_extensions);

    var create_info: c.VkInstanceCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = @intCast(required_extensions.len),
        .ppEnabledExtensionNames = required_extensions.ptr,
    };

    var dbg_create_info: c.VkDebugUtilsMessengerCreateInfoEXT = undefined;

    if (enable_validation_layers) {
        create_info.enabledLayerCount = @intCast(validation_layers.len);
        create_info.ppEnabledLayerNames = &validation_layers;

        dbg_create_info = vk_util.get_debug_utils_messenger_create_info();
        create_info.pNext = &dbg_create_info;
    }

    if (builtin.os.tag == .macos) { // since we added the port. extension
        create_info.flags |= c.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    }

    var instance: c.VkInstance = undefined;
    const ret = c.vkCreateInstance(&create_info, null, &instance);
    if (ret != c.VK_SUCCESS) {
        std.log.err("Failed to create Vulkan instance ({})", .{ret});
        return Error.VkInitError;
    }

    return instance;
}

pub fn init() Error!@This() {
    var self = @This(){
        .window = try init_window(),
        .vk_instance = try init_vk_instance(),
        .debug_messenger = null,
    };

    if (comptime enable_validation_layers) {
        self.debug_messenger = try init_debug_messenger(self.vk_instance);
    }

    return self;
}

pub fn deinit(self: *@This()) void {
    if (comptime enable_validation_layers) {
        vk_util.destroy_debug_utils_messenger_ext(
            self.vk_instance,
            self.debug_messenger,
            null,
        );
    }

    c.vkDestroyInstance(self.vk_instance, null);
    c.glfwDestroyWindow(self.window);
    c.glfwTerminate();
}

// must catch all errors, since this is a "subtrait" of Renderer.render
// and error union return is expensive for every loop it.
pub fn render(self: *@This()) bool {
    if (c.glfwWindowShouldClose(self.window) == 0) {
        c.glfwPollEvents();
    }
    return true;
}
