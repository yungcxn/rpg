const std = @import("std");
const c = @import("c_vk_glfw");
const util = @import("util.zig");
const ZVkError = util.ZVkError;

graphics: ?u32 = null,
present: ?u32 = null,

pub fn alloc_unique_set(
    self: @This(),
    alloc: std.mem.Allocator,
) ZVkError!std.ArrayList(u32) {
    if (!self.complete()) return ZVkError.ErrorInitializationFailed;

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
        if (should_add) set.append(alloc, qf_id) catch
            return ZVkError.ErrorOutOfHostMemory;
    }
    return set;
}

fn find_ids(
    alloc: std.mem.Allocator,
    physdevice: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
) ZVkError!@This() {
    var queue_familyc: u32 = 0;
    _ = c.vkGetPhysicalDeviceQueueFamilyProperties(physdevice, &queue_familyc, null);

    const queue_families = alloc.alloc(
        c.VkQueueFamilyProperties,
        queue_familyc,
    ) catch return ZVkError.ErrorOutOfHostMemory;
    defer alloc.free(queue_families);

    _ = c.vkGetPhysicalDeviceQueueFamilyProperties(
        physdevice,
        &queue_familyc,
        queue_families.ptr,
    );

    var indices = @This(){};

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

pub fn alloc_qf_slice(
    alloc: std.mem.Allocator,
    physdevices: []c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
) ZVkError![]@This() {
    var qf_lists = alloc.alloc(@This(), physdevices.len) catch return ZVkError.ErrorOutOfHostMemory;
    for (physdevices, 0..) |physdevice, i| {
        qf_lists[i] = try find_ids(alloc, physdevice, surface);
    }
    return qf_lists;
}

pub fn complete(self: @This()) bool {
    inline for (@typeInfo(@This()).@"struct".fields) |field| {
        if (@field(self, field.name) == null) return false;
    }
    return true;
}
