const std = @import("std");
const uefi = std.os.uefi;
const toU16 = @import("util.zig").toEfiStringLiteral;

pub const EfiVar = struct {
    buf: []u8,
    alloc: std.mem.Allocator,
    pub fn getRaw(allocator: std.mem.Allocator, rt: *uefi.tables.RuntimeServices, comptime name: [:0]const u8, guid: *align(8) const uefi.Guid) !EfiVar {
        var l: usize = @sizeOf(*u16) * 1024;
        var buf = try allocator.alloc(u8, l);
        errdefer allocator.free(buf);

        try rt.getVariable(toU16(name).ptr, guid, undefined, &l, @ptrCast(&buf)).err();

        return EfiVar{ .buf = buf, .alloc = allocator };
    }
    pub fn deinit(self: *EfiVar) void {
        self.alloc.free(self.buf);
    }
};
