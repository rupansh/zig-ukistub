const std = @import("std");
const uefi = std.os.uefi;
const BootServices = uefi.tables.BootServices;
const util = @import("util.zig");
const initrd = @import("initrd.zig");

const LinuxPayloadDp = extern struct {
    payload: uefi.DevicePath.Media.VendorDevicePath align(1) = uefi.DevicePath.Media.VendorDevicePath{ .type = uefi.DevicePath.Type.Media, .subtype = uefi.DevicePath.Media.Subtype.Vendor, .length = @offsetOf(LinuxPayloadDp, "end"), .guid = uefi.Guid{
        .time_low = 0x55c5d1f8,
        .time_mid = 0x04cd,
        .time_high_and_version = 0x46b5,
        .clock_seq_high_and_reserved = 0x8a,
        .clock_seq_low = 0x20,
        .node = [_]u8{ 0xe5, 0x6c, 0xbb, 0x30, 0x52, 0xd0 },
    } },
    end: uefi.DevicePath.End.EndEntireDevicePath align(1) = uefi.DevicePath.End.EndEntireDevicePath{
        .type = uefi.DevicePath.Type.End,
        .subtype = uefi.DevicePath.End.Subtype.EndEntire,
        .length = @sizeOf(LinuxPayloadDp) - @offsetOf(LinuxPayloadDp, "end"),
    },
};

pub fn linuxExec(alloc: std.mem.Allocator, bs: *BootServices, cmdline: ?[]u8, linux: []const u8, initrd_im: []const u8) !void {
    const linux_dp = LinuxPayloadDp{};
    var linux_image: ?uefi.Handle = undefined;
    try bs.loadImage(false, uefi.handle, @ptrCast(&linux_dp), linux.ptr, linux.len, &linux_image).err();
    const linux_im = linux_image.?;

    defer _ = bs.unloadImage(linux_im);

    const loaded_image = try bs.openProtocolSt(uefi.protocol.LoadedImage, linux_im);

    var utf16_cmdline: ?[]u16 = null;
    defer if (utf16_cmdline) |line| alloc.free(line);

    if (cmdline) |line| {
        utf16_cmdline = try std.unicode.utf8ToUtf16LeAlloc(alloc, line);
        loaded_image.load_options = line.ptr;
        loaded_image.load_options_size = @intCast(line.len);
    }

    const initrd_handle = try initrd.initrdReg(alloc, bs, initrd_im);
    defer if (initrd_handle) |handle| initrd.initrdUnreg(alloc, bs, handle) catch {};

    var buf = [_]u8{0} ** 40;
    util.printf(&buf, uefi.system_table.con_out.?, "Starting Linux kernel...", .{});
    try bs.startImage(linux_im, null, null).err();
    return error.StartImg;
}
