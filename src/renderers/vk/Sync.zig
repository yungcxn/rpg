const std = @import("std");
const c = @import("c_vk_glfw");
const util = @import("util.zig");
const req_vksuc = util.req_vksuc;
const ZVkError = util.ZVkError;

const max_flightframes = @import("Command.zig").max_flightframes;

present_complete_sems: [max_flightframes]c.VkSemaphore,
render_finished_sems: []c.VkSemaphore,
fences_d: [max_flightframes]c.VkFence,
device: c.VkDevice, // not needed inherently, but for helpers
swap_chain_imgc: u32,

pub fn drawfence(self: @This(), frame_idx: u32) ZVkError!void {
    try req_vksuc(
        c.vkWaitForFences(
            self.device,
            1,
            &self.fences_d[frame_idx],
            c.VK_TRUE, // wait \forall
            std.math.maxInt(u64), // inf timeout
        ),
    );
    try req_vksuc(c.vkResetFences(self.device, 1, &self.fences_d[frame_idx]));
}

pub fn init(
    alloc: std.mem.Allocator,
    device: c.VkDevice,
    swap_chain_imgc: u32,
) ZVkError!@This() {
    const sem_info = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    const fence_info = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    };

    var present_complete_sems: [max_flightframes]c.VkSemaphore = undefined;
    var fences_d: [max_flightframes]c.VkFence = undefined;
    var render_finished_sems: []c.VkSemaphore = alloc.alloc(
        c.VkSemaphore,
        swap_chain_imgc,
    ) catch return ZVkError.ErrorOutOfHostMemory;

    for (0..max_flightframes) |i| {
        try req_vksuc(
            c.vkCreateSemaphore(device, &sem_info, null, &present_complete_sems[i]),
        );
        try req_vksuc(c.vkCreateFence(device, &fence_info, null, &fences_d[i]));
    }

    for (0..swap_chain_imgc) |i| {
        try req_vksuc(
            c.vkCreateSemaphore(device, &sem_info, null, &render_finished_sems[i]),
        );
    }

    return @This(){
        .present_complete_sems = present_complete_sems,
        .render_finished_sems = render_finished_sems,
        .fences_d = fences_d,
        .device = device,
        .swap_chain_imgc = swap_chain_imgc,
    };
}

pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
    for (0..self.swap_chain_imgc) |i| {
        c.vkDestroySemaphore(self.device, self.render_finished_sems[i], null);
    }
    alloc.free(self.render_finished_sems);

    for (0..max_flightframes) |i| {
        c.vkDestroyFence(self.device, self.fence_d[i], null);
        c.vkDestroySemaphore(self.device, self.present_complete_sem[i], null);
    }
}
