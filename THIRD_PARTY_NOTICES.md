# Third-party notices

## Hatari

The Atari ST/STE/TT/Falcon emulation in this app is **Hatari**, by the Hatari
team, used under the **GNU General Public Licence version 2 or later**.

* Source: https://github.com/hatari/hatari
* Vendored at `vendor/hatari` as a git submodule, **unmodified**. This project
  adds its own UI backend (`native/atarist_core/backend/`) alongside Hatari's
  SDL one rather than patching any Hatari source file, so the exact upstream
  revision this app was built from is the submodule's recorded commit.

Because this app links Hatari, the app as a whole is distributed under the
GPL v2 or later. The full licence text is in `LICENSE`.

## Not included

* **Atari TOS** -- the proprietary Atari operating-system ROM is not bundled.
  Users may supply an image they are entitled to use instead of EmuTOS.
* **Commercial games.** No commercial game is bundled. The iOS release runs disk images
  explicitly imported by the user through Apple's document picker and does not
  download games. This iOS restriction does not prohibit a separate Android
  Android release from retaining authenticated, administrator-only RetroMedia downloads;
  its distributor remains responsible for the necessary content rights.

## Retro-AtariST core demo

The app bundles a project-authored FAT12 test floppy whose source is in
`native/assets/demo/`. It displays a moving marker under EmuTOS and waits for
keyboard input. It contains no Atari ROM or third-party game content and is
distributed under GPL v2 or later.

## Dear ImGui

The native mobile user interface uses **Dear ImGui**, Copyright (c) 2014-2026
Omar Cornut and contributors, under the MIT License. The vendored source and
license are in `third_party/imgui/`.

## EmuTOS

The iOS and Android apps bundle the UK 512 KiB image from **EmuTOS 1.4**, the GPLv2 open
replacement for Atari TOS. Its original README, licence and exact source/archive
provenance are stored under `native/assets/emutos/`. Corresponding source is
available from the official EmuTOS 1.4 release page linked there.

## Referenced but not used

**ASE (Atari System Emulator)**, by The Bit Culture, GPL v3 --
https://github.com/thebitculture/ase. This project was started from a request
to build on ASE and consulted it as a reference, but ships none of its code:
ASE is C#/.NET and is not linked into this native iOS application. See the README.
