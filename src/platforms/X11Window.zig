const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const hack = @import("../util/hack.zig");
const env = @import("../util/env.zig");
const io = @import("../util/io.zig");

const ne = @import("builtin").target.cpu.arch.endian();
const PrefFatPtr = hack.PrefFatPtr;

fd: posix.socket_t,

root_window: u32,
resource_id_base: u32,
resource_id_mask: u32,
resource_id_counter: u32 = 0,

outbuf: [65536]u8 = undefined,
outlen: usize = 0,

pub const Error = error{
    ConnectError,
    ConnectRequestOfferError,
    ConnectRequestAnswerError,
    SendError,
    EventReadError,
    NoHomeDirError,
    HomeDirReadError,
    NoCookieError,
    BufferError,
    CloseError,
};

const XAuthorityEntry = struct {
    family: u16,
    addr: PrefFatPtr(u16, u8),
    display: PrefFatPtr(u16, u8),
    name: PrefFatPtr(u16, u8),
    data: PrefFatPtr(u16, u8),
};

fn errprint(eventbuf: [32]u8) void {
    std.debug.print("Error: code={} seq={} resid={x} major={} minor={}\n", .{
        eventbuf[1],
        std.mem.readInt(u16, eventbuf[2..4], ne),
        std.mem.readInt(u32, eventbuf[4..8], ne),
        eventbuf[9],
        eventbuf[8],
    });
}

fn read_xauth_cookie() Error![]const u8 {
    const home = env.get("HOME") orelse return Error.NoHomeDirError;

    var path_buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/.Xauthority", .{home}) catch
        return Error.BufferError;

    const file = std.Io.Dir.openFileAbsolute(io.get(), path, .{}) catch
        return Error.HomeDirReadError;
    defer file.close(io.get());

    var buf: [4096]u8 = undefined;
    var file_reader = file.reader(io.get(), &buf);
    const reader = &file_reader.interface;
    reader.readSliceAll(&buf) catch return Error.HomeDirReadError;
    var cursor: []const u8 = buf[0..];
    while (cursor.len > 0) {
        const xauthentry = hack.complex_parsetostruct(
            &cursor,
            XAuthorityEntry,
            .big,
        );

        if (std.mem.eql(u8, xauthentry.name.slice(), "MIT-MAGIC-COOKIE-1") and
            std.mem.eql(u8, xauthentry.display.slice(), "0"))
        {
            return xauthentry.data.slice()[0..16];
        }
    }
    return Error.NoCookieError;
}

fn connect() Error!@This() {
    const fd: i32 = @intCast(linux.socket(posix.AF.UNIX, posix.SOCK.STREAM, 0));
    if (fd < 0) return Error.ConnectError;

    var addr = std.mem.zeroes(posix.sockaddr.un);
    addr.family = posix.AF.UNIX;

    const socket_path = "/tmp/.X11-unix/X0";
    @memcpy(addr.path[0..socket_path.len], socket_path);

    if (linux.connect(fd, @ptrCast(&addr), @sizeOf(posix.sockaddr.un)) < 0) {
        _ = posix.close(fd);
        return Error.ConnectError;
    }

    std.log.debug("(1/2) Connected!", .{});

    const auth_name = "MIT-MAGIC-COOKIE-1";
    const auth_data = read_xauth_cookie() catch |err| {
        std.log.err("XAuth Error: {s}", .{@errorName(err)});
        return Error.ConnectRequestOfferError;
    };

    const auth_name_len: u16 = @intCast(auth_name.len);
    const auth_data_len: u16 = @intCast(auth_data.len);
    const auth_name_pad = (4 - (auth_name.len % 4)) % 4;
    const auth_data_pad = (4 - (auth_data.len % 4)) % 4;

    {
        const SetupReq = extern struct {
            const maxsize: usize = 256;
            const pre_flexbuf_size = @sizeOf(Header);

            header: Header,
            name_data: [maxsize - pre_flexbuf_size]u8 = undefined,

            const Header = extern struct {
                byte_order: u8,
                pad: u8,
                major_version: u16,
                minor_version: u16,
                auth_name_len: u16,
                auth_data_len: u16,
                pad2: u16,
            };
        };

        var setupreq = SetupReq{ .header = .{
            .byte_order = if (ne == .little) 'l' else 'B',
            .pad = 0,
            .major_version = std.mem.nativeTo(u16, 11, ne),
            .minor_version = std.mem.nativeTo(u16, 0, ne),
            .auth_name_len = std.mem.nativeTo(u16, auth_name_len, ne),
            .auth_data_len = std.mem.nativeTo(u16, auth_data_len, ne),
            .pad2 = 0,
        } };
        @memcpy(setupreq.name_data[0..auth_name.len], auth_name);
        @memset(setupreq.name_data[auth_name.len .. auth_name.len + auth_name_pad], 0);
        @memcpy(setupreq.name_data[auth_name.len + auth_name_pad ..][0..auth_data.len], auth_data);
        @memset(setupreq.name_data[auth_name.len + auth_name_pad + auth_data.len ..][0..auth_data_pad], 0);
        const used_size: usize = SetupReq.pre_flexbuf_size + auth_name.len + auth_name_pad + auth_data.len + auth_data_pad;

        const n = linux.write(fd, std.mem.asBytes(&setupreq), used_size);
        if (n < 0) return Error.ConnectRequestOfferError;
    }

    var repbuf: [4096]u8 = undefined;

    var header: [8]u8 = undefined;
    var hreceived: usize = 0;
    while (hreceived < 8) {
        const n = posix.read(fd, header[hreceived..8]) catch
            return Error.ConnectRequestAnswerError;
        if (n == 0) return Error.ConnectRequestAnswerError;
        hreceived += n;
    }

    if (header[0] != 1) {
        // 0 = failed, 2 = authenticate
        std.log.debug("X11 Connection Failed: {d}", .{header[0]});

        if (header[0] == 0) {
            const reason_len = header[1];
            const additional_len = std.mem.readInt(u16, header[6..8], ne);
            const total_len = @as(usize, additional_len) * 4;

            var received: usize = 0;
            while (received < total_len) {
                const n = posix.read(fd, repbuf[received..total_len]) catch return Error.ConnectRequestAnswerError;
                if (n == 0) break;
                received += n;
            }
            std.debug.print("X11 Connection Refused: {s}\n", .{repbuf[0..reason_len]});
        }

        return Error.ConnectRequestAnswerError;
    }

    const additional_len = std.mem.readInt(u16, header[6..8], ne);
    const total_len: usize = 8 + @as(usize, additional_len) * 4;
    @memcpy(repbuf[0..8], &header);
    var received: usize = 8;
    while (received < total_len) {
        const n = posix.read(fd, repbuf[received..total_len]) catch return Error.ConnectRequestAnswerError;
        if (n == 0) return Error.ConnectRequestAnswerError;
        received += n;
    }

    const vendor_len = std.mem.readInt(u16, repbuf[24..26], ne);
    const vendor_padded: usize = (@as(usize, vendor_len) + 3) & ~@as(usize, 3);
    const num_formats: usize = repbuf[29];
    const screens_offset: usize = 40 + vendor_padded + num_formats * 8;

    const x11_window: @This() = .{
        .fd = fd,
        .resource_id_base = std.mem.readInt(u32, repbuf[12..16], ne),
        .resource_id_mask = std.mem.readInt(u32, repbuf[16..20], ne),
        .root_window = std.mem.readInt(u32, repbuf[screens_offset..][0..4], ne),
    };

    std.log.debug("(2/2) Context Created!", .{});
    return x11_window;
}

fn enqueue_out(self: *@This(), data: []const u8) void {
    @memcpy(self.outbuf[self.outlen..(self.outlen + data.len)], data);
    self.outlen += data.len;
}

fn flush_out(self: *@This()) Error!void {
    const n = linux.write(self.fd, &self.outbuf, self.outlen);
    if (n < 0) return Error.SendError;
    self.outlen = 0;
}

fn send(self: *@This(), data: []const u8) Error!void {
    self.enqueue_out(data);
    try self.flush_out();
}

fn new_id(self: *@This()) u32 {
    defer self.resource_id_counter += 1;
    return self.resource_id_base | (self.resource_id_counter & self.resource_id_mask);
}

// transforms your argstruct into an x11 req struct
// (opcode, {x,y,z}) -> {opcode, pad, length, x, y, z}
fn Op(comptime opcode: u8, comptime ArgStruct: type) type {
    const l: u16 = @sizeOf(ArgStruct) / 4 + 1;

    const OpPre = struct {
        opcode: u8 = opcode,
        pad: u8 = 0,
        length: u16 = l,
    };

    return hack.EStructMix(OpPre, ArgStruct);
}

// fills Op(opcode, ArgStruct) from the args of a given func minus self-arg
// e.g. OpFromSelfFunc(8, map_window(self, wid))
//        -> Op(8, struct { wid: u32 })
fn OpFromSelfFunc(comptime opcode: u8, comptime func: anytype) type {
    const ArgSt = hack.ESubStruct(std.meta.ArgsTuple(@TypeOf(func)), 1, null);
    return Op(opcode, ArgSt);
}

fn exec_op(self: *@This(), comptime opcode: u8, func: anytype, args: anytype) void {
    const req = hack.tupled_init(OpFromSelfFunc(opcode, func), args);
    self.enqueue_out(std.mem.asBytes(&req));
}

fn create_window(
    self: *@This(),
    wid: u32,
    parent: u32,
    dim: [4]u16, // x, y, width, height
    border_width: u16,
    class: u16,
    visual: u32,
    value_mask: u32,
    background_pixel: u32,
    border_pixel: u32,
    event_mask: u32,
) void {
    exec_op(self, 1, create_window, .{
        wid,
        parent,
        dim,
        border_width,
        class,
        visual,
        value_mask,
        background_pixel,
        border_pixel,
        event_mask,
    });
}

fn map_window(self: *@This(), wid: u32) void {
    exec_op(self, 8, map_window, .{wid});
}

fn create_gc(
    self: *@This(),
    gc: u32,
    drawable: u32,
    value_mask: u32,
    fg: u32,
    bg: u32,
) void {
    exec_op(self, 55, create_gc, .{ gc, drawable, value_mask, fg, bg });
}

fn next_event(self: *@This(), evbuf: *[32]u8) Error!usize {
    return posix.read(self.fd, evbuf) catch {
        return Error.EventReadError;
    };
}

pub fn init() Error!@This() {
    var self = connect() catch |err| {
        std.log.err("Connection Error: {s}", .{@errorName(err)});
        return err;
    };

    const win: u32 = self.new_id();
    const gc: u32 = self.new_id();
    self.create_window(
        win,
        self.root_window,
        [4]u16{ 0, 0, 800, 600 },
        0,
        1,
        0,
        0x80A,
        0,
        0xffffffff,
        0x8000,
    );
    self.create_gc(gc, win, 0x0C, 0xFFFFFF, 0x000000);
    self.map_window(win);
    try self.flush_out();

    return self;
}

pub fn deinit(self: *@This()) void {
    _ = linux.close(self.fd); // no error handling since close
}

// must catch all errors, since this is a subtrait of Window.proc_event
// and error union return is expensive for every loop it.
pub fn proc_event(self: *@This()) bool {
    var ev: [32]u8 = undefined;
    const readbytes = self.next_event(&ev) catch |err| {
        std.log.err("{s}", .{@errorName(err)});
        return false;
    };
    if (readbytes == 0) return false;

    if (ev[0] == 0) {
        errprint(ev);
        return false;
    }

    if (ev[0] == 12) { // expose
        self.flush_out() catch |err| {
            std.log.err("{s}", .{@errorName(err)});
            return false;
        };
    }
    return true;
}
