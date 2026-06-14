const c = @import("c_vk_glfw");
const std = @import("std");
const builtin = @import("builtin");

pub const QueueFamilyIds = struct {
    graphics: ?u32 = null,
    present: ?u32 = null,

    pub fn complete(self: @This()) bool {
        inline for (@typeInfo(@This()).@"struct".fields) |field| {
            if (@field(self, field.name) == null) return false;
        }
        return true;
    }

    pub fn alloc_unique_set(self: @This(), alloc: std.mem.Allocator) !?std.ArrayList(u32) {
        if (!self.complete()) return null;

        var set = std.ArrayList(u32).empty;

        inline for (@typeInfo(@This()).@"struct".fields) |field| {
            const qf_id = @field(self, field.name).?;
            var should_add = true;
            for (set.items) |id| {
                if (id == qf_id) {
                    should_add = false;
                    break;
                }
            }
            if (should_add) try set.append(alloc, qf_id);
        }
        return set;
    }
};

pub const FeaturedDeviceCreateInfo = struct {
    vk10f: c.VkPhysicalDeviceFeatures,
    vk12f: c.VkPhysicalDeviceVulkan12Features,
    vk13f: c.VkPhysicalDeviceVulkan13Features,

    queue_create_infos: std.ArrayList(c.VkDeviceQueueCreateInfo),
    dev_create_info: c.VkDeviceCreateInfo,

    // alloc is needed since feature pointers are kept in fields, which render invalid on return
    pub fn init(
        alloc: std.mem.Allocator,
        qf_ids: QueueFamilyIds,
        device_extensions: []const [*c]const u8,
    ) !?*@This() {
        const qfprio: f32 = 1.0;

        var unique_ids: std.ArrayList(u32) = try qf_ids.alloc_unique_set(alloc) orelse return null;
        defer unique_ids.deinit(alloc); // values are copied, so freeing is ok

        var queue_create_infos = std.ArrayList(c.VkDeviceQueueCreateInfo).empty;

        for (unique_ids.items) |qf_idx| {
            try queue_create_infos.append(alloc, c.VkDeviceQueueCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .queueFamilyIndex = qf_idx,
                .queueCount = 1,
                .pQueuePriorities = &qfprio,
            });
        }

        var this = try alloc.create(@This());
        this.* = @This(){
            .vk10f = c.VkPhysicalDeviceFeatures{
                .samplerAnisotropy = c.VK_TRUE,
            },
            .vk12f = c.VkPhysicalDeviceVulkan12Features{
                .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
                .descriptorIndexing = c.VK_TRUE,
                .shaderSampledImageArrayNonUniformIndexing = c.VK_TRUE,
                .descriptorBindingVariableDescriptorCount = c.VK_TRUE,
                .runtimeDescriptorArray = c.VK_TRUE,
                .bufferDeviceAddress = c.VK_TRUE,
            },
            .vk13f = c.VkPhysicalDeviceVulkan13Features{
                .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
                .pNext = null, // defered
                .synchronization2 = c.VK_TRUE,
                .dynamicRendering = c.VK_TRUE,
            },
            .queue_create_infos = queue_create_infos,
            .dev_create_info = c.VkDeviceCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                .pNext = null, // defered
                .queueCreateInfoCount = @intCast(queue_create_infos.items.len),
                .pQueueCreateInfos = queue_create_infos.items.ptr,
                .enabledExtensionCount = @intCast(device_extensions.len),
                .ppEnabledExtensionNames = device_extensions.ptr,
                .pEnabledFeatures = &this.vk10f,
            },
        };

        this.*.vk13f.pNext = &this.vk12f;
        this.*.dev_create_info.pNext = &this.vk13f;

        return this;
    }

    pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        self.queue_create_infos.deinit(alloc);
        alloc.destroy(self);
    }
};

fn find_qf_ids(
    alloc: std.mem.Allocator,
    physdevice: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
) !QueueFamilyIds {
    var queue_familyc: u32 = 0;
    _ = c.vkGetPhysicalDeviceQueueFamilyProperties(physdevice, &queue_familyc, null);

    const queue_families = try alloc.alloc(c.VkQueueFamilyProperties, queue_familyc);
    defer alloc.free(queue_families);

    _ = c.vkGetPhysicalDeviceQueueFamilyProperties(
        physdevice,
        &queue_familyc,
        queue_families.ptr,
    );

    var indices = QueueFamilyIds{};

    for (queue_families, 0..) |qf, i| {
        const idx: u32 = @intCast(i);

        if ((qf.queueFlags & c.VK_QUEUE_GRAPHICS_BIT) != 0) {
            indices.graphics = idx;
        }

        var present_support: c.VkBool32 = c.VK_FALSE;
        _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(physdevice, idx, surface, &present_support);
        if (present_support == c.VK_TRUE) {
            indices.present = idx;
        }

        if (indices.complete()) break;
    }

    return indices;
}

pub fn alloc_physdevice_slice(
    alloc: std.mem.Allocator,
    instance: c.VkInstance,
) ![]c.VkPhysicalDevice {
    var devc: u32 = 0;
    _ = c.vkEnumeratePhysicalDevices(instance, &devc, null); // to get devicecount
    const physdevices = try alloc.alloc(c.VkPhysicalDevice, devc);
    _ = c.vkEnumeratePhysicalDevices(instance, &devc, physdevices.ptr);
    return physdevices;
}

pub fn alloc_qf_slice(
    alloc: std.mem.Allocator,
    physdevices: []c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
) ![]QueueFamilyIds {
    var qf_lists = try alloc.alloc(QueueFamilyIds, physdevices.len);
    for (physdevices, 0..) |physdevice, i| {
        qf_lists[i] = try find_qf_ids(alloc, physdevice, surface);
    }
    return qf_lists;
}

pub fn check_validation_layer_support(
    alloc: std.mem.Allocator,
    comptime N: usize,
    validation_layers: [N][*c]const u8,
) std.mem.Allocator.Error!bool {
    var layers: c_uint = undefined;
    _ = c.vkEnumerateInstanceLayerProperties(&layers, null);

    const available_layers: []c.VkLayerProperties = try alloc.alloc(
        c.VkLayerProperties,
        layers,
    );
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

// you need to free yourself! that's why it's called alloc_* throughout
pub fn alloc_req_extensions(
    alloc: std.mem.Allocator,
    comptime N: usize,
    added_exts: [N][*c]const u8,
) ![][*c]const u8 {
    var count: u32 = 0;
    const glfw_exts = c.glfwGetRequiredInstanceExtensions(&count)[0..count];

    const extensions: [][*c]const u8 = try alloc.alloc(
        [*c]const u8,
        glfw_exts.len + added_exts.len,
    );

    @memcpy(extensions[0..glfw_exts.len], glfw_exts);
    @memcpy(extensions[glfw_exts.len..], &added_exts);

    return extensions;
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

pub fn create_debug_utils_messenger_ext(
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

pub fn destroy_debug_utils_messenger_ext(
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

// call conv should be changed when support for Windows is introduced
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
