const std = @import("std");

const c = @cImport({
    @cInclude("xlsxio_read.h");
});

/// XLSX Reader handle
pub const Reader = struct {
    handle: c.xlsxioreader,
    allocator: std.mem.Allocator,

    /// Open an XLSX file
    pub fn open(allocator: std.mem.Allocator, filename: []const u8) !Reader {
        const filename_z = try allocator.dupeZ(u8, filename);
        defer allocator.free(filename_z);

        const handle = c.xlsxioread_open(filename_z);
        if (handle == null) {
            return error.OpenFailed;
        }
        return Reader{ .handle = handle, .allocator = allocator };
    }

    /// Open an XLSX file from a file handle
    pub fn openFileHandle(allocator: std.mem.Allocator, filehandle: std.os.fd_t) !Reader {
        const handle = c.xlsxioread_open_filehandle(@intCast(filehandle));
        if (handle == null) {
            return error.OpenFailed;
        }

        return Reader{ .handle = handle, .allocator = allocator };
    }

    /// Open an XLSX file from memory
    pub fn openMemory(allocator: std.mem.Allocator, data: []const u8, freedata: bool) !Reader {
        const handle = c.xlsxioread_open_memory(
            @constCast(data.ptr),
            @intCast(data.len),
            if (freedata) 1 else 0,
        );
        if (handle == null) {
            return error.OpenFailed;
        }

        return Reader{ .handle = handle, .allocator = allocator };
    }

    /// Close the XLSX file
    pub fn close(self: Reader) void {
        c.xlsxioread_close(self.handle);
    }

    /// List all sheets in the workbook
    pub fn listSheets(self: Reader, callback: *const fn (name: []const u8) anyerror!void) !void {
        const wrapper = struct {
            fn callback_wrapper(name: [*c]const u8, data: ?*anyopaque) callconv(.C) c_int {
                const cb = @as(*const fn (name: []const u8) anyerror!void, @ptrCast(@alignCast(data)));
                cb(std.mem.span(name)) catch return 1;
                return 0;
            }
        }.callback_wrapper;

        c.xlsxioread_list_sheets(self.handle, wrapper, @constCast(@ptrCast(@alignCast(callback))));
    }

    /// Open a sheet by name (null for first sheet)
    pub fn openSheet(self: Reader, sheetname: ?[]const u8, flags: SheetFlags) !Sheet {
        const c_sheetname = if (sheetname) |name|
            try self.allocator.dupeZ(u8, name)
        else
            null;
        defer if (c_sheetname) |name| self.allocator.free(name);

        const sheet_handle = c.xlsxioread_sheet_open(
            self.handle,
            if (c_sheetname) |name| name.ptr else null,
            @intCast(flags.toInt()),
        );
        if (sheet_handle == null) {
            return error.SheetOpenFailed;
        }

        return Sheet{ .handle = sheet_handle, .allocator = self.allocator };
    }

    /// Open sheet list
    pub fn openSheetList(self: Reader) !SheetList {
        const sheetlist_handle = c.xlsxioread_sheetlist_open(self.handle);
        if (sheetlist_handle == null) {
            return error.SheetListOpenFailed;
        }

        return SheetList{ .handle = sheetlist_handle };
    }

    /// Process all rows and columns of a worksheet
    pub fn process(
        self: Reader,
        sheetname: ?[]const u8,
        flags: SheetFlags,
        cell_callback: *const fn (row: usize, col: usize, value: []const u8) anyerror!void,
        row_callback: ?*const fn (row: usize, maxcol: usize) anyerror!void,
    ) !void {
        const Context = struct {
            cell_callback: *const fn (row: usize, col: usize, value: []const u8) anyerror!void,
            row_callback: ?*const fn (row: usize, maxcol: usize) anyerror!void,
        };

        const wrappers = struct {
            fn cell_wrapper(row: usize, col: usize, value: [*c]const u8, data: ?*anyopaque) callconv(.C) c_int {
                const ctx = @as(*const Context, @ptrCast(@alignCast(data)));
                ctx.cell_callback(row, col, std.mem.span(value)) catch return 1;
                return 0;
            }
            fn row_wrapper(row: usize, maxcol: usize, data: ?*anyopaque) callconv(.C) c_int {
                const ctx = @as(*const Context, @ptrCast(@alignCast(data)));
                if (ctx.row_callback) |callback| {
                    callback(row, maxcol) catch return 1;
                }
                return 0;
            }
        };

        const c_sheetname = if (sheetname) |name|
            try self.allocator.dupeZ(u8, name)
        else
            null;
        defer if (c_sheetname) |name| self.allocator.free(name);

        var ctx = Context{ .cell_callback = cell_callback, .row_callback = row_callback };
        const result = c.xlsxioread_process(
            self.handle,
            if (c_sheetname) |name| name.ptr else null,
            @intCast(flags.toInt()),
            wrappers.cell_wrapper,
            wrappers.row_wrapper,
            &ctx,
        );

        if (result != 0) {
            return error.ProcessFailed;
        }
    }
};

/// Sheet handle for reading worksheet data
pub const Sheet = struct {
    handle: c.xlsxioreadersheet,
    allocator: std.mem.Allocator,

    /// Close the sheet
    pub fn close(self: Sheet) void {
        c.xlsxioread_sheet_close(self.handle);
    }

    /// Get the last row index read
    pub fn getLastRowIndex(self: Sheet) usize {
        return c.xlsxioread_sheet_last_row_index(self.handle);
    }

    /// Get the last column index read
    pub fn getLastColumnIndex(self: Sheet) usize {
        return c.xlsxioread_sheet_last_column_index(self.handle);
    }

    /// Get the flags used to open the sheet
    pub fn getFlags(self: Sheet) SheetFlags {
        return SheetFlags.fromInt(c.xlsxioread_sheet_flags(self.handle));
    }

    /// Move to the next row
    pub fn nextRow(self: Sheet) bool {
        return c.xlsxioread_sheet_next_row(self.handle) != 0;
    }

    /// Get the next cell as a string (caller must free the result)
    pub fn nextCellString(self: Sheet) !?[]u8 {
        var value: [*c]u8 = null;
        if (c.xlsxioread_sheet_next_cell_string(self.handle, &value) != 0) {
            // If the function returns non-zero, value should be non-null
            const result = std.mem.span(value);
            return try self.allocator.dupe(u8, result);
        }
        return null;
    }

    /// Get the next cell as an integer
    pub fn nextCellInt(self: Sheet) !?i64 {
        var value: i64 = 0;
        if (c.xlsxioread_sheet_next_cell_int(self.handle, &value) != 0) {
            return value;
        }
        return null;
    }

    /// Get the next cell as a float
    pub fn nextCellFloat(self: Sheet) !?f64 {
        var value: f64 = 0.0;
        if (c.xlsxioread_sheet_next_cell_float(self.handle, &value) != 0) {
            return value;
        }
        return null;
    }

    /// Get the next cell as a datetime
    pub fn nextCellDateTime(self: Sheet) !?i64 {
        var value: i64 = 0;
        if (c.xlsxioread_sheet_next_cell_datetime(self.handle, &value) != 0) {
            return value;
        }
        return null;
    }

    /// Get the next cell as a generic value (caller must free the result)
    pub fn nextCell(self: Sheet) ?[]u8 {
        const value = c.xlsxioread_sheet_next_cell(self.handle);
        if (value != null) {
            return std.mem.span(value);
        }
        return null;
    }

    /// Iterator for reading all cells in a row
    pub const RowIterator = struct {
        sheet: Sheet,
        current_cell: ?[]u8,

        pub fn init(sheet: Sheet) RowIterator {
            return RowIterator{ .sheet = sheet, .current_cell = null };
        }

        pub fn next(self: *RowIterator) ?[]u8 {
            const cell = self.sheet.nextCell();
            self.current_cell = cell;
            return cell;
        }

        pub fn deinit(self: *RowIterator) void {
            if (self.current_cell) |cell| {
                c.xlsxioread_free(@ptrCast(cell.ptr));
            }
        }
    };

    /// Get an iterator for the current row
    pub fn rowIterator(self: Sheet) RowIterator {
        return RowIterator.init(self);
    }
};

/// Sheet list handle for enumerating worksheets
pub const SheetList = struct {
    handle: c.xlsxioreadersheetlist,

    /// Close the sheet list
    pub fn close(self: SheetList) void {
        c.xlsxioread_sheetlist_close(self.handle);
    }

    /// Get the next sheet name
    pub fn next(self: SheetList) ?[]const u8 {
        const name = c.xlsxioread_sheetlist_next(self.handle);
        if (name != null) {
            return std.mem.span(name);
        }
        return null;
    }

    /// Iterator for sheet names
    pub const Iterator = struct {
        sheetlist: SheetList,

        pub fn init(sheetlist: SheetList) Iterator {
            return Iterator{ .sheetlist = sheetlist };
        }

        pub fn next(self: *Iterator) ?[]const u8 {
            return self.sheetlist.next();
        }
    };

    /// Get an iterator for sheet names
    pub fn iterator(self: SheetList) Iterator {
        return Iterator.init(self);
    }
};

/// Sheet flags for controlling how data is processed
pub const SheetFlags = packed struct {
    skip_empty_rows: bool = false,
    skip_empty_cells: bool = false,
    skip_extra_cells: bool = false,
    skip_hidden_rows: bool = false,
    _padding: u28 = 0,

    pub const none = SheetFlags{};
    pub const skip_all_empty = SheetFlags{ .skip_empty_rows = true, .skip_empty_cells = true };

    pub fn toInt(self: SheetFlags) u32 {
        var flags: u32 = 0;
        if (self.skip_empty_rows) flags |= c.XLSXIOREAD_SKIP_EMPTY_ROWS;
        if (self.skip_empty_cells) flags |= c.XLSXIOREAD_SKIP_EMPTY_CELLS;
        if (self.skip_extra_cells) flags |= c.XLSXIOREAD_SKIP_EXTRA_CELLS;
        if (self.skip_hidden_rows) flags |= c.XLSXIOREAD_SKIP_HIDDEN_ROWS;
        return flags;
    }

    pub fn fromInt(flags: u32) SheetFlags {
        return SheetFlags{
            .skip_empty_rows = (flags & c.XLSXIOREAD_SKIP_EMPTY_ROWS) != 0,
            .skip_empty_cells = (flags & c.XLSXIOREAD_SKIP_EMPTY_CELLS) != 0,
            .skip_extra_cells = (flags & c.XLSXIOREAD_SKIP_EXTRA_CELLS) != 0,
            .skip_hidden_rows = (flags & c.XLSXIOREAD_SKIP_HIDDEN_ROWS) != 0,
        };
    }
};

/// Free memory allocated by the library
pub fn free(data: []u8) void {
    c.xlsxioread_free(@ptrCast(data.ptr));
}

/// Cell value with type information
pub const CellValue = union(enum) {
    string: []u8,
    integer: i64,
    float: f64,
    datetime: i64,
    empty,

    pub fn deinit(self: CellValue, allocator: std.mem.Allocator) void {
        switch (self) {
            .string => |s| allocator.free(s),
            else => {},
        }
    }
};

/// Enhanced sheet with typed cell reading
pub const TypedSheet = struct {
    sheet: Sheet,

    pub fn init(sheet: Sheet) TypedSheet {
        return TypedSheet{ .sheet = sheet };
    }

    pub fn close(self: TypedSheet) void {
        self.sheet.close();
    }

    pub fn nextRow(self: TypedSheet) bool {
        return self.sheet.nextRow();
    }

    /// Get the next cell with type information
    pub fn nextCell(self: TypedSheet) !?CellValue {
        // Get the raw cell value first
        const raw_value = self.sheet.nextCell() orelse return null;

        // Try to parse as different types in order of preference
        const value_str = raw_value;

        // Try to parse as integer
        if (std.fmt.parseInt(i64, value_str, 10)) |integer| {
            // Free the original memory since we're not using it as a string
            c.xlsxioread_free(@ptrCast(raw_value.ptr));
            return CellValue{ .integer = integer };
        } else |_| {}

        // Try to parse as float
        if (std.fmt.parseFloat(f64, value_str)) |float| {
            // Free the original memory since we're not using it as a string
            c.xlsxioread_free(@ptrCast(raw_value.ptr));
            return CellValue{ .float = float };
        } else |_| {}

        // Try to parse as datetime (basic ISO format check)
        if (value_str.len >= 19 and value_str[4] == '-' and value_str[7] == '-' and value_str[10] == 'T') {
            // Basic ISO datetime format check - in a real implementation you'd use a proper datetime parser
            // For now, just treat as string
        }

        // For string values, we need to duplicate the memory and then free the original
        const duplicated_string = try self.sheet.allocator.dupe(u8, value_str);
        c.xlsxioread_free(@ptrCast(raw_value.ptr));
        return CellValue{ .string = duplicated_string };
    }

    /// Iterator for typed cells in a row
    pub const TypedRowIterator = struct {
        sheet: TypedSheet,
        current_cell: ?CellValue,

        pub fn init(sheet: TypedSheet) TypedRowIterator {
            return TypedRowIterator{ .sheet = sheet, .current_cell = null };
        }

        pub fn next(self: *TypedRowIterator) !?CellValue {
            const cell = try self.sheet.nextCell();
            self.current_cell = cell;
            return cell;
        }

        pub fn deinit(self: *TypedRowIterator) void {
            if (self.current_cell) |cell| {
                cell.deinit(self.sheet.sheet.allocator);
            }
        }
    };

    /// Get an iterator for typed cells in the current row
    pub fn typedRowIterator(self: TypedSheet) TypedRowIterator {
        return TypedRowIterator.init(self);
    }
};
