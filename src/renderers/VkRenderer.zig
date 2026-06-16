const c = @import("c_vk_glfw");
const std = @import("std");
const alloc = std.heap.page_allocator; // TODO: better allocator
const builtin = @import("builtin");

const hack = @import("../util/hack.zig");

const vk_util = @import("vk/util.zig");
const vk_debug = @import("vk/debug.zig");
const QueueFamilyIds = @import("vk/QueueFamilyIds.zig");
const FeatDeviceCreateInfo = @import("vk/FeatDeviceCreateInfo.zig");
const SwapChain = @import("vk/SwapChain.zig");

const enable_validation_layers: bool = builtin.mode == .Debug;

const validation_layers = [_][*c]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const extensions = hack.conditioned_build_arr(
    [*c]const u8,
    .{
        (enable_validation_layers), .{c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME},
        (builtin.os.tag == .macos), .{c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME},
    },
);

const device_extensions = hack.conditioned_build_arr(
    [*c]const u8,
    .{
        (builtin.os.tag == .macos), .{"VK_KHR_portability_subset"},
        (true),                     .{c.VK_KHR_SWAPCHAIN_EXTENSION_NAME},
    },
);

const app = "RPG";

window: ?*c.GLFWwindow = null,
vk_instance: c.VkInstance = null,
debug_messenger: c.VkDebugUtilsMessengerEXT = null, // only for debug
surface: c.VkSurfaceKHR = null,
phys_device: c.VkPhysicalDevice = null,
device: c.VkDevice = null, // gpu device *handle*
present_q: c.VkQueue = null,
graphics_q: c.VkQueue = null,
swap_chain_data: ?SwapChain.Data = null,

pub const Error = error{
    OOMError,
    VkInitError,
    WindowSetupError,
    RenderError,
    ValidationLayerSupportError,
    DebugMessengerSetupError,
    NoGPUFound,
    PhysDeviceSelectionError,
    FeatDeviceCreateInfoInitError,
    DeviceCreationError,
    QueueInitError,
    SurfaceInitError,
    QueueFamilyIdxNotFound,
    SwapChainDataCreationError,
};

fn init_surface(
    vk_instance: c.VkInstance,
    window: ?*c.GLFWwindow,
) Error!c.VkSurfaceKHR {
    var surface: c.VkSurfaceKHR = undefined;
    const ret = c.glfwCreateWindowSurface(vk_instance, window, null, &surface);
    if (ret != c.VK_SUCCESS) {
        std.log.err("Failed to create window surface: {}", .{ret});
        return Error.SurfaceInitError;
    }
    return surface;
}

fn init_queue(dev: c.VkDevice, qf_id: u32) Error!c.VkQueue {
    var queue: c.VkQueue = null;
    c.vkGetDeviceQueue(dev, qf_id, 0, &queue);
    if (queue == null) return Error.QueueInitError;
    return queue;
}

fn init_device(physdevice: c.VkPhysicalDevice, qf_ids: QueueFamilyIds) Error!c.VkDevice {
    const fdev_create_info = FeatDeviceCreateInfo.init(
        alloc,
        qf_ids,
        device_extensions[0..],
    ) catch {
        return Error.OOMError;
    } orelse return Error.FeatDeviceCreateInfoInitError;
    defer FeatDeviceCreateInfo.deinit(fdev_create_info, alloc);

    var new_dev: c.VkDevice = undefined;

    const d_ci = (fdev_create_info.*.dev_create_info);
    if (c.vkCreateDevice(physdevice, &d_ci, null, &new_dev) != c.VK_SUCCESS)
        return Error.DeviceCreationError;

    return new_dev;
}

// should only be called when enable_validation_layers!
fn init_debug_messenger(instance: c.VkInstance) Error!c.VkDebugUtilsMessengerEXT {
    var debug_messenger: c.VkDebugUtilsMessengerEXT = undefined;

    var dbg_create_info: c.VkDebugUtilsMessengerCreateInfoEXT =
        vk_debug.get_debug_utils_messenger_create_info();

    const retcode = vk_debug.create_debug_utils_messenger_ext(
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
        const is_sup: bool = vk_debug.check_validation_layer_support(
            alloc,
            validation_layers.len,
            validation_layers,
        ) catch return Error.OOMError;

        if (!is_sup) return Error.ValidationLayerSupportError;
    }

    const app_info: c.VkApplicationInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = app,
        .apiVersion = c.VK_API_VERSION_1_3,
    };

    const required_extensions = vk_util.alloc_req_extensions(
        alloc,
        extensions.len,
        extensions,
    ) catch return Error.OOMError;
    defer alloc.free(required_extensions);

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

        dbg_create_info = vk_debug.get_debug_utils_messenger_create_info();
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
    var self = @This(){};

    self.window = try init_window();
    self.vk_instance = try init_vk_instance();

    if (comptime enable_validation_layers) {
        self.debug_messenger = try init_debug_messenger(self.vk_instance);
    }

    self.surface = try init_surface(self.vk_instance, self.window);

    const physdevices = vk_util.alloc_physdevice_slice(alloc, self.vk_instance) catch {
        return Error.OOMError;
    };
    defer alloc.free(physdevices);

    const qf_lists = QueueFamilyIds.alloc_qf_slice(alloc, physdevices, self.surface) catch {
        return Error.OOMError;
    };
    defer alloc.free(qf_lists);

    // physical device selection must be based on supporting multiple factors
    // TODO: separate func?
    // these vars need to be found for physdevice
    var swap_chain_support: ?SwapChain.SupportDetails = null;
    var qf_ids: QueueFamilyIds = undefined;
    for (physdevices, 0..) |physdevice, i| {
        qf_ids = qf_lists[i];
        const dev_ext_support: bool = vk_util.supports_dev_extensions(
            alloc,
            physdevice,
            device_extensions[0..],
        ) catch return Error.OOMError;

        if (dev_ext_support) {
            if (swap_chain_support != null) {
                swap_chain_support.?.deinit(alloc);
            }
            swap_chain_support = SwapChain.SupportDetails.init(
                alloc,
                physdevice,
                self.surface,
            ) catch return Error.OOMError;

            if (qf_ids.complete() and swap_chain_support.?.adequate()) {
                // now init_device(...) is safe
                self.phys_device = physdevice;
                break;
            }
        }
    }
    if (self.phys_device == null) return Error.NoGPUFound;

    defer if (swap_chain_support) |*s| s.deinit(alloc);

    self.device = try init_device(self.phys_device, qf_ids);

    self.present_q = try init_queue(self.device, qf_ids.present.?);
    self.graphics_q = try init_queue(self.device, qf_ids.graphics.?);

    self.swap_chain_data = SwapChain.Data.init(
        alloc,
        swap_chain_support.?,
        self.window,
        self.surface,
        qf_ids,
        self.device,
    ) catch return Error.SwapChainDataCreationError;

    return self;
}

pub fn deinit(self: *@This()) void {
    if (comptime enable_validation_layers) {
        vk_debug.destroy_debug_utils_messenger_ext(
            self.vk_instance,
            self.debug_messenger,
            null,
        );
    }

    if (self.swap_chain_data) |*scd| scd.deinit(alloc, self.device);
    c.vkDestroyDevice(self.device, null);
    c.vkDestroySurfaceKHR(self.vk_instance, self.surface, null);
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
