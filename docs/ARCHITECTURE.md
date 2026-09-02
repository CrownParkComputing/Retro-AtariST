# Architecture

## Native mobile stack

```
iOS: UIKit + document picker + Metal
Android: NativeActivity + SAF + OpenGL ES
                    |
         Dear ImGui C++ frontend
                    |
           atarist_bridge C ABI
                    |
     Hatari core + headless backend
```

Everything runs in one application process. Hatari is statically linked on iOS
and packaged as a private native library on Android; there is no child emulator
process, managed UI runtime, SDL window or downloaded core.

RetroMedia HTTP work remains in the Objective-C++ platform layer. It stores the
revocable session cookie in iOS Keychain, turns downloaded artwork into Metal
textures, and caches that artwork in Application Support. The iOS client has no
game-catalogue or game-download API. The ImGui frontend owns only account and
artwork presentation and sync actions. On Android, the Java platform layer
additionally exposes authenticated catalogue/download calls to administrators;
the iOS implementation deliberately has no matching network API.

The platform shells own only facilities that must be platform-native:

- application lifecycle and safe private file locations;
- the system document picker and copying imported files into the container;
- Metal/MetalKit on iOS or EGL/OpenGL ES on Android;
- touch and physical-keyboard events.

`native/frontend/` owns navigation, machine/media selection, the library,
settings, compliance evidence and the in-session overlay. It speaks only to
the public functions in `atarist_bridge.h`.

## Hatari's UI is a seam, not a library

Hatari's core calls out to `Screen_*`, `Audio_*`, `Keymap_*`, `JoyUI_*`,
`Statusbar_*`, `Timing_*` and a few dialog functions. Upstream ships SDL and
libretro implementations; `native/atarist_core/backend/` is a third peer that
renders into memory and receives input from the native frontend.

No file under `vendor/hatari` is patched. Upstream updates therefore remain a
normal submodule version bump.

## Threads

Hatari's `M68000_Start` loop is blocking, so the C bridge starts it on a
dedicated emulation thread. The platform UI/render thread continues to run the
native lifecycle, GPU backend and Dear ImGui.

Two rules govern cross-thread communication:

1. Level-triggered input such as joystick direction is atomic. Key events use
   a queue so that a make/break pair cannot be lost.
2. Operations that touch machine state—reset, disk swap and snapshots—go
   through the bridge mailbox and execute from the emulation thread at VBL.

The frontend copies a completed Hatari framebuffer when its generation counter
changes. The shell uploads that stable copy to a Metal or OpenGL texture. Consumers
must respect Hatari's pitch because the framebuffer uses a fixed overscan-sized
stride rather than `width * 4`.

## Audio

Hatari produces signed 16-bit samples through its ordinary audio seam. On iOS,
`audio_sink_ios.m` presents them with a RemoteIO Audio Unit and configures an
`AVAudioSession`; Android uses AAudio from API 26. Audio does not pass through
ImGui or the GPU shell.

## Configuration

`AtariStConfig` is a flat, stable C structure. The bridge translates it into
Hatari command-line options instead of exposing Hatari's large and frequently
changing `CNF_PARAMS` structure.

## CPU execution and App Store constraints

The WinUAE-derived CPU interpreter is generated into ordinary C functions at
build time. Hatari's `src/cpu/jit/` directory is not part of the target, and
the app never allocates writable/executable memory. Release builds therefore
remain compatible with iOS code-signing and App Store execution rules.

## Display aspect

Atari modes were displayed on a 4:3 monitor even when their pixel dimensions
were 320x200 or 640x200. The bridge reports the display aspect separately from
the framebuffer dimensions; the frontend uses that value unless “Fill screen”
is enabled.
