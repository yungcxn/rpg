const c = @import("c_vk_glfw");
const std = @import("std");
const builtin = @import("builtin");
const hack = @import("../../util/hack.zig");
const QueueFamilyIds = @import("QueueFamilyIds.zig");
const SwapChain = @import("SwapChain.zig");
const Sync = @import("Sync.zig");
const Command = @import("Command.zig");
const Pipeline = @import("Pipeline.zig");
const Queue = @import("Queue.zig");

const max_flightframes = Command.max_flightframes;

pub const ZVkResult = enum(c_int) {
    Success = c.VK_SUCCESS,
    NotReady = c.VK_NOT_READY,
    Timeout = c.VK_TIMEOUT,
    EventSet = c.VK_EVENT_SET,
    EventReset = c.VK_EVENT_RESET,
    Incomplete = c.VK_INCOMPLETE,
    PipelineCompileRequired = c.VK_PIPELINE_COMPILE_REQUIRED,
    SuboptimalKHR = c.VK_SUBOPTIMAL_KHR,
    ThreadIdleKHR = c.VK_THREAD_IDLE_KHR,
    ThreadDoneKHR = c.VK_THREAD_DONE_KHR,
    OperationDeferredKHR = c.VK_OPERATION_DEFERRED_KHR,
    OperationNotDeferredKHR = c.VK_OPERATION_NOT_DEFERRED_KHR,
    IncompatibleShaderBinaryEXT = c.VK_INCOMPATIBLE_SHADER_BINARY_EXT,
    PipelineBinaryMissingKHR = c.VK_PIPELINE_BINARY_MISSING_KHR,
};

pub const ZVkError = error{
    ErrorOutOfHostMemory,
    ErrorOutOfDeviceMemory,
    ErrorInitializationFailed,
    ErrorDeviceLost,
    ErrorMemoryMapFailed,
    ErrorLayerNotPresent,
    ErrorExtensionNotPresent,
    ErrorFeatureNotPresent,
    ErrorIncompatibleDriver,
    ErrorTooManyObjects,
    ErrorFormatNotSupported,
    ErrorFragmentedPool,
    ErrorUnknown,
    ErrorValidationFailed,
    ErrorOutOfPoolMemory,
    ErrorInvalidExternalHandle,
    ErrorInvalidOpaqueCaptureAddress,
    ErrorFragmentation,
    ErrorNotPermitted,
    ErrorSurfaceLostKHR,
    ErrorNativeWindowInUseKHR,
    ErrorOutOfDateKHR,
    ErrorIncompatibleDisplayKHR,
    ErrorInvalidShaderNV,
    ErrorImageUsageNotSupportedKHR,
    ErrorVideoPictureLayoutNotSupportedKHR,
    ErrorVideoProfileOperationNotSupportedKHR,
    ErrorVideoProfileFormatNotSupportedKHR,
    ErrorVideoProfileCodecNotSupportedKHR,
    ErrorVideoStdVersionNotSupportedKHR,
    ErrorInvalidDrmFormatModifierPlaneLayoutEXT,
    ErrorPresentTimingQueueFullEXT,
    ErrorFullScreenExclusiveModeLostEXT,
    ErrorInvalidVideoStdParametersKHR,
    ErrorCompressionExhaustedEXT,
    ErrorNotEnoughSpaceKHR,
    Unhandled,
};

pub fn to_zvkresult_or_error(result: c.VkResult) ZVkError!ZVkResult {
    return switch (result) {
        c.VK_SUCCESS => .Success,
        c.VK_NOT_READY => .NotReady,
        c.VK_TIMEOUT => .Timeout,
        c.VK_EVENT_SET => .EventSet,
        c.VK_EVENT_RESET => .EventReset,
        c.VK_INCOMPLETE => .Incomplete,
        c.VK_PIPELINE_COMPILE_REQUIRED => .PipelineCompileRequired,
        c.VK_SUBOPTIMAL_KHR => .SuboptimalKHR,
        c.VK_THREAD_IDLE_KHR => .ThreadIdleKHR,
        c.VK_THREAD_DONE_KHR => .ThreadDoneKHR,
        c.VK_OPERATION_DEFERRED_KHR => .OperationDeferredKHR,
        c.VK_OPERATION_NOT_DEFERRED_KHR => .OperationNotDeferredKHR,
        c.VK_INCOMPATIBLE_SHADER_BINARY_EXT => .IncompatibleShaderBinaryEXT,
        c.VK_PIPELINE_BINARY_MISSING_KHR => .PipelineBinaryMissingKHR,

        c.VK_ERROR_OUT_OF_HOST_MEMORY => error.ErrorOutOfHostMemory,
        c.VK_ERROR_OUT_OF_DEVICE_MEMORY => error.ErrorOutOfDeviceMemory,
        c.VK_ERROR_INITIALIZATION_FAILED => error.ErrorInitializationFailed,
        c.VK_ERROR_DEVICE_LOST => error.ErrorDeviceLost,
        c.VK_ERROR_MEMORY_MAP_FAILED => error.ErrorMemoryMapFailed,
        c.VK_ERROR_LAYER_NOT_PRESENT => error.ErrorLayerNotPresent,
        c.VK_ERROR_EXTENSION_NOT_PRESENT => error.ErrorExtensionNotPresent,
        c.VK_ERROR_FEATURE_NOT_PRESENT => error.ErrorFeatureNotPresent,
        c.VK_ERROR_INCOMPATIBLE_DRIVER => error.ErrorIncompatibleDriver,
        c.VK_ERROR_TOO_MANY_OBJECTS => error.ErrorTooManyObjects,
        c.VK_ERROR_FORMAT_NOT_SUPPORTED => error.ErrorFormatNotSupported,
        c.VK_ERROR_FRAGMENTED_POOL => error.ErrorFragmentedPool,
        c.VK_ERROR_UNKNOWN => error.ErrorUnknown,
        c.VK_ERROR_VALIDATION_FAILED => error.ErrorValidationFailed,
        c.VK_ERROR_OUT_OF_POOL_MEMORY => error.ErrorOutOfPoolMemory,
        c.VK_ERROR_INVALID_EXTERNAL_HANDLE => error.ErrorInvalidExternalHandle,
        c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS => error.ErrorInvalidOpaqueCaptureAddress,
        c.VK_ERROR_FRAGMENTATION => error.ErrorFragmentation,
        c.VK_ERROR_NOT_PERMITTED => error.ErrorNotPermitted,
        c.VK_ERROR_SURFACE_LOST_KHR => error.ErrorSurfaceLostKHR,
        c.VK_ERROR_NATIVE_WINDOW_IN_USE_KHR => error.ErrorNativeWindowInUseKHR,
        c.VK_ERROR_OUT_OF_DATE_KHR => error.ErrorOutOfDateKHR,
        c.VK_ERROR_INCOMPATIBLE_DISPLAY_KHR => error.ErrorIncompatibleDisplayKHR,
        c.VK_ERROR_INVALID_SHADER_NV => error.ErrorInvalidShaderNV,
        c.VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR => error.ErrorImageUsageNotSupportedKHR,
        c.VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR => error.ErrorVideoPictureLayoutNotSupportedKHR,
        c.VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR => error.ErrorVideoProfileOperationNotSupportedKHR,
        c.VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR => error.ErrorVideoProfileFormatNotSupportedKHR,
        c.VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR => error.ErrorVideoProfileCodecNotSupportedKHR,
        c.VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR => error.ErrorVideoStdVersionNotSupportedKHR,
        c.VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT => error.ErrorInvalidDrmFormatModifierPlaneLayoutEXT,
        c.VK_ERROR_PRESENT_TIMING_QUEUE_FULL_EXT => error.ErrorPresentTimingQueueFullEXT,
        c.VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT => error.ErrorFullScreenExclusiveModeLostEXT,
        c.VK_ERROR_INVALID_VIDEO_STD_PARAMETERS_KHR => error.ErrorInvalidVideoStdParametersKHR,
        c.VK_ERROR_COMPRESSION_EXHAUSTED_EXT => error.ErrorCompressionExhaustedEXT,
        c.VK_ERROR_NOT_ENOUGH_SPACE_KHR => error.ErrorNotEnoughSpaceKHR,

        else => error.Unhandled,
    };
}
pub fn wrap_vkres(res: c.VkResult) ZVkError!ZVkResult {
    const zvkres = to_zvkresult_or_error(res) catch |err| {
        std.log.err("Vulkan error: {}", .{err});
        return err;
    };
    return zvkres;
}

pub fn req_vksuc(res: c.VkResult) ZVkError!void {
    const zvkres = try wrap_vkres(res);
    if (zvkres != ZVkResult.Success) {
        std.log.warn(
            "Vulkan returned non-success result: {} - proceeding",
            .{zvkres},
        );
    }
}

pub fn draw_frame(
    sync: Sync,
    swap_chain_data: SwapChain.Data,
    command: Command,
    pipeline: Pipeline,
    queue: Queue,
    frame_counter: *u32,
) ZVkError!void {
    const frame_idx: u32 = frame_counter.*;
    try sync.drawfence(frame_idx); // syncs CPU and GPU

    var img_idx: u32 = 0;
    try req_vksuc(c.vkAcquireNextImageKHR(
        sync.device,
        swap_chain_data.swap_chain,
        std.math.maxInt(u64),
        sync.present_complete_sems[frame_idx],
        null,
        &img_idx,
    ));

    const img = swap_chain_data.imgs[img_idx];
    const img_view = swap_chain_data.img_views[img_idx];

    try command.record_command_buffer(
        frame_idx,
        img,
        img_view,
        swap_chain_data.extent,
        pipeline.pipeline,
    );

    const wait_mask: c.VkPipelineStageFlags = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    const submit_info = c.VkSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &sync.present_complete_sems[frame_idx],
        .pWaitDstStageMask = &wait_mask,
        .commandBufferCount = 1,
        .pCommandBuffers = &command.cmd_bufs[frame_idx],
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &sync.render_finished_sems[img_idx],
    };
    try req_vksuc(
        c.vkQueueSubmit(queue.graphics, 1, &submit_info, sync.fences_d[frame_idx]),
    );

    const present_info = c.VkPresentInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &sync.render_finished_sems[img_idx],
        .swapchainCount = 1,
        .pSwapchains = &swap_chain_data.swap_chain,
        .pImageIndices = &img_idx,
    };
    try req_vksuc(c.vkQueuePresentKHR(queue.present, &present_info));

    frame_counter.* = (frame_idx + 1) % max_flightframes;
}
