const c = @import("c_vl_glfw");

pub const Error = error{
    RenderError,
};

pub fn init() Error!@This() {
    const self = @This(){};
    return self;
}

pub fn deinit(self: *@This()) void {
    _ = self;
}

// must catch all errors, since this is a subtrait of Renderer.render
// and error union return is expensive for every loop it.
pub fn render(self: *@This()) bool {
    _ = self;
    return true;
}
