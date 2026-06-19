const c = @import("c_vk_glfw");
const std = @import("std");
const alloc = std.heap.page_allocator; // TODO: better allocator
const builtin = @import("builtin");
const hack = @import("../util/hack.zig");
const vk_util = @import("vk/util.zig");
const Base = @import("vk/Base.zig");
const QueueFamilyIds = @import("vk/QueueFamilyIds.zig");
const Queue = @import("vk/Queue.zig");
const SwapChain = @import("vk/SwapChain.zig");
const Pipeline = @import("vk/Pipeline.zig");
const Sync = @import("vk/Sync.zig");
const Command = @import("vk/Command.zig");
const req_vksuc = vk_util.req_vksuc;

const app = "RPG";
// this is used by Renderer as a subtrait
pub const Error = vk_util.ZVkError;
pub const max_frames_in_flight = 2;

base: Base,
queue: Queue,
swap_chain_data: SwapChain.Data,
pipeline: Pipeline,
command: Command,
sync: Sync,

pub fn init() Error!@This() {
    const base = try Base.init(alloc, app);
    const queue = try Queue.init(base.device, base.qf_ids);

    const swap_chain_data = try SwapChain.Data.init(
        alloc,
        base.sc_sup,
        base.window,
        base.surface,
        base.qf_ids,
        base.device,
    );

    const pipeline = try Pipeline.init(
        base.device,
        swap_chain_data.extent,
        swap_chain_data.img_format,
    );

    const command = try Command.init(base.device, base.qf_ids);
    const sync = try Sync.init(base.device);

    return @This(){
        .base = base,
        .queue = queue,
        .swap_chain_data = swap_chain_data,
        .pipeline = pipeline,
        .command = command,
        .sync = sync,
    };
}

pub fn deinit(self: *@This()) void {
    // before deinit ANYTHING, sync with gpu
    c.vkDeviceWaitIdle(self.base.device);

    self.sync.deinit();
    self.command.deinit();
    self.pipeline.deinit();
    self.swap_chain_data.deinit(alloc);
    self.base.deinit(alloc);
}

// must catch all errors, since this is a "subtrait" of Renderer.render
// and error union return is expensive for every loop it.
pub fn render(self: *@This()) bool {
    if (c.glfwWindowShouldClose(self.base.window) == 0) {
        c.glfwPollEvents();
        vk_util.draw_frame(
            self.sync,
            self.swap_chain_data,
            self.command,
            self.pipeline,
            self.queue,
        ) catch return false;
    }
    return true;
}
