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
    key: [0xF]bool = .{false} ** 0xF,

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

    pub fn next(self: *VM, speed: usize, callback: *const fn (chip8: *VM) void) void {
        for (0..speed) |_| {
            if (self.pc >= 4096) {
                std.debug.print("VM.PC too high, reseting\n", .{});
                self.pc = INITIAL_ADDRESS;
            }
            const operation: u16 = (@as(u16, self.ram[self.pc]) << 8) | @as(u16, self.ram[self.pc + 1]);
            self.pc += 2;
            std.debug.print("0x{x:0>4}\n", .{operation});

            const instruction = operation & 0xF000 >> 12;
            const subinst = 0x000F & operation;

            const data_byte: u8 = @truncate(operation & 0x00FF);
            const addr = operation & 0x0FFF;
            const x: u8 = @truncate((0x0F00 & operation) >> 8);
            const y: u8 = @truncate((0x00F0 & operation) >> 4);

            switch (instruction) {
                0x0 => {
                    switch (data_byte) { // Switching on const byte instead of const instruction should probably make the asm switch table smaller.
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
                0x3 => self.skip_if(self.v[x] == data_byte),
                0x4 => self.skip_if(self.v[x] != data_byte),
                0x5 => self.skip_if(self.v[x] == self.v[y]),
                0x6 => self.v[x] = data_byte,
                0x7 => self.v[x] +%= data_byte,
                0x8 => {
                    switch (subinst) {
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
                    self.v[x] = gen.random().int(u8) & data_byte;
                },
                0xD => {
                    if (subinst != 0) { // chip8 draw
                        for (0..subinst) |y_pos| {
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
                    switch (data_byte) {
                        0x9E => self.skip_if(self.key[x]),
                        0xA1 => self.skip_if(!self.key[x]),
                        else => {},
                    }
                },
                0xF => {
                    switch (data_byte) {
                        0x07 => self.v[x] = self.delay,
                        0x0A => self.v[x] = self.get_keypress(),
                        0x15 => self.delay = x,
                        0x18 => self.sound = x,
                        0x1E => self.index +%= self.v[x],
                        0x29 => self.index = self.ram[x + FONT_POSITION],
                        // 0x30 => // superchip font version of 0x29,
                        0x33 => {
                            self.ram[self.index] = self.v[x] / 100;
                            self.ram[self.index + 1] = (self.v[x] / 10) % 10;
                            self.ram[self.index + 2] = self.v[x] % 10;
                        },
                        0x55 => {
                            for (0..x) |i| {
                                self.ram[self.index + i] = self.v[i];
                            }
                        },
                        0x65 => {
                            for (1..x + 1) |i| {
                                self.v[i] = self.ram[self.index + i];
                            }
                        },
                        else => {},
                    }
                },
                else => {},
            }

            if (self.delay == 0) { // VM ready for callback
                callback(self);
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
        const throttle = 17; // millisec loop throttle - limits loop to 60 times per second

        var event: c.SDL_Event = undefined;
        while (true) {
            if (c.SDL_PollEvent(&event) == 0) {
                c.SDL_Delay(throttle);
                continue;
            }
            switch (event.type) {
                c.SDL_QUIT => {
                    self.display.sdl.quit = true;
                },
                c.SDL_KEYDOWN => {
                    if (event.key.keysym.sym == c.SDLK_ESCAPE) {
                        self.display.sdl.quit = true;
                        return 0; // doesn't matter, the program should end here.
                    }
                    // This is a simplified way of taking key input.
                    // A better version should probably take key info from a config file and define the presses to look for at runtime.
                    var key: u4 = 0x0;
                    switch (event.key.keysym.sym) {
                        c.SDLK_1 => key = 0x1,
                        c.SDLK_2 => key = 0x2,
                        c.SDLK_3 => key = 0x3,
                        c.SDLK_4 => key = 0xC,

                        c.SDLK_q => key = 0x4,
                        c.SDLK_w => key = 0x5,
                        c.SDLK_f => key = 0x6,
                        c.SDLK_p => key = 0xD,

                        c.SDLK_a => key = 0x7,
                        c.SDLK_r => key = 0x8,
                        c.SDLK_s => key = 0x9,
                        c.SDLK_t => key = 0xE,

                        c.SDLK_z => key = 0xA,
                        c.SDLK_x => key = 0x0,
                        c.SDLK_c => key = 0xB,
                        c.SDLK_d => key = 0xF,
                        else => {
                            c.SDL_Delay(throttle);
                            continue;
                        },
                    }
                    self.press(key);
                    return key;
                },
                else => {
                    c.SDL_Delay(throttle);
                    continue;
                },
            }
            // Throttle checks to 60 times per second
            c.SDL_Delay(17);
        }
    }

    pub fn press(self: *VM, key: u4) void {
        self.key[key] = true;
    }

    pub fn release(self: *VM, key: u4) void {
        self.key[key] = false;
    }
};
