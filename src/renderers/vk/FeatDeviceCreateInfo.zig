const std = @import("std");
const c = @import("c_vk_glfw");
const QueueFamilyIds = @import("QueueFamilyIds.zig");

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
    device_extensions: []const [*c]const u8,
) !*@This() {
    var unique_ids: std.ArrayList(u32) = try qf_ids.alloc_unique_set(alloc);
    defer unique_ids.deinit(alloc); // values are copied, so freeing is ok

    var queue_create_infos = std.ArrayList(c.VkDeviceQueueCreateInfo).empty;

    var self = try alloc.create(@This());
    self.qf_prio = 1.0;

    for (unique_ids.items) |qf_idx| {
        try queue_create_infos.append(alloc, c.VkDeviceQueueCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = qf_idx,
            .queueCount = 1,
            .pQueuePriorities = &self.qf_prio,
        });
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
        .ppEnabledExtensionNames = device_extensions.ptr,
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
