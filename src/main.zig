const std = @import("std");
const posix = std.posix;
const ne = @import("builtin").target.cpu.arch.endian();

const hack = @import("hack.zig");
const util = @import("util.zig");
const PrefFatPtr = hack.PrefFatPtr;
const dprint = util.dprint;
const errprint = util.errprint;

const XContext = struct {
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
        NoCookieError,
    };

    const XAuthorityEntry = struct {
        family: u16,
        addr: PrefFatPtr(u16, u8),
        display: PrefFatPtr(u16, u8),
        name: PrefFatPtr(u16, u8),
        data: PrefFatPtr(u16, u8),
    };

    pub fn errprint(eventbuf: [32]u8) void {
        std.debug.print("Error: code={} seq={} resid={x} major={} minor={}\n", .{
            eventbuf[1],
            std.mem.readInt(u16, eventbuf[2..4], ne),
            std.mem.readInt(u32, eventbuf[4..8], ne),
            eventbuf[9],
            eventbuf[8],
        });
    }

    fn read_xauth_cookie() ![]const u8 {
        const home = std.posix.getenv("HOME") orelse
            return Error.NoHomeDirError;

        var path_buf: [256]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/.Xauthority", .{home});

        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();

        var buf: [4096]u8 = undefined;
        _ = try file.read(&buf);
        var cursor: []const u8 = buf[0..];
        while (cursor.len > 0) {
            const xauthentry = hack.complex_parsetostruct(
                &cursor,
                XAuthorityEntry,
                .big,
            );

            if (util.str_eq(xauthentry.name.slice(), "MIT-MAGIC-COOKIE-1") and
                util.str_eq(xauthentry.display.slice(), "0"))
            {
                return xauthentry.data.slice()[0..16];
            }
        }
        return Error.NoCookieError;
    }

    pub fn connect() Error!XContext {
        const fd = posix.socket(posix.AF.UNIX, posix.SOCK.STREAM, 0) catch {
            return Error.ConnectError;
        };
        var addr = std.mem.zeroes(posix.sockaddr.un);
        addr.family = posix.AF.UNIX;

        const socket_path = "/tmp/.X11-unix/X0";
        @memcpy(addr.path[0..socket_path.len], socket_path);

        posix.connect(fd, @ptrCast(&addr), @sizeOf(posix.sockaddr.un)) catch {
            return Error.ConnectError;
        };

        dprint("(1/2) Connected!");

        const auth_name = "MIT-MAGIC-COOKIE-1";
        const auth_data = read_xauth_cookie() catch |err| {
            std.debug.print("XAuth Error: {s}\n", .{@errorName(err)});
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

            _ = posix.write(fd, std.mem.asBytes(&setupreq)[0..used_size]) catch
                return Error.ConnectRequestOfferError;
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
            dprint(header[0]); // 0 = failed, 2 = authenticate

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

        const xcontext: XContext = .{
            .fd = fd,
            .resource_id_base = std.mem.readInt(u32, repbuf[12..16], ne),
            .resource_id_mask = std.mem.readInt(u32, repbuf[16..20], ne),
            .root_window = std.mem.readInt(u32, repbuf[screens_offset..][0..4], ne),
        };

        dprint("(2/2) Context Created!");
        return xcontext;
    }

    fn enqueue_out(self: *@This(), data: []const u8) void {
        @memcpy(self.outbuf[self.outlen..(self.outlen + data.len)], data);
        self.outlen += data.len;
    }

    pub fn flush_out(self: *@This()) Error!void {
        _ = posix.write(self.fd, self.outbuf[0..self.outlen]) catch {
            return Error.SendError;
        };
        self.outlen = 0;
    }

    pub fn send(self: *@This(), data: []const u8) Error!void {
        self.enqueue_out(data);
        try self.flush_out();
    }

    pub fn new_id(self: *@This()) u32 {
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

    pub fn create_window(
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

    pub fn map_window(self: *@This(), wid: u32) void {
        exec_op(self, 8, map_window, .{wid});
    }

    pub fn create_gc(
        self: *@This(),
        gc: u32,
        drawable: u32,
        value_mask: u32,
        fg: u32,
        bg: u32,
    ) void {
        exec_op(self, 55, create_gc, .{ gc, drawable, value_mask, fg, bg });
    }

    pub fn next_event(self: *@This(), evbuf: *[32]u8) Error!usize {
        return posix.read(self.fd, evbuf) catch {
            return Error.EventReadError;
        };
    }
};

pub fn main() void {
    var xcon: XContext = XContext.connect() catch |err| {
        errprint(err);
        return;
    };

    const win: u32 = xcon.new_id();
    const gc: u32 = xcon.new_id();
    xcon.create_window(
        win,
        xcon.root_window,
        [4]u16{ 0, 0, 800, 600 },
        0,
        1,
        0,
        0x80A,
        0,
        0xffffffff,
        0x8000,
    );
    xcon.create_gc(gc, win, 0x0C, 0xFFFFFF, 0x000000);
    xcon.map_window(win);
    xcon.flush_out() catch |err| {
        errprint(err);
        return;
    };

    while (true) {
        var ev: [32]u8 = undefined;
        const readbytes = xcon.next_event(&ev) catch |err| {
            errprint(err);
            return;
        };
        if (readbytes == 0) break;

        if (ev[0] == 0) {
            XContext.errprint(ev);
            return;
        }

        if (ev[0] == 12) { // expose
            xcon.flush_out() catch |err| {
                errprint(err);
                return;
            };
        }
    }
}
