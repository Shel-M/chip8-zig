const std = @import("std");
const Display = @import("display.zig").Display;
const SDL = @import("sdl.zig").SDL;

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const FONT_POSITION = 0x050;
const INITIAL_ADDRESS = 0x200;

pub const VM = struct {
    display: *Display,
    ram: [4096]u8 = .{0} ** 4096,
    key: [0xF]bool = .{false} * 0xF,

    pc: u16 = INITIAL_ADDRESS,
    stack_pointer: u8 = 0,
    stack: [16]u16 = .{0} ** 16,

    v: [16:0]u8 = .{0} ** 16,
    index: u16 = 0,
    delay: u8 = 0,
    sound: u8 = 0,

    pub fn init(display: *Display) VM {
        var self = VM{ .display = display };
        self.init_font();
        return self;
    }

    pub fn init_font(self: *VM) void {
        const font = [_]u8{
            0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
            0x20, 0x60, 0x20, 0x20, 0x70, // 1
            0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
            0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
            0x90, 0x90, 0xF0, 0x10, 0x10, // 4
            0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
            0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
            0xF0, 0x10, 0x20, 0x40, 0x40, // 7
            0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
            0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
            0xF0, 0x90, 0xF0, 0x90, 0x90, // A
            0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
            0xF0, 0x80, 0x80, 0x80, 0xF0, // C
            0xE0, 0x90, 0x90, 0x90, 0xE0, // D
            0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
            0xF0, 0x80, 0xF0, 0x80, 0x80, // F
        };
        for (font, 0..) |value, i| {
            self.ram[i + FONT_POSITION] = value;
        }
    }

    pub fn load(self: *VM, rom: []u8) !void {
        for (rom, 0..) |b, i| {
            if (i + INITIAL_ADDRESS > self.ram.len) {
                return error.RomTooLarge;
            }
            self.ram[i + INITIAL_ADDRESS] = b;
        }
    }

    pub fn next(self: *VM, speed: usize, callback: *const fn (sdl: *SDL) void) void {
        for (0..speed) |_| {
            if (self.pc >= 4096) {
                std.debug.print("VM.PC too high, reseting\n", .{});
                self.pc = INITIAL_ADDRESS;
            }
            const instruction: u16 = (@as(u16, self.ram[self.pc]) << 8) | @as(u16, self.ram[self.pc + 1]);
            self.pc += 2;
            std.debug.print("0x{x:0>4}\n", .{instruction});

            const op = instruction & 0xF000 >> 12;
            const subop = 0x000F & instruction;

            const byte: u8 = @truncate(instruction & 0x00FF);
            const addr = instruction & 0x0FFF;
            const x = (0x0F00 & instruction) >> 8;
            const y = (0x00F0 & instruction) >> 4;

            switch (op) {
                0x0 => {
                    switch (byte) { // Switching on const byte instead of const instruction should probably make the asm switch table smaller.
                        // CLS
                        0xE0 => self.display.clear(),
                        // RET
                        0xEE => self.stack_return(),
                        else => {},
                    }
                },
                // JP addr - 0x1<addr>
                0x1 => self.pc = addr,
                // CALL addr - 0x2<addr>, store current VM.pc to stack.
                0x2 => {
                    self.stack[self.stack_pointer] = self.pc;
                    self.stack_pointer += 1;
                    self.pc = addr;
                },
                0x3 => self.skip_if(self.v[x] == byte),
                0x4 => self.skip_if(self.v[x] != byte),
                0x5 => self.skip_if(self.v[x] == self.v[y]),
                0x6 => self.v[x] = byte,
                0x7 => self.v[x] +%= byte,
                0x8 => {
                    switch (subop) {
                        0x0 => self.v[x] = self.v[y],
                        0x1 => self.v[x] |= self.v[y],
                        0x2 => self.v[x] &= self.v[y],
                        0x3 => self.v[x] ^= self.v[y],
                        0x4 => {
                            self.v[x], const ov = @addWithOverflow(self.v[x], self.v[y]);
                            self.v[0xF] = ov;
                        },
                        0x5 => {
                            self.v[x], const ov = @subWithOverflow(self.v[x], self.v[y]);
                            self.v[0xF] = ov;
                        },
                        0x6 => {
                            self.v[0xF] = self.v[x] & 0x1;
                            self.v[x] = self.v[x] >> 1;
                        },
                        0x7 => {
                            self.v[x], const ov = @subWithOverflow(self.v[y], self.v[x]);
                            self.v[0xF] = ov;
                        },
                        0xE => {
                            self.v[0xF] = self.v[x] & 0b1000_0000;
                            self.v[x] = self.v[x] << 1;
                        },
                        else => {},
                    }
                },
                0x9 => self.skip_if(self.v[x] != self.v[y]),
                0xA => self.index = addr,
                0xB => self.pc = addr + self.v[0],
                0xC => {
                    var gen = std.rand.DefaultPrng.init(0);
                    self.v[x] = gen.random().int(u8) & byte;
                },
                0xD => {
                    if (subop != 0) { // chip8 draw
                        for (0..subop) |y_pos| {
                            const line = self.ram[self.index + y_pos];
                            for (0..8) |x_pos| {
                                const x_shift: u3 = @truncate(x_pos);
                                if ((line & (@as(u8, 0b1000_0000) >> x_shift)) != 0) {
                                    if (self.display.xor_pixel(@truncate(self.v[x] + x_pos), @truncate(self.v[y] + y_pos))) {
                                        self.v[0xF] = 1;
                                    }
                                }
                            }
                        }
                    }
                    // else { // superchip draw
                    // }
                    self.display.sdl.render();
                },
                0xE => {
                    switch (byte) {
                        0x9E => self.skip_if(self.key[x]),
                        0xA1 => self.skip_if(!self.key[x]),
                        else => {},
                    }
                },
                0xF => {
                    switch (byte) {
                        0x07 => self.v[x] = self.delay,
                        0x0A => self.v[x] = self.get_keypress(),
                        0x15 => self.delay = x,
                        0x18 => self.sound = x,
                        0x1E => self.index +%= self.v[x],
                        0x29 => self.index = self.ram[x + FONT_POSITION],
                        // 0x30 => // superchip font version of 0x29,
                        0x33 => {},
                        else => {},
                    }
                },
                else => {},
            }

            if (self.delay == 0) { // VM ready for callback
                callback(self.display.sdl);
            }
        }
    }

    pub fn update(self: *VM) void {
        if (self.delay > 0) {
            self.delay -= 1;
        }
        if (self.sound > 0) {
            self.sound -= 1;
        }
    }

    fn stack_return(self: *VM) void {
        if (self.stack_pointer > 0) {
            self.pc = self.stack[self.stack_pointer - 1];
            self.stack_pointer -= 1;
        }
    }

    fn skip_if(self: *VM, condition: bool) void {
        if (condition) {
            self.pc += 2;
        }
    }

    fn get_keypress(self: *VM) u4 {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    self.display.sdl.quit = true;
                },
                c.SDL_KEYDOWN => {
                    if (event.key.keysym.sym == c.SDLK_ESCAPE) {
                        self.display.sdl.quit = true;
                        break;
                    }
                    // This is a simplified way of taking key input.
                    // A better version should probably take key info from a config file and define the presses to look for at runtime.
                    switch (event.key.keysym.sym) {
                        c.SDLK_1 => return self.press(0x1),
                        c.SDLK_2 => return self.press(0x2),
                        c.SDLK_3 => return self.press(0x3),
                        c.SDLK_4 => return self.press(0xC),

                        c.SDLK_q => return self.press(0x4),
                        c.SDLK_w => return self.press(0x5),
                        c.SDLK_f => return self.press(0x6),
                        c.SDLK_p => return self.press(0xD),

                        c.SDLK_a => return self.press(0x7),
                        c.SDLK_r => return self.press(0x8),
                        c.SDLK_s => return self.press(0x9),
                        c.SDLK_t => return self.press(0xE),

                        c.SDLK_z => return self.press(0xA),
                        c.SDLK_x => return self.press(0x0),
                        c.SDLK_c => return self.press(0xB),
                        c.SDLK_d => return self.press(0xF),
                        else => {},
                    }
                },
                else => {},
            }

            // Throttle checks to 60 times per second
            c.SDL_Delay(17);
        }
    }

    fn press(self: *VM, key: u4) void {
        self.key[key] = true;
    }

    fn release(self: *VM, key: u4) void {
        self.key[key] = false;
    }
};
