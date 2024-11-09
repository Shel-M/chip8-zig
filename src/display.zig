const std = @import("std");
const SDL = @import("sdl.zig").SDL;
const x_max_size = @import("main.zig").x_max_size;
const y_max_size = @import("main.zig").y_max_size;

const total_size = x_max_size * y_max_size;

const chip8_dimensions: [2]u32 = .{ 64, 32 };
const hp48_dimensions: [2]u32 = .{ 128, 64 };

pub const Display = struct {
    x_size: u32,
    y_size: u32,
    sdl: *SDL,

    pixels: [total_size]u32,
    hp48: bool,

    pub fn init(sdl: *SDL, hp48: bool) Display {
        const dimensions = if (hp48) hp48_dimensions else chip8_dimensions;

        return Display{
            .x_size = dimensions[0],
            .y_size = dimensions[1],
            .sdl = sdl,
            .pixels = .{0} ** total_size,
            .hp48 = false,
        };
    }

    pub fn clear(self: *Display) void {
        self.pixels = .{0} ** total_size;
    }

    // Discards updates out of range
    pub fn set_pixel(self: *Display, x_pos: u32, y_pos: u32, value: bool) void {
        if (x_pos > self.x_size or y_pos > self.y_size) {
            return;
        }
        const actual_y_pos = self.x_size * y_pos;
        const pos = (x_pos + actual_y_pos);
        const b: u32 = @intCast(@intFromBool(value));
        self.pixels[pos] = b * 0xff_ff_ff;
    }

    pub fn xor_pixel(self: *Display, x_pos: u32, y_pos: u32) bool {
        if (x_pos > self.x_size or y_pos > self.y_size) {
            return false;
        }
        const actual_y_pos = self.x_size * y_pos;
        const pos = (x_pos + actual_y_pos);
        const old = self.pixels[pos];
        self.pixels[pos] ^= 0xff_ff_ff;

        return old > self.pixels[pos];
    }

    pub fn resize(self: *Display, hp48: bool) !void {
        if (self.hp48 == hp48) {
            return;
        }

        if (!hp48) {
            self.x_size = 64;
            self.y_size = 32;
        } else {
            self.x_size = x_max_size;
            self.y_size = y_max_size;
        }

        try self.sdl.update_screen_size(@intCast(self.x_size), @intCast(self.y_size));
    }

    pub fn update_sdl(self: *Display) !void {
        const end = self.x_size * self.y_size;
        try self.sdl.update_texture(self.pixels[0..end]);
    }
};
