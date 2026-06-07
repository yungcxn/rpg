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

## Setup

Every C-header dependency needs it's include folders set as environment variables.

For this, either create a `.env` folder in root and set the keys, e.g. for MacOS:
```
GLFW_INCLUDE=/opt/homebrew/include 
VULKAN_INCLUDE=/Users/<user>/VulkanSDK/<version>/macOS/include
```
This depends, where your includes are. e.g. for Linux:
```
GLFW_INCLUDE=/usr/include
VULKAN_INCLUDE=/usr/include
```
This, because the includes are usually at `/usr/include/glfw/glfw3.h` and `usr/include/vulkan/vulkan.h`.

Now, just run:

```bash
zig build
```