const std = @import("std");
const c = @import("c_vk_glfw");
const util = @import("util.zig");
const req_vksuc = util.req_vksuc;
const ZVkError = util.ZVkError;
const QueueFamilyIds = @import("QueueFamilyIds.zig");

pub const max_flightframes = 2;

cmd_pool: c.VkCommandPool,
cmd_bufs: [max_flightframes]c.VkCommandBuffer,
device: c.VkDevice,

pub fn init(
    device: c.VkDevice,
    qf_ids: QueueFamilyIds,
) ZVkError!@This() {
    const pool_ci = c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = qf_ids.graphics.?,
    };

    var cmd_pool: c.VkCommandPool = undefined;
    try req_vksuc(c.vkCreateCommandPool(device, &pool_ci, null, &cmd_pool));

    const alloc_info = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = cmd_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = max_flightframes,
    };

    var cmd_bufs: [max_flightframes]c.VkCommandBuffer = undefined;
    try req_vksuc(c.vkAllocateCommandBuffers(device, &alloc_info, &cmd_bufs));
    return @This(){
        .cmd_pool = cmd_pool,
        .cmd_bufs = cmd_bufs,
        .device = device,
    };
}

pub fn deinit(self: @This()) void {
    // destroys the cmd_buf aswell
    c.vkDestroyCommandPool(self.device, self.cmd_pool, null);
}

pub fn record_command_buffer(
    self: @This(),
    frame_idx: u32,
    img: c.VkImage,
    img_view: c.VkImageView,
    extent: c.VkExtent2D,
    pipeline: c.VkPipeline,
) ZVkError!void {
    const cmd_buf = self.cmd_bufs[frame_idx];

    const begin_info = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    };
    try req_vksuc(c.vkBeginCommandBuffer(cmd_buf, &begin_info));

    transition_image_layout(
        cmd_buf,
        img,
        c.VK_IMAGE_LAYOUT_UNDEFINED,
        c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        0,
        c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
        c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
        c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
    );

    const clear_color = c.VkClearValue{
        .color = .{ .float32 = [4]f32{ 0.0, 0.0, 0.0, 1.0 } },
    };

    const attachment_info = c.VkRenderingAttachmentInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = img_view,
        .imageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = clear_color,
    };

    const render_info = c.VkRenderingInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = c.VkRect2D{
            .offset = c.VkOffset2D{ .x = 0, .y = 0 },
            .extent = extent,
        },
        .layerCount = 1,
        .colorAttachmentCount = 1,
        .pColorAttachments = &attachment_info,
    };

    c.vkCmdBeginRendering(cmd_buf, &render_info);
    c.vkCmdBindPipeline(cmd_buf, c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);

    const dyn_viewport = c.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(extent.width),
        .height = @floatFromInt(extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    c.vkCmdSetViewport(cmd_buf, 0, 1, &dyn_viewport);

    const dyn_scissor = c.VkRect2D{
        .offset = c.VkOffset2D{ .x = 0, .y = 0 },
        .extent = extent,
    };
    c.vkCmdSetScissor(cmd_buf, 0, 1, &dyn_scissor);

    c.vkCmdDraw(cmd_buf, 3, 1, 0, 0);

    c.vkCmdEndRendering(cmd_buf);

    transition_image_layout(
        cmd_buf,
        img,
        c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
        0,
        c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
        c.VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT,
    );

    try req_vksuc(c.vkEndCommandBuffer(cmd_buf));
}

fn transition_image_layout(
    cmd_buf: c.VkCommandBuffer,
    img: c.VkImage,
    old_layout: c.VkImageLayout,
    new_layout: c.VkImageLayout,
    src_access_mask: c.VkAccessFlags2,
    dst_access_mask: c.VkAccessFlags2,
    src_stage_mask: c.VkPipelineStageFlags2,
    dst_stage_mask: c.VkPipelineStageFlags2,
) void {
    const barrier = c.VkImageMemoryBarrier2{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .pNext = null,
        .srcStageMask = src_stage_mask,
        .dstStageMask = dst_stage_mask,
        .srcAccessMask = src_access_mask,
        .dstAccessMask = dst_access_mask,
        .oldLayout = old_layout,
        .newLayout = new_layout,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .image = img,
        .subresourceRange = c.VkImageSubresourceRange{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    const dep_info = c.VkDependencyInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .dependencyFlags = 0,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &barrier,
    };

    c.vkCmdPipelineBarrier2(cmd_buf, &dep_info);
}
