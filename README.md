# Retro-AtariST

An Atari ST front end for Android, iOS and Linux, in the shape of the rest of
the `Retro-*` family. It wraps the **Hatari** emulator behind a `dart:ffi`
bridge, so the same Flutter UI runs on every target rather than being a desktop
launcher with a mobile port bolted on later.

Emulates the **ST**, **Mega ST**, **STE**, **Mega STE**, **TT** and
**Falcon 030**.

## Layout

```
flutter_app/            The launcher. Runs against a stub core with no native
                        build, no device and no TOS ROM.
  lib/ffi/              The dart:ffi layer + the stub.
  lib/widgets/sidebar.dart
                        Identical in every Retro-* app -- copied, never
                        rewritten. A fix there is meant to land everywhere.
native/atarist_core/
  bridge/               The C ABI the whole app talks through.
  backend/              Our implementation of Hatari's UI seam. A PEER of
                        Hatari's src/sdl/, not a patch of it.
  linux|android|ios/    Per-target build scripts.
vendor/hatari/          Hatari, as an unmodified submodule.
```

## Why Hatari and not ASE

This project began from a request to build on
[thebitculture/ase](https://github.com/thebitculture/ase), an Atari ST emulator
written in **C# / .NET 10 with Avalonia**. ASE is a good emulator and its
write-up is worth reading, but a C# core cannot be bridged into Flutter on
Android or iOS, and "runs on every platform" was the requirement that decided
the architecture.

Hatari is C, is what ASE itself ported parts from, and is the most accurate ST
emulator available. ASE is kept as a reference for ST behaviour and for its
game-metadata work.

## Getting started

```sh
git submodule update --init --recursive
./native/atarist_core/linux/build.sh      # builds libatarist_core.so
cd flutter_app && flutter run -d linux
```

The launcher falls back to a stub core if the native library is missing and
says so in a banner, so the UI can be worked on without ever building Hatari.

**A TOS ROM is required.** TOS is copyrighted by Atari and is not included --
supply your own image, exactly as with the KERNAL in Retro-C64. Drop one (or
several) into the app's ROM folder and the launcher identifies each by its
header and picks the right one for the selected machine.

That choice is by **nativeness, not version**. A plain ST gets TOS 1.0x even
when 2.06 is installed: 2.06 on an ST comes up in mono and sits at the memory
test, which looks like a booted machine that will not start the game.

Protected originals (`.stx`, `.ipf`) are launched with cycle-accurate FDC
timing automatically. They load in real 1988-1991 time -- up to a minute of
black screen -- and the emulator screen says so while it happens.

## Licence

GPL v2 or later, because it links Hatari. See `LICENSE` and
`THIRD_PARTY_NOTICES.md`.
