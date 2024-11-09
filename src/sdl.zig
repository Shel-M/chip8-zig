const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

pub const SDL = struct {
    scale: u8,
    x_size: c_int,
    y_size: c_int,
    screen: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    texture: *c.SDL_Texture,

    quit: bool = false,

    pub fn init(x_size: c_int, y_size: c_int, scale: u8) !SDL {
        if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
            c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        }

        const screen = c.SDL_CreateWindow("Chip8", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, x_size * scale, y_size * scale, c.SDL_WINDOW_OPENGL) orelse {
            c.SDL_Log("Unable to create window %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        const renderer = c.SDL_CreateRenderer(screen, -1, 0) orelse {
            c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        const texture = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGB888, c.SDL_TEXTUREACCESS_STREAMING, x_size, y_size) orelse {
            c.SDL_Log("Unable to create texture: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        return SDL{
            .scale = scale,
            .x_size = x_size,
            .y_size = y_size,
            .screen = screen,
            .renderer = renderer,
            .texture = texture,
        };
    }

    pub fn update_texture(self: *SDL, buffer: []u32) !void {
        if (buffer.len > self.x_size * self.y_size) {
            return error.SDLUpdateTextureBufferOutOfBounds;
        }
        if (c.SDL_UpdateTexture(self.texture, null, @ptrCast(buffer), self.x_size * @sizeOf(u32)) != 0) {
            c.SDL_Log("Unable to update texture: %s", c.SDL_GetError());
            return error.SDLUpdateTextureFailed;
        }
    }

    pub fn update_screen_size(self: *SDL, x_size: c_int, y_size: c_int) !void {
        self.x_size = x_size;
        self.y_size = y_size;
        c.SDL_SetWindowSize(self.screen, x_size * self.scale, y_size * self.scale);

        c.SDL_DestroyTexture(self.texture);
        self.texture = c.SDL_CreateTexture(self.renderer, c.SDL_PIXELFORMAT_RGB888, c.SDL_TEXTUREACCESS_STREAMING, x_size, y_size) orelse {
            c.SDL_Log("Unable to create texture: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
    }

    pub fn render(self: *SDL) void {
        _ = c.SDL_RenderClear(self.renderer);
        _ = c.SDL_RenderCopy(self.renderer, self.texture, null, null);
        c.SDL_RenderPresent(self.renderer);
    }

    pub fn cleanup(self: *SDL) void {
        c.SDL_Quit();
        c.SDL_DestroyWindow(self.screen);
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyTexture(self.texture);
    }
};
