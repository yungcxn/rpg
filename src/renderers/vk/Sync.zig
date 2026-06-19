const std = @import("std");
const c = @import("c_vk_glfw");
const util = @import("util.zig");
const req_vksuc = util.req_vksuc;
const ZVkError = util.ZVkError;

present_complete_sem: c.VkSemaphore,
render_finished_sem: c.VkSemaphore,
fence_d: c.VkFence,
device: c.VkDevice, // not needed inherently, but for helpers

pub fn drawfence(self: @This()) ZVkError!void {
    try req_vksuc(
        c.vkWaitForFences(
            self.device,
            1,
            &self.fence_d,
            c.VK_TRUE, // wait \forall
            std.math.maxInt(u64), // inf timeout
        ),
    );
    try req_vksuc(c.vkResetFences(self.device, 1, &self.fence_d));
}

pub fn init(device: c.VkDevice) ZVkError!@This() {
    const sem_info = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };

    var present_complete_sem: c.VkSemaphore = null;
    try req_vksuc(
        c.vkCreateSemaphore(device, &sem_info, null, &present_complete_sem),
    );

    var render_finished_sem: c.VkSemaphore = null;
    try req_vksuc(
        c.vkCreateSemaphore(device, &sem_info, null, &render_finished_sem),
    );

    const fence_info = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    };
    var fence_d: c.VkFence = null;
    try req_vksuc(c.vkCreateFence(device, &fence_info, null, &fence_d));

    return @This(){
        .present_complete_sem = present_complete_sem,
        .render_finished_sem = render_finished_sem,
        .fence_d = fence_d,
        .device = device,
    };
}

pub fn deinit(self: @This()) void {
    c.vkDestroyFence(self.device, self.fence_d, null);
    c.vkDestroySemaphore(self.device, self.render_finished_sem, null);
    c.vkDestroySemaphore(self.device, self.present_complete_sem, null);
}
