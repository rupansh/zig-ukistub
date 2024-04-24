const std = @import("std");
const uefi = std.os.uefi;
const File = uefi.protocol.File;

const DosHeader = extern struct {
    e_magic: u16 align(1),
    e_cblp: u16 align(1),
    e_cp: u16 align(1),
    e_crlc: u16 align(1),
    e_cparhdr: u16 align(1),
    e_minalloc: u16 align(1),
    e_maxalloc: u16 align(1),
    e_ss: u16 align(1),
    e_sp: u16 align(1),
    e_csum: u16 align(1),
    e_ip: u16 align(1),
    e_cs: u16 align(1),
    e_lfarlc: u16 align(1),
    e_ovno: u16 align(1),
    e_res: [4]u16 align(1),
    e_oemid: u16 align(1),
    e_oeminfo: u16 align(1),
    e_res2: [10]u16 align(1),
    e_lfanew: u32 align(1),
};

const pe_header_machine: u16 = 0x8664;
const FileHeader = extern struct {
    machine: u16 align(1),
    number_of_sections: u16 align(1),
    time_date_stamp: u32 align(1),
    pointer_to_symbol_table: u32 align(1),
    number_of_symbols: u32 align(1),
    size_of_optional_header: u16 align(1),
    characteristics: u16 align(1),
};
pub const SectionHeader = extern struct {
    name: [8]u8 align(1),
    virtual_size: u32 align(1),
    virtual_address: u32 align(1),
    size_of_raw_data: u32 align(1),
    pointer_to_raw_data: u32 align(1),
    pointer_to_relocations: u32 align(1),
    pointer_to_linenumbers: u32 align(1),
    number_of_relocations: u16 align(1),
    number_of_linenumbers: u16 align(1),
    characteristics: u32 align(1),
};

const EFI_FILE_MODE_READ: u64 = 0x0000000000000001;
const DOS_MAGIC: u16 = 0x5A4D;

pub fn locateSections(comptime N: usize, lookup_names: [N][]const u8, dir: *const File, path: [:0]u16) ![N]?SectionHeader {
    var handle: *const File = undefined;
    try dir.open(&handle, path, EFI_FILE_MODE_READ, 0).err();
    defer _ = dir.close();

    var len: usize = @sizeOf(DosHeader);
    var dos_header = std.mem.zeroes(DosHeader);
    try handle.read(&len, @ptrCast(&dos_header)).err();
    if (len != @sizeOf(DosHeader)) {
        return error.EfiLoad;
    }
    if (dos_header.e_magic != DOS_MAGIC) {
        return error.EfiLoad;
    }

    try handle.setPosition(dos_header.e_lfanew).err();

    var magic = [_]u8{0} ** 4;
    len = magic.len;
    try handle.read(&len, &magic).err();
    if (len == 0) {
        return error.EfiLoad;
    }
    if (magic[0] != 'P' or magic[1] != 'E' or magic[2] != 0 or magic[3] != 0) {
        return error.EfiLoad;
    }

    var pe_header = std.mem.zeroes(FileHeader);
    len = @sizeOf(FileHeader);
    try handle.read(&len, @ptrCast(&pe_header)).err();
    if (len != @sizeOf(FileHeader)) {
        return error.EfiLoad;
    }

    if (pe_header.machine != pe_header_machine) {
        return error.EfiLoad;
    }
    if (pe_header.number_of_sections > 96) {
        return error.EfiLoad;
    }

    try handle.setPosition(dos_header.e_lfanew + @sizeOf(@TypeOf(magic)) + @sizeOf(FileHeader) + pe_header.size_of_optional_header).err();

    var sections = [_]?SectionHeader{null} ** N;

    for (0..pe_header.number_of_sections) |_| {
        var section_header = std.mem.zeroes(SectionHeader);
        len = @sizeOf(SectionHeader);
        try handle.read(&len, @ptrCast(&section_header)).err();
        if (len != @sizeOf(SectionHeader)) {
            return error.EfiLoad;
        }
        for (lookup_names, 0..) |name, j| {
            if (std.mem.startsWith(u8, &section_header.name, name)) {
                sections[j] = section_header;
            }
        }
    }

    return sections;
}
