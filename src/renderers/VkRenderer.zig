const c = @import("c_vk_glfw");
const std = @import("std");

window: *c.GLFWwindow,

pub const Error = error{
    WindowSetupError,
    RenderError,
};

pub fn init() Error!@This() {
    _ = c.glfwInit();
    _ = c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    _ = c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);

    const window = c.glfwCreateWindow(500, 500, "Vulkan", null, null) orelse
        return Error.WindowSetupError;

    return @This(){
        .window = window,
    };
}

pub fn deinit(self: *@This()) void {
    c.glfwDestroyWindow(self.window);

    c.glfwTerminate();
}

// must catch all errors, since this is a subtrait of Renderer.render
// and error union return is expensive for every loop it.
pub fn render(self: *@This()) bool {
    if (c.glfwWindowShouldClose(self.window) == 0) {
        c.glfwPollEvents();
    }
    return true;
}
