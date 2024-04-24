const std = @import("std");
const uefi = std.os.uefi;
const fmt = std.fmt;
const EfiVar = @import("efivar.zig").EfiVar;
const util = @import("util.zig");
const pe = @import("pe.zig");
const linuxExec = @import("linux.zig").linuxExec;

var con_out: *uefi.protocol.SimpleTextOutput = undefined;
const global_guid align(8) = uefi.Guid{
    .time_low = 0x8BE4DF61,
    .time_mid = 0x93CA,
    .time_high_and_version = 0x11d2,
    .clock_seq_high_and_reserved = 0xAA,
    .clock_seq_low = 0x0D,
    .node = .{ 0x00, 0xE0, 0x98, 0x03, 0x2B, 0x8C },
};

pub fn init() !void {
    const sys = uefi.system_table;
    const bs = sys.boot_services.?;
    const rt = sys.runtime_services;
    const alloc = uefi.pool_allocator;
    var buf: [40]u8 = undefined;

    const loaded_image = try bs.openProtocolSt(uefi.protocol.LoadedImage, uefi.handle);
    const loaded_image_path = try util.devicePathToStr(alloc, loaded_image.file_path);
    defer alloc.free(loaded_image_path);

    var sfsp = try bs.openProtocolSt(uefi.protocol.SimpleFileSystem, loaded_image.device_handle.?);
    var root_dir: *const uefi.protocol.File = undefined;
    try sfsp.openVolume(&root_dir).err();

    var secure: bool = false;
    const secure_var = EfiVar.getRaw(alloc, rt, "SecureBoot", &global_guid);
    if (secure_var) |evc| {
        var ev = evc;
        defer ev.deinit();
        secure = ev.buf.ptr == undefined;
    } else |_| {
        secure = false;
    }

    const section_lookup = [_][]const u8{
        ".cmdline",
        ".linux",
        ".initrd",
        ".ucode",
        ".splash",
    };
    util.printf(buf[0..], con_out, "locating sections", .{});
    const sections = try pe.locateSections(5, section_lookup, root_dir, loaded_image_path);
    util.printf(buf[0..], con_out, "done", .{});

    var cmdline: ?[]u8 = null;
    if (sections[0]) |cmd_section| {
        const cmdline_raw: [*]u8 = loaded_image.image_base + cmd_section.virtual_address;
        cmdline = cmdline_raw[0..cmd_section.virtual_size];
    }

    if (!secure and loaded_image.load_options_size > 0) {
        const options: [*]align(1) u16 = @ptrCast(loaded_image.load_options);
        const cmdline_len = (loaded_image.load_options_size / @sizeOf(u16)) * @sizeOf(u8);
        const cmdline_a = try alloc.alloc(u8, cmdline_len);
        defer alloc.free(cmdline_a);
        for (0..cmdline_len) |i| {
            cmdline_a[i] = @intCast(options[i]);
        }
        cmdline = cmdline_a;
    }

    util.printf(buf[0..], con_out, "executing linux!", .{});
    const linux = (loaded_image.image_base + sections[1].?.virtual_address)[0..@intCast(sections[1].?.virtual_size)];
    const initrd = (loaded_image.image_base + sections[2].?.virtual_address)[0..@intCast(sections[2].?.virtual_size)];
    try linuxExec(
        alloc,
        bs,
        cmdline,
        linux,
        initrd,
    );
}

pub fn main() usize {
    var buf: [40]u8 = undefined;
    con_out = uefi.system_table.con_out.?;
    init() catch |err| {
        util.printf(buf[0..], con_out, "{}", .{err});
        _ = uefi.system_table.boot_services.?.stall(3_000_000);
        return 1;
    };
    return 0;
}
