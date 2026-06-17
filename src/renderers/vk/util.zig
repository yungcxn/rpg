const c = @import("c_vk_glfw");
const std = @import("std");
const builtin = @import("builtin");
const hack = @import("../../util/hack.zig");

pub fn create_shader_mod(
    device: c.VkDevice,
    spv: []const u8,
) !c.VkShaderModule {
    const create_info = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = spv.len,
        .pCode = @ptrCast(@alignCast(spv.ptr)),
    };

    var shader_module: c.VkShaderModule = undefined;
    try req_vksuc(
        c.vkCreateShaderModule(device, &create_info, null, &shader_module),
    );
    return shader_module;
}

pub fn supports_dev_extensions(
    alloc: std.mem.Allocator,
    physdevice: c.VkPhysicalDevice,
    dev_extensions: []const [*c]const u8,
) !bool {
    var extc: u32 = 0;
    try req_vksuc(c.vkEnumerateDeviceExtensionProperties(physdevice, null, &extc, null));

    const supported_exts = try alloc.alloc(c.VkExtensionProperties, extc);
    defer alloc.free(supported_exts);

    try req_vksuc(
        c.vkEnumerateDeviceExtensionProperties(physdevice, null, &extc, supported_exts.ptr),
    );

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
    try req_vksuc(c.vkEnumeratePhysicalDevices(instance, &devc, null));
    const physdevices = try alloc.alloc(c.VkPhysicalDevice, devc);
    try req_vksuc(
        c.vkEnumeratePhysicalDevices(instance, &devc, physdevices.ptr),
    );
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
