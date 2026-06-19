const std = @import("std");
const c = @import("c_vk_glfw");
const QueueFamilyIds = @import("QueueFamilyIds.zig");
const util = @import("util.zig");
const req_vksuc = util.req_vksuc;
const ZVkError = util.ZVkError;

present: c.VkQueue,
graphics: c.VkQueue,

pub fn init(
    device: c.VkDevice,
    qf_ids: QueueFamilyIds,
) ZVkError!@This() {
    var present_q: c.VkQueue = null;
    c.vkGetDeviceQueue(device, qf_ids.present.?, 0, &present_q);
    if (present_q == null) return ZVkError.ErrorInitializationFailed;

    var graphics_q: c.VkQueue = null;
    c.vkGetDeviceQueue(device, qf_ids.graphics.?, 0, &graphics_q);
    if (graphics_q == null) return ZVkError.ErrorInitializationFailed;

    return @This(){
        .present = present_q,
        .graphics = graphics_q,
    };
}
