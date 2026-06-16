const c = @import("c_vk_glfw");
const std = @import("std");
const builtin = @import("builtin");

const Error = error{
    OOMError,
    VkPhysicalDeviceQueryError,
    VkQueryError,
    FailedToCreateShaderModule,
};

pub fn create_shader_mod(
    device: c.VkDevice,
    spv: []const u8,
) Error!c.VkShaderModule {
    const create_info = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = spv.len,
        .pCode = @ptrCast(@alignCast(spv.ptr)),
    };

    var shader_module: c.VkShaderModule = undefined;
    const ret = c.vkCreateShaderModule(device, &create_info, null, &shader_module);
    if (ret != c.VK_SUCCESS) {
        return Error.FailedToCreateShaderModule;
    }
    return shader_module;
}

pub fn supports_dev_extensions(
    alloc: std.mem.Allocator,
    physdevice: c.VkPhysicalDevice,
    dev_extensions: []const [*c]const u8,
) !bool {
    var extc: u32 = 0;
    const ret = c.vkEnumerateDeviceExtensionProperties(physdevice, null, &extc, null);
    if (ret != c.VK_SUCCESS) {
        std.log.err("Failed to enumerate device extension properties: {}", .{ret});
        return Error.VkQueryError;
    }
    const supported_exts = try alloc.alloc(c.VkExtensionProperties, extc);
    defer alloc.free(supported_exts);
    const ret2 = c.vkEnumerateDeviceExtensionProperties(physdevice, null, &extc, supported_exts.ptr);
    if (ret2 != c.VK_SUCCESS) {
        std.log.err("Failed to enumerate device extension properties: {}", .{ret2});
        return Error.VkQueryError;
    }

    for (dev_extensions) |d| {
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

pub fn alloc_physdevice_slice(
    alloc: std.mem.Allocator,
    instance: c.VkInstance,
) ![]c.VkPhysicalDevice {
    var devc: u32 = 0;
    const ret = c.vkEnumeratePhysicalDevices(instance, &devc, null); // to get devicecount
    if (ret != c.VK_SUCCESS) {
        std.log.err("Failed to enumerate physical devices: {}", .{ret});
        return Error.VkQueryError;
    }
    const physdevices = try alloc.alloc(c.VkPhysicalDevice, devc);
    const ret2 = c.vkEnumeratePhysicalDevices(instance, &devc, physdevices.ptr);
    if (ret2 != c.VK_SUCCESS) {
        std.log.err("Failed to enumerate physical devices: {}", .{ret2});
        return Error.VkQueryError;
    }
    return physdevices;
}

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
