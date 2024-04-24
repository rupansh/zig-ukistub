const std = @import("std");
const uefi = std.os.uefi;
const DevicePath = uefi.protocol.DevicePath;

pub fn toEfiStringLiteral(comptime s: [:0]const u8) [:0]const u16 {
    const utf16 = std.unicode.utf8ToUtf16LeStringLiteral(s);
    return utf16;
}

// from https://github.com/fifty-six/zbl/blob/master/src/device_path.zig
const tag_to_utf16_literal = init: {
    @setEvalBranchQuota(10000);
    const KV = struct { @"0": []const u8, @"1": []const u16 };

    const enums = [_]type{
        uefi.DevicePath.Media.Subtype,
        uefi.DevicePath.Hardware.Subtype,
        uefi.DevicePath.Type,
    };

    var kv: []const KV = &.{};

    for (enums) |e| {
        const fields = @typeInfo(e).Enum.fields;

        for (fields) |field| {
            kv = kv ++ &[_]KV{.{
                .@"0" = field.name,
                .@"1" = std.unicode.utf8ToUtf16LeStringLiteral(field.name),
            }};
        }
    }

    const map = std.ComptimeStringMap([]const u16, kv);

    break :init map;
};

// from https://github.com/fifty-six/zbl/blob/master/src/device_path.zig
pub fn devicePathToStr(alloc: std.mem.Allocator, dev_path: *DevicePath) ![:0]u16 {
    var res = std.ArrayList(u16).init(alloc);
    errdefer res.deinit();

    var node = dev_path;
    while (node.type != .End) {
        const q_path = node.getDevicePath();
        if (q_path == null) {
            try res.appendSlice(tag_to_utf16_literal.get(@tagName(node.type)).?);
            try res.append('\\');
            node = @as(@TypeOf(node), @ptrCast(@as([*]u8, @ptrCast(node)) + node.length));
            continue;
        }

        const path = q_path.?;
        switch (path) {
            .Hardware => |hw| {
                try res.appendSlice(tag_to_utf16_literal.get(@tagName(hw)).?);
            },
            .Media => |m| {
                switch (m) {
                    .FilePath => |fp| {
                        const fp_path = fp.getPath();
                        var i = @as(usize, 0);
                        while (fp_path[i] != 0) {
                            try res.append(fp_path[i]);
                            i += 1;
                        }
                    },
                    else => {
                        try res.appendSlice(tag_to_utf16_literal.get(@tagName(m)).?);
                    },
                }
            },
            .Messaging, .Acpi => {
                // TODO: upstream
            },
            // We're adding a backslash after anyways, so use that.
            .End => {},
            else => {
                try res.append('?');
            },
        }

        try res.append('\\');

        node = @as(@TypeOf(node), @ptrCast(@as([*]u8, @ptrCast(node)) + node.length));
    }
    _ = res.pop();

    return try res.toOwnedSliceSentinel(0);
}

fn puts(con_out: *uefi.protocol.SimpleTextOutput, msg: []const u8) void {
    for (msg) |c| {
        const c_ = [2:0]u16{ c, 0 };
        _ = con_out.outputString(&c_);
    }
}

pub fn printf(buf: []u8, con_out: *uefi.protocol.SimpleTextOutput, comptime format: []const u8, args: anytype) void {
    puts(con_out, std.fmt.bufPrint(buf, format, args) catch unreachable);
}
