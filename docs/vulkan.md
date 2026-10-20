# Vulkan

Every oakMOSS image carries the GE8300's Vulkan driver from the SDK's `libgpu` package:
`/usr/lib/libVK_IMG.so` ("PowerVR Rogue Vulkan Driver", DDK 1.19@6345021, Vulkan 1.3.225, conformance
1.3.3.1) and PowerVR's own loader, `/usr/lib/libvulkan.so(.1)`. Its window-system support is
`VK_KHR_display` (and `VK_EXT_headless_surface`): Vulkan draws straight to the panel, with no X11 or
Wayland.

## What was proven (2026-10-18, Zero 28, v0.5.0-beta.2)

- `vulkaninfo --summary` finds GPU0 "PowerVR Rogue GE8300" through PowerVR's loader (instance 1.3.225, no
  layers) and through the Khronos loader 1.3.290 with the driver as its ICD.
- `vkcube` (WSI selection `DISPLAY`, 300 frames) ran with both loaders, about 5 s each (about 60 fps), and the
  picture was upright and filled the screen.
- The kit and records: `devices/builds/20261018-2119-vulkan-proof-zero28` in the spruce workspace.

Not yet tried: the Zero 40 and XU20 panels, a program that draws over another (Knulli's 4.9-era fb0
global-alpha fix may be needed), and frame pacing with two swapchain images.

## The Khronos loader (OAKMOSS_VULKAN)

PowerVR's loader stays the default. An image built with `OAKMOSS_VULKAN` also carries the Khronos
loader 1.3.290, for programs that need layers or a current loader:

| path | what |
|---|---|
| `/usr/lib/oakmoss/vulkan/libvulkan.so.1` | the Khronos loader (Vulkan-Loader v1.3.290, Apache-2.0) |
| `/usr/lib/oakmoss/vulkan/LICENSE.txt`, `BUILD-INFO`, `SHA256SUMS` | its licence and lane record |
| `/usr/share/vulkan/icd.d/powervr_icd.json` | the driver as its ICD (`assets/vulkan/powervr_icd.json`) |

`/usr/lib/oakmoss/vulkan` is on no default library path, so nothing changes until a program asks for it:

```
LD_LIBRARY_PATH=/usr/lib/oakmoss/vulkan:$LD_LIBRARY_PATH ./program
```

PowerVR's loader reads no manifest, so the manifest changes nothing for it.

## Building it

```
PORTS_SET=flip PORTS_TOOLCHAIN=armgnu13 OUT=builds/<stamp>-vulkan-loader \
    scripts/run-userland-lane.sh vulkanheaders vulkanloader
OAKMOSS_VULKAN=builds/<stamp>-vulkan-loader OAKMOSS_LIBS=... scripts/build.sh all zero28 zero40 xu20
```

The two lane packages are not in the flip set's list, so building the loader leaves the library set as it
is. The sources are pinned in `inputs/userland/` (the GitHub tag archives of v1.3.290, the same trees as
Khronos's tags `b379292b` and `f8616928`). The lane's glibc gate covers `lib/vulkan`, and `build.sh`
refuses an image whose loader, manifest or `libVK_IMG.so` is missing, or whose loader links anything the
image lacks.
