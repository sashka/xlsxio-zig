# A thin XLSX I/O wrapper for Zig

Only the read functionality of [XLSX I/O](https://github.com/brechtsanders/xlsxio) is wrapped here since I only need to read XLSX files.

```zig
const xlsxio = @import("xlsxio");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
    // Open an XLSX file
    var reader = try xlsxio.Reader.open(allocator, "data.xlsx");
    defer reader.close();
    
    // Open the first sheet
    var sheet = try reader.openSheet(null, .{});
    defer sheet.close();
    
    // Read all rows and cells
    while (sheet.nextRow()) {
        while (sheet.nextCell()) |cell| {
            std.debug.print("{s}\t", .{cell});
            xlsxio.free(cell);
        }
        std.debug.print("\n", .{});
    }
}
```

## Install

I use this package as part of a project source tree like "/pkg/xlsxio", so my `build.zig.zon` contains these dependencies:

```zig
.dependencies = .{
    .xlsxio = .{
        .path = "pkg/xlsxio",
    },
    .expat = .{
        .url = "git+https://github.com/allyourcodebase/libexpat.git#2.7.1",
        .hash = "libexpat-2.7.1-y_akI1M7AAA1huPJVegH4dosRVA-lMRgzMuX9vC7aB1s",
    },
    .libzip = .{
        .url = "git+https://github.com/allyourcodebase/libzip.git#1.11.2",
        .hash = "libzip-1.11.2-WX_L8Ck4AADFFAXJ5QvIrrZ9osNgIQJWPgih_6rg8K97",
    },
},
```

## API

The main types are:
- `Reader` - for opening and managing XLSX files
- `Sheet` - for reading worksheet data
- `SheetList` - for enumerating worksheets

## License

MIT License, same as the underlying [XLSX I/O](https://github.com/brechtsanders/xlsxio) library.
