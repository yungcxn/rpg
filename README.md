# rpg (with zig)

My first `zig` learning-project where I implement an 2d rpg game.
My main inspiration for this are the first _The Legend of Zelda_ Games in the early NES, SNES and GBC/GBA era.

- I try to be creative with the game's content, but that's not the main goal

## Challenges

- As less deps as possible
- High performance
- Abuse `zig`'s `comptime` and everything that comes with it (since `comptime` was my motivation to start with `zig`)
- Make use of `zig`'s other (advanced) features

## Dependencies

- `zig` from `master` -- last build @`0.17 (31f157d8)`
- `vulkan` for graphical rendering
- `glfw` for platform-independent window frames

## Build

```bash
zig build
```