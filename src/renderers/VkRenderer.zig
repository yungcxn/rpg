const c = @import("c_vk_glfw");
const std = @import("std");
const alloc = std.heap.page_allocator; // TODO: better allocator
const builtin = @import("builtin");
const vk_util = @import("vk/util.zig");
const QueueFamilyIds = vk_util.QueueFamilyIds;
const FeaturedDeviceCreateInfo = vk_util.FeaturedDeviceCreateInfo;
const SwapChainHelpers = vk_util.SwapChainHelpers;
const hack = @import("../util/hack.zig");

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
swap_chain: c.VkSwapchainKHR = null,

pub const Error = error{
    OOMError,
    VkInitError,
    WindowSetupError,
    RenderError,
    ValidationLayerSupportError,
    DebugMessengerSetupError,
    NoGPUFound,
    PhysDeviceSelectionError,
    FeaturedDeviceCreateInfoInitError,
    DeviceCreationError,
    QueueInitError,
    SurfaceInitError,
    QueueFamilyIdxNotFound,
    SwapChainCreationError,
};

fn init_swap_chain(
    support_details: SwapChainHelpers.SupportDetails,
    window: ?*c.GLFWwindow,
    surface: c.VkSurfaceKHR,
    qf_ids: QueueFamilyIds,
    device: c.VkDevice,
) !c.VkSwapchainKHR {
    const surface_format: c.VkSurfaceFormatKHR = SwapChainHelpers.choose_swap_surface_format(
        support_details.formats.?,
    );

    const present_mode: c.VkPresentModeKHR = SwapChainHelpers.choose_swap_present_mode(
        support_details.present_modes.?,
    );

    const extent: c.VkExtent2D = SwapChainHelpers.choose_swap_extent(
        support_details.capabilities,
        window,
    );

    var imagec: u32 = support_details.capabilities.minImageCount + 1;
    if (support_details.capabilities.maxImageCount > 0 and
        imagec > support_details.capabilities.maxImageCount)
    {
        imagec = support_details.capabilities.maxImageCount;
    }

    var swap_chain_ci = c.VkSwapchainCreateInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface,
        .minImageCount = imagec,
        .imageFormat = surface_format.format,
        .imageColorSpace = surface_format.colorSpace,
        .imageExtent = extent,
        .imageArrayLayers = 1,
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
    };

    if (qf_ids.graphics != qf_ids.present) {
        swap_chain_ci.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
        swap_chain_ci.queueFamilyIndexCount = 2;
        swap_chain_ci.pQueueFamilyIndices = &[2]u32{
            qf_ids.graphics.?,
            qf_ids.present.?,
        };
    } else {
        swap_chain_ci.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
        swap_chain_ci.queueFamilyIndexCount = 0;
        swap_chain_ci.pQueueFamilyIndices = null;
    }

    swap_chain_ci.preTransform = support_details.capabilities.currentTransform;
    swap_chain_ci.compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    swap_chain_ci.presentMode = present_mode;
    swap_chain_ci.clipped = c.VK_TRUE;
    swap_chain_ci.oldSwapchain = null;

    var swap_chain: c.VkSwapchainKHR = undefined;
    const ret = c.vkCreateSwapchainKHR(device, &swap_chain_ci, null, &swap_chain);
    if (ret != c.VK_SUCCESS) {
        std.log.err("Failed to create swap chain ({})", .{ret});
        return Error.SwapChainCreationError;
    }

    return swap_chain;
}

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
    const fdev_create_info = FeaturedDeviceCreateInfo.init(
        alloc,
        qf_ids,
        device_extensions[0..],
    ) catch {
        return Error.OOMError;
    } orelse return Error.FeaturedDeviceCreateInfoInitError;
    defer FeaturedDeviceCreateInfo.deinit(fdev_create_info, alloc);

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
    var swap_chain_support: SwapChainHelpers.SupportDetails = undefined;

    var qf_ids: QueueFamilyIds = undefined;
    for (physdevices, 0..) |physdevice, i| {
        qf_ids = qf_lists[i];
        const dev_ext_support: bool = vk_util.supports_dev_extensions(
            alloc,
            physdevice,
            device_extensions[0..],
        ) catch return Error.OOMError;

        if (dev_ext_support) {
            swap_chain_support = SwapChainHelpers.SupportDetails.init(
                alloc,
                physdevice,
                self.surface,
            ) catch return Error.OOMError;

            if (qf_ids.complete() and swap_chain_support.adequate()) {
                // now init_device(...) is safe
                self.phys_device = physdevice;
                break;
            }

            swap_chain_support.deinit(alloc);
        }
    }
    defer swap_chain_support.deinit(alloc);

    self.device = try init_device(self.phys_device, qf_ids);

    self.present_q = try init_queue(self.device, qf_ids.present.?);
    self.graphics_q = try init_queue(self.device, qf_ids.graphics.?);

    self.swap_chain = try init_swap_chain(
        swap_chain_support,
        self.window,
        self.surface,
        qf_ids,
        self.device,
    );

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

    c.vkDestroySwapchainKHR(self.device, self.swap_chain, null);
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
