const std = @import("std");
const c = @import("c_vk_glfw");
const util = @import("util.zig");
const req_vksuc = util.req_vksuc;
const ZVkError = util.ZVkError;
const QueueFamilyIds = @import("QueueFamilyIds.zig");

pub const SupportDetails = struct {
    capabilities: c.VkSurfaceCapabilitiesKHR,
    formats: ?[]c.VkSurfaceFormatKHR = null,
    present_modes: ?[]c.VkPresentModeKHR = null,

    pub fn init(
        alloc: std.mem.Allocator,
        physdevice: c.VkPhysicalDevice,
        surface: c.VkSurfaceKHR,
    ) ZVkError!@This() {
        var details = @This(){
            .capabilities = undefined,
        };

        try req_vksuc(
            c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
                physdevice,
                surface,
                &details.capabilities,
            ),
        );
        var formatc: u32 = 0;

        try req_vksuc(
            c.vkGetPhysicalDeviceSurfaceFormatsKHR(
                physdevice,
                surface,
                &formatc,
                null,
            ),
        );

        if (formatc != 0) {
            details.formats = alloc.alloc(c.VkSurfaceFormatKHR, formatc) catch
                return ZVkError.ErrorOutOfHostMemory;
            errdefer alloc.free(details.formats.?);

            try req_vksuc(
                c.vkGetPhysicalDeviceSurfaceFormatsKHR(
                    physdevice,
                    surface,
                    &formatc,
                    details.formats.?.ptr,
                ),
            );
        }

        var present_modec: u32 = 0;
        try req_vksuc(
            c.vkGetPhysicalDeviceSurfacePresentModesKHR(
                physdevice,
                surface,
                &present_modec,
                null,
            ),
        );

        if (present_modec != 0) {
            details.present_modes = alloc.alloc(
                c.VkPresentModeKHR,
                present_modec,
            ) catch return ZVkError.ErrorOutOfHostMemory;
            errdefer alloc.free(details.present_modes.?);
            try req_vksuc(
                c.vkGetPhysicalDeviceSurfacePresentModesKHR(
                    physdevice,
                    surface,
                    &present_modec,
                    details.present_modes.?.ptr,
                ),
            );
        }

        return details;
    }

    pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        if (self.formats) |f| {
            alloc.free(f);
            self.formats = null;
        }

        if (self.present_modes) |pm| {
            alloc.free(pm);
            self.present_modes = null;
        }
    }

    pub fn adequate(self: @This()) bool {
        return self.formats != null and self.present_modes != null;
    }
};

pub const Data = struct {
    swap_chain: c.VkSwapchainKHR,
    imgs: []c.VkImage,
    img_format: c.VkFormat = 0,
    extent: c.VkExtent2D = .{ .width = 0, .height = 0 },
    img_views: []c.VkImageView,
    device: c.VkDevice,
    // these are for reinit needed
    support_details: SupportDetails,
    window: ?*c.GLFWwindow = null,
    surface: c.VkSurfaceKHR,
    qf_ids: QueueFamilyIds,
    phys_device: c.VkPhysicalDevice,

    fn init_image_views(
        alloc: std.mem.Allocator,
        imgs: []c.VkImage,
        img_format: c.VkFormat,
        device: c.VkDevice,
    ) ZVkError![]c.VkImageView {
        var img_views = alloc.alloc(c.VkImageView, imgs.len) catch
            return ZVkError.ErrorOutOfHostMemory;

        for (imgs, 0..) |img, i| {
            const img_v_ci = c.VkImageViewCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image = img,
                .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
                .format = img_format,
                .components = c.VkComponentMapping{
                    .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                },
                .subresourceRange = c.VkImageSubresourceRange{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            };

            try req_vksuc(
                c.vkCreateImageView(device, &img_v_ci, null, &img_views[i]),
            );

            errdefer {
                for (img_views, 0..i) |iv, _| {
                    c.vkDestroyImageView(device, iv, null);
                }
                alloc.free(img_views);
            }
        }

        return img_views;
    }

    pub fn init(
        alloc: std.mem.Allocator,
        support_details: SupportDetails,
        window: ?*c.GLFWwindow,
        surface: c.VkSurfaceKHR,
        qf_ids: QueueFamilyIds,
        device: c.VkDevice,
        physdevice: c.VkPhysicalDevice,
    ) ZVkError!@This() {
        const surface_format: c.VkSurfaceFormatKHR = choose_swap_surface_format(
            support_details.formats.?,
        );
        const present_mode: c.VkPresentModeKHR = choose_swap_present_mode(
            support_details.present_modes.?,
        );

        const img_format = surface_format.format;
        const extent = choose_swap_extent(
            support_details.capabilities,
            window,
        );

        var imgc: u32 = support_details.capabilities.minImageCount + 1;
        if (support_details.capabilities.maxImageCount > 0 and
            imgc > support_details.capabilities.maxImageCount)
        {
            imgc = support_details.capabilities.maxImageCount;
        }

        var swap_chain_ci = c.VkSwapchainCreateInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = surface,
            .minImageCount = imgc,
            .imageFormat = surface_format.format,
            .imageColorSpace = surface_format.colorSpace,
            .imageExtent = extent,
            .imageArrayLayers = 1,
            .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        };

        if (qf_ids.graphics != qf_ids.present) {
            swap_chain_ci.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
            swap_chain_ci.queueFamilyIndexCount = 2;
            swap_chain_ci.pQueueFamilyIndices = &[2]u32{
                qf_ids.graphics.?,
                qf_ids.present.?,
            };
        } else {
            swap_chain_ci.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
            swap_chain_ci.queueFamilyIndexCount = 0;
            swap_chain_ci.pQueueFamilyIndices = null;
        }

        swap_chain_ci.preTransform = support_details.capabilities.currentTransform;
        swap_chain_ci.compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
        swap_chain_ci.presentMode = present_mode;
        swap_chain_ci.clipped = c.VK_TRUE;
        swap_chain_ci.oldSwapchain = null;

        var swap_chain: c.VkSwapchainKHR = undefined;
        try req_vksuc(
            c.vkCreateSwapchainKHR(device, &swap_chain_ci, null, &swap_chain),
        );

        try req_vksuc(
            c.vkGetSwapchainImagesKHR(device, swap_chain, &imgc, null),
        );

        // free'd in global deinit of this
        const imgs = alloc.alloc(c.VkImage, imgc) catch return ZVkError.ErrorOutOfHostMemory;
        errdefer alloc.free(imgs);
        try req_vksuc(
            c.vkGetSwapchainImagesKHR(device, swap_chain, &imgc, imgs.ptr),
        );

        const img_views = try init_image_views(
            alloc,
            imgs,
            img_format,
            device,
        );

        return @This(){
            .swap_chain = swap_chain,
            .imgs = imgs,
            .img_format = img_format,
            .extent = extent,
            .img_views = img_views,
            .device = device,
            .support_details = support_details,
            .window = window,
            .surface = surface,
            .qf_ids = qf_ids,
            .phys_device = physdevice,
        };
    }

    pub fn reinit(
        self: *@This(),
        alloc: std.mem.Allocator,
        window: ?*c.GLFWwindow,
    ) ZVkError!void {
        var wh = @Vector(2, c_int){ 0, 0 };
        c.glfwGetFramebufferSize(window, &wh[0], &wh[1]);
        while (wh[0] == 0 or wh[1] == 0) {
            c.glfwGetFramebufferSize(window, &wh[0], &wh[1]);
            c.glfwWaitEvents();
        }

        try req_vksuc(c.vkDeviceWaitIdle(self.device));

        self.deinit(alloc);
        self.support_details.deinit(alloc);

        self.support_details = try SupportDetails.init(
            alloc,
            self.phys_device,
            self.surface,
        );

        self.* = try @This().init(
            alloc,
            self.support_details,
            self.window,
            self.surface,
            self.qf_ids,
            self.device,
            self.phys_device,
        );
    }

    pub fn deinit(
        self: *@This(),
        alloc: std.mem.Allocator,
    ) void {
        for (self.img_views) |iv| {
            c.vkDestroyImageView(self.device, iv, null);
        }
        c.vkDestroySwapchainKHR(self.device, self.swap_chain, null);
        self.swap_chain = null;
        alloc.free(self.img_views);
        alloc.free(self.imgs);
    }
};

fn choose_swap_surface_format(
    available_formats: []c.VkSurfaceFormatKHR,
) c.VkSurfaceFormatKHR {
    for (available_formats) |f| {
        if (f.format == c.VK_FORMAT_B8G8R8A8_SRGB and
            f.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
        {
            return f;
        }
    }
    return available_formats[0];
}

fn choose_swap_present_mode(
    available_present_modes: []c.VkPresentModeKHR,
) c.VkPresentModeKHR {
    for (available_present_modes) |pm| {
        if (pm == c.VK_PRESENT_MODE_MAILBOX_KHR) {
            return pm;
        }
    }
    return c.VK_PRESENT_MODE_FIFO_KHR;
}

fn choose_swap_extent(
    caps: c.VkSurfaceCapabilitiesKHR,
    window: ?*c.GLFWwindow,
) c.VkExtent2D {
    if (caps.currentExtent.width != std.math.maxInt(u32)) {
        return caps.currentExtent;
    } else {
        // uint needed for getframebuffersize
        var c_i_wh = @Vector(2, c_int){ 0, 0 };
        c.glfwGetFramebufferSize(window, &c_i_wh[0], &c_i_wh[1]);
        const u_wh = @Vector(2, u32){
            @intCast(c_i_wh[0]),
            @intCast(c_i_wh[1]),
        };

        const actual_extent2d = c.VkExtent2D{
            .width = std.math.clamp(
                u_wh[0],
                caps.minImageExtent.width,
                caps.maxImageExtent.width,
            ),
            .height = std.math.clamp(
                u_wh[1],
                caps.minImageExtent.height,
                caps.maxImageExtent.height,
            ),
        };
        return actual_extent2d;
    }
}
