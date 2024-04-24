const std = @import("std");
const uefi = std.os.uefi;

const EfiInitrdDp = extern struct {
    vendor: uefi.DevicePath.Media.VendorDevicePath align(1) = uefi.DevicePath.Media.VendorDevicePath{ .type = uefi.DevicePath.Type.Media, .subtype = uefi.DevicePath.Media.Subtype.Vendor, .length = @sizeOf(uefi.DevicePath.Media.VendorDevicePath), .guid = uefi.Guid{
        .time_low = 0x5568e427,
        .time_mid = 0x68fc,
        .time_high_and_version = 0x4f3d,
        .clock_seq_high_and_reserved = 0xac,
        .clock_seq_low = 0x74,
        .node = [_]u8{ 0xca, 0x55, 0x52, 0x31, 0xcc, 0x68 },
    } },
    end: uefi.DevicePath.End.EndEntireDevicePath align(1) = .{
        .type = uefi.DevicePath.Type.End,
        .subtype = uefi.DevicePath.End.Subtype.EndEntire,
        .length = @sizeOf(uefi.protocol.DevicePath),
    },
};

const efi_initrd_dp: EfiInitrdDp align(8) = EfiInitrdDp{};

const EfiLoadFile2 = extern struct {
    loadFile: *const fn (self: ?*@This(), file_path: ?*uefi.protocol.DevicePath, boot_policy: bool, buffer_size: ?*usize, buffer: ?*anyopaque) callconv(uefi.cc) uefi.Status,
};
const InitrdLoadFile = extern struct {
    load_file: EfiLoadFile2,
    addr: [*]const u8,
    length: usize,
    pub const guid: uefi.Guid align(8) = uefi.Guid{
        .time_low = 0x4006c0c1,
        .time_mid = 0xfcb3,
        .time_high_and_version = 0x403e,
        .clock_seq_high_and_reserved = 0x99,
        .clock_seq_low = 0x6d,
        .node = [_]u8{ 0x4a, 0x6c, 0x87, 0x24, 0xe0, 0x6d },
    };
};

fn loadInitrd(self: ?*EfiLoadFile2, file_path: ?*uefi.protocol.DevicePath, boot_policy: bool, buffer_size: ?*usize, buffer: ?*anyopaque) callconv(uefi.cc) uefi.Status {
    const this: *InitrdLoadFile = if (self) |s| @ptrCast(s) else return .InvalidParameter;
    const buffer_sz = buffer_size orelse return .InvalidParameter;
    if (file_path == null) {
        return .InvalidParameter;
    }

    if (boot_policy) {
        return uefi.Status.Unsupported;
    }
    if (this.length == 0) {
        return uefi.Status.NotFound;
    }
    if (buffer == null or buffer_sz.* < this.length) {
        buffer_sz.* = this.length;
        return uefi.Status.BufferTooSmall;
    }

    const buf: [*]u8 = @ptrCast(buffer);
    @memcpy(buf, this.addr[0..this.length]);
    buffer_sz.* = this.length;
    return uefi.Status.Success;
}

pub fn initrdReg(alloc: std.mem.Allocator, bs: *uefi.tables.BootServices, initrd: []const u8) !?uefi.Handle {
    // Nullability is explicitly required
    // see https://github.com/tianocore/edk2/blob/master/MdeModulePkg/Core/Dxe/Hand/Handle.c#L415
    var handle: ?uefi.Handle = null;

    if (initrd.len == 0) {
        return null;
    }

    var handle_check: ?uefi.Handle = null;
    var dp: *EfiInitrdDp = @constCast(&efi_initrd_dp);
    const status = bs.locateDevicePath(&InitrdLoadFile.guid, @ptrCast(&dp), &handle_check);
    if (status != .NotFound) {
        return error.AlreadyStarted;
    }

    const loader = try alloc.create(InitrdLoadFile);
    errdefer alloc.destroy(loader);
    loader.* = InitrdLoadFile{
        .load_file = .{
            .loadFile = &loadInitrd,
        },
        .addr = initrd.ptr,
        .length = initrd.len,
    };

    try bs.installMultipleProtocolInterfaces(@ptrCast(&handle), &uefi.protocol.DevicePath.guid, &efi_initrd_dp, &InitrdLoadFile.guid, loader, @as(usize, 0)).err();
    return null;
}

pub fn initrdUnreg(alloc: std.mem.Allocator, bs: *uefi.tables.BootServices, initrd_handle: uefi.Handle) !void {
    var handle = initrd_handle;
    const loader = try bs.openProtocolSt(InitrdLoadFile, handle);
    defer alloc.destroy(loader);

    try bs.uninstallMultipleProtocolInterfaces(&handle, &uefi.protocol.DevicePath.guid, &efi_initrd_dp, &InitrdLoadFile.guid, loader, @as(usize, 0)).err();
}
