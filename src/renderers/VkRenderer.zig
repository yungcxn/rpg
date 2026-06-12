const c = @import("c_vk_glfw");
const std = @import("std");
const builtin = @import("builtin");
const vk_util = @import("vk/util.zig");
const alloc = std.heap.page_allocator; // TODO: better allocator

const phys_device_id: u32 = 0; // TODO: better device selection
const enable_validation_layers: bool = builtin.mode == .Debug;
const validation_layers = [_][*c]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const extensions =
    (if (builtin.os.tag == .macos) [_][*c]const u8{
        c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,
    } else [0][*c]const u8{}) ++
    (if (enable_validation_layers) [_][*c]const u8{
        c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME,
    } else [0][*c]const u8{});

const device_extensions =
    (if (builtin.os.tag == .macos) [_][*c]const u8{
        "VK_KHR_portability_subset", // required by moltenvk on macos
    } else [0][*c]const u8{}) ++
    [_][*c]const u8{
        c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
    };

const app = "RPG";

window: *c.GLFWwindow,
vk_instance: c.VkInstance,
debug_messenger: c.VkDebugUtilsMessengerEXT, // only for debug
phys_device: c.VkPhysicalDevice,
qf_idx: u32,
device: c.VkDevice, // gpu device *handle*
queue: c.VkQueue,
// TODO: surface and swapchain are next !

pub const Error = error{
    OOMError,
    VkInitError,
    WindowSetupError,
    RenderError,
    ValidationLayerSupportError,
    DebugMessengerSetupError,
    NoGPUFound,
    PhysDeviceSelectionError,
    DeviceCreationError,
    QueueFamilyIdxNotFound,
    QueueInitError,
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

fn init_queue(dev: c.VkDevice, qf_idx: u32) Error!c.VkQueue {
    var queue: c.VkQueue = null;
    c.vkGetDeviceQueue(dev, qf_idx, 0, &queue);
    if (queue == null) return Error.QueueInitError;
    return queue;
}

fn init_device(physdevice: c.VkPhysicalDevice, qf_idx: u32) Error!c.VkDevice {
    const qfprio: f32 = 1.0;
    const queue_create_info = c.VkDeviceQueueCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = qf_idx,
        .queueCount = 1,
        .pQueuePriorities = &qfprio,
    };

    var vk10f = c.VkPhysicalDeviceFeatures{
        .samplerAnisotropy = c.VK_TRUE,
    };
    var vk12f = c.VkPhysicalDeviceVulkan12Features{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        .descriptorIndexing = c.VK_TRUE,
        .shaderSampledImageArrayNonUniformIndexing = c.VK_TRUE,
        .descriptorBindingVariableDescriptorCount = c.VK_TRUE,
        .runtimeDescriptorArray = c.VK_TRUE,
        .bufferDeviceAddress = c.VK_TRUE,
    };
    var vk13f = c.VkPhysicalDeviceVulkan13Features{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        .pNext = &vk12f,
        .synchronization2 = c.VK_TRUE,
        .dynamicRendering = c.VK_TRUE,
    };

    var dev_create_info = c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = &vk13f, // through pNext the features are chained together.
        .queueCreateInfoCount = 1,
        .pQueueCreateInfos = &queue_create_info,
        .enabledExtensionCount = @intCast(device_extensions.len),
        .ppEnabledExtensionNames = &device_extensions,
        .pEnabledFeatures = &vk10f,
    };

    var new_dev: c.VkDevice = undefined;

    if (c.vkCreateDevice(
        physdevice,
        &dev_create_info,
        null,
        &new_dev,
    ) != c.VK_SUCCESS) return Error.DeviceCreationError;

    return new_dev;
}

// TODO: should search device by feature support
fn init_phys_device(instance: c.VkInstance) Error!c.VkPhysicalDevice {
    const physdevice = vk_util.get_physdevice(
        alloc,
        instance,
        phys_device_id,
    ) catch return Error.PhysDeviceSelectionError;

    if (physdevice == null) return Error.NoGPUFound;

    if (comptime builtin.mode == .Debug) { // print physdev info only
        var dev_props = c.VkPhysicalDeviceProperties2{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,
        };
        c.vkGetPhysicalDeviceProperties2(physdevice, &dev_props);
        std.log.debug(
            "Using physical device: {s}",
            .{dev_props.properties.deviceName},
        );
    }

    return physdevice;
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
    var self = @This(){
        .window = try init_window(),
        .vk_instance = try init_vk_instance(),
        .phys_device = null,
        .qf_idx = 0,
        .device = null,
        .queue = null,
        .debug_messenger = null,
    };

    self.phys_device = try init_phys_device(self.vk_instance);

    self.qf_idx = (vk_util.find_qf_idx(
        alloc,
        self.phys_device,
        self.vk_instance,
    ) catch return Error.OOMError) orelse return Error.QueueFamilyIdxNotFound;

    self.device = try init_device(self.phys_device, self.qf_idx);
    self.queue = try init_queue(self.device, self.qf_idx);

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

    c.vkDestroyDevice(self.device, null);
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
