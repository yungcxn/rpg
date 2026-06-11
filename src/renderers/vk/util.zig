const c = @import("c_vk_glfw");
const std = @import("std");
const builtin = @import("builtin");

// "correct" means: queue-family checked
pub fn get_correct_physdevice(
    alloc: std.mem.Allocator,
    instance: c.VkInstance,
    phys_device_id: u32,
) std.mem.Allocator.Error!c.VkPhysicalDevice {
    var devc: u32 = 0;
    _ = c.vkEnumeratePhysicalDevices(instance, &devc, null); // to get devicecount
    const physdevices = try alloc.alloc(c.VkPhysicalDevice, devc);
    defer alloc.free(physdevices);
    _ = c.vkEnumeratePhysicalDevices(instance, &devc, physdevices.ptr);
    const chosen_physdevice = physdevices[phys_device_id];

    { // queue family check
        var queue_familyc: u32 = 0;
        _ = c.vkGetPhysicalDeviceQueueFamilyProperties(
            physdevices[phys_device_id],
            &queue_familyc,
            null,
        );

        const queue_families = try alloc.alloc(c.VkQueueFamilyProperties, queue_familyc);
        defer alloc.free(queue_families);

        _ = c.vkGetPhysicalDeviceQueueFamilyProperties(
            physdevices[phys_device_id],
            &queue_familyc,
            queue_families.ptr,
        );

        var queue_family_idx: u32 = 0;
        for (queue_families, 0..) |qf, i| {
            if ((qf.queueFlags & c.VK_QUEUE_GRAPHICS_BIT) != 0) {
                queue_family_idx = @intCast(i);
                break;
            }
        }

        if (c.glfwGetPhysicalDevicePresentationSupport(
            instance,
            chosen_physdevice,
            queue_family_idx,
        ) == 0) {
            std.log.debug("Chosen queue family not supported!", .{});
            return null;
        }
    }

    return chosen_physdevice;
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
