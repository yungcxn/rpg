const std = @import("std");
const c = @import("c_vk_glfw");
const util = @import("util.zig");
const QueueFamilyIds = @import("QueueFamilyIds.zig");

pub const SupportDetails = struct {
    capabilities: c.VkSurfaceCapabilitiesKHR,
    formats: ?[]c.VkSurfaceFormatKHR = null,
    present_modes: ?[]c.VkPresentModeKHR = null,

    const Error = error{ OOMError, VkQueryError };

    pub fn init(
        alloc: std.mem.Allocator,
        physdevice: c.VkPhysicalDevice,
        surface: c.VkSurfaceKHR,
    ) !@This() {
        var details = @This(){
            .capabilities = undefined,
        };

        const ret = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
            physdevice,
            surface,
            &details.capabilities,
        );

        if (ret != c.VK_SUCCESS) {
            std.log.err("Failed to query swap chain support details ({})", .{ret});
            return Error.VkQueryError;
        }

        var formatc: u32 = 0;
        const ret2 = c.vkGetPhysicalDeviceSurfaceFormatsKHR(
            physdevice,
            surface,
            &formatc,
            null,
        );

        if (ret2 != c.VK_SUCCESS) {
            std.log.err("Failed to query swap chain surface formats ({})", .{ret2});
            return Error.VkQueryError;
        }

        if (formatc != 0) {
            details.formats = alloc.alloc(c.VkSurfaceFormatKHR, formatc) catch {
                return Error.OOMError;
            };
            errdefer alloc.free(details.formats.?);

            const ret3 = c.vkGetPhysicalDeviceSurfaceFormatsKHR(
                physdevice,
                surface,
                &formatc,
                details.formats.?.ptr,
            );

            if (ret3 != c.VK_SUCCESS) {
                std.log.err("Failed to query swap chain surface formats ({})", .{ret3});
                return Error.VkQueryError;
            }
        }

        var present_modec: u32 = 0;
        const ret4 = c.vkGetPhysicalDeviceSurfacePresentModesKHR(
            physdevice,
            surface,
            &present_modec,
            null,
        );
        if (ret4 != c.VK_SUCCESS) {
            std.log.err("Failed to query swap chain present modes ({})", .{ret4});
            return Error.VkQueryError;
        }

        if (present_modec != 0) {
            details.present_modes = alloc.alloc(c.VkPresentModeKHR, present_modec) catch {
                return Error.OOMError;
            };
            errdefer alloc.free(details.present_modes.?);
            const ret5 = c.vkGetPhysicalDeviceSurfacePresentModesKHR(
                physdevice,
                surface,
                &present_modec,
                details.present_modes.?.ptr,
            );
            if (ret5 != c.VK_SUCCESS) {
                std.log.err("Failed to query swap chain present modes ({})", .{ret5});
                return Error.VkQueryError;
            }
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
    swap_chain: c.VkSwapchainKHR = null,
    imgs: ?[]c.VkImage = null,
    img_format: c.VkFormat = 0,
    extent: c.VkExtent2D = .{ .width = 0, .height = 0 },

    const Error = error{ SwapChainCreationError, SwapChainGetImagesError, SwapChainDataCreationError };

    pub fn init(
        alloc: std.mem.Allocator,
        support_details: SupportDetails,
        window: ?*c.GLFWwindow,
        surface: c.VkSurfaceKHR,
        qf_ids: QueueFamilyIds,
        device: c.VkDevice,
    ) !@This() {
        var self = @This(){};

        const surface_format: c.VkSurfaceFormatKHR = choose_swap_surface_format(
            support_details.formats.?,
        );
        const present_mode: c.VkPresentModeKHR = choose_swap_present_mode(
            support_details.present_modes.?,
        );

        self.img_format = surface_format.format;
        self.extent = choose_swap_extent(
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
            .imageExtent = self.extent,
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
        const ret = c.vkCreateSwapchainKHR(device, &swap_chain_ci, null, &swap_chain);
        if (ret != c.VK_SUCCESS) {
            std.log.err("Failed to create swap chain ({})", .{ret});
            return Error.SwapChainCreationError;
        }

        self.swap_chain = swap_chain;

        const ret2 = c.vkGetSwapchainImagesKHR(device, swap_chain, &imgc, null);
        if (ret2 != c.VK_SUCCESS) {
            std.log.err("Failed to get swap chain images ({})", .{ret2});
            return Error.SwapChainGetImagesError;
        }

        // free'd in global deinit of this
        self.imgs = alloc.alloc(c.VkImage, imgc) catch {
            return Error.SwapChainCreationError;
        };
        errdefer alloc.free(self.imgs.?);
        const ret3 = c.vkGetSwapchainImagesKHR(device, swap_chain, &imgc, self.imgs.?.ptr);
        if (ret3 != c.VK_SUCCESS) {
            std.log.err("Failed to get swap chain images ({})", .{ret3});
            return Error.SwapChainGetImagesError;
        }

        return self;
    }

    pub fn deinit(
        self: *@This(),
        alloc: std.mem.Allocator,
        device: c.VkDevice,
    ) void {
        if (self.swap_chain != null) {
            c.vkDestroySwapchainKHR(device, self.swap_chain, null);
            self.swap_chain = null;
        }

        if (self.imgs) |imgs| {
            alloc.free(imgs);
            self.imgs = null;
        }
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
