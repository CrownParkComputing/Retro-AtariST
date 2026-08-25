# Architecture

## The one decision everything else follows from

Flutter UI ⇄ `dart:ffi` ⇄ C bridge ⇄ Hatari core, all in one process.

That is the same shape as Retro-Dosbox, Retro-C64 and Retro-Saturn, and it is
what makes Android and iOS possible at all. A launcher that spawns an emulator
binary is a desktop-only design; there is no `fork`/`exec` of a second GUI
process on mobile.

```
  Flutter (Dart)
      screens/, widgets/          <- knows nothing about ffi
      ffi/atarist_core.dart       <- the interface
         |                    \
      ffi/atarist_bindings.dart   ffi/stub_atarist_core.dart
         |
  ===== dart:ffi =====
      bridge/atarist_bridge.h     <- the ONLY public C surface, 25 symbols
      bridge/atarist_bridge.c     <- emulation thread + mailbox
      backend/                    <- our implementation of Hatari's UI seam
      vendor/hatari/src           <- unmodified
```

## Hatari's UI is a seam, not a library

Hatari's core calls out to `Screen_*`, `Audio_*`, `Keymap_*`, `JoyUI_*`,
`Statusbar_*`, `Timing_*` and a few dialog functions and expects someone to
supply them. Upstream ships two implementations:

| implementation | drives |
|---|---|
| `src/sdl/` | a real SDL2 window and audio device |
| `src/retro/` | libretro callbacks — experimental: `retro_run` does not push video and `retro_serialize` returns `false` |

`native/atarist_core/backend/` is the **third**. It renders into memory and
takes its input from the launcher.

The consequence worth stating plainly: **no file under `vendor/hatari` is
patched.** We are a peer of `src/sdl/`, so a `git submodule update --remote` is
an ordinary version bump rather than a rebase of a patch queue. If you find
yourself editing Hatari sources, the change almost certainly belongs in
`backend/`.

## Threads

Hatari's emulation is a blocking loop (`M68000_Start`), so it gets its own
thread. Two rules keep that safe:

1. **Level-triggered input is atomic; event-triggered input is queued.**
   Joystick direction and mouse buttons are *states* — the newest value is
   always correct and a dropped intermediate is not a lost input. Keys are
   *events*: a make with no break leaves a key held down forever, so they go
   through a small lock-free ring instead.

2. **Anything that touches machine state goes through the mailbox.** Reset,
   disk swap and snapshots are posted by the UI thread and executed by the
   emulation thread inside `Timing_WaitOnVbl` — the one point per frame where
   the ST is quiescent. `backend/timing.c` is therefore the meeting point of
   the whole design.

## Configuration goes through Hatari's command line

`AtariStConfig` is translated into Hatari command-line arguments rather than
written into `ConfigureParams`. `CNF_PARAMS` is ~40 nested structs whose layout
changes between releases; the options in `options.c` are documented, stable,
and validated by Hatari itself — an out-of-range memory size is *rejected with
a message* rather than booting a broken machine.

## Symbol hiding is a correctness requirement

`libatarist_core` exports exactly the 25 `atarist_core_*` entry points and
nothing else, enforced by `atarist_core.map`. Hatari contributes thousands of
symbols to this library, some with names as generic as `main`, `select` and
`debug`. On Android the app, Flutter's engine and every plugin `.so` share one
symbol namespace, and an exported `main` from an emulator core is a vicious
source of crashes in unrelated code.

Verify after any build:

```sh
nm -D --defined-only build/libatarist_core.so | grep -c ' T '   # must be 25
```

## Why the framebuffer is a fixed stride

`backend/screen.c` allocates once at the widest overscan mode and never
reallocates, unlike `src/retro/screen.c` which frees and mallocs on every mode
change. The launcher reads that pointer from another thread, and a realloc
during a resolution change — which is exactly what a game does on its title
screen — would hand the UI a dangling pointer for one frame.

The cost is that pitch ≠ width × 4, and every consumer has to respect it.
Getting that wrong produces the classic diagonally-sheared emulator screenshot.

## Pixel aspect is 4:3, not width/height

Every ST mode was shown on a 4:3 monitor, so the pixels are not square:

| mode | pixels | pixel shape |
|---|---|---|
| low | 320×200 | twice as wide as tall |
| medium | 640×200 | four times as wide as tall |
| mono | 640×400 | square |

Stretching to the *display* aspect is what keeps a circle round in all three.
Using width/height makes it an oval in two of them.
