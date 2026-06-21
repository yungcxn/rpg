// this is for every step up until device retrieval

const std = @import("std");
const builtin = @import("builtin");
const hack = @import("../../util/hack.zig");
const c = @import("c_vk_glfw");
const util = @import("util.zig");
const req_vksuc = util.req_vksuc;
const ZVkError = util.ZVkError;
const QueueFamilyIds = @import("QueueFamilyIds.zig");
const SwapChainSupportDetails = @import("SwapChain.zig").SupportDetails;

const enable_validation_layers: bool = builtin.mode == .Debug;
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

window: ?*c.GLFWwindow,
framebuffer_resized: bool = false,
vk_instance: c.VkInstance,
debug_messenger: c.VkDebugUtilsMessengerEXT = null, // only for debug
surface: c.VkSurfaceKHR,
phys_device: c.VkPhysicalDevice,
sc_sup: SwapChainSupportDetails,
qf_ids: QueueFamilyIds,
device: c.VkDevice, // gpu device *handle*

pub fn init(
    alloc: std.mem.Allocator,
    appname: []const u8,
) ZVkError!@This() {
    var self: @This() = undefined;
    self.window = try init_window(appname, &self);
    self.vk_instance = try init_vk_instance(alloc, appname);

    var debug_messenger: c.VkDebugUtilsMessengerEXT = undefined;
    if (comptime enable_validation_layers) {
        debug_messenger = try debug.init_debug_messenger(self.vk_instance);
    } else {
        debug_messenger = null;
    }

    self.surface = try init_surface(self.vk_instance, self.window);
    const physdevices = try alloc_physdevice_slice(alloc, self.vk_instance);
    defer alloc.free(physdevices);

    const qf_lists = try QueueFamilyIds.alloc_qf_slice(alloc, physdevices, self.surface);
    defer alloc.free(qf_lists);

    self.phys_device, self.sc_sup, self.qf_ids = try pick_phys_device_and_props(
        alloc,
        physdevices,
        qf_lists,
        self.surface,
    );

    self.device = try init_device(alloc, self.phys_device, self.qf_ids);

    return self;
}

pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    if (comptime enable_validation_layers) {
        debug.deinit_debug_utils_messenger_ext(
            self.vk_instance,
            self.debug_messenger,
            null,
        );
    }

    c.vkDestroyDevice(self.device, null);
    self.sc_sup.deinit(alloc);
    c.vkDestroySurfaceKHR(self.vk_instance, self.surface, null);
    c.vkDestroyInstance(self.vk_instance, null);
    c.glfwDestroyWindow(self.window);
    c.glfwTerminate();
}

fn supports_dev_extensions(
    alloc: std.mem.Allocator,
    physdevice: c.VkPhysicalDevice,
) ZVkError!bool {
    var extc: u32 = 0;
    try req_vksuc(
        c.vkEnumerateDeviceExtensionProperties(physdevice, null, &extc, null),
    );

    const supported_exts = alloc.alloc(c.VkExtensionProperties, extc) catch
        return ZVkError.ErrorOutOfHostMemory;
    defer alloc.free(supported_exts);

    try req_vksuc(
        c.vkEnumerateDeviceExtensionProperties(physdevice, null, &extc, supported_exts.ptr),
    );

    for (device_extensions) |d| {
        var is_supported = false;
        for (supported_exts) |s| {
            if (std.mem.eql(
                u8,
                std.mem.sliceTo(&s.extensionName, 0),
                std.mem.sliceTo(d, 0),
            )) {
                is_supported = true;
                break;
            }
        }
        if (!is_supported) return false;
    }
    return true;
}

fn alloc_physdevice_slice(
    alloc: std.mem.Allocator,
    instance: c.VkInstance,
) ZVkError![]c.VkPhysicalDevice {
    var devc: u32 = 0;
    try req_vksuc(c.vkEnumeratePhysicalDevices(instance, &devc, null));
    const physdevices = alloc.alloc(c.VkPhysicalDevice, devc) catch
        return ZVkError.ErrorOutOfHostMemory;
    try req_vksuc(
        c.vkEnumeratePhysicalDevices(instance, &devc, physdevices.ptr),
    );
    return physdevices;
}

fn alloc_req_extensions(
    alloc: std.mem.Allocator,
) ZVkError![][*c]const u8 {
    var count: u32 = 0;
    const glfw_exts = c.glfwGetRequiredInstanceExtensions(&count)[0..count];

    const all_exts: [][*c]const u8 = alloc.alloc(
        [*c]const u8,
        glfw_exts.len + extensions.len,
    ) catch return ZVkError.ErrorOutOfHostMemory;

    @memcpy(all_exts[0..glfw_exts.len], glfw_exts);
    @memcpy(all_exts[glfw_exts.len..], &extensions);

    return all_exts;
}

fn init_surface(
    vk_instance: c.VkInstance,
    window: ?*c.GLFWwindow,
) ZVkError!c.VkSurfaceKHR {
    var surface: c.VkSurfaceKHR = undefined;
    try req_vksuc(c.glfwCreateWindowSurface(vk_instance, window, null, &surface));
    return surface;
}

fn init_queue(dev: c.VkDevice, qf_id: u32) ZVkError!c.VkQueue {
    var queue: c.VkQueue = null;
    c.vkGetDeviceQueue(dev, qf_id, 0, &queue);
    if (queue == null) return ZVkError.ErrorInitializationFailed;
    return queue;
}

fn init_device(alloc: std.mem.Allocator, physdevice: c.VkPhysicalDevice, qf_ids: QueueFamilyIds) ZVkError!c.VkDevice {
    const fdev_create_info = FeatDeviceCreateInfo.init(
        alloc,
        qf_ids,
    ) catch return ZVkError.ErrorInitializationFailed;
    defer FeatDeviceCreateInfo.deinit(fdev_create_info, alloc);

    var new_dev: c.VkDevice = undefined;

    const d_ci = (fdev_create_info.*.dev_create_info);
    try req_vksuc(c.vkCreateDevice(physdevice, &d_ci, null, &new_dev));
    return new_dev;
}

fn init_window(appname: []const u8, thisref: ?*anyopaque) ZVkError!*c.GLFWwindow {
    _ = c.glfwInit();
    _ = c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    _ = c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_TRUE);

    const window = c.glfwCreateWindow(500, 500, appname.ptr, null, null) orelse
        return ZVkError.ErrorInitializationFailed;

    c.glfwSetWindowUserPointer(window, thisref);
    _ = c.glfwSetFramebufferSizeCallback(window, framebuffer_resize_callback);

    return window;
}

fn framebuffer_resize_callback(
    window: ?*c.GLFWwindow,
    width: c_int,
    height: c_int,
) callconv(.c) void {
    _ = width;
    _ = height;
    const thisref: *@This() = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(window)));
    thisref.framebuffer_resized = true;
}

fn init_vk_instance(
    alloc: std.mem.Allocator,
    appname: []const u8,
) ZVkError!c.VkInstance {
    if (enable_validation_layers) {
        const is_sup: bool = debug.check_validation_layer_support(
            alloc,
        ) catch @panic("validation layers in debug not available.");

        if (!is_sup) @panic("validation layers in debug not available.");
    }

    const app_info: c.VkApplicationInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = appname.ptr,
        .apiVersion = c.VK_API_VERSION_1_3,
    };

    const required_extensions = alloc_req_extensions(
        alloc,
    ) catch return ZVkError.ErrorOutOfHostMemory;
    defer alloc.free(required_extensions);

    var create_info: c.VkInstanceCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = @intCast(required_extensions.len),
        .ppEnabledExtensionNames = required_extensions.ptr,
    };

    var dbg_create_info: c.VkDebugUtilsMessengerCreateInfoEXT = undefined;

    if (enable_validation_layers) {
        create_info.enabledLayerCount = @intCast(debug.validation_layers.len);
        create_info.ppEnabledLayerNames = &debug.validation_layers;

        dbg_create_info = debug.get_debug_utils_messenger_create_info();
        create_info.pNext = &dbg_create_info;
    }

    if (builtin.os.tag == .macos) { // since we added the port. extension
        create_info.flags |= c.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    }

    var instance: c.VkInstance = undefined;
    try req_vksuc(c.vkCreateInstance(&create_info, null, &instance));

    return instance;
}

fn pick_phys_device_and_props(
    alloc: std.mem.Allocator,
    physdevices: []c.VkPhysicalDevice,
    qf_lists: []QueueFamilyIds,
    surface: c.VkSurfaceKHR,
) ZVkError!struct {
    c.VkPhysicalDevice,
    SwapChainSupportDetails,
    QueueFamilyIds,
} {
    var swap_chain_support: ?SwapChainSupportDetails = null;
    for (physdevices, 0..) |pd, i| {
        const dev_ext_support: bool = try supports_dev_extensions(
            alloc,
            pd,
        );

        if (dev_ext_support) {
            if (swap_chain_support != null) {
                swap_chain_support.?.deinit(alloc);
            }
            swap_chain_support = try SwapChainSupportDetails.init(
                alloc,
                pd,
                surface,
            );

            if (qf_lists[i].complete() and swap_chain_support.?.adequate()) {
                return .{ pd, swap_chain_support.?, qf_lists[i] };
            }
        }
    }
    return ZVkError.Unhandled; // since we _could_ dynamically reduce features later
}

const FeatDeviceCreateInfo = struct {
    vk10f: c.VkPhysicalDeviceFeatures,
    vk12f: c.VkPhysicalDeviceVulkan12Features,
    vk13f: c.VkPhysicalDeviceVulkan13Features,

    qf_prio: f32,
    queue_create_infos: std.ArrayList(c.VkDeviceQueueCreateInfo),
    dev_create_info: c.VkDeviceCreateInfo,

    // alloc is needed since feature pointers are kept in fields, which render invalid on return
    pub fn init(
        alloc: std.mem.Allocator,
        qf_ids: QueueFamilyIds,
    ) ZVkError!*@This() {
        var unique_ids: std.ArrayList(u32) = try qf_ids.alloc_unique_set(alloc);
        defer unique_ids.deinit(alloc); // values are copied, so freeing is ok

        var queue_create_infos = std.ArrayList(c.VkDeviceQueueCreateInfo).empty;

        var self = alloc.create(@This()) catch
            return ZVkError.ErrorOutOfHostMemory;

        self.qf_prio = 1.0;

        for (unique_ids.items) |qf_idx| {
            queue_create_infos.append(alloc, c.VkDeviceQueueCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .queueFamilyIndex = qf_idx,
                .queueCount = 1,
                .pQueuePriorities = &self.qf_prio,
            }) catch return ZVkError.ErrorOutOfHostMemory;
        }

        self.vk10f = c.VkPhysicalDeviceFeatures{
            .samplerAnisotropy = c.VK_TRUE,
            .shaderInt16 = c.VK_TRUE,
        };
        self.vk12f = c.VkPhysicalDeviceVulkan12Features{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
            .descriptorIndexing = c.VK_TRUE,
            .shaderSampledImageArrayNonUniformIndexing = c.VK_TRUE,
            .descriptorBindingVariableDescriptorCount = c.VK_TRUE,
            .runtimeDescriptorArray = c.VK_TRUE,
            .bufferDeviceAddress = c.VK_TRUE,
            .shaderInt8 = c.VK_TRUE,
        };
        self.vk13f = c.VkPhysicalDeviceVulkan13Features{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
            .pNext = null, // defered
            .synchronization2 = c.VK_TRUE,
            .dynamicRendering = c.VK_TRUE,
        };
        self.queue_create_infos = queue_create_infos;
        self.dev_create_info = c.VkDeviceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pNext = null, // defered
            .queueCreateInfoCount = @intCast(queue_create_infos.items.len),
            .pQueueCreateInfos = queue_create_infos.items.ptr,
            .enabledExtensionCount = @intCast(device_extensions.len),
            .ppEnabledExtensionNames = &device_extensions,
            .pEnabledFeatures = &self.vk10f,
        };

        self.*.vk13f.pNext = &self.vk12f;
        self.*.dev_create_info.pNext = &self.vk13f;

        return self;
    }

    pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        self.queue_create_infos.deinit(alloc);
        alloc.destroy(self);
    }
};

const debug = struct {
    const validation_layers = [_][*c]const u8{
        "VK_LAYER_KHRONOS_validation",
    };

    // should only be called when enable_validation_layers!
    pub fn init_debug_messenger(instance: c.VkInstance) ZVkError!c.VkDebugUtilsMessengerEXT {
        var debug_messenger: c.VkDebugUtilsMessengerEXT = undefined;

        var dbg_create_info: c.VkDebugUtilsMessengerCreateInfoEXT =
            get_debug_utils_messenger_create_info();

        try req_vksuc(create_debug_utils_messenger_ext(
            instance,
            &dbg_create_info,
            null,
            &debug_messenger,
        ));

        return debug_messenger;
    }

    pub fn deinit_debug_utils_messenger_ext(
        instance: c.VkInstance,
        debug_messenger: c.VkDebugUtilsMessengerEXT,
        p_allocator: ?*c.VkAllocationCallbacks,
    ) void {
        const voidfptr: c.PFN_vkVoidFunction = c.vkGetInstanceProcAddr(
            instance,
            "vkDestroyDebugUtilsMessengerEXT",
        );
        const fptr: c.PFN_vkDestroyDebugUtilsMessengerEXT = @ptrCast(voidfptr);

        if (fptr) |f| f(
            instance,
            debug_messenger,
            p_allocator,
        );
    }

    pub fn check_validation_layer_support(
        alloc: std.mem.Allocator,
    ) ZVkError!bool {
        var layers: c_uint = undefined;
        _ = c.vkEnumerateInstanceLayerProperties(&layers, null);

        const available_layers: []c.VkLayerProperties = alloc.alloc(
            c.VkLayerProperties,
            layers,
        ) catch return ZVkError.ErrorOutOfHostMemory;
        defer alloc.free(available_layers);

        _ = c.vkEnumerateInstanceLayerProperties(&layers, available_layers.ptr);

        for (validation_layers) |layer_name| {
            var layer_found = false;

            for (available_layers) |layer_properties| {
                if (std.mem.eql(
                    u8,
                    std.mem.sliceTo(&layer_properties.layerName, 0),
                    std.mem.sliceTo(layer_name, 0),
                )) {
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

    // not done globally so we can change the args later on runtime
    pub fn get_debug_utils_messenger_create_info() c.VkDebugUtilsMessengerCreateInfoEXT {
        return c.VkDebugUtilsMessengerCreateInfoEXT{
            .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
            .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT |
                c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
                c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
            .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
                c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
                c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
            .pfnUserCallback = &debug_callback,
            .pUserData = null, // optional
        };
    }

    fn create_debug_utils_messenger_ext(
        instance: c.VkInstance,
        p_create_info: *c.VkDebugUtilsMessengerCreateInfoEXT,
        p_allocator: ?*c.VkAllocationCallbacks,
        p_debug_messenger: *c.VkDebugUtilsMessengerEXT,
    ) c.VkResult {
        const voidfptr: c.PFN_vkVoidFunction = c.vkGetInstanceProcAddr(
            instance,
            "vkCreateDebugUtilsMessengerEXT",
        );
        const fptr: c.PFN_vkCreateDebugUtilsMessengerEXT = @ptrCast(voidfptr);

        return if (fptr) |f| f(
            instance,
            p_create_info,
            p_allocator,
            p_debug_messenger,
        ) else c.VK_ERROR_EXTENSION_NOT_PRESENT;
    }

    pub fn debug_callback(
        message_severity: c.VkDebugUtilsMessageSeverityFlagBitsEXT,
        message_type: c.VkDebugUtilsMessageTypeFlagsEXT,
        pCallbackData: [*c]const c.VkDebugUtilsMessengerCallbackDataEXT,
        pUserData: ?*anyopaque,
    ) callconv(.c) c.VkBool32 {
        // avoid unused param warnings
        _ = .{ message_severity, message_type, pUserData };
        std.log.debug("[VALIDATE] {s}", .{pCallbackData.*.pMessage});
        return c.VK_FALSE;
    }
};
