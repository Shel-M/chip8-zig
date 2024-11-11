const std = @import("std");
const SDL = @import("sdl.zig").SDL;
const Display = @import("display.zig").Display;
const VM = @import("chip8.zig").VM;

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const assert = @import("std").debug.assert;

pub const x_max_size = 128;
pub const y_max_size = 64;

pub fn main() !void {
    const initial_x_size = 64;
    const initial_y_size = 32;

    var sdl: SDL = try SDL.init(initial_x_size, initial_y_size, 10);
    defer sdl.cleanup();

    var display = Display.init(&sdl, false);
    var chip8 = VM.init(&display);

    chip8.ram[0x200] = 0;
    chip8.ram[0x201] = 0xE0;

    while (!sdl.quit) {
        var timer = try std.time.Timer.start();

        chip8.next(4, sdl_callback);
        try display.update_sdl();

        std.time.sleep(10_000_000 - timer.read());
        _ = timer.lap();

        sdl.render();
    }
}

fn sdl_callback(chip8: *VM) void {
    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event) != 0) {
        switch (event.type) {
            c.SDL_QUIT => {
                chip8.display.sdl.quit = true;
            },

            c.SDL_KEYDOWN => {
                if (event.key.keysym.sym == c.SDLK_ESCAPE) {
                    chip8.display.sdl.quit = true;
                    break;
                }
                // This is a simplified way of taking key input.
                // A better version should probably take key info from a config file and define the presses to look for at runtime.
                switch (event.key.keysym.sym) {
                    c.SDLK_1 => chip8.press(0x1),
                    c.SDLK_2 => chip8.press(0x2),
                    c.SDLK_3 => chip8.press(0x3),
                    c.SDLK_4 => chip8.press(0xC),

                    c.SDLK_q => chip8.press(0x4),
                    c.SDLK_w => chip8.press(0x5),
                    c.SDLK_f => chip8.press(0x6),
                    c.SDLK_p => chip8.press(0xD),

                    c.SDLK_a => chip8.press(0x7),
                    c.SDLK_r => chip8.press(0x8),
                    c.SDLK_s => chip8.press(0x9),
                    c.SDLK_t => chip8.press(0xE),

                    c.SDLK_z => chip8.press(0xA),
                    c.SDLK_x => chip8.press(0x0),
                    c.SDLK_c => chip8.press(0xB),
                    c.SDLK_d => chip8.press(0xF),
                    else => {},
                }
            },
            c.SDL_KEYUP => {
                switch (event.key.keysym.sym) {
                    c.SDLK_1 => chip8.release(0x1),
                    c.SDLK_2 => chip8.release(0x2),
                    c.SDLK_3 => chip8.release(0x3),
                    c.SDLK_4 => chip8.release(0xC),

                    c.SDLK_q => chip8.release(0x4),
                    c.SDLK_w => chip8.release(0x5),
                    c.SDLK_f => chip8.release(0x6),
                    c.SDLK_p => chip8.release(0xD),

                    c.SDLK_a => chip8.release(0x7),
                    c.SDLK_r => chip8.release(0x8),
                    c.SDLK_s => chip8.release(0x9),
                    c.SDLK_t => chip8.release(0xE),

                    c.SDLK_z => chip8.release(0xA),
                    c.SDLK_x => chip8.release(0x0),
                    c.SDLK_c => chip8.release(0xB),
                    c.SDLK_d => chip8.release(0xF),
                    else => {},
                }
            },
            else => {},
        }
    }
}
